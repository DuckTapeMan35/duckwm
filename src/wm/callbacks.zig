const std = @import("std");
const ziglua = @import("ziglua");
const graph = @import("graph");
const types = @import("types");
const core = @import("core.zig");
const protocol = @import("protocol");
const command = @import("command.zig");
const ipc = @import("ipc.zig");
const settings = @import("settings.zig");

const wire = protocol.wire;
const WM = core.WM;
const Graph = graph.Graph;
const Callback = types.Callback;

pub const Rule = struct { id: u32, cb: Callback };

/// Run a callback, inside the caller's transaction. An error means it failed
/// (already reported); the caller rolls back.
pub fn invoke(wm: *WM, cb: Callback, call: protocol.CallArgs) !void {
    switch (cb) {
        .lua => |ref| try invoke_lua(wm, ref, call),
        .remote => |r| _ = try ipc.call(wm, r.client, r.id, call),
    }
}

fn invoke_lua(self: *WM, ref: i32, call: protocol.CallArgs) !void {
    const lua = self.lua orelse return error.NoLua;
    const top = lua.getTop();
    _ = lua.getIndexRaw(ziglua.registry_index, ref);
    const nargs: i32 = switch (call) {
        .key => 0,
        .rule => |r| blk: {
            _ = lua.pushString(r.event);
            lua.pushInteger(@intCast(r.id));
            break :blk 2;
        },
        .arranger => |a| blk: {
            _ = lua.pushString(a.event);
            lua.pushInteger(@intCast(a.id));
            if (a.prev_id) |p| lua.pushInteger(@intCast(p)) else lua.pushNil();
            break :blk 3;
        },
        // Factories are called through instantiate, which takes the result.
        .factory => unreachable,
    };
    lua.protectedCall(.{ .args = nargs, .results = 0 }) catch |err| {
        const msg = lua.toString(-1) catch null;
        std.debug.print("{s} callback error: {} {s}\n", .{ @tagName(call), err, msg orelse "" });
        lua.setTop(top);
        return error.CallbackFailed;
    };
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
            const made = (try ipc.call(wm, r.client, r.id, .factory)) orelse return error.CallbackFailed;
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
        invoke(wm, wm.rules.items[i].cb, .{ .rule = .{ .event = event, .id = node_id } }) catch {
            wm.tx_end(m, false);
            continue;
        };
        wm.tx_end(m, true);
    }
}

/// Call the arranger for graph (made from the default factory if it has none).
pub fn call_arranger(wm: *WM, g: *Graph, event: [:0]const u8, node_id: u32, prev_id: ?u32) void {
    if (g.arranger == null and wm.default_arranger == null) return;
    const m = wm.tx_begin();
    if (g.arranger == null) {
        g.arranger = instantiate(wm, wm.default_arranger.?, g) catch return wm.tx_end(m, false);
    }
    invoke(wm, g.arranger.?, .{ .arranger = .{ .event = event, .id = node_id, .prev_id = prev_id } }) catch
        return wm.tx_end(m, false);
    wm.tx_end(m, true);
}

/// Run whatever is bound to combo, if anything.
pub fn handle_key(wm: *WM, combo: types.KeyCombo) void {
    const kb = wm.keybinds.get(.{ .combo = combo, .owner = wm.current_graph }) orelse
        wm.keybinds.get(.{ .combo = combo, .owner = null }) orelse return;
    switch (kb) {
        .zig => |action| action(wm) catch |err| {
            std.debug.print("Keybinding error: {}\n", .{err});
        },
        .call => |cb| {
            const m = wm.tx_begin();
            invoke(wm, cb, .key) catch return wm.tx_end(m, false);
            wm.tx_end(m, true);
        },
        .commands => |bytes| {
            var arena = std.heap.ArenaAllocator.init(wm.allocator);
            defer arena.deinit();
            const a = arena.allocator();
            // Our own encoding, so it decodes; the decode copies, so a command
            // in the list may replace this very bind.
            const cmds = wire.decode_request(bytes, a) catch return;
            const results = a.alloc(protocol.Value, cmds.len) catch return;
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
        if (e.value_ptr.* == .call and owned_by(e.value_ptr.call, client))
            doomed.append(self.allocator, e.key_ptr.*) catch {};
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
    drop_arrangers(&self.graph, client);
}

fn drop_arrangers(g: *Graph, client: u32) void {
    if (g.arranger) |cb| {
        if (owned_by(cb, client)) g.arranger = null;
    }
    for (g.nodes.items) |node| {
        if (node.content == .workspace) drop_arrangers(node.content.workspace, client);
    }
}
