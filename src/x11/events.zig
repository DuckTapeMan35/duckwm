const std = @import("std");
const c = @import("xlib");
const types = @import("types");
const docks = @import("docks.zig");
const info = @import("info.zig");
const bars = @import("bars.zig");
const scene = @import("scene.zig");
const Backend = @import("backend.zig").Backend;
const Strut = @import("docks.zig").Strut;

/// The core event e stands for, if any; what only the backend cares about is
/// handled here and gives null.
pub fn translate(self: *Backend, e: *c.XEvent) ?types.Event {
    if (self.rr_event_base >= 0 and e.type == self.rr_event_base + c.RRScreenChangeNotify) {
        _ = c.XRRUpdateConfiguration(e);
        return .reserved_area_changed;
    }
    switch (e.type) {
        c.KeyPress => {
            if (self.bar) |b| if (b.grabbed) return bars.prompt_key(&e.xkey);
            const keysym = c.XkbKeycodeToKeysym(self.display, @as(u8, @truncate(e.xkey.keycode)), 0, 0);
            const mods = e.xkey.state & ~@as(c_uint, c.LockMask | c.Mod2Mask);
            return .{ .key = .{ .mods = @intCast(mods), .keysym = @intCast(keysym) } };
        },
        c.Expose => {
            if (e.xexpose.count != 0) return null;
            if (self.bar) |*b| if (e.xexpose.window == b.win) {
                bars.draw_bar(self, b);
                return null;
            };
            const client = self.frames.client_of(e.xexpose.window) orelse return null;
            return .{ .expose = client };
        },
        c.MappingNotify => {
            _ = c.XRefreshKeyboardMapping(&e.xmapping);
            if (e.xmapping.request == c.MappingKeyboard or e.xmapping.request == c.MappingModifier) {
                self.ungrab_all_keys();
                return .keymap_changed;
            }
            return null;
        },
        c.ConfigureRequest => {
            handle_configure_request(self, &e.xconfigurerequest);
            return null;
        },
        c.ConfigureNotify => {
            const rect: types.Rect = .{
                .x = e.xconfigure.x,
                .y = e.xconfigure.y,
                .width = @intCast(e.xconfigure.width),
                .height = @intCast(e.xconfigure.height),
            };
            return if (self.docks.set_rect(e.xconfigure.window, rect)) .reserved_area_changed else null;
        },
        c.CreateNotify, c.ReparentNotify => return null,
        c.MapRequest => return translate_map_request(self, &e.xmaprequest),
        c.MapNotify => {
            if (self.overlays.contains(e.xmap.window)) {
                _ = c.XSetInputFocus(self.display, e.xmap.window, c.RevertToParent, c.CurrentTime);
            }
            return null;
        },
        c.UnmapNotify => return translate_unmap(self, &e.xunmap),
        c.DestroyNotify => return translate_destroy(self, &e.xdestroywindow),
        c.PropertyNotify => return translate_property(self, &e.xproperty),
        c.ClientMessage => {
            if (forward_xdnd(self, &e.xclient)) return null;
            return translate_client_message(self, &e.xclient);
        },
        c.ButtonPress => return translate_button(self, &e.xbutton, true),
        c.ButtonRelease => return translate_button(self, &e.xbutton, false),
        c.MotionNotify => {
            // Only the latest position matters; drop the queued backlog.
            var latest = e.xmotion;
            var next: c.XEvent = undefined;
            while (c.XCheckTypedEvent(self.display, c.MotionNotify, &next) != 0) latest = next.xmotion;
            return .{ .pointer_motion = .{ .x = latest.x_root, .y = latest.y_root } };
        },
        c.EnterNotify => return translate_enter(self, &e.xcrossing),
        c.LeaveNotify => return null,
        else => return null,
    }
}

fn translate_map_request(self: *Backend, req: *c.XMapRequestEvent) ?types.Event {
    const win = req.window;
    var attrs: c.XWindowAttributes = undefined;
    if (c.XGetWindowAttributes(self.display, win, &attrs) == 0) return null; // already gone
    if (attrs.override_redirect != 0) return null;

    // Already ours (e.g. remapped after being hidden): just map the client.
    if (self.frames.frame_of(win) != null) {
        _ = c.XMapWindow(self.display, win);
        return null;
    }

    const traits = info.read_traits(self.display, &self.atoms, self.root, win);
    if (traits.kind == .dock) {
        _ = c.XMapWindow(self.display, win);
        docks.add(self, win, self.read_strut(win) orelse Strut{}) catch return null;
        docks.restack(self);
        if (traits.focusable_dock) self.overlays.put(self.allocator, win, {}) catch {};
        return .reserved_area_changed;
    }

    return .{ .map_request = .{
        .window = win,
        .size = .{ .width = @intCast(attrs.width), .height = @intCast(attrs.height) },
        .traits = traits,
    } };
}

