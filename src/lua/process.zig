const ziglua = @import("ziglua");
const util = @import("util.zig");
const Lua = ziglua.Lua;

pub fn l_exec_once(lua: *Lua) i32 {
    if (util.global_wm.startup_done) return 0;
    return spawn_from_table(lua, "exec_once");
}

/// argv as a Lua table of strings at index 1.
fn spawn_from_table(lua: *Lua, comptime name: []const u8) i32 {
    lua.checkType(1, .table);
    const len = lua.lenRaw(1);
    const wm = util.global_wm;
    const args = wm.allocator.alloc([]const u8, len) catch
        util.luaL_error_str(lua, name ++ ": out of memory");
    for (0..len) |i| {
        _ = lua.getIndexRaw(1, @intCast(i + 1));
        args[i] = lua.toString(-1) catch {
            wm.allocator.free(args);
            util.luaL_error_str(lua, name ++ ": expected string in argv table");
        };
        lua.pop(1);
    }
    // Strings are copied into the queued effect, so args can go right after.
    const result = wm.spawn(args);
    wm.allocator.free(args);
    result catch util.luaL_error_str(lua, name ++ ": failed to spawn process");
    return 0;
}
