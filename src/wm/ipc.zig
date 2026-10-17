const std = @import("std");
const linux = std.os.linux;
const POLL = std.posix.POLL;
const protocol = @import("protocol");
const wire = protocol.wire;
const core = @import("core.zig");
const command = @import("command.zig");
const WM = core.WM;

/// A frame longer than this closes the connection: no request is legitimately this big.
const max_frame = 16 * 1024 * 1024;

pub const Client = struct {
    fd: i32,
    /// Stable for the connection's life: callbacks refer to clients by it.
    id: u32,
    /// The connection failed during a call; removed at the next poll.
    dead: bool = false,
    /// Bytes received that don't yet form a complete frame.
    in: std.ArrayListUnmanaged(u8) = .empty,
    /// Encoded responses the socket hasn't accepted yet.
    out: std.ArrayListUnmanaged(u8) = .empty,

    fn deinit(c: *Client, a: std.mem.Allocator) void {
        close_fd(c.fd);
        c.in.deinit(a);
        c.out.deinit(a);
    }
};

pub const State = struct {
    /// The listening socket (-1 until init).
    fd: i32 = -1,
    clients: std.ArrayListUnmanaged(Client) = .empty,
    next_client_id: u32 = 1,
};

// ---- setup and teardown ----
fn close_fd(fd: i32) void {
    _ = linux.close(fd);
}

fn delete_socket(path: []const u8) void {
    var buf: [4096:0]u8 = undefined;
    if (path.len >= buf.len) return;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    _ = linux.unlink(&buf);
}

pub fn get_path(allocator: std.mem.Allocator) ![]u8 {
    if (std.c.getenv("XDG_RUNTIME_DIR")) |dir| {
        return std.fmt.allocPrint(allocator, "{s}/duckwm.sock", .{std.mem.span(dir)});
    }
    return std.fmt.allocPrint(allocator, "/tmp/duckwm-{d}.sock", .{linux.getuid()});
}

pub fn init(wm: *WM) !void {
    const path = try get_path(wm.allocator);
    defer wm.allocator.free(path);

    delete_socket(path);

    const rc = linux.socket(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.NONBLOCK | linux.SOCK.CLOEXEC, 0);
    if (linux.errno(rc) != .SUCCESS) return error.SocketFailed;
    const fd: i32 = @intCast(rc);
    errdefer close_fd(fd);

    var addr = std.mem.zeroes(linux.sockaddr.un);
    addr.family = linux.AF.UNIX;
    if (path.len >= addr.path.len) return error.PathTooLong;
    @memcpy(addr.path[0..path.len], path);

    if (linux.errno(linux.bind(fd, @ptrCast(&addr), @sizeOf(linux.sockaddr.un))) != .SUCCESS) return error.BindFailed;
    if (linux.errno(linux.listen(fd, 8)) != .SUCCESS) return error.ListenFailed;

    wm.ipc_state.fd = fd;
    std.debug.print("IPC socket at {s}\n", .{path});
}

pub fn deinit(wm: *WM) void {
    for (wm.ipc_state.clients.items) |*c| c.deinit(wm.allocator);
    wm.ipc_state.clients.deinit(wm.allocator);
    wm.ipc_state.clients = .empty;
    if (wm.ipc_state.fd >= 0) {
        close_fd(wm.ipc_state.fd);
        wm.ipc_state.fd = -1;
        const path = get_path(wm.allocator) catch return;
        defer wm.allocator.free(path);
        delete_socket(path);
    }
}

// ---- polling ----
const PollFd = std.posix.pollfd;
const PollEvents = @FieldType(PollFd, "events");

/// Append the listening socket, then every client, to the poll set.
/// handle expects exactly these entries, in this order.
pub fn add_poll_fds(wm: *WM, fds: *std.ArrayListUnmanaged(PollFd)) !void {
    try fds.append(wm.allocator, .{ .fd = wm.ipc_state.fd, .events = POLL.IN, .revents = 0 });
    for (wm.ipc_state.clients.items) |c| {
        var events: PollEvents = POLL.IN;
        if (c.out.items.len > 0) events |= POLL.OUT;
        try fds.append(wm.allocator, .{ .fd = c.fd, .events = events, .revents = 0 });
    }
}

/// Act on what poll reported, for the entries add_poll_fds appended.
pub fn handle(wm: *WM, fds: []const PollFd) void {
    // Backwards: a closed client is removed from the list.
    var i = wm.ipc_state.clients.items.len;
    while (i > 0) {
        i -= 1;
        const c = &wm.ipc_state.clients.items[i];
        const revents = fds[1 + i].revents;
        const keep = !c.dead and (revents == 0 or service(wm, c, revents));
        if (!keep) {
            wm.drop_client_callbacks(c.id);
            c.deinit(wm.allocator);
            _ = wm.ipc_state.clients.orderedRemove(i);
        }
    }
    // After the clients, so the indices above still match the poll set.
    if (fds[0].revents & POLL.IN != 0) accept_all(wm);
}

