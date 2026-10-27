const std = @import("std");
const graph_mod = @import("graph");
const core = @import("core.zig");
const types = @import("types");
const layouts = @import("./commands/layouts.zig");
const navigation = @import("navigation.zig");
const protocol = @import("protocol");

pub const CommandId = protocol.CommandId;
pub const Command = protocol.Command;
pub const Value = protocol.Value;
pub const NodeId = protocol.NodeId;
pub const One = protocol.One;
pub const Pair = protocol.Pair;
pub const Axis = protocol.Axis;
pub const Dir = protocol.Dir;
pub const Side = protocol.Side;
pub const Gaps = protocol.Gaps;
pub const ReparentStrategy = protocol.ReparentStrategy;
pub const ConstraintKind = protocol.ConstraintKind;
const WM = core.WM;
const Node = graph_mod.Node;
const Constraint = graph_mod.Constraint;

const handlers = .{
    @import("commands/windows.zig"),
    @import("commands/constraints.zig"),
    @import("commands/nodes.zig"),
    @import("commands/view.zig"),
    @import("commands/input.zig"),
    @import("commands/appearance.zig"),
    @import("commands/workspaces.zig"),
    @import("commands/system.zig"),
    @import("commands/layouts.zig"),
    @import("commands/arrangers.zig"),
    @import("commands/outputs.zig"),
    @import("commands/groups.zig"),
    @import("commands/diagram.zig"),
    @import("commands/subscriptions.zig"),
};
comptime {
    for (@typeInfo(ConstraintKind).@"enum".field_names) |f_name| {
        if (!@hasField(Constraint, f_name)) @compileError("ConstraintKind." ++ f_name ++ " is not a constraint");
    }
    for (@typeInfo(Constraint).@"union".field_names) |f_name| {
        if (!@hasField(ConstraintKind, f_name)) @compileError("constraint " ++ f_name ++ " is missing from ConstraintKind");
    }
}

fn count_handlers(comptime name: []const u8) usize {
    @setEvalBranchQuota(100000);
    comptime var n: usize = 0;
    inline for (handlers) |m| {
        if (@hasDecl(m, name)) n += 1;
    }
    return n;
}

/// The handler file that defines `pub fn <name>`.
fn module_for(comptime name: []const u8) type {
    @setEvalBranchQuota(100000);
    inline for (handlers) |m| {
        if (@hasDecl(m, name)) return m;
    }
    unreachable;
}

/// Apply one command. Must be called inside a transaction.
/// arena holds anything the returned Value points to.
pub fn execute(wm: *WM, cmd: Command, arena: std.mem.Allocator) !Value {
    switch (cmd) {
        inline else => |args, tag| {
            const name = @tagName(tag);
            if (comptime count_handlers(name) != 1)
                @compileError("command '" ++ name ++ "' needs exactly one handler, in one of the files in `handlers`");
            return @field(module_for(name), name)(wm, args, arena);
        },
    }
}

pub const RunError = error{Rejected};

pub fn error_text(err: anyerror) []const u8 {
    return switch (err) {
        error.Rejected => "the result was invalid, so nothing was changed",
        error.InvalidNode => "no such node",
        error.NotFloating => "node is not floating",
        error.NotInGraph => "node is not in a graph",
        error.InvalidGridCell => "cols and rows must be positive and the cell inside the grid",
        error.InvalidSplit => "split needs 1-16 children, one positive ratio each",
        error.NotAContainer => "node is not a container",
        error.InvalidButton => "button must be between 1 and 255",
        error.InvalidKeymap => "invalid layout, variant, options or model",
        error.NotAWorkspace => "node is not a workspace or group",
        error.EmptyArgv => "argv must contain at least the program name",
        error.SetenvFailed => "invalid variable name",
        error.UnknownKey => "unknown key name",
        error.EmptyBind => "a bind needs at least one command",
        error.InvalidCallback => "invalid callback",
        error.UnknownRule => "no such rule",
        error.InvalidCurve => "bezier x1 and x2 must be within 0..1; samples need 2 or more finite values",
        error.NoCallbackHost => "a function can't be passed from here",
        error.CallbackTimeout => "the client's callback didn't return in time",
        error.ClientGone => "the client that owns the callback has disconnected",
        error.CallbackFailed => "the callback failed",
        error.NoLua => "duckwm has no Lua VM",
        error.EvalFailed => "the REPL's evaluator failed",
        error.InvalidZoom => "zoom must be between 0 (fit) and 1",
        error.NotAGroup => "node is not a group",
        error.NotSameGraph => "group members must be in the same workspace or group",
        error.TooDeep => "groups nest at most 15 deep",
        error.UnknownSubscription => "no such subscription",
        else => @errorName(err),
    };
}

/// Run commands as one transaction: all of them take effect, or none do.
/// results must be at least as long as cmds.
pub fn run(wm: *WM, cmds: []const Command, arena: std.mem.Allocator, results: []Value) !void {
    const tx = wm.tx_begin();
    for (cmds, 0..) |cmd, i| {
        results[i] = execute(wm, cmd, arena) catch |err| {
            wm.tx_end(tx, false);
            return err;
        };
    }
    if (!wm.tx_finish(tx, true)) return error.Rejected;
}
