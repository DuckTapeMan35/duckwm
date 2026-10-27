const std = @import("std");
const ziglua = @import("ziglua");
const wm_mod = @import("wm");
const util = @import("util.zig");
const Lua = ziglua.Lua;
const scopes = wm_mod.scopes;

/// wm.within(path, fn): run fn with the binds it makes applying only with
/// focus in path. Nested, paths add up: within("DP-1", ...) around
/// within("web", ...) is "DP-1/web".
pub fn l_within(lua: *Lua) i32 {
    const wm = util.global_wm;
    const path = lua.checkString(1);
    lua.checkType(2, .function);

    const outer = wm.lua_scope;
    const prefix = scopes.path_of(wm, outer);
    var buf: [1024]u8 = undefined;
    const full = if (prefix.len == 0)
        path
    else
        std.fmt.bufPrint(&buf, "{s}/{s}", .{ prefix, path }) catch util.luaL_error_str(lua, "within: path too long");
    const inner = scopes.intern(wm, full) catch |err| util.raise_with(lua, "within: ", @errorName(err));

    wm.lua_scope = inner;
    lua.pushValue(2);
    const failed = if (lua.protectedCall(.{ .args = 0, .results = 0 })) |_| false else |_| true;
    wm.lua_scope = outer;
    if (failed) lua.raiseError(); // fn's own error, already on the stack
    return 0;
}