fn translate_unmap(self: *Backend, ev: *c.XUnmapEvent) ?types.Event {
    const win = ev.window;

    if (self.ignore_unmaps.getPtr(win)) |n| {
        n.* -= 1;
        if (n.* == 0) _ = self.ignore_unmaps.remove(win);
        return null;
    }
    if (self.overlays.contains(win)) return .refocus;
    if (self.docks.remove(win)) {
        docks.restack(self);
        return .reserved_area_changed;
    }
    if (self.frames.is_frame(win)) return null; // our own frame being hidden
    if (self.frames.frame_of(win) == null) return null; // not a managed client
    if (ev.send_event != 0) return null; // synthetic, from reparenting

    // The client withdrew itself: rescue it from the frame before the frame goes.
    self.unframe(win, true);
    return .{ .window_gone = win };
}

fn translate_destroy(self: *Backend, ev: *c.XDestroyWindowEvent) ?types.Event {
    const win = ev.window;
    _ = self.overlays.remove(win);
    _ = self.ignore_unmaps.remove(win);
    if (self.docks.remove(win)) {
        docks.restack(self);
        return .reserved_area_changed;
    }
    if (self.frames.is_frame(win)) return null;
    self.unframe(win, false);
    return .{ .window_gone = win };
}

fn translate_property(self: *Backend, ev: *c.XPropertyEvent) ?types.Event {
    const a = &self.atoms;
    const win = ev.window;
    const atom = ev.atom;

    if (atom == a._NET_WM_ICON) {
        self.renderer.forget_icon(self.allocator, win);
        return null;
    }
    if (atom == a.WM_CLASS or atom == a.WM_NAME or atom == a._NET_WM_NAME) {
        return .{ .info_changed = win };
    }
    if (atom == a.WM_PROTOCOLS) {
        refresh_focus_model(self, win);
        return null;
    }
    if (atom == a.WM_HINTS) {
        if (self.frames.frame_of(win) == null) return null;
        refresh_focus_model(self, win);
        const hints = c.XGetWMHints(self.display, win);
        // A cleared hint (null) still counts: xterm drops it right after setting it.
        const urgent = if (hints != null) blk: {
            defer _ = c.XFree(hints);
            break :blk (hints.*.flags & c.XUrgencyHint) != 0;
        } else true;
        return .{ .urgency_hint = .{ .window = win, .urgent = urgent } };
    }
    if (atom == a._NET_WM_WINDOW_TYPE) {
        if (self.frames.frame_of(win) == null) return null;
        if (info.read_traits(self.display, &self.atoms, self.root, win).kind != .dock) return null;
        if (self.read_strut(win)) |s| docks.add(self, win, s) catch {};
        return .{ .became_dock = win };
    }
    if (atom == a._NET_WM_STRUT_PARTIAL) {
        return if (docks.update_strut(self, win, self.read_strut(win))) .reserved_area_changed else null;
    }
    return null;
}

fn translate_client_message(self: *Backend, ev: *c.XClientMessageEvent) ?types.Event {
    const a = &self.atoms;

    if (ev.message_type == a._NET_ACTIVE_WINDOW) {
        return .{ .activate_request = ev.window };
    }

    if (ev.message_type == a._NET_WM_STATE) {
        const action: types.StateAction = switch (ev.data.l[0]) {
            0 => .remove,
            1 => .add,
            2 => .toggle,
            else => return null,
        };
        const p1: c.Atom = @bitCast(ev.data.l[1]);
        const p2: c.Atom = @bitCast(ev.data.l[2]);
        const fullscreen = p1 == a._NET_WM_STATE_FULLSCREEN or p2 == a._NET_WM_STATE_FULLSCREEN;
        const attention = p1 == a._NET_WM_STATE_DEMANDS_ATTENTION or p2 == a._NET_WM_STATE_DEMANDS_ATTENTION;
        if (!fullscreen and !attention) return null;
        return .{ .state_request = .{
            .window = ev.window,
            .action = action,
            .fullscreen = fullscreen,
            .attention = attention,
        } };
    }
    return null;
}

