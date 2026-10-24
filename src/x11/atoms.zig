const std = @import("std");
const c = @import("xlib");

/// Every atom duckwm uses, interned in a single round-trip at startup.
/// Field names are the atom names, so adding one is just adding a field.
pub const Atoms = struct {
    // predefined types (interning returns the XA_* constants anyway)
    ATOM: c.Atom,
    CARDINAL: c.Atom,
    WINDOW: c.Atom,
    STRING: c.Atom,
    UTF8_STRING: c.Atom,
    WM_STATE: c.Atom,

    // ICCCM
    WM_PROTOCOLS: c.Atom,
    WM_DELETE_WINDOW: c.Atom,
    WM_TAKE_FOCUS: c.Atom,
    WM_HINTS: c.Atom,
    WM_CLASS: c.Atom,
    WM_NAME: c.Atom,
    RESOURCE_MANAGER: c.Atom,

    // EWMH root / WM
    _NET_SUPPORTED: c.Atom,
    _NET_SUPPORTING_WM_CHECK: c.Atom,
    _NET_WM_NAME: c.Atom,
    _NET_WORKAREA: c.Atom,
    _NET_ACTIVE_WINDOW: c.Atom,
    _NET_NUMBER_OF_DESKTOPS: c.Atom,
    _NET_CURRENT_DESKTOP: c.Atom,
    _NET_CLIENT_LIST: c.Atom,
    _NET_WM_DESKTOP: c.Atom,
    _NET_FRAME_EXTENTS: c.Atom,
    _NET_WM_PID: c.Atom,
    _NET_WM_ICON: c.Atom,
    _NET_WM_STRUT_PARTIAL: c.Atom,

    // EWMH state
    _NET_WM_STATE: c.Atom,
    _NET_WM_STATE_FULLSCREEN: c.Atom,
    _NET_WM_STATE_DEMANDS_ATTENTION: c.Atom,
    _NET_WM_STATE_ABOVE: c.Atom,
    _NET_WM_STATE_STICKY: c.Atom,

    // EWMH window types
    _NET_WM_WINDOW_TYPE: c.Atom,
    _NET_WM_WINDOW_TYPE_DOCK: c.Atom,
    _NET_WM_WINDOW_TYPE_TOOLBAR: c.Atom,
    _NET_WM_WINDOW_TYPE_DIALOG: c.Atom,
    _NET_WM_WINDOW_TYPE_UTILITY: c.Atom,
    _NET_WM_WINDOW_TYPE_SPLASH: c.Atom,
    _NET_WM_WINDOW_TYPE_POPUP_MENU: c.Atom,
    _NET_WM_WINDOW_TYPE_MENU: c.Atom,
    _NET_WM_WINDOW_TYPE_TOOLTIP: c.Atom,
    _NET_WM_WINDOW_TYPE_NOTIFICATION: c.Atom,
    _KDE_NET_WM_WINDOW_TYPE_OVERRIDE: c.Atom,

    // XDND
    XdndAware: c.Atom,
    XdndEnter: c.Atom,
    XdndPosition: c.Atom,
    XdndLeave: c.Atom,
    XdndDrop: c.Atom,
    XdndStatus: c.Atom,
    XdndFinished: c.Atom,
    XdndActionCopy: c.Atom,

    pub fn init(display: *c.Display) !Atoms {
        const fields = @typeInfo(Atoms).@"struct".field_names;
        var names: [fields.len][*c]u8 = undefined;
        inline for (fields, 0..) |name, i| names[i] = @constCast(name.ptr);

        var out: [fields.len]c.Atom = undefined;
        if (c.XInternAtoms(display, &names, fields.len, 0, &out) == 0)
            return error.AtomInternFailed;

        var a: Atoms = undefined;
        inline for (fields, 0..) |name, i| @field(a, name) = out[i];
        return a;
    }
};
