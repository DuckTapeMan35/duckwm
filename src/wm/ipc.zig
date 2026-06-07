const std = @import("std");
const ziglua = @import("ziglua");
const WM = @import("core.zig").WM;

fn close_fd(fd: i32) void {
    _ = std.os.linux.close(fd);
}

fn delete_socket(path: []const u8) void {
    var buf: [4096:0]u8 = undefined;
    if (path.len >= buf.len) return;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    _ = std.os.linux.unlink(&buf);
}

pub fn init(wm: *WM) !void {
    const path = try get_path(wm.allocator);
    defer wm.allocator.free(path);

    delete_socket(path);

    const fd: i32 = @intCast(std.os.linux.socket(
        std.os.linux.AF.UNIX,
        std.os.linux.SOCK.STREAM | std.os.linux.SOCK.NONBLOCK | std.os.linux.SOCK.CLOEXEC,
        0,
    ));
    if (fd < 0) return error.SocketFailed;
    errdefer close_fd(fd);

    var addr = std.mem.zeroes(std.os.linux.sockaddr.un);
    addr.family = std.os.linux.AF.UNIX;
    if (path.len >= addr.path.len) return error.PathTooLong;
    @memcpy(addr.path[0..path.len], path);

    const bind_rc = std.os.linux.bind(fd, @ptrCast(&addr), @sizeOf(std.os.linux.sockaddr.un));
    if (bind_rc != 0) return error.BindFailed;

    const listen_rc = std.os.linux.listen(fd, 8);
    if (listen_rc != 0) return error.ListenFailed;

    wm.ipc_fd = fd;
    std.debug.print("IPC socket at {s}\n", .{path});
}

pub fn deinit(wm: *WM) void {
    if (wm.ipc_fd >= 0) {
        close_fd(wm.ipc_fd);
        wm.ipc_fd = -1;
    }
    for (wm.ipc_clients.items) |fd| close_fd(fd);
    wm.ipc_clients.deinit(wm.allocator);

    const path = get_path(wm.allocator) catch return;
    defer wm.allocator.free(path);
    delete_socket(path);
}

pub fn get_path(allocator: std.mem.Allocator) ![]u8 {
    if (std.c.getenv("XDG_RUNTIME_DIR")) |dir| {
        return std.fmt.allocPrint(allocator, "{s}/duckwm.sock", .{std.mem.span(dir)});
    }
    return std.fmt.allocPrint(allocator, "/tmp/duckwm-{d}.sock", .{std.os.linux.getuid()});
}

pub fn accept_clients(wm: *WM) void {
    while (true) {
        const rc: isize = @bitCast(std.os.linux.accept(wm.ipc_fd, null, null));
        if (rc < 0) return;
        const fd: i32 = @intCast(rc);
        wm.ipc_clients.append(wm.allocator, fd) catch {
            close_fd(fd);
        };
    }
}

pub fn handle_clients(wm: *WM) void {
    var i: usize = 0;
    while (i < wm.ipc_clients.items.len) {
        const fd = wm.ipc_clients.items[i];
        const keep = handle_client(wm, fd);
        if (keep) {
            i += 1;
        } else {
            close_fd(fd);
            _ = wm.ipc_clients.swapRemove(i);
        }
    }
}

fn read_fd(fd: i32, buf: []u8) isize {
    return @bitCast(std.os.linux.read(fd, buf.ptr, buf.len));
}

fn write_fd(fd: i32, buf: []const u8) void {
    _ = std.os.linux.sendto(fd, buf.ptr, buf.len, std.os.linux.MSG.NOSIGNAL, null, 0);
}

fn handle_client(wm: *WM, fd: i32) bool {
    var buf: [4096]u8 = undefined;
    const n = read_fd(fd, &buf);
    if (n <= 0) return false;

    const msg = std.mem.trim(u8, buf[0..@intCast(n)], "\n\r ");
    if (msg.len == 0) return false;

    const response = execute_command(wm, msg) catch |err| blk: {
        break :blk std.fmt.allocPrint(wm.allocator,
            "{{\"ok\":false,\"error\":\"{s}\"}}\n", .{@errorName(err)}) catch return false;
    };
    defer wm.allocator.free(response);

    write_fd(fd, response);
    return false;
}

