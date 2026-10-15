const std = @import("std");
const ziglua = @import("ziglua");
const graph_mod = @import("graph");
const types = @import("types");
const core = @import("core.zig");
const protocol = @import("protocol");
const command = @import("command.zig");

const wire = protocol.wire;
const WM = core.WM;
const Graph = graph_mod.Graph;

pub fn call_rules(self: *WM, event_str: [:0]const u8, node_id: u32) void {
    const lua = self.lua orelse return;
    for (self.rules.items) |ref| {
        const top = lua.getTop();
        const m = self.tx_begin();
        _ = lua.getIndexRaw(ziglua.registry_index, ref);
        _ = lua.pushString(event_str);
        lua.pushInteger(@intCast(node_id));
        lua.protectedCall(.{ .args = 2, .results = 0 }) catch |err| {
            const msg = lua.toString(-1) catch null;
            std.debug.print("rule error: {} {s}\n", .{ err, msg orelse "" });
            lua.setTop(top);
            self.tx_end(m, false);
            continue;
        };
        self.tx_end(m, true);
    }
}

// Call the arranger for graph (or the default) with the given event.
pub fn call_arranger(
    self: *WM,
    graph: *graph_mod.Graph,
    event_str: [:0]const u8,
    node_id: u32,
    prev_id: ?u32,
) void {
    const lua = self.lua orelse return;
    if (graph.arranger_ref == 0 and self.default_arranger_ref == 0) return;
    const top_before = lua.getTop();
    const m = self.tx_begin();

    if (graph.arranger_ref == 0) {
        _ = lua.getIndexRaw(ziglua.registry_index, self.default_arranger_ref);
        lua.protectedCall(.{ .args = 0, .results = 1 }) catch |err| {
            std.debug.print("arranger factory error: {}\n", .{err});
            lua.setTop(top_before);
            return self.tx_end(m, false);
        };
        if (lua.typeOf(-1) != .function) {
            std.debug.print("arranger factory did not return a function (got {})\n", .{lua.typeOf(-1)});
            lua.setTop(top_before);
            return self.tx_end(m, false);
        }
        graph.arranger_ref = lua.ref(ziglua.registry_index);
    }

    _ = lua.getIndexRaw(ziglua.registry_index, graph.arranger_ref);
    _ = lua.pushString(event_str);
    lua.pushInteger(@intCast(node_id));
    if (prev_id) |pid| lua.pushInteger(@intCast(pid)) else lua.pushNil();
    lua.protectedCall(.{ .args = 3, .results = 0 }) catch |err| {
        const lua_msg = lua.toString(-1) catch null;
        std.debug.print("arranger callback error: {} msg={s}\n", .{ err, lua_msg orelse "none" });
        lua.setTop(top_before);
        return self.tx_end(m, false);
    };
    self.tx_end(m, true);
}

/// Run whatever is bound to combo, if anything.
pub fn handle_key(self: *WM, combo: types.KeyCombo) void {
    const kb = self.keybinds.get(combo) orelse return;
    switch (kb) {
        .zig => |action| action(self) catch |err| {
            std.debug.print("Keybinding error: {}\n", .{err});
        },
        .lua => |ref| {
            const lua = self.lua orelse return;
            const top = lua.getTop();
            const m = self.tx_begin();
            _ = lua.getIndexRaw(ziglua.registry_index, ref);
            lua.protectedCall(.{ .args = 0, .results = 0 }) catch |err| {
                const msg = lua.toString(-1) catch null;
                std.debug.print("Lua keybinding error: {} {s}\n", .{ err, msg orelse "" });
                lua.setTop(top);
                return self.tx_end(m, false);
            };
            self.tx_end(m, true);
        },
        .commands => |bytes| {
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();
            const a = arena.allocator();
            // Our own encoding, so it decodes; the decode copies, so a command
            // in the list may replace this very bind.
            const cmds = wire.decode_request(bytes, a) catch return;
            const results = a.alloc(protocol.Value, cmds.len) catch return;
            command.run(self, cmds, a, results) catch |err|
                std.debug.print("keybind: {s}\n", .{command.error_text(err)});
        },
    }
}
