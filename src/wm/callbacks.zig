const std = @import("std");
const ziglua = @import("ziglua");
const graph = @import("graph");
const types = @import("types");
const core = @import("core.zig");
const protocol = @import("protocol");
const command = @import("command.zig");
const ipc = @import("ipc.zig");
const settings = @import("settings.zig");
const luaconv = @import("luaconv.zig");
const layouts = @import("commands/layouts.zig");
const util = @import("commands/util.zig");
const output = @import("output.zig");

const wire = protocol.wire;
const WM = core.WM;
const Graph = graph.Graph;
const Callback = types.Callback;

pub const Rule = struct { id: u32, cb: Callback };

/// What a callback handed back besides running its commands (arrangers only).
pub const Reply = struct { layout: ?protocol.LayoutSpec = null, state: ?protocol.Value = null };

/// Run a callback, inside the caller's transaction. An error means it failed
/// (already reported); the caller rolls back.
pub fn invoke(wm: *WM, cb: Callback, call: protocol.CallArgs, a: std.mem.Allocator) !Reply {
    switch (cb) {
        .lua => |ref| return invoke_lua(wm, ref, call, a),
        .remote => |r| {
            const ret = try ipc.call(wm, r.client, r.id, call, a);
            return .{ .layout = ret.layout, .state = ret.state };
        },
    }
}

fn invoke_lua(self: *WM, ref: i32, call: protocol.CallArgs, a: std.mem.Allocator) !Reply {
    const lua = self.lua orelse return error.NoLua;
    const top = lua.getTop();
    _ = lua.getIndexRaw(ziglua.registry_index, ref);
    const nargs: i32, const nresults: i32 = switch (call) {
        .key => .{ 0, 0 },
        .rule => |r| blk: {
            _ = lua.pushString(r.event);
            lua.pushInteger(@intCast(r.id));
            break :blk .{ 2, 0 };
        },
        // (event, id, prev_id, snapshot) -> layout, state; old arrangers ignore
        // the snapshot and return nothing.
        .arranger => |s| blk: {
            _ = lua.pushString(@tagName(s.event));
            lua.pushInteger(@intCast(s.id));
            if (s.prev_id) |p| lua.pushInteger(@intCast(p)) else lua.pushNil();
            luaconv.push(lua, protocol.Snapshot, s);
            break :blk .{ 4, 2 };
        },
        .line => |l| blk: {
            _ = lua.pushString(l.text);
            break :blk .{ 1, 0 };
        },
        // Factories are called through instantiate, which takes the result.
        .factory => unreachable,
    };
    lua.protectedCall(.{ .args = nargs, .results = nresults }) catch |err| {
        const msg = lua.toString(-1) catch null;
        std.debug.print("{s} callback error: {} {s}\n", .{ @tagName(call), err, msg orelse "" });
        lua.setTop(top);
        return error.CallbackFailed;
    };
    defer lua.setTop(top);
    if (nresults == 0) return .{};

    const layout: ?protocol.LayoutSpec = if (lua.typeOf(-2) == .table)
        luaconv.read(protocol.LayoutSpec, lua, -2, a) catch |err| {
            std.debug.print("arranger returned an invalid layout: {s}\n", .{@errorName(err)});
            return error.CallbackFailed;
        }
    else
        null;
    const state: ?protocol.Value = if (lua.isNoneOrNil(-1))
        null
    else
        luaconv.to_value(lua, -1, a) catch |err| {
            std.debug.print("arranger returned an invalid state: {s}\n", .{@errorName(err)});
            return error.CallbackFailed;
        };
    return .{ .layout = layout, .state = state };
}

