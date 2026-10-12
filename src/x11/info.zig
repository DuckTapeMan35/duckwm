const std = @import("std");
const c = @import("xlib");
const types = @import("types");
const Atoms = @import("atoms.zig").Atoms;
const Strut = @import("docks.zig").Strut;
const FocusModel = @import("frames.zig").FocusModel;

pub fn read_focus_model(display: *c.Display, atoms: *const Atoms, win: c.Window) FocusModel {
    var m: FocusModel = .{};
    if (c.XGetWMHints(display, win)) |h| {
        defer _ = c.XFree(h);
        if ((h.*.flags & c.InputHint) != 0) m.accepts_input = h.*.input != 0;
    }
    var protocols: [*c]c.Atom = null;
    var n: c_int = 0;
    if (c.XGetWMProtocols(display, win, &protocols, &n) != 0) {
        defer _ = c.XFree(@ptrCast(protocols));
        for (protocols[0..@intCast(n)]) |p| {
            if (p == atoms.WM_TAKE_FOCUS) {
                m.takes_focus = true;
                break;
            }
        }
    }
    return m;
}

pub fn read_info(display: *c.Display, atoms: *const Atoms, win: c.Window) types.WindowInfo {
    var info: types.WindowInfo = .{};
    read_class(display, win, &info);
    read_title(display, atoms, win, &info);
    info.pid = read_pid(display, atoms, win);
    return info;
}

fn read_class(display: *c.Display, win: c.Window, info: *types.WindowInfo) void {
    var hint: c.XClassHint = std.mem.zeroes(c.XClassHint);
    if (c.XGetClassHint(display, win, &hint) == 0) return;
    defer {
        if (hint.res_name) |n| _ = c.XFree(n);
        if (hint.res_class) |cl| _ = c.XFree(cl);
    }
    if (hint.res_name) |n| info.set_instance(std.mem.span(n));
    if (hint.res_class) |cl| info.set_class(std.mem.span(cl));
}

/// Prefer UTF-8 _NET_WM_NAME, fall back to legacy WM_NAME.
fn read_title(display: *c.Display, atoms: *const Atoms, win: c.Window, info: *types.WindowInfo) void {
    var actual_type: c.Atom = 0;
    var actual_format: c_int = 0;
    var nitems: c_ulong = 0;
    var bytes_after: c_ulong = 0;
    var prop: [*c]u8 = null;
    if (c.XGetWindowProperty(
        display,
        win,
        atoms._NET_WM_NAME,
        0,
        1024,
        0,
        atoms.UTF8_STRING,
        &actual_type,
        &actual_format,
        &nitems,
        &bytes_after,
        &prop,
    ) == c.Success and prop != null) {
        defer _ = c.XFree(prop);
        if (actual_format == 8 and nitems > 0) {
            info.set_title(prop[0..@intCast(nitems)]);
            return;
        }
    }

    var name: [*c]u8 = null;
    if (c.XFetchName(display, win, &name) != 0 and name != null) {
        defer _ = c.XFree(name);
        info.set_title(std.mem.span(name));
    }
}

fn read_pid(display: *c.Display, atoms: *const Atoms, win: c.Window) ?u32 {
    var actual_type: c.Atom = undefined;
    var actual_format: c_int = undefined;
    var nitems: c_ulong = undefined;
    var bytes_after: c_ulong = undefined;
    var prop: [*c]u8 = null;
    const result = c.XGetWindowProperty(display, win, atoms._NET_WM_PID, 0, 1, 0, c.AnyPropertyType, &actual_type, &actual_format, &nitems, &bytes_after, &prop);
    if (result != c.Success or prop == null or nitems == 0) {
        if (prop != null) _ = c.XFree(prop);
        return null;
    }
    defer _ = c.XFree(prop);
    const pid: c_ulong = @as(*c_ulong, @ptrCast(@alignCast(prop))).*;
    return @intCast(pid);
}

/// Read an atom-list property (format 32) into out. Returns the filled prefix.
pub fn read_atoms(display: *c.Display, win: c.Window, prop: c.Atom, out: []c.Atom) []c.Atom {
    var actual_type: c.Atom = 0;
    var actual_format: c_int = 0;
    var nitems: c_ulong = 0;
    var bytes_after: c_ulong = 0;
    var data: [*c]u8 = null;
    if (c.XGetWindowProperty(
        display,
        win,
        prop,
        0,
        @intCast(out.len),
        0,
        c.AnyPropertyType,
        &actual_type,
        &actual_format,
        &nitems,
        &bytes_after,
        &data,
    ) != c.Success) return out[0..0];
    defer if (data != null) {
        _ = c.XFree(data);
    };
    if (data == null or actual_format != 32 or nitems == 0) return out[0..0];

    const n = @min(@as(usize, @intCast(nitems)), out.len);
    const src: [*]const c_ulong = @ptrCast(@alignCast(data));
    for (0..n) |i| out[i] = src[i];
    return out[0..n];
}

