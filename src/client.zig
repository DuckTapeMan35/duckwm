const std = @import("std");
const linux = std.os.linux;
const protocol = @import("protocol");
const wire = protocol.wire;
const Allocator = std.mem.Allocator;

pub const Command = protocol.Command;
pub const Value = protocol.Value;
pub const CallArgs = protocol.CallArgs;
pub const Callback = protocol.Callback;

/// Larger frames are refused rather than read.
pub const max_frame = 16 * 1024 * 1024;

pub const Error = error{
    /// duckwm closed the connection (it quit, restarted, or dropped us).
    Closed,
    /// duckwm refused the batch; nothing in it took effect. Client.why says why.
    Rejected,
    /// duckwm sent something that isn't the protocol.
    Protocol,
    SocketFailed,
    ConnectFailed,
    PathTooLong,
} || Allocator.Error;

/// What a callback hands back: commands to run in duckwm's transaction; for an
/// arranger, its layout and next state; for a factory, the arranger it made.
pub const Reply = struct {
    commands: []const Command = &.{},
    layout: ?protocol.LayoutSpec = null,
    /// null leaves the state as it is.
    state: ?Value = null,
    made: ?u64 = null,
    /// Fail duckwm's transaction with this message (for callbacks that report
    /// errors as text; a returned Zig error does the same with its name).
    err: ?[]const u8 = null,
};

/// A callback: a function and the context it was registered with. arena lives
/// for the call; requests made with c inside it run in duckwm's transaction.
pub const Handler = struct {
    ctx: ?*anyopaque,
    func: *const fn (ctx: ?*anyopaque, c: *Client, args: CallArgs, arena: Allocator) anyerror!Reply,

    /// A handler calling f(ctx, c, args, arena) with ctx's own type.
    pub fn of(
        comptime T: type,
        ctx: *T,
        comptime f: fn (ctx: *T, c: *Client, args: CallArgs, arena: Allocator) anyerror!Reply,
    ) Handler {
        const Wrap = struct {
            fn call(p: ?*anyopaque, c: *Client, args: CallArgs, arena: Allocator) anyerror!Reply {
                return f(@ptrCast(@alignCast(p.?)), c, args, arena);
            }
        };
        return .{ .ctx = ctx, .func = Wrap.call };
    }
};

/// `$XDG_RUNTIME_DIR/duckwm.sock`, or `/tmp/duckwm-<uid>.sock`, like duckwm.
pub fn socket_path(a: Allocator) Allocator.Error![]u8 {
    if (std.c.getenv("XDG_RUNTIME_DIR")) |dir| {
        return std.fmt.allocPrint(a, "{s}/duckwm.sock", .{std.mem.span(dir)});
    }
    return std.fmt.allocPrint(a, "/tmp/duckwm-{d}.sock", .{linux.getuid()});
}

