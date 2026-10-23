const std = @import("std");
const c = @import("xlib");
const types = @import("types");
const info = @import("info.zig");
const util = @import("util.zig");
const Backend = @import("backend.zig").Backend;

const NormalState: c_ulong = 1;

/// What duckwm hears from its frames.
pub const event_mask: c_long = c.SubstructureRedirectMask | c.SubstructureNotifyMask |
    c.ButtonPressMask | c.ButtonReleaseMask | c.PointerMotionMask |
    c.EnterWindowMask | c.LeaveWindowMask | c.ExposureMask;

pub const FocusModel = struct {
    /// WM_HINTS.input: may the WM call XSetInputFocus on it?
    accepts_input: bool = true,
    /// Supports WM_TAKE_FOCUS: wants to be told when it gets focus.
    takes_focus: bool = false,
};

/// Bidirectional client <-> frame map.
pub const Frames = struct {
    by_client: std.AutoHashMapUnmanaged(c.Window, c.Window) = .empty,
    by_frame: std.AutoHashMapUnmanaged(c.Window, c.Window) = .empty,
    argb: std.AutoHashMapUnmanaged(c.Window, void) = .empty, // keyed by frame
    focus_models: std.AutoHashMapUnmanaged(c.Window, FocusModel) = .empty,

    pub fn deinit(self: *Frames, gpa: std.mem.Allocator) void {
        self.by_client.deinit(gpa);
        self.by_frame.deinit(gpa);
        self.argb.deinit(gpa);
        self.focus_models.deinit(gpa);
    }

    /// Reserve room for one entry so the later insert cannot fail.
    pub fn reserve(self: *Frames, gpa: std.mem.Allocator) !void {
        try self.by_client.ensureUnusedCapacity(gpa, 1);
        try self.by_frame.ensureUnusedCapacity(gpa, 1);
        try self.argb.ensureUnusedCapacity(gpa, 1);
        try self.focus_models.ensureUnusedCapacity(gpa, 1);
    }

    pub fn put_reserved(self: *Frames, client: c.Window, frame: c.Window, argb: bool, model: FocusModel) void {
        self.by_client.putAssumeCapacity(client, frame);
        self.by_frame.putAssumeCapacity(frame, client);
        if (argb) self.argb.putAssumeCapacity(frame, {});
        self.focus_models.putAssumeCapacity(client, model);
    }

    /// Returns the frame that was attached to client, if any.
    pub fn remove(self: *Frames, client: c.Window) ?c.Window {
        const kv = self.by_client.fetchRemove(client) orelse return null;
        _ = self.by_frame.remove(kv.value);
        _ = self.argb.remove(kv.value);
        _ = self.focus_models.remove(client);
        return kv.value;
    }

    pub fn focus_model(self: *const Frames, client: c.Window) FocusModel {
        return self.focus_models.get(client) orelse .{};
    }

    pub fn is_argb(self: *const Frames, frame: c.Window) bool {
        return self.argb.contains(frame);
    }

    pub fn frame_of(self: *const Frames, client: c.Window) ?c.Window {
        return self.by_client.get(client);
    }

    pub fn client_of(self: *const Frames, frame: c.Window) ?c.Window {
        return self.by_frame.get(frame);
    }

    pub fn is_frame(self: *const Frames, win: c.Window) bool {
        return self.by_frame.contains(win);
    }
};

// ---- the X side: creating and destroying frames ----