fn execute_command(wm: *WM, msg: []const u8) ![]u8 {
    const lua = wm.lua orelse return error.LuaNotInitialized;

    var it = std.mem.tokenizeScalar(u8, msg, ' ');
    const fn_name = it.next() orelse return error.EmptyCommand;

    var fn_name_buf: [256:0]u8 = undefined;
    if (fn_name.len >= fn_name_buf.len) return error.CommandTooLong;
    @memcpy(fn_name_buf[0..fn_name.len], fn_name);
    fn_name_buf[fn_name.len] = 0;
    const fn_name_z: [:0]const u8 = fn_name_buf[0..fn_name.len :0];

    _ = lua.getGlobal("wm");
    const field_type = lua.getField(-1, fn_name_z);
    if (field_type != .function) {
        lua.pop(2);
        return error.UnknownCommand;
    }
    lua.remove(-2);

    var argc: i32 = 0;
    const is_table_cmd = std.mem.eql(u8, fn_name, "spawn") or std.mem.eql(u8, fn_name, "exec_once");

    if (is_table_cmd) {
        lua.newTable();
        var table_idx: i32 = 1;
        while (it.next()) |arg| {
            _ = lua.pushString(arg);
            lua.setIndexRaw(-2, table_idx);
            table_idx += 1;
        }
        argc = 1;
    } else {
        while (it.next()) |arg| {
            if (std.fmt.parseInt(i64, arg, 10)) |n| {
                lua.pushInteger(n);
            } else |_| {
                if (std.mem.eql(u8, arg, "true")) {
                    lua.pushBoolean(true);
                } else if (std.mem.eql(u8, arg, "false")) {
                    lua.pushBoolean(false);
                } else {
                    _ = lua.pushString(arg);
                }
            }
            argc += 1;
        }
    }

    const top_before = lua.getTop() - argc - 1;
    lua.protectedCall(.{ .args = argc, .results = ziglua.mult_return }) catch |err| {
        const lua_msg = lua.toString(-1) catch null;
        const emsg = lua_msg orelse @errorName(err);
        const owned = try std.fmt.allocPrint(wm.allocator,
            "{{\"ok\":false,\"error\":\"{s}\"}}\n", .{emsg});
        lua.setTop(top_before);
        return owned;
    };

    const nresults = lua.getTop() - top_before;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(wm.allocator);

    try out.appendSlice(wm.allocator, "{\"ok\":true,\"result\":");
    if (nresults == 0) {
        try out.appendSlice(wm.allocator, "null");
    } else if (nresults == 1) {
        try lua_value_to_json(wm.allocator, lua, -1, &out);
    } else {
        try out.append(wm.allocator, '[');
        for (0..@intCast(nresults)) |i| {
            if (i > 0) try out.append(wm.allocator, ',');
            try lua_value_to_json(wm.allocator, lua, @intCast(@as(i32, @intCast(i)) - nresults), &out);
        }
        try out.append(wm.allocator, ']');
    }
    try out.appendSlice(wm.allocator, "}\n");
    lua.setTop(top_before);

    return out.toOwnedSlice(wm.allocator);
}

fn lua_value_to_json(allocator: std.mem.Allocator, lua: *ziglua.Lua, idx: i32, out: *std.ArrayListUnmanaged(u8)) !void {
    switch (lua.typeOf(idx)) {
        .nil => try out.appendSlice(allocator, "null"),
        .boolean => try out.appendSlice(allocator, if (lua.toBoolean(idx)) "true" else "false"),
        .number => {
            if (lua.toInteger(idx)) |n| {
                try out.print(allocator, "{d}", .{n});
            } else |_| {
                const f = lua.toNumber(idx) catch 0.0;
                try out.print(allocator, "{d}", .{f});
            }
        },
        .string => {
            const s = lua.toString(idx) catch "";
            try out.append(allocator, '"');
            for (s) |ch| {
                switch (ch) {
                    '"'  => try out.appendSlice(allocator, "\\\""),
                    '\\' => try out.appendSlice(allocator, "\\\\"),
                    '\n' => try out.appendSlice(allocator, "\\n"),
                    '\r' => try out.appendSlice(allocator, "\\r"),
                    '\t' => try out.appendSlice(allocator, "\\t"),
                    else => try out.append(allocator, ch),
                }
            }
            try out.append(allocator, '"');
        },
        .table => {
            const len = lua.lenRaw(idx);
            if (len > 0) {
                try out.append(allocator, '[');
                for (1..len + 1) |i| {
                    if (i > 1) try out.append(allocator, ',');
                    _ = lua.getIndexRaw(idx, @intCast(i));
                    try lua_value_to_json(allocator, lua, -1, out);
                    lua.pop(1);
                }
                try out.append(allocator, ']');
            } else {
                // Check if it has any string keys — if not, treat as empty array
                lua.pushNil();
                const has_keys = lua.next(if (idx < 0) idx - 1 else idx);
                if (has_keys) {
                    lua.pop(2); // pop key and value
                    // re-serialize as object
                    try out.append(allocator, '{');
                    var first = true;
                    lua.pushNil();
                    while (lua.next(if (idx < 0) idx - 1 else idx)) {
                        if (!first) try out.append(allocator, ',');
                        first = false;
                        try out.append(allocator, '"');
                        const key = lua.toString(-2) catch "?";
                        try out.appendSlice(allocator, key);
                        try out.appendSlice(allocator, "\":");
                        try lua_value_to_json(allocator, lua, -1, out);
                        lua.pop(1);
                    }
                    try out.append(allocator, '}');
                } else {
                    try out.appendSlice(allocator, "[]");
                }
            }
        },
        else => try out.appendSlice(allocator, "null"),
    }
}