pub const Client = struct {
    fd: i32,
    gpa: Allocator,
    handlers: std.AutoHashMapUnmanaged(u64, Handler) = .empty,
    next_id: u64 = 1,
    /// After error.Rejected: what duckwm said, in the arena run() was given.
    why: []const u8 = "",

    /// Connect at socket_path().
    pub fn connect(gpa: Allocator) Error!Client {
        const path = try socket_path(gpa);
        defer gpa.free(path);
        return connect_to(gpa, path);
    }

    /// Connect at a given path, e.g. another user's `/run/user/<uid>/duckwm.sock`.
    pub fn connect_to(gpa: Allocator, path: []const u8) Error!Client {
        const rc = linux.socket(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0);
        if (linux.errno(rc) != .SUCCESS) return error.SocketFailed;
        const fd: i32 = @intCast(rc);
        errdefer _ = linux.close(fd);

        var addr = std.mem.zeroes(linux.sockaddr.un);
        addr.family = linux.AF.UNIX;
        if (path.len >= addr.path.len) return error.PathTooLong;
        @memcpy(addr.path[0..path.len], path);
        if (linux.errno(linux.connect(fd, @ptrCast(&addr), @sizeOf(linux.sockaddr.un))) != .SUCCESS)
            return error.ConnectFailed;
        return from_fd(gpa, fd);
    }

    /// A client on a socket that's already connected; it closes it on deinit.
    pub fn from_fd(gpa: Allocator, fd: i32) Client {
        return .{ .fd = fd, .gpa = gpa };
    }

    pub fn deinit(c: *Client) void {
        c.handlers.deinit(c.gpa);
        _ = linux.close(c.fd);
        c.* = undefined;
    }

    // ---- requests ----

    /// Run the commands as one transaction; one result per command, in arena.
    /// duckwm's calls that arrive meanwhile (set off by these commands) are
    /// answered before it returns.
    pub fn run(c: *Client, arena: Allocator, cmds: []const Command) Error![]const Value {
        try c.send(arena, .{ .request = .{ .commands = cmds } });
        // A call not set off by this request crossed it on the wire: duckwm
        // runs the request inside that call and answers it first, so the call
        // is handled once the answer is in.
        var crossed: std.ArrayListUnmanaged(protocol.Call) = .empty;
        // Events for subscribers wait for the response too: what they do is
        // requests of their own, which can't go out in the middle of this one.
        var events: std.ArrayListUnmanaged(protocol.Event) = .empty;
        const resp = while (true) {
            switch (try c.recv(arena)) {
                .response => |r| break r,
                .call => |call| if (call.nested) try c.handle(call) else try crossed.append(arena, call),
                .event => |e| try events.append(arena, e),
            }
        };
        for (crossed.items) |call| try c.handle(call);
        for (events.items) |e| try c.notify(e);
        if (resp.err) |why| {
            c.why = why;
            return error.Rejected;
        }
        return resp.results;
    }

    /// Run one command and return its result.
    pub fn run_one(c: *Client, arena: Allocator, cmd: Command) Error!Value {
        const results = try c.run(arena, &.{cmd});
        if (results.len != 1) return error.Protocol;
        return results[0];
    }

    /// Answer duckwm's calls until the connection closes (error.Closed).
    pub fn serve(c: *Client) Error!void {
        var arena: std.heap.ArenaAllocator = .init(c.gpa);
        defer arena.deinit();
        while (true) {
            _ = arena.reset(.retain_capacity);
            switch (try c.recv(arena.allocator())) {
                .call => |call| try c.handle(call),
                .event => |e| try c.notify(e),
                .response => return error.Protocol, // nothing was asked
            }
        }
    }

    /// For an event loop: when fd is readable, answer the calls waiting
    /// without blocking for more. error.Closed once duckwm has gone.
    pub fn dispatch(c: *Client) Error!void {
        var arena: std.heap.ArenaAllocator = .init(c.gpa);
        defer arena.deinit();
        while (readable(c.fd)) {
            _ = arena.reset(.retain_capacity);
            switch (try c.recv(arena.allocator())) {
                .call => |call| try c.handle(call),
                .event => |e| try c.notify(e),
                .response => return error.Protocol, // nothing was asked
            }
        }
    }

    // ---- callbacks ----
    /// Register h; the Callback goes into a command (bind, add_rule, set_arranger, ...).
    pub fn register(c: *Client, h: Handler) Allocator.Error!Callback {
        const id = c.next_id;
        c.next_id += 1;
        try c.handlers.put(c.gpa, id, h);
        return .{ .id = id };
    }

    pub fn unregister(c: *Client, cb: Callback) void {
        _ = c.handlers.remove(cb.id);
    }

    /// Run the handler for one call and send its Return. A handler error, or a
    /// callback nobody registered, goes back to duckwm as the Return's err.
    fn handle(c: *Client, call: protocol.Call) Error!void {
        var arena: std.heap.ArenaAllocator = .init(c.gpa);
        defer arena.deinit();
        const a = arena.allocator();

        var ret: protocol.Return = .{ .commands = &.{}, .err = null, .callback = null, .layout = null, .state = null };
        if (c.handlers.get(call.callback)) |h| {
            if (h.func(h.ctx, c, call.args, a)) |r| {
                ret.err = r.err;
                ret.commands = r.commands;
                ret.layout = r.layout;
                ret.state = r.state;
                ret.callback = r.made;
            } else |err| switch (err) {
                // The connection itself failed inside the callback: nothing to answer on.
                error.Closed => return error.Closed,
                error.Rejected => ret.err = c.why,
                else => ret.err = @errorName(err),
            }
        } else ret.err = "no such callback";
        try c.send(a, .{ .ret = ret });
    }

    /// Run a subscriber's handler for one event. Nothing goes back: duckwm
    /// isn't waiting. The commands its Reply holds run as a request of their
    /// own; a handler error is dropped, there being no one to give it to.
    fn notify(c: *Client, e: protocol.Event) Error!void {
        const h = c.handlers.get(e.callback) orelse return;
        var arena: std.heap.ArenaAllocator = .init(c.gpa);
        defer arena.deinit();
        const a = arena.allocator();
        const r = h.func(h.ctx, c, .{ .notice = e.notice }, a) catch |err| switch (err) {
            error.Closed => return error.Closed,
            else => return,
        };
        if (r.commands.len > 0) _ = c.run(a, r.commands) catch |err| switch (err) {
            error.Closed => return error.Closed,
            else => {},
        };
    }

    // ---- frames ----
    /// One frame: a little-endian u32 length, then the message.
    fn send(c: *Client, a: Allocator, msg: protocol.ClientMessage) Error!void {
        const body = wire.encode_client_message(a, msg) catch return error.OutOfMemory;
        var len: [4]u8 = undefined;
        std.mem.writeInt(u32, &len, @intCast(body.len), .little);
        try write_all(c.fd, &len);
        try write_all(c.fd, body);
    }

    fn recv(c: *Client, a: Allocator) Error!wire.ServerMessage {
        var len: [4]u8 = undefined;
        try read_exact(c.fd, &len);
        const n = std.mem.readInt(u32, &len, .little);
        if (n > max_frame) return error.Protocol;
        const frame = try a.alloc(u8, n);
        try read_exact(c.fd, frame);
        return wire.decode_server_message(frame, a) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.Protocol,
        };
    }
};

