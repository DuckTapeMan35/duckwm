const std = @import("std");
const graph_mod = @import("graph");
const WM = @import("core.zig").WM;

pub const NodeId = u32;

/// Result of a command. Small enough to serialize to Lua, JSON or protobuf.
pub const Value = union(enum) {
    nil,
    boolean: bool,
    integer: i64,
    number: f64,
    string: []const u8,
    list: []const Value,
    map: []const Field,

    pub const Field = struct { key: []const u8, value: Value };
};

/// One request. The payload's fields are the arguments, in order.
pub const Command = union(enum) {
    // focus
    focus_left,
    focus_right,
    focus_up,
    focus_down,
    focus: struct { id: NodeId },
    get_focused,

    // exchange
    exchange_left,
    exchange_right,
    exchange_up,
    exchange_down,

    // window state
    kill_client,
    toggle_floating,
    toggle_fullscreen,
};

/// Apply one command. Must be called inside a transaction.
/// arena holds anything the returned Value points to.
pub fn execute(wm: *WM, cmd: Command, arena: std.mem.Allocator) !Value {
    _ = arena;
    switch (cmd) {
        .focus_left => try wm.focus_left(),
        .focus_right => try wm.focus_right(),
        .focus_up => try wm.focus_up(),
        .focus_down => try wm.focus_down(),
        .focus => |a| wm.focus(wm.get_node_by_id(a.id) orelse return error.InvalidNode),
        .get_focused => {
            const f = wm.focused orelse return .nil;
            const id = wm.get_id_for_node(f) orelse return .nil;
            return .{ .integer = id };
        },

        .exchange_left => try wm.exchange_left(),
        .exchange_right => try wm.exchange_right(),
        .exchange_up => try wm.exchange_up(),
        .exchange_down => try wm.exchange_down(),

        .kill_client => try wm.kill_client(),
        .toggle_floating => try wm.toggle_floating(),
        .toggle_fullscreen => try wm.toggle_fullscreen(),
    }
    return .nil;
}

pub const RunError = error{Rejected};

/// Run commands as one transaction: all of them take effect, or none do.
/// results must be at least as long as cmds.
pub fn run(wm: *WM, cmds: []const Command, arena: std.mem.Allocator, results: []Value) !void {
    const tx = wm.tx_begin();
    for (cmds, 0..) |c, i| {
        results[i] = execute(wm, c, arena) catch |err| {
            wm.tx_end(tx, false);
            return err;
        };
    }
    if (!wm.tx_finish(tx, true)) return error.Rejected;
}
