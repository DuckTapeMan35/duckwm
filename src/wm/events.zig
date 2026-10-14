const std = @import("std");
const types = @import("types");
const core = @import("core.zig");
const lifecycle = @import("lifecycle.zig");
const requests = @import("requests.zig");
const pointer = @import("pointer.zig");
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
            const size = wm.backend.screen_size();
            wm.screen_width = size.width;
            wm.screen_height = size.height;
            wm.relayout();
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