fn write_all(fd: i32, buf: []const u8) Error!void {
    var done: usize = 0;
    while (done < buf.len) {
        const rc = linux.write(fd, buf[done..].ptr, buf.len - done);
        switch (linux.errno(rc)) {
            .SUCCESS => done += rc,
            .INTR => continue,
            else => return error.Closed,
        }
    }
}

/// Something to read (or the other end hung up), right now.
fn readable(fd: i32) bool {
    var pfd = [1]linux.pollfd{.{ .fd = fd, .events = linux.POLL.IN, .revents = 0 }};
    const rc = linux.poll(&pfd, 1, 0);
    return linux.errno(rc) == .SUCCESS and rc > 0;
}

fn read_exact(fd: i32, buf: []u8) Error!void {
    var done: usize = 0;
    while (done < buf.len) {
        const rc = linux.read(fd, buf[done..].ptr, buf.len - done);
        switch (linux.errno(rc)) {
            .SUCCESS => {
                if (rc == 0) return error.Closed;
                done += rc;
            },
            .INTR => continue,
            else => return error.Closed,
        }
    }
}

// ---- tests: the client against a fake duckwm on a socket pair ----
const testing = std.testing;

/// duckwm's end of the pair: reads client messages, writes server ones.
const Fake = struct {
    fd: i32,
    arena: std.heap.ArenaAllocator,

    fn recv(f: *Fake) !protocol.ClientMessage {
        const a = f.arena.allocator();
        var len: [4]u8 = undefined;
        try read_exact(f.fd, &len);
        const frame = try a.alloc(u8, std.mem.readInt(u32, &len, .little));
        try read_exact(f.fd, frame);
        return wire.decode_client_message(frame, a);
    }

    fn send_frame(f: *Fake, body: []const u8) !void {
        var len: [4]u8 = undefined;
        std.mem.writeInt(u32, &len, @intCast(body.len), .little);
        try write_all(f.fd, &len);
        try write_all(f.fd, body);
    }

    fn respond(f: *Fake, results: []const Value, err: ?[]const u8) !void {
        try f.send_frame(try wire.encode_server_response(f.arena.allocator(), results, err));
    }

    fn call(f: *Fake, callback: u64, args: CallArgs, nested: bool) !void {
        const body = try wire.encode_server_call(f.arena.allocator(), .{ .callback = callback, .args = args, .nested = nested });
        try f.send_frame(body);
    }

    fn event(f: *Fake, callback: u64, notice: protocol.Notice) !void {
        try f.send_frame(try wire.encode_server_event(f.arena.allocator(), .{ .callback = callback, .notice = notice }));
    }
};