fn translate_button(self: *Backend, ev: *c.XButtonEvent, pressed: bool) ?types.Event {
    if (pressed and bars.is_error_bar(self, ev.window)) {
        return if (self.hide_error()) .reserved_area_changed else null;
    }

    const mods: types.Mods = @intCast(ev.state &
        ~@as(c_uint, c.LockMask | c.Mod2Mask | c.Mod3Mask | c.Mod5Mask));
    const lookup = if (ev.window == self.root) ev.subwindow else ev.window;
    const window: ?types.WindowHandle = if (lookup != 0) self.frames.client_of(lookup) else null;

    // A click caught by the click-to-focus grab freezes the pointer until we
    // decide: keep it if it starts a WM drag, otherwise pass it to the client.
    if (pressed and self.click_to_focus and self.frames.is_frame(ev.window)) {
        const mode = if (is_drag_modifier(self, mods)) c.AsyncPointer else c.ReplayPointer;
        _ = c.XAllowEvents(self.display, mode, c.CurrentTime);
    }

    const b: types.PointerButton = .{
        .window = window,
        .button = @intCast(ev.button),
        .mods = mods,
        .pos = .{ .x = ev.x_root, .y = ev.y_root },
    };
    return if (pressed) .{ .button_press = b } else .{ .button_release = b };
}

fn is_drag_modifier(self: *const Backend, mods: types.Mods) bool {
    for (self.pointer_grabs[0..self.pointer_grab_count]) |g| {
        if (mods & g.mods != 0) return true;
    }
    return false;
}

fn translate_enter(self: *Backend, ev: *c.XCrossingEvent) ?types.Event {
    // Grab/ungrab crossings and moves into a child aren't real "entering".
    if (ev.mode != c.NotifyNormal or ev.detail == c.NotifyInferior) return null;
    if (scene.caused_by_us(self, ev.serial)) return null;
    const lookup = if (ev.window == self.root) ev.subwindow else ev.window;
    if (lookup == 0) return null;
    if (self.frames.client_of(lookup)) |client| return .{ .pointer_enter = client };
    if (self.frames.frame_of(lookup) != null) return null; // a client itself: nothing to do
    self.release_keyboard_grab(); // over something unmanaged
    return null;
}

fn refresh_focus_model(self: *Backend, win: c.Window) void {
    if (self.frames.focus_models.getPtr(win)) |m| {
        m.* = info.read_focus_model(self.display, &self.atoms, win);
    }
}

fn handle_configure_request(self: *Backend, req: *c.XConfigureRequestEvent) void {
    var mask = req.value_mask;
    if (self.docks.contains(req.window)) mask &= ~@as(c_ulong, c.CWX | c.CWY);
    var changes = c.XWindowChanges{
        .x = req.x,
        .y = req.y,
        .width = req.width,
        .height = req.height,
        .border_width = req.border_width,
        .sibling = req.above,
        .stack_mode = req.detail,
    };
    _ = c.XConfigureWindow(self.display, req.window, @intCast(mask), &changes);
    if (self.frames.frame_of(req.window) != null) self.invalidate_window(req.window);
}

/// XDND messages that duckwm relays between drag sources and framed clients.
/// Returns true if the message was XDND and has been handled.
fn forward_xdnd(self: *Backend, ev: *c.XClientMessageEvent) bool {
    const a = &self.atoms;
    const mt = ev.message_type;

    // Replies from a client back to the drag source.
    if (mt == a.XdndStatus or mt == a.XdndFinished) {
        const source: c.Window = @intCast(ev.data.l[0]);
        if (source == 0) return false;
        var fwd = ev.*;
        fwd.window = source;
        _ = c.XSendEvent(self.display, source, 0, c.NoEventMask, @ptrCast(&fwd));
        return true;
    }

    // Messages from a drag source to one of our frames.
    if (mt != a.XdndEnter and mt != a.XdndPosition and mt != a.XdndLeave and mt != a.XdndDrop) return false;
    const client = self.frames.client_of(ev.window) orelse return false;
    const source: c.Window = @intCast(ev.data.l[0]);

    var fwd = ev.*;
    fwd.window = client;
    _ = c.XSendEvent(self.display, client, 0, c.NoEventMask, @ptrCast(&fwd));

    if (mt == a.XdndEnter or mt == a.XdndPosition) {
        var status: c.XEvent = std.mem.zeroes(c.XEvent);
        status.xclient.type = c.ClientMessage;
        status.xclient.display = self.display;
        status.xclient.window = source;
        status.xclient.message_type = a.XdndStatus;
        status.xclient.format = 32;
        status.xclient.data.l[0] = @intCast(ev.window);
        status.xclient.data.l[1] = 1;
        status.xclient.data.l[4] = @intCast(a.XdndActionCopy);
        _ = c.XSendEvent(self.display, source, 0, c.NoEventMask, &status);
    }
    return true;
}
