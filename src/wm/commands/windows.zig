const std = @import("std");
const graph_mod = @import("graph");
const core = @import("../core.zig");
const command = @import("../command.zig");
const util = @import("util.zig");
const WM = core.WM;
const Node = graph_mod.Node;
const Value = command.Value;
const Args = util.Args;
const Allocator = std.mem.Allocator;

// ---- focus and exchange ----
pub fn focus_left(wm: *WM, _: void, _: Allocator) !Value {
    try wm.focus_left();
    return .nil;
}

pub fn focus_right(wm: *WM, _: void, _: Allocator) !Value {
    try wm.focus_right();
    return .nil;
}

pub fn focus_up(wm: *WM, _: void, _: Allocator) !Value {
    try wm.focus_up();
    return .nil;
}

pub fn focus_down(wm: *WM, _: void, _: Allocator) !Value {
    try wm.focus_down();
    return .nil;
}

pub fn focus(wm: *WM, args: Args(.focus), _: Allocator) !Value {
    wm.set_focus(try util.node(wm, args.id));
    return .nil;
}

pub fn get_focused(wm: *WM, _: void, _: Allocator) !Value {
    const f = wm.focused orelse return .nil;
    return util.id_value(wm, f);
}

pub fn exchange_left(wm: *WM, _: void, _: Allocator) !Value {
    try wm.exchange_left();
    return .nil;
}

pub fn exchange_right(wm: *WM, _: void, _: Allocator) !Value {
    try wm.exchange_right();
    return .nil;
}

pub fn exchange_up(wm: *WM, _: void, _: Allocator) !Value {
    try wm.exchange_up();
    return .nil;
}

pub fn exchange_down(wm: *WM, _: void, _: Allocator) !Value {
    try wm.exchange_down();
    return .nil;
}

// ---- window state ----
pub fn kill_client(wm: *WM, _: void, _: Allocator) !Value {
    try wm.kill_client();
    return .nil;
}

pub fn toggle_floating(wm: *WM, _: void, _: Allocator) !Value {
    try wm.toggle_floating();
    return .nil;
}

pub fn toggle_fullscreen(wm: *WM, _: void, _: Allocator) !Value {
    try wm.toggle_fullscreen();
    return .nil;
}

pub fn set_floating(wm: *WM, args: Args(.set_floating), _: Allocator) !Value {
    const n = wm.get_node_by_id(args.id) orelse return .nil;
    if (n.content != .window) return .nil;
    try wm.set_floating(n, args.floating);
    wm.relayout();
    return .nil;
}

pub fn set_fullscreen(wm: *WM, args: Args(.set_fullscreen), _: Allocator) !Value {
    const n = wm.get_node_by_id(args.id) orelse return .nil;
    if (n.content != .window) return .nil;
    const already = if (n.owner_graph) |og| og.fullscreen_node == n else false;
    if (args.fullscreen == already) return .nil;
    wm.journal.set(wm, "focused", n);
    try wm.toggle_fullscreen();
    return .nil;
}

pub fn get_urgent(wm: *WM, args: Args(.get_urgent), _: Allocator) !Value {
    const n = wm.get_node_by_id(args.id) orelse return .{ .boolean = false };
    return .{ .boolean = n.urgent };
}

pub fn set_urgent(wm: *WM, args: Args(.set_urgent), _: Allocator) !Value {
    const n = wm.get_node_by_id(args.id) orelse return .nil;
    wm.journal.set(n, "urgent", args.urgent);
    try wm.flush(wm.current_graph);
    return .nil;
}

pub fn hide_window(wm: *WM, args: Args(.hide_window), _: Allocator) !Value {
    const n = wm.get_node_by_id(args.id) orelse return .nil;
    wm.journal.set(n, "hidden", true);
    if (n.window()) |h| wm.backend.hide_window(h);
    try wm.rebuild_focus_edges();
    return .nil;
}

