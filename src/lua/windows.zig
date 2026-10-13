const std = @import("std");
const ziglua = @import("ziglua");
const graph_mod = @import("graph");
const wm_mod = @import("wm");
const util = @import("util.zig");
const Lua = ziglua.Lua;
const Node = graph_mod.Node;
const WM = wm_mod.WM;

// ---- window info ----
pub fn l_get_window_class(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse {
        lua.pushNil();
        return 1;
    };
    if (node.content != .window) {
        lua.pushNil();
        return 1;
    }
    const info = &node.info;
    if (info.class_len == 0) lua.pushNil() else _ = lua.pushString(info.class());
    if (info.instance_len == 0) lua.pushNil() else _ = lua.pushString(info.instance());
    return 2;
}

pub fn l_get_window_name(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse {
        lua.pushNil();
        return 1;
    };
    if (node.content != .window or node.info.title_len == 0) {
        lua.pushNil();
        return 1;
    }
    _ = lua.pushString(node.info.title());
    return 1;
}

pub fn l_get_window_pid(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse {
        lua.pushNil();
        return 1;
    };
    const pid = if (node.content == .window) node.info.pid else null;
    if (pid) |p| lua.pushInteger(@intCast(p)) else lua.pushNil();
    return 1;
}

// ---- floating and fullscreen ----
pub fn l_set_floating(lua: *Lua) i32 {
    const id = util.check_node_id(lua, 1) orelse return 0;
    const val = lua.toBoolean(2);
    const wm = util.global_wm;
    const node = wm.get_node_by_id(id) orelse return 0;
    if (node.content != .window or node.floating == val) return 0;
    const g = node.owner_graph orelse return 0;

    g.replace_constraints(node, &.{}) catch util.luaL_error_str(lua, "set_floating: out of memory");
    if (val) {
        wm.call_arranger(wm.current_graph, "unmap", id, null);
        wm.journal.set(node, "floating", true);
        wm.center_node(node);
    } else {
        wm.journal.set(node, "floating", false);
        const prev_id: ?u32 = if (wm.focused) |f|
            (if (f != node) wm.get_id_for_node(f) else null)
        else
            null;
        wm.call_arranger(wm.current_graph, "map", id, prev_id);
    }
    wm.relayout();
    return 0;
}

pub fn l_set_fullscreen(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse return 0;
    const val = lua.toBoolean(2);
    if (node.content != .window) return 0;
    const already = if (node.owner_graph) |og| og.fullscreen_node == node else false;
    if (val == already) return 0;
    const wm = util.global_wm;
    wm.journal.set(wm, "focused", node);
    wm.toggle_fullscreen() catch {};
    return 0;
}

// ---- urgency ----
pub fn l_get_urgent(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse {
        lua.pushBoolean(false);
        return 1;
    };
    lua.pushBoolean(node.urgent);
    return 1;
}

pub fn l_set_urgent(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse return 0;
    util.global_wm.journal.set(node, "urgent", lua.toBoolean(2));
    util.global_wm.flush(util.global_wm.current_graph) catch {};
    return 0;
}

// ---- visibility ----
pub fn l_hide_window(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse return 0;
    const wm = util.global_wm;
    wm.journal.set(node, "hidden", true);
    if (WM.node_window(node)) |h| wm.backend.hide_window(h);
    wm.rebuild_focus_edges() catch {};
    return 0;
}

pub fn l_show_window(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse return 0;
    const wm = util.global_wm;
    wm.journal.set(node, "hidden", false);
    wm.flush(wm.current_graph) catch {};
    if (WM.node_window(node)) |h| wm.backend.raise_window(h);
    wm.rebuild_focus_edges() catch {};
    wm.focus(node);
    return 0;
}

// ---- swallowing ----
pub fn l_register_swallow(lua: *Lua) i32 {
    const term = lua.checkString(1);
    const child = lua.checkString(2);
    const wm = util.global_wm;
    const term_owned = wm.allocator.dupe(u8, term) catch
        util.luaL_error_str(lua, "register_swallow: out of memory");
    const child_owned = wm.allocator.dupe(u8, child) catch {
        wm.allocator.free(term_owned);
        util.luaL_error_str(lua, "register_swallow: out of memory");
    };
    wm.swallow_pairs.append(wm.allocator, .{ .terminal = term_owned, .child = child_owned }) catch {
        wm.allocator.free(term_owned);
        wm.allocator.free(child_owned);
        util.luaL_error_str(lua, "register_swallow: out of memory");
    };
    return 0;
}

pub fn l_unregister_swallow(lua: *Lua) i32 {
    const term = lua.checkString(1);
    const child = lua.checkString(2);
    const wm = util.global_wm;
    var i: usize = 0;
    while (i < wm.swallow_pairs.items.len) {
        const p = wm.swallow_pairs.items[i];
        if (std.mem.eql(u8, p.terminal, term) and std.mem.eql(u8, p.child, child)) {
            wm.allocator.free(p.terminal);
            wm.allocator.free(p.child);
            _ = wm.swallow_pairs.swapRemove(i);
        } else i += 1;
    }
    return 0;
}

// ---- scratchpad ----
pub fn l_scratchpad_toggle(lua: *Lua) i32 {
    const id = util.check_node_id(lua, 1) orelse return 0;
    util.global_wm.toggle_scratchpad(id) catch {};
    return 0;
}

pub fn l_scratchpad_show(lua: *Lua) i32 {
    const id = util.check_node_id(lua, 1) orelse return 0;
    util.global_wm.show_scratchpad(id) catch {};
    return 0;
}

pub fn l_scratchpad_hide(lua: *Lua) i32 {
    const id = util.check_node_id(lua, 1) orelse return 0;
    util.global_wm.hide_scratchpad(id) catch {};
    return 0;
}
