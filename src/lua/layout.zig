const std = @import("std");
const ziglua = @import("ziglua");
const util = @import("util.zig");
const bridge = @import("bridge.zig");
const Lua = ziglua.Lua;

/// The get_layout command's result, plus by_id: the same node tables keyed
/// by id, so edits through either one are what set_layout reads back.
pub fn l_get_layout(lua: *Lua) i32 {
    var arena = std.heap.ArenaAllocator.init(util.global_wm.allocator);
    _ = bridge.run_and_push(lua, .get_layout, {}, &arena);

    lua.newTable(); // by_id
    _ = lua.getField(-2, "nodes");
    const len = lua.lenRaw(-1);
    for (1..len + 1) |k| {
        _ = lua.getIndexRaw(-1, @intCast(k)); // layout, by_id, nodes, node
        _ = lua.getField(-1, "id");
        const id = lua.toInteger(-1) catch 0;
        lua.pop(1);
        lua.setIndexRaw(-3, id); // by_id[id] = node
    }
    lua.pop(1); // nodes
    lua.setField(-2, "by_id");
    return 1;
}