fn accept_all(wm: *WM) void {
    while (true) {
        const rc = linux.accept4(wm.ipc_state.fd, null, null, linux.SOCK.NONBLOCK | linux.SOCK.CLOEXEC);
        switch (linux.errno(rc)) {
            .SUCCESS => {
                const fd: i32 = @intCast(rc);
                const id = wm.ipc_state.next_client_id;
                wm.ipc_state.clients.append(wm.allocator, .{ .fd = fd, .id = id }) catch {
                    close_fd(fd);
                    continue;
                };
                wm.ipc_state.next_client_id += 1;
            },
            .INTR => continue,
            else => return, // AGAIN: nothing more pending
        }
    }
}

// ---- one client ----
/// false: the client is gone or misbehaved, close it.
fn service(wm: *WM, c: *Client, revents: PollEvents) bool {
    if (c.dead) return false;
    if (revents & (POLL.IN | POLL.HUP) != 0) {
        const r = read_available(wm, c);
        if (r == .failed) return false;
        handle_frames(wm, c) catch return false;
        if (r == .eof) {
            // The client closed its side; answer what it sent, then close ours.
            _ = flush_out(c);
            return false;
        }
    }
    if (revents & POLL.ERR != 0) return false;
    if (c.out.items.len > 0) return flush_out(c);
    return true;
}

const Read = enum { more, eof, failed };

fn read_available(wm: *WM, c: *Client) Read {
    var buf: [16 * 1024]u8 = undefined;
    while (true) {
        const rc = linux.read(c.fd, &buf, buf.len);
        switch (linux.errno(rc)) {
            .SUCCESS => {
                if (rc == 0) return .eof;
                c.in.appendSlice(wm.allocator, buf[0..rc]) catch return .failed;
            },
            .AGAIN => return .more,
            .INTR => continue,
            else => return .failed,
        }
    }
}

/// Remove the first complete frame from c.in, copied into a. null: none yet.
fn take_frame(c: *Client, a: std.mem.Allocator) !?[]u8 {
    if (c.in.items.len < 4) return null;
    const len = std.mem.readInt(u32, c.in.items[0..4], .little);
    if (len > max_frame) return error.FrameTooLarge;
    if (c.in.items.len - 4 < len) return null;
    const frame = try a.dupe(u8, c.in.items[4..][0..len]);
    const rest = c.in.items.len - 4 - len;
    std.mem.copyForwards(u8, c.in.items[0..rest], c.in.items[4 + len ..]);
    c.in.shrinkRetainingCapacity(rest);
    return frame;
}

fn send(wm: *WM, c: *Client, body: []const u8) !void {
    var len: [4]u8 = undefined;
    std.mem.writeInt(u32, &len, @intCast(body.len), .little);
    try c.out.appendSlice(wm.allocator, &len);
    try c.out.appendSlice(wm.allocator, body);
}

/// Run a client's commands as one transaction, with it as the callback source.
fn run_request(wm: *WM, c: *Client, cmds: []const protocol.Command, a: std.mem.Allocator) ![]u8 {
    const results = try a.alloc(protocol.Value, cmds.len);
    const saved = wm.callback_source;
    wm.callback_source = .{ .client = c.id };
    defer wm.callback_source = saved;
    command.run(wm, cmds, a, results) catch |err|
        return wire.encode_server_response(a, &.{}, command.error_text(err));
    return wire.encode_server_response(a, results, null);
}