/// Call a factory (set_default_arranger's function) and keep the callback it returns.
pub fn instantiate(wm: *WM, factory: Callback, owner: *Graph) !Callback {
    const saved = wm.bind_owner;
    wm.bind_owner = owner;
    defer wm.bind_owner = saved;
    switch (factory) {
        .lua => |ref| {
            const lua = wm.lua orelse return error.NoLua;
            const top = lua.getTop();
            _ = lua.getIndexRaw(ziglua.registry_index, ref);
            lua.protectedCall(.{ .args = 0, .results = 1 }) catch |err| {
                std.debug.print("arranger factory error: {}\n", .{err});
                lua.setTop(top);
                return error.CallbackFailed;
            };
            if (lua.typeOf(-1) != .function) {
                std.debug.print("arranger factory did not return a function (got {})\n", .{lua.typeOf(-1)});
                lua.setTop(top);
                return error.CallbackFailed;
            }
            return .{ .lua = lua.ref(ziglua.registry_index) };
        },
        .remote => |r| {
            var arena = std.heap.ArenaAllocator.init(wm.allocator);
            defer arena.deinit();
            const ret = try ipc.call(wm, r.client, r.id, .factory, arena.allocator());
            const made = ret.callback orelse return error.CallbackFailed;
            return .{ .remote = .{ .client = r.client, .id = made } };
        },
    }
}

/// Drop a callback (its Lua function can then be collected).
pub fn release(wm: *WM, cb: Callback) void {
    switch (cb) {
        .lua => |ref| if (wm.lua) |lua| lua.unref(ziglua.registry_index, ref),
        .remote => {},
    }
}

pub fn call_rules(wm: *WM, event: [:0]const u8, node_id: u32) void {
    // By index: a rule may add rules, which can move the list.
    var i: usize = 0;
    while (i < wm.rules.items.len) : (i += 1) {
        const m = wm.tx_begin();
        var arena = std.heap.ArenaAllocator.init(wm.allocator);
        defer arena.deinit();
        _ = invoke(
            wm,
            wm.rules.items[i].cb,
            .{ .rule = .{ .event = event, .id = node_id } },
            arena.allocator(),
        ) catch {
            wm.tx_end(m, false);
            continue;
        };
        wm.tx_end(m, true);
    }
}

/// Call the arranger for graph (made from the default factory if it has none).
pub fn call_arranger(wm: *WM, g: *Graph, event: protocol.ArrangerEvent, node_id: u32, prev_id: ?u32) void {
    if (g.arranger == null and wm.default_arranger == null) return;
    const m = wm.tx_begin();
    if (g.arranger == null) {
        g.arranger = instantiate(wm, wm.default_arranger.?, g) catch return wm.tx_end(m, false);
    }
    var arena = std.heap.ArenaAllocator.init(wm.allocator);
    defer arena.deinit();
    run_arranger(wm, g, event, node_id, prev_id, arena.allocator()) catch return wm.tx_end(m, false);
    wm.tx_end(m, true);
}

fn run_arranger(wm: *WM, g: *Graph, event: protocol.ArrangerEvent, node_id: u32, prev_id: ?u32, a: std.mem.Allocator) !void {
    const cb = g.arranger.?;
    const snap = try snapshot(wm, g, event, node_id, prev_id, a);
    const reply = try invoke(wm, cb, .{ .arranger = snap }, a);
    if (reply.layout) |l| try layouts.apply(wm, g, l, a, .whole);
    if (reply.state) |s| try g.replace_bytes(&g.arranger_state, try wire.encode_value(a, s));
}

/// Everything an arranger needs for one event.
fn snapshot(wm: *WM, g: *Graph, event: protocol.ArrangerEvent, node_id: u32, prev_id: ?u32, a: std.mem.Allocator) !protocol.Snapshot {
    const wa = output.work_area_of(wm, g);
    // As get_cursor_relative_to_focused.
    var dx: i32 = 0;
    var dy: i32 = 0;
    if (wm.focused) |f| {
        const p = wm.backend.pointer_position();
        const c = util.center(f);
        dx = @intCast(p.x - c.x);
        dy = @intCast(p.y - c.y);
    }
    return .{
        .event = event,
        .id = node_id,
        .prev_id = prev_id,
        .work_area = .{ .x = @intCast(wa.x), .y = @intCast(wa.y), .width = @intCast(wa.width), .height = @intCast(wa.height) },
        .cursor_dx = dx,
        .cursor_dy = dy,
        .focused = if (wm.focused) |f| wm.get_id_for_node(f) else null,
        .windows = try layouts.tiled_windows(wm, g, a),
        .layout = try layouts.describe_spec(wm, g, a),
        .state = if (g.arranger_state.len > 0) try wire.decode_value(g.arranger_state, a) else null,
    };
}

