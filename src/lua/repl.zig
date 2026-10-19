const std = @import("std");
const ziglua = @import("ziglua");
const wm_mod = @import("wm");
const protocol = @import("protocol");
const Lua = ziglua.Lua;
const WM = wm_mod.WM;
const Value = protocol.Value;

/// Where the evaluator lives, in the registry.
const registry_key = "duckwm.repl";

/// Put the evaluator in a new VM's registry. setup_lua calls this.
pub fn install(lua: *Lua) void {
    lua.loadBuffer(@embedFile("repl.lua"), "=duckwm/repl.lua", .text) catch {
        std.debug.print("repl: {s}\n", .{lua.toString(-1) catch "failed to load"});
        lua.pop(1);
        return;
    };
    lua.protectedCall(.{ .results = 1 }) catch {
        std.debug.print("repl: {s}\n", .{lua.toString(-1) catch "failed to run"});
        lua.pop(1);
        return;
    };
    lua.setField(ziglua.registry_index, registry_key);
}

/// Run src; { status = "ok" | "error" | "incomplete", output = text }.
/// A Lua error is a result, not a failed command: what the snippet did
/// before failing stays done, as in any REPL.
pub fn eval(wm: *WM, src: []const u8, arena: std.mem.Allocator) !Value {
    const lua = wm.lua orelse return error.NoLua;
    const top = lua.getTop();
    defer lua.setTop(top);
    if (lua.getField(ziglua.registry_index, registry_key) != .function) return error.NoLua;
    _ = lua.pushString(src);
    lua.protectedCall(.{ .args = 1, .results = 2 }) catch return error.EvalFailed;
    const fields = try arena.alloc(Value.Field, 2);
    fields[0] = .{ .key = "status", .value = .{ .str = try arena.dupe(u8, lua.toString(-2) catch "error") } };
    fields[1] = .{ .key = "output", .value = .{ .str = try arena.dupe(u8, lua.toString(-1) catch "") } };
    return .{ .map = fields };
}