/// Answer every complete frame in the input buffer.
fn handle_frames(wm: *WM, c: *Client) !void {
    while (true) {
        var arena = std.heap.ArenaAllocator.init(wm.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const frame = (try take_frame(c, a)) orelse return;
        const msg = wire.decode_client_message(frame, a) catch |err| {
            const text = try std.fmt.allocPrint(a, "malformed message: {s}", .{@errorName(err)});
            try send(wm, c, try wire.encode_server_response(a, &.{}, text));
            continue;
        };
        switch (msg) {
            .request => |req| try send(wm, c, try run_request(wm, c, req.commands, a)),
            // A Return only means something while call() waits for it; one
            // arriving now is late (the call timed out) and is dropped.
            .ret => {},
        }
    }
}

/// Run one request as a transaction and queue its response.
fn answer(wm: *WM, c: *Client, frame: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(wm.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const body = blk: {
        const cmds = wire.decode_request(frame, a) catch |err| {
            const msg = try std.fmt.allocPrint(a, "malformed request: {s}", .{@errorName(err)});
            break :blk try wire.encode_response(a, &.{}, msg);
        };
        const results = try a.alloc(protocol.Value, cmds.len);
        command.run(wm, cmds, a, results) catch |err| {
            break :blk try wire.encode_response(a, &.{}, command.error_text(err));
        };
        break :blk try wire.encode_response(a, results, null);
    };

    var len: [4]u8 = undefined;
    std.mem.writeInt(u32, &len, @intCast(body.len), .little);
    try c.out.appendSlice(wm.allocator, &len);
    try c.out.appendSlice(wm.allocator, body);
}

/// Write as much queued output as the socket accepts. false: the client is gone.
fn flush_out(c: *Client) bool {
    var sent: usize = 0;
    defer {
        const rest = c.out.items.len - sent;
        std.mem.copyForwards(u8, c.out.items[0..rest], c.out.items[sent..]);
        c.out.shrinkRetainingCapacity(rest);
    }
    while (sent < c.out.items.len) {
        const pending = c.out.items[sent..];
        // NOSIGNAL: a client that hung up must not SIGPIPE the WM.
        const rc = linux.sendto(c.fd, pending.ptr, pending.len, linux.MSG.NOSIGNAL, null, 0);
        switch (linux.errno(rc)) {
            .SUCCESS => sent += rc,
            .AGAIN => return true, // the rest goes out on the next POLLOUT
            .INTR => continue,
            else => return false,
        }
    }
    return true;
}

/// How long a client's callback may take before the call fails.
const call_timeout_ms = 100;

fn now_ms() i64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(linux.CLOCK.MONOTONIC, &ts);
    return ts.sec * 1000 + @divTrunc(ts.nsec, 1_000_000);
}

fn find(wm: *WM, id: u32) ?*Client {
    for (wm.ipc_state.clients.items) |*c| if (c.id == id) return c;
    return null;
}

/// Call a client's callback inside the current transaction, serving the
/// requests its body makes (in the same transaction) until it returns.
/// Returns Return.callback: the arranger a factory made.
pub fn call(wm: *WM, client: u32, callback: u64, args: protocol.CallArgs, a: std.mem.Allocator) !protocol.Return {
    const c = find(wm, client) orelse return error.ClientGone;
    if (c.dead) return error.ClientGone;

    try send(wm, c, try wire.encode_server_call(a, .{ .callback = callback, .args = args }));

    const deadline = now_ms() + call_timeout_ms;
    var eof = false;
    while (true) {
        // Handle what has arrived first, so a quick client never waits on poll.
        while (try take_frame(c, a)) |frame| {
            const msg = wire.decode_client_message(frame, a) catch {
                c.dead = true;
                return error.CallbackFailed;
            };
            switch (msg) {
                .request => |req| try send(wm, c, try run_request(wm, c, req.commands, a)),
                .ret => |r| {
                    if (r.err) |e| {
                        std.debug.print("callback error (client {d}): {s}\n", .{ client, e });
                        return error.CallbackFailed;
                    }
                    const results = try a.alloc(protocol.Value, r.commands.len);
                    const saved = wm.callback_source;
                    wm.callback_source = .{ .client = client };
                    defer wm.callback_source = saved;
                    command.run(wm, r.commands, a, results) catch |err| {
                        std.debug.print("callback commands (client {d}): {s}\n", .{ client, command.error_text(err) });
                        return error.CallbackFailed;
                    };
                    return r;
                },
            }
        }
        if (eof or !flush_out(c)) {
            c.dead = true;
            return error.ClientGone;
        }
        const left = deadline - now_ms();
        if (left <= 0) {
            std.debug.print("callback timed out (client {d}); disconnecting it\n", .{client});
            c.dead = true;
            return error.CallbackTimeout;
        }
        var pfd = [1]std.posix.pollfd{.{
            .fd = c.fd,
            .events = POLL.IN | @as(PollEvents, if (c.out.items.len > 0) POLL.OUT else 0),
            .revents = 0,
        }};
        _ = std.posix.poll(&pfd, @intCast(left)) catch return error.ClientGone;
        if (pfd[0].revents & (POLL.IN | POLL.HUP) != 0) {
            switch (read_available(wm, c)) {
                .more => {},
                .eof => eof = true, // a Return may still be in what was read
                .failed => {
                    c.dead = true;
                    return error.ClientGone;
                },
            }
        } else if (pfd[0].revents & POLL.ERR != 0) {
            c.dead = true;
            return error.ClientGone;
        }
    }
}