pub fn read_traits(display: *c.Display, atoms: *const Atoms, root: c.Window, win: c.Window) types.WindowTraits {
    var t: types.WindowTraits = .{};

    var transient: c.Window = 0;
    if (c.XGetTransientForHint(display, win, &transient) != 0 and
        transient != 0 and transient != win and transient != root)
    {
        t.transient_for = transient;
    }

    var float_type = false;
    var dock_type = false;
    var buf: [8]c.Atom = undefined;
    for (read_atoms(display, win, atoms._NET_WM_WINDOW_TYPE, &buf)) |a| {
        if (a == atoms._NET_WM_WINDOW_TYPE_DIALOG or a == atoms._NET_WM_WINDOW_TYPE_UTILITY or
            a == atoms._NET_WM_WINDOW_TYPE_SPLASH or a == atoms._NET_WM_WINDOW_TYPE_POPUP_MENU or
            a == atoms._NET_WM_WINDOW_TYPE_MENU or a == atoms._NET_WM_WINDOW_TYPE_TOOLTIP or
            a == atoms._NET_WM_WINDOW_TYPE_NOTIFICATION) float_type = true;
        if (a == atoms._NET_WM_WINDOW_TYPE_DOCK or a == atoms._NET_WM_WINDOW_TYPE_TOOLBAR) dock_type = true;
        if (a == atoms._KDE_NET_WM_WINDOW_TYPE_OVERRIDE) t.focusable_dock = true;
    }

    t.kind = if (t.transient_for != null or float_type) .floating else if (dock_type) .dock else .normal;
    return t;
}

pub fn read_hints(display: *c.Display, atoms: *const Atoms, win: c.Window) types.InitialHints {
    var h: types.InitialHints = .{};

    var buf: [32]c.Atom = undefined;
    for (read_atoms(display, win, atoms._NET_WM_STATE, &buf)) |a| {
        if (a == atoms._NET_WM_STATE_FULLSCREEN) {
            h.fullscreen = true;
        } else if (a == atoms._NET_WM_STATE_DEMANDS_ATTENTION) {
            h.urgent = true;
        } else if (a == atoms._NET_WM_STATE_ABOVE or a == atoms._NET_WM_STATE_STICKY) {
            h.keep_above = true;
        }
    }

    var sh: c.XSizeHints = undefined;
    var supplied: c_long = 0;
    if (c.XGetWMNormalHints(display, win, &sh, &supplied) != 0) {
        const has_min = (sh.flags & c.PMinSize) != 0;
        const has_max = (sh.flags & c.PMaxSize) != 0;
        if (has_min and has_max and
            sh.min_width == sh.max_width and sh.min_height == sh.max_height and
            sh.min_width > 0 and sh.min_height > 0)
        {
            h.fixed_size = .{ .width = @intCast(sh.min_width), .height = @intCast(sh.min_height) };
        }
        if ((sh.flags & c.PAspect) != 0 and
            sh.min_aspect.x == sh.max_aspect.x and
            sh.min_aspect.y == sh.max_aspect.y and
            sh.min_aspect.y > 0)
        {
            h.fixed_aspect = true;
        }
    }

    if (c.XGetWMHints(display, win)) |wmh| {
        defer _ = c.XFree(wmh);
        if ((wmh.*.flags & c.XUrgencyHint) != 0) h.urgent = true;
    }

    return h;
}

pub fn read_strut(display: *c.Display, atoms: *const Atoms, win: c.Window) ?Strut {
    var actual_type: c.Atom = 0;
    var actual_format: c_int = 0;
    var nitems: c_ulong = 0;
    var bytes_after: c_ulong = 0;
    var data: [*c]u8 = null;
    if (c.XGetWindowProperty(display, win, atoms._NET_WM_STRUT_PARTIAL, 0, 12, 0, atoms.CARDINAL, &actual_type, &actual_format, &nitems, &bytes_after, &data) != c.Success) return null;
    defer if (data != null) {
        _ = c.XFree(data);
    };
    if (data == null or nitems < 12 or actual_format != 32) return null;

    const v: [*]const c_ulong = @ptrCast(@alignCast(data));
    return .{
        .left = @intCast(v[0]),
        .right = @intCast(v[1]),
        .top = @intCast(v[2]),
        .bottom = @intCast(v[3]),
    };
}