/// The bind a press runs: the current workspace's before global ones, and
/// within each, a client's over the commands file's over the config's.
fn find_bind(wm: *WM, combo: types.KeyCombo) ?settings.Keybind {
    for ([_]?@TypeOf(wm.current_graph){ wm.current_graph, null }) |owner| {
        for ([_]settings.Layer{ .client, .commands, .config }) |layer| {
            if (wm.keybinds.get(.{ .combo = combo, .owner = owner, .layer = layer })) |kb| return kb;
        }
    }
    return null;
}

/// Run whatever is bound to combo, if anything.
pub fn handle_key(wm: *WM, combo: types.KeyCombo) void {
    const kb = find_bind(wm, combo) orelse return;
    switch (kb) {
        .zig => |action| action(wm) catch |err| {
            std.debug.print("Keybinding error: {}\n", .{err});
        },
        .call => |cb| {
            const m = wm.tx_begin();
            var arena = std.heap.ArenaAllocator.init(wm.allocator);
            defer arena.deinit();
            _ = invoke(wm, cb, .key, arena.allocator()) catch return wm.tx_end(m, false);
            wm.tx_end(m, true);
        },
        .commands => |cmd| {
            var arena = std.heap.ArenaAllocator.init(wm.allocator);
            defer arena.deinit();
            const a = arena.allocator();
            // Our own encoding, so it decodes; the decode copies, so a command
            // in the list may replace this very bind.
            const cmds = wire.decode_request(cmd.bytes, a) catch return;
            const results = a.alloc(protocol.Value, cmds.len) catch return;
            // As whoever made the bind: callbacks in it (set_arranger's factory) are theirs.
            const saved = wm.callback_source;
            wm.callback_source = cmd.source;
            defer wm.callback_source = saved;
            command.run(wm, cmds, a, results) catch |err|
                std.debug.print("keybind: {s}\n", .{command.error_text(err)});
        },
    }
}

fn owned_by(cb: Callback, client: u32) bool {
    return cb == .remote and cb.remote.client == client;
}

/// A client disconnected: its functions can't be called any more, so drop the
/// binds, rules and arrangers it gave. Its workspaces fall back to the default arranger.
pub fn drop_client(self: *WM, client: u32) void {
    var doomed: std.ArrayListUnmanaged(settings.BindKey) = .empty;
    defer doomed.deinit(self.allocator);
    var it = self.keybinds.iterator();
    while (it.next()) |e| {
        const owned = switch (e.value_ptr.*) {
            .call => |cb| owned_by(cb, client),
            .commands => |cmd| cmd.source == .client and cmd.source.client == client,
            .zig => false,
        };
        if (owned) doomed.append(self.allocator, e.key_ptr.*) catch {};
    }
    for (doomed.items) |key| self.remove_keybind(key);

    var i = self.rules.items.len;
    while (i > 0) {
        i -= 1;
        if (owned_by(self.rules.items[i].cb, client)) _ = self.rules.orderedRemove(i);
    }
    if (self.default_arranger) |cb| {
        if (owned_by(cb, client)) self.default_arranger = null;
    }
    for (self.outputs.items) |o| drop_arrangers(&o.root, client);

    if (self.prompt_cb) |cb| if (owned_by(cb, client)) {
        self.prompt_cb = null;
        self.backend.hide_prompt();
    };
}

fn drop_arrangers(g: *Graph, client: u32) void {
    if (g.arranger) |cb| {
        if (owned_by(cb, client)) {
            g.arranger = null;
            g.replace_bytes(&g.arranger_state, "") catch {};
        }
    }
    for (g.nodes.items) |node| {
        if (node.content == .workspace) drop_arrangers(node.content.workspace, client);
    }
}
