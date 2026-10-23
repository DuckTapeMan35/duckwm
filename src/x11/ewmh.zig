const std = @import("std");
const info = @import("info.zig");
const util = @import("util.zig");
const c = @import("xlib");
const types = @import("types");
const Backend = @import("backend.zig").Backend;

comptime {
    if (@sizeOf(c_ulong) != @sizeOf(types.WindowHandle))
        @compileError("window_list assumes WindowHandle has the size of c_ulong");
}

/// A WM_PROTOCOLS message (WM_DELETE_WINDOW, WM_TAKE_FOCUS) to win.
pub fn send_protocol(self: *const Backend, win: c.Window, proto: c.Atom) void {
    var ev: c.XEvent = std.mem.zeroes(c.XEvent);
    ev.xclient.type = c.ClientMessage;
    ev.xclient.window = win;
    ev.xclient.message_type = self.atoms.WM_PROTOCOLS;
    ev.xclient.format = 32;
    ev.xclient.data.l[0] = @intCast(proto);
    ev.xclient.data.l[1] = c.CurrentTime;
    _ = c.XSendEvent(self.display, win, 0, c.NoEventMask, &ev);
}

// ---- root properties ----
/// _NET_SUPPORTED, and the check window that says an EWMH WM is running.
pub fn announce_supported(self: *Backend) void {
    const a = &self.atoms;
    const supported = [_]c.Atom{
        a._NET_WM_STATE,            a._NET_WM_STATE_FULLSCREEN, a._NET_WM_STATE_DEMANDS_ATTENTION,
        a._NET_WM_WINDOW_TYPE,      a._NET_WM_WINDOW_TYPE_DOCK, a._NET_WM_WINDOW_TYPE_TOOLBAR,
        a._NET_WM_STRUT_PARTIAL,    a._NET_WORKAREA,            a._NET_ACTIVE_WINDOW,
        a._NET_NUMBER_OF_DESKTOPS,  a._NET_CURRENT_DESKTOP,     a._NET_CLIENT_LIST,
        a._NET_WM_DESKTOP,          a.WM_HINTS,                 a._NET_FRAME_EXTENTS,
        a._NET_SUPPORTING_WM_CHECK, a._NET_WM_NAME,
    };
    util.set_prop32(self.display, self.root, a._NET_SUPPORTED, a.ATOM, &supported);

    self.check_win = c.XCreateSimpleWindow(self.display, self.root, -1, -1, 1, 1, 0, 0, 0);
    util.set_prop32(self.display, self.root, a._NET_SUPPORTING_WM_CHECK, a.WINDOW, &.{self.check_win});
    util.set_prop32(self.display, self.check_win, a._NET_SUPPORTING_WM_CHECK, a.WINDOW, &.{self.check_win});
    _ = c.XChangeProperty(self.display, self.check_win, a._NET_WM_NAME, a.UTF8_STRING, 8, c.PropModeReplace, "duckwm", 6);
}

/// _NET_WORKAREA: what's left for windows once docks are out of the way.
pub fn work_area(self: *const Backend, area: types.Rect) void {
    const vals = [4]c_ulong{
        @intCast(area.x), @intCast(area.y), area.width, area.height,
    };
    util.set_prop32(self.display, self.root, self.atoms._NET_WORKAREA, self.atoms.CARDINAL, &vals);
}

/// _NET_NUMBER_OF_DESKTOPS and _NET_CURRENT_DESKTOP.
pub fn workspaces(self: *const Backend, count: u32, current: u32) void {
    util.set_prop32(self.display, self.root, self.atoms._NET_NUMBER_OF_DESKTOPS, self.atoms.CARDINAL, &.{count});
    util.set_prop32(self.display, self.root, self.atoms._NET_CURRENT_DESKTOP, self.atoms.CARDINAL, &.{current});
}

/// _NET_CLIENT_LIST.
pub fn window_list(self: *const Backend, handles: []const types.WindowHandle) void {
    if (handles.len == 0) {
        _ = c.XDeleteProperty(self.display, self.root, self.atoms._NET_CLIENT_LIST);
        return;
    }
    util.set_prop32(self.display, self.root, self.atoms._NET_CLIENT_LIST, self.atoms.WINDOW, @ptrCast(handles));
}

/// _NET_ACTIVE_WINDOW; 0 for none.
pub fn set_active_window(self: *const Backend, win: c.Window) void {
    util.set_prop32(self.display, self.root, self.atoms._NET_ACTIVE_WINDOW, self.atoms.WINDOW, &.{win});
}

// ---- client properties ----
/// _NET_WM_DESKTOP: the workspace win is on.
pub fn window_workspace(self: *const Backend, win: c.Window, index: u32) void {
    util.set_prop32(self.display, win, self.atoms._NET_WM_DESKTOP, self.atoms.CARDINAL, &.{index});
}

/// Tell the outside world whether win is fullscreen, preserving its other states.
pub fn window_fullscreen(self: *const Backend, win: c.Window, on: bool) void {
    const a = &self.atoms;

    var current: [32]c.Atom = undefined;
    var next: [33]c.Atom = undefined;
    var n: usize = 0;
    for (info.read_atoms(self.display, win, a._NET_WM_STATE, &current)) |s| {
        if (s == a._NET_WM_STATE_FULLSCREEN) continue;
        next[n] = s;
        n += 1;
    }
    if (on) {
        next[n] = a._NET_WM_STATE_FULLSCREEN;
        n += 1;
    }
    util.set_prop32(self.display, win, a._NET_WM_STATE, a.ATOM, next[0..n]);
}