pub fn show_window(wm: *WM, args: Args(.show_window), _: Allocator) !Value {
    const n = wm.get_node_by_id(args.id) orelse return .nil;
    wm.journal.set(n, "hidden", false);
    try wm.flush(wm.current_graph);
    if (n.window()) |h| wm.backend.raise_window(h);
    try wm.rebuild_focus_edges();
    wm.set_focus(n);
    return .nil;
}

// ---- window info ----
pub fn get_window_class(wm: *WM, args: Args(.get_window_class), arena: Allocator) !Value {
    const n = wm.get_node_by_id(args.id) orelse return .nil;
    if (n.content != .window) return .nil;
    return .{ .multi = try arena.dupe(Value, &.{
        try util.text(arena, n.info.class()),
        try util.text(arena, n.info.instance()),
    }) };
}

pub fn get_window_name(wm: *WM, args: Args(.get_window_name), arena: Allocator) !Value {
    const n = wm.get_node_by_id(args.id) orelse return .nil;
    if (n.content != .window) return .nil;
    return util.text(arena, n.info.title());
}

pub fn get_window_pid(wm: *WM, args: Args(.get_window_pid), _: Allocator) !Value {
    const n = wm.get_node_by_id(args.id) orelse return .nil;
    if (n.content != .window) return .nil;
    const pid = n.info.pid orelse return .nil;
    return .{ .integer = pid };
}

// ---- swallowing ----
pub fn register_swallow(wm: *WM, args: Args(.register_swallow), _: Allocator) !Value {
    const terminal = try wm.allocator.dupe(u8, args.terminal);
    errdefer wm.allocator.free(terminal);
    const child = try wm.allocator.dupe(u8, args.child);
    errdefer wm.allocator.free(child);
    try wm.swallow_pairs.append(wm.allocator, .{ .terminal = terminal, .child = child });
    return .nil;
}

pub fn unregister_swallow(wm: *WM, args: Args(.unregister_swallow), _: Allocator) !Value {
    var i: usize = 0;
    while (i < wm.swallow_pairs.items.len) {
        const p = wm.swallow_pairs.items[i];
        if (std.mem.eql(u8, p.terminal, args.terminal) and std.mem.eql(u8, p.child, args.child)) {
            wm.allocator.free(p.terminal);
            wm.allocator.free(p.child);
            _ = wm.swallow_pairs.swapRemove(i);
        } else i += 1;
    }
    return .nil;
}

// ---- scratchpad ----
pub fn scratchpad_toggle(wm: *WM, args: Args(.scratchpad_toggle), _: Allocator) !Value {
    try wm.toggle_scratchpad(args.id);
    return .nil;
}

pub fn scratchpad_show(wm: *WM, args: Args(.scratchpad_show), _: Allocator) !Value {
    try wm.show_scratchpad(args.id);
    return .nil;
}

pub fn scratchpad_hide(wm: *WM, args: Args(.scratchpad_hide), _: Allocator) !Value {
    try wm.hide_scratchpad(args.id);
    return .nil;
}

/// The nodes stashed in the scratchpad, oldest first.
pub fn get_scratchpad(wm: *WM, _: void, arena: Allocator) !Value {
    var out: std.ArrayListUnmanaged(Value) = .empty;
    for (wm.scratch_graph.nodes.items) |n| {
        if (n.content == .empty) continue;
        if (wm.get_id_for_node(n)) |id| try out.append(arena, .{ .integer = id });
    }
    return .{ .list = out.items };
}

// ---- rules ----
pub fn add_rule(wm: *WM, args: Args(.add_rule), _: Allocator) !Value {
    const cb = try util.callback(wm, args.callback);
    const id = wm.next_rule_id;
    try wm.rules.append(wm.allocator, .{ .id = id, .cb = cb });
    wm.next_rule_id += 1;
    return .{ .integer = id };
}

pub fn remove_rule(wm: *WM, args: Args(.remove_rule), _: Allocator) !Value {
    for (wm.rules.items, 0..) |r, i| {
        if (r.id != args.id) continue;
        wm.release_callback(r.cb);
        _ = wm.rules.orderedRemove(i);
        return .nil;
    }
    return error.UnknownRule;
}
