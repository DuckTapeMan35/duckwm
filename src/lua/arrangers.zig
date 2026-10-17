const std = @import("std");
const ziglua = @import("ziglua");
const util = @import("util.zig");
const Lua = ziglua.Lua;

// ---- transactions ----
pub fn l_transaction(lua: *Lua) i32 {
    lua.checkType(1, .function);
    const wm = util.global_wm;
    const tx = wm.tx_begin();
    lua.pushValue(1);
    lua.protectedCall(.{ .args = 0, .results = 1 }) catch {
        wm.tx_end(tx, false);
        lua.raiseError(); // re-raise the original error, already on the stack
    };
    // Returning false rolls back without being an error.
    const ok = !(lua.typeOf(-1) == .boolean and !lua.toBoolean(-1));
    lua.pop(1);
    wm.tx_end(tx, ok);
    lua.pushBoolean(ok);
    return 1;
}
