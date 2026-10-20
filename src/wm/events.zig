const std = @import("std");
const graph = @import("graph");
const types = @import("types");
const core = @import("core.zig");
const lifecycle = @import("lifecycle.zig");
const requests = @import("requests.zig");
const pointer = @import("pointer.zig");
const input_bar = @import("input_bar.zig");
const output = @import("output.zig");
const WM = core.WM;

pub fn handle_event(wm: *WM, ev: types.Event) void {
    const m = wm.tx_begin();
    wm.tx_end(m, dispatch(wm, ev));
}

/// false: the handler failed, roll the event back.
fn dispatch(wm: *WM, ev: types.Event) bool {
    switch (ev) {
        .key => |k| wm.handle_key(k),
        .expose => |h| window_exposed(wm, h),
        .keymap_changed => wm.regrab_keys(),
        .reserved_area_changed => {
            output.sync(wm) catch |err| std.debug.print("outputs: {}\n", .{err});
            for (wm.outputs.items) |o| {
                const resized = o.usable.width != o.arranged.width or o.usable.height != o.arranged.height;
                o.arranged = o.usable;
                if (resized) rearrange_all(wm, &o.root);
                const g = output.visible(wm, o);
                wm.resolve(g) catch {};
                wm.flush(g) catch {};
            }
            wm.rebuild_focus_edges() catch {};
        },
        .map_request => |req| lifecycle.window_mapped(wm, req) catch |err| {
            std.debug.print("map_request: {}\n", .{err});
            return false;
        },
        .window_gone => |h| lifecycle.window_gone(wm, h) catch |err| {
            std.debug.print("window_gone: {}\n", .{err});
            return false;
        },
        .refocus => if (wm.focused) |n| wm.set_focus(n),
        .info_changed => |h| requests.info_changed(wm, h),
        .urgency_hint => |hint| requests.urgency_hint(wm, hint),
        .became_dock => |h| wm.unmanage_as_dock(h) catch |err| {
            std.debug.print("became_dock: {}\n", .{err});
            return false;
        },
        .activate_request => |h| requests.activate(wm, h),
        .state_request => |r| requests.state_request(wm, r) catch |err| {
            std.debug.print("state_request: {}\n", .{err});
            return false;
        },
        .button_press => |b| pointer.button_press(wm, b),
        .button_release => pointer.button_release(wm),
        .pointer_motion => |p| pointer.motion(wm, p),
        .pointer_enter => |h| pointer.enter(wm, h),
        .prompt_key => |k| input_bar.key(wm, k),
    }
    return true;
}

/// Part of a window became visible again: repaint what duckwm draws on it.
fn window_exposed(wm: *WM, h: types.WindowHandle) void {
    const id = wm.window_to_node_id.get(h) orelse return;
    const node = wm.node_registry.get(id) orelse return;
    wm.paint_borders(node, null);
    if (node.content == .workspace) wm.repaint_preview(node);
}

/// The work area changed size: every workspace's arranger lays it out again
/// (layouts pin their root to the work area they were given).
fn rearrange_all(wm: *WM, g: *graph.Graph) void {
    if (g.arranger != null) {
        const saved = wm.current_graph;
        wm.current_graph = g;
        defer wm.current_graph = saved;
        const id: u32 = if (wm.focused) |f| wm.get_id_for_node(f) orelse 0 else 0;
        wm.call_arranger(g, .area, id, null);
        wm.resolve(g) catch {};
    }
    for (g.nodes.items) |node| {
        if (node.content == .workspace) rearrange_all(wm, node.content.workspace);
    }
}