/// Reparent client into a new frame.
pub fn create(self: *Backend, client: c.Window, opts: types.FrameOptions) !c.Window {
    try self.frames.reserve(self.allocator); // nothing below this line can fail

    var attrs: c.XWindowAttributes = undefined;
    if (c.XGetWindowAttributes(self.display, client, &attrs) == 0) return error.WindowGone;

    const argb = if (opts.allow_argb and attrs.depth == 32) argb_visual(self.display) else null;
    const use_alpha = argb != null;
    const visual = argb orelse c.XDefaultVisual(self.display, 0);
    const depth = if (use_alpha) @as(c_int, 32) else c.XDefaultDepth(self.display, 0);
    const colormap = if (use_alpha)
        c.XCreateColormap(self.display, self.root, visual, c.AllocNone)
    else
        c.XDefaultColormap(self.display, 0);

    var swa: c.XSetWindowAttributes = std.mem.zeroes(c.XSetWindowAttributes);
    swa.backing_store = c.WhenMapped;
    swa.bit_gravity = c.NorthWestGravity;
    swa.win_gravity = c.NorthWestGravity;
    swa.border_pixel = opts.border_color;
    swa.background_pixel = if (use_alpha) 0x00000000 else c.None;
    swa.colormap = colormap;
    const mask: c_ulong = c.CWBackingStore | c.CWBitGravity | c.CWWinGravity |
        c.CWBorderPixel | c.CWBackPixel | c.CWColormap;

    const frame = c.XCreateWindow(
        self.display,
        self.root,
        attrs.x,
        attrs.y,
        @intCast(attrs.width),
        @intCast(attrs.height),
        0,
        depth,
        c.InputOutput,
        visual,
        mask,
        &swa,
    );
    if (frame == 0) {
        if (use_alpha) _ = c.XFreeColormap(self.display, colormap);
        return error.FrameCreationFailed;
    }

    const xdnd_version: c_ulong = 5;
    util.set_prop32(self.display, frame, self.atoms.XdndAware, self.atoms.ATOM, &.{xdnd_version});
    util.set_prop32(self.display, client, self.atoms.XdndAware, self.atoms.ATOM, &.{xdnd_version});

    if (use_alpha) _ = c.XSetWindowBackgroundPixmap(self.display, frame, c.None);

    // Offscreen until the first flush positions it.
    _ = c.XMoveWindow(self.display, frame, -10000, -10000);

    if (self.click_to_focus) grab_click(self, frame);

    _ = c.XSelectInput(self.display, frame, event_mask);

    const bw: c_int = @intCast(opts.border_width);
    _ = c.XAddToSaveSet(self.display, client);
    _ = c.XReparentWindow(self.display, client, frame, bw, bw);
    _ = c.XSetWindowBorderWidth(self.display, client, 0);
    _ = c.XSync(self.display, 0);

    if (opts.configured_size) |s| {
        var ce: c.XEvent = std.mem.zeroes(c.XEvent);
        ce.xconfigure.type = c.ConfigureNotify;
        ce.xconfigure.display = self.display;
        ce.xconfigure.event = client;
        ce.xconfigure.window = client;
        ce.xconfigure.x = attrs.x;
        ce.xconfigure.y = attrs.y;
        ce.xconfigure.width = @intCast(s.width);
        ce.xconfigure.height = @intCast(s.height);
        ce.xconfigure.above = c.None;
        _ = c.XSendEvent(self.display, client, 0, c.StructureNotifyMask, &ce);
    }

    set_extents(self, client, opts.border_width);
    const model = info.read_focus_model(self.display, &self.atoms, client);
    self.frames.put_reserved(client, frame, use_alpha, model);
    _ = c.XSelectInput(self.display, client, c.PropertyChangeMask);
    set_wm_state(self, client, NormalState);
    return frame;
}

/// Stop framing client. With keep_client, it is reparented to the root first so it survives.
pub fn destroy(self: *Backend, client: c.Window, keep_client: bool) void {
    const frame = self.frames.remove(client) orelse return;
    _ = self.applied.remove(client);
    if (keep_client) {
        _ = c.XReparentWindow(self.display, client, self.root, 0, 0);
        _ = c.XRemoveFromSaveSet(self.display, client);
        _ = c.XDeleteProperty(self.display, client, self.atoms.WM_STATE);
    }
    self.renderer.forget_icon(self.allocator, client);
    destroy_window(self, frame);
}

/// Destroy a frame, and the colormap an ARGB one was given.
fn destroy_window(self: *Backend, frame: c.Window) void {
    var attrs: c.XWindowAttributes = undefined;
    if (c.XGetWindowAttributes(self.display, frame, &attrs) != 0) {
        const default_cmap = c.XDefaultColormap(self.display, 0);
        if (attrs.colormap != 0 and attrs.colormap != default_cmap) {
            _ = c.XFreeColormap(self.display, attrs.colormap);
        }
    }
    _ = c.XDestroyWindow(self.display, frame);
}

/// _NET_FRAME_EXTENTS: how much the frame adds on each side.
pub fn set_extents(self: *const Backend, client: c.Window, bw: u32) void {
    const v: c_ulong = bw;
    const vals = [4]c_ulong{ v, v, v, v };
    util.set_prop32(self.display, client, self.atoms._NET_FRAME_EXTENTS, self.atoms.CARDINAL, &vals);
}

fn set_wm_state(self: *const Backend, client: c.Window, state: c_ulong) void {
    const data = [2]c_ulong{ state, c.None }; // state, icon window
    util.set_prop32(self.display, client, self.atoms.WM_STATE, self.atoms.WM_STATE, &data);
}

/// Hold clicks on the frame until translate_button decides who gets them.
pub fn grab_click(self: *const Backend, frame: c.Window) void {
    _ = c.XGrabButton(self.display, c.Button1, c.AnyModifier, frame, 0, c.ButtonPressMask | c.ButtonReleaseMask, c.GrabModeSync, c.GrabModeAsync, c.None, c.None);
}

pub fn ungrab_click(self: *const Backend, frame: c.Window) void {
    _ = c.XUngrabButton(self.display, c.Button1, c.AnyModifier, frame);
}

fn argb_visual(display: *c.Display) ?*c.Visual {
    var template: c.XVisualInfo = undefined;
    template.screen = c.XDefaultScreen(display);
    template.depth = 32;
    template.class = c.TrueColor;
    var nitems: c_int = 0;
    const list = c.XGetVisualInfo(display, c.VisualScreenMask | c.VisualDepthMask | c.VisualClassMask, &template, &nitems);
    defer if (list != null) {
        _ = c.XFree(@ptrCast(list));
    };
    if (nitems > 0) return list[0].visual;
    return null;
}