/// A client and the fake duckwm at the other end. Writes all fit in the socket
/// buffers, so one thread can play both sides as long as each reads in order.
fn pair() !struct { Client, Fake } {
    var fds: [2]i32 = undefined;
    if (linux.errno(linux.socketpair(linux.AF.UNIX, linux.SOCK.STREAM, 0, &fds)) != .SUCCESS)
        return error.SocketFailed;
    return .{ Client.from_fd(testing.allocator, fds[0]), .{ .fd = fds[1], .arena = .init(testing.allocator) } };
}

fn teardown(c: *Client, f: *Fake) void {
    c.deinit();
    _ = linux.close(f.fd);
    f.arena.deinit();
}

test "a request and its results; a rejection" {
    var c, var f = try pair();
    defer teardown(&c, &f);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    // The fake answers ahead of time: the response waits in the socket.
    try f.respond(&.{.{ .number = 0.5 }}, null);
    try testing.expectEqual(Value{ .number = 0.5 }, try c.run_one(arena.allocator(), .get_zoom));
    const sent = try f.recv();
    try testing.expect(sent.request.commands[0] == .get_zoom);

    try f.respond(&.{}, "no such node");
    try testing.expectError(error.Rejected, c.run_one(arena.allocator(), .{ .focus = .{ .id = 99 } }));
    try testing.expectEqualStrings("no such node", c.why);
}

const Press = struct {
    presses: usize = 0,
    focused: ?Value = null,

    fn on_key(p: *Press, c: *Client, args: CallArgs, arena: Allocator) anyerror!Reply {
        try testing.expect(args == .key);
        p.presses += 1;
        p.focused = try c.run_one(arena, .get_focused); // inside duckwm's transaction
        return .{ .commands = try arena.dupe(Command, &.{.kill_client}) };
    }
};

test "a callback, its nested request, and its reply" {
    var c, var f = try pair();
    defer teardown(&c, &f);
    var p: Press = .{};
    const cb = try c.register(.of(Press, &p, Press.on_key));

    // A key press, then the answer to the callback's own request; serve
    // handles the call, then sees the connection close.
    try f.call(cb.id, .key, false);
    try f.respond(&.{.{ .integer = 7 }}, null);
    _ = linux.shutdown(f.fd, linux.SHUT.WR);
    try testing.expectError(error.Closed, c.serve());

    try testing.expectEqual(@as(usize, 1), p.presses);
    try testing.expectEqual(Value{ .integer = 7 }, p.focused.?);
    try testing.expect((try f.recv()).request.commands[0] == .get_focused);
    const ret = (try f.recv()).ret;
    try testing.expectEqual(@as(?[]const u8, null), ret.err);
    try testing.expect(ret.commands[0] == .kill_client);
}

test "a call crossing a request is answered after the request" {
    var c, var f = try pair();
    defer teardown(&c, &f);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var p: Press = .{};
    const cb = try c.register(.of(Press, &p, Press.on_key));

    // On the wire, in order: a key press that crossed our get_zoom (not nested),
    // get_zoom's answer, then the answer to the press's own get_focused.
    try f.call(cb.id, .key, false);
    try f.respond(&.{.{ .number = 0.5 }}, null);
    try f.respond(&.{.{ .integer = 7 }}, null);

    try testing.expectEqual(Value{ .number = 0.5 }, try c.run_one(arena.allocator(), .get_zoom));
    try testing.expectEqual(Value{ .integer = 7 }, p.focused.?);
    try testing.expect((try f.recv()).request.commands[0] == .get_zoom);
    try testing.expect((try f.recv()).request.commands[0] == .get_focused);
    try testing.expect((try f.recv()) == .ret);
}

test "failing and unknown callbacks still answer" {
    var c, var f = try pair();
    defer teardown(&c, &f);
    const Fails = struct {
        fn on(_: *u8, _: *Client, _: CallArgs, _: Allocator) anyerror!Reply {
            return error.NotToday;
        }
    };
    var dummy: u8 = 0;
    const cb = try c.register(.of(u8, &dummy, Fails.on));

    try f.call(cb.id, .key, true);
    try f.call(999, .key, true);
    _ = linux.shutdown(f.fd, linux.SHUT.WR);
    try testing.expectError(error.Closed, c.serve());
    try testing.expectEqualStrings("NotToday", (try f.recv()).ret.err.?);
    try testing.expectEqualStrings("no such callback", (try f.recv()).ret.err.?);
}

test "dispatch answers what's waiting, and returns" {
    var c, var f = try pair();
    defer teardown(&c, &f);
    var p: Press = .{};
    const cb = try c.register(.of(Press, &p, Press.on_key));

    try c.dispatch(); // nothing waiting: returns at once
    try f.call(cb.id, .key, true);
    try f.respond(&.{.{ .integer = 7 }}, null);
    try c.dispatch();
    try testing.expectEqual(@as(usize, 1), p.presses);
    _ = linux.shutdown(f.fd, linux.SHUT.WR);
    try testing.expectError(error.Closed, c.dispatch());
}

/// A subscriber: counts its events, and answers a focus event with a command.
const Watch = struct {
    seen: usize = 0,
    last: ?protocol.Notice = null,

    fn on(w: *Watch, _: *Client, args: CallArgs, a: Allocator) anyerror!Reply {
        w.seen += 1;
        w.last = args.notice;
        if (args.notice.topic != .focus) return .{};
        return .{ .commands = try a.dupe(Command, &.{.get_zoom}) };
    }
};

test "an event is handled once the request it arrived during is answered, and isn't answered itself" {
    var c, var f = try pair();
    defer teardown(&c, &f);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var w: Watch = .{};
    const cb = try c.register(.of(Watch, &w, Watch.on));

    // An event first, then the response to the request: the event waits for it.
    try f.event(cb.id, .{ .topic = .scene, .serial = 3, .id = null });
    try f.respond(&.{.{ .integer = 1 }}, null);
    _ = try c.run_one(arena.allocator(), .get_zoom);
    try testing.expectEqual(@as(usize, 1), w.seen);
    try testing.expectEqual(@as(u64, 3), w.last.?.serial);
    try testing.expect((try f.recv()).request.commands[0] == .get_zoom); // only the request: no Return

    // From dispatch; its reply's commands go out as a request of their own.
    try f.event(cb.id, .{ .topic = .focus, .serial = 4, .id = 9 });
    try f.respond(&.{.{ .number = 1.0 }}, null);
    try c.dispatch();
    try testing.expectEqual(@as(?u32, 9), w.last.?.id);
    try testing.expect((try f.recv()).request.commands[0] == .get_zoom);

    // One for a callback nobody registered is dropped, silently.
    try f.event(999, .{ .topic = .names, .serial = 5, .id = 1 });
    try c.dispatch();
    try testing.expectEqual(@as(usize, 2), w.seen);
}
