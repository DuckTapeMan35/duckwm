/// Longest prefix of s that fits in max bytes without splitting a UTF-8 codepoint.
fn utf8_prefix_len(s: []const u8, max: usize) usize {
    if (s.len <= max) return s.len;
    var n = max;
    while (n > 0 and (s[n] & 0xC0) == 0x80) n -= 1;
    return n;
}

pub const platform = struct {
    pub const x11 = 1;
    pub const river = 2;
};

/// A monitor, as a backend reports it.
pub const OutputInfo = struct {
    /// Stays the same while it's connected.
    id: u32,
    /// Where it is, in global coordinates.
    rect: Rect,
    /// rect minus the docks and bars on it.
    usable: Rect,
};

pub const Event = union(enum) {
    /// A bound key was pressed.
    key: KeyCombo,
    /// A window's frame needs its border/contents repainted.
    expose: WindowHandle,
    /// The keyboard mapping changed; bindings must be grabbed again.
    keymap_changed,
    /// Monitors or docks changed: outputs and work areas must be read again.
    reserved_area_changed,
    /// A new top-level window wants to be shown.
    map_request: MapRequest,
    /// A managed window was destroyed, or withdrew itself.
    window_gone: WindowHandle,
    /// Something that briefly held focus (a launcher panel) went away; re-apply focus.
    refocus,
    /// Class or title changed; the WM's cached info is stale.
    info_changed: WindowHandle,
    /// The client set or cleared its urgency hint.
    urgency_hint: UrgencyHint,
    /// A managed window declared itself a dock or panel.
    became_dock: WindowHandle,
    /// Someone (a pager, a taskbar, xdotool) asked to activate a window.
    activate_request: WindowHandle,
    /// A client asked to change its fullscreen or attention state.
    state_request: StateRequest,
    button_press: PointerButton,
    button_release: PointerButton,
    pointer_motion: Point,
    /// The pointer entered a managed window (for focus-follows-mouse).
    pointer_enter: WindowHandle,
    /// Only while the input bar holds the keyboard; binds don't fire then.
    prompt_key: PromptKey,
};

pub const Callback = union(enum) {
    lua: i32,
    /// A socket client's function: its connection's id and the id it chose.
    remote: struct { client: u32, id: u64 },
};

/// Who the commands being run came from, i.e. who keeps the functions they pass.
pub const CallbackSource = union(enum) { none, lua, client: u32 };

pub const MapRequest = struct {
    window: WindowHandle,
    size: Size,
    traits: WindowTraits,
};

pub const UrgencyHint = struct { window: WindowHandle, urgent: bool };

pub const StateAction = enum { remove, add, toggle };

pub const StateRequest = struct {
    window: WindowHandle,
    action: StateAction,
    fullscreen: bool,
    attention: bool,
};

pub const PointerButton = struct {
    /// Managed window under the pointer (resolved through its frame), if any.
    window: ?WindowHandle,
    button: Button,
    /// Lock-style modifiers (Caps/Num Lock, Mod3, Mod5) already stripped.
    mods: Mods,
    /// Root coordinates.
    pos: Point,
};

// dedicated shared types across backend and frontend
pub const Rect = struct {
    x: i32,
    y: i32,
    width: u32,
    height: u32,

    pub fn inset(r: Rect, i: Insets) Rect {
        return .{
            .x = r.x + @as(i32, @intCast(i.left)),
            .y = r.y + @as(i32, @intCast(i.top)),
            .width = r.width -| i.left -| i.right,
            .height = r.height -| i.top -| i.bottom,
        };
    }
};

pub const Size = struct {
    width: u32,
    height: u32,
};

pub const Insets = struct {
    left: u32 = 0,
    right: u32 = 0,
    top: u32 = 0,
    bottom: u32 = 0,
};

pub const WindowInfo = struct {
    class_buf: [128]u8 = undefined,
    class_len: u8 = 0,
    title_buf: [512]u8 = undefined,
    title_len: u16 = 0,
    pid: ?u32 = null,
    instance_buf: [128]u8 = undefined,
    instance_len: u8 = 0,

    pub fn instance(self: *const WindowInfo) []const u8 {
        return self.instance_buf[0..self.instance_len];
    }

    pub fn set_instance(self: *WindowInfo, s: []const u8) void {
        const n = utf8_prefix_len(s, self.instance_buf.len);
        @memcpy(self.instance_buf[0..n], s[0..n]);
        self.instance_len = @intCast(n);
    }

    pub fn class(self: *const WindowInfo) []const u8 {
        return self.class_buf[0..self.class_len];
    }

    pub fn title(self: *const WindowInfo) []const u8 {
        return self.title_buf[0..self.title_len];
    }

    pub fn set_class(self: *WindowInfo, s: []const u8) void {
        const n = utf8_prefix_len(s, self.class_buf.len);
        @memcpy(self.class_buf[0..n], s[0..n]);
        self.class_len = @intCast(n);
    }

    pub fn set_title(self: *WindowInfo, s: []const u8) void {
        const n = utf8_prefix_len(s, self.title_buf.len);
        @memcpy(self.title_buf[0..n], s[0..n]);
        self.title_len = @intCast(n);
    }
};

pub const WindowTraits = struct {
    kind: WindowKind = .normal,
    transient_for: ?WindowHandle = null,
    focusable_dock: bool = false,
};

/// Desired on-screen state of one managed window, as computed by core.
pub const WindowState = struct {
    handle: WindowHandle,
    /// Frame rectangle in screen coordinates (unclamped).
    frame: Rect,
    /// Border thickness inside the frame; 0 when fullscreen.
    border_width: u32,
    /// Colors to paint, or null to leave the border unpainted.
    borders: ?BorderColors,
    /// Tiled windows are stacked below floating ones.
    tiled: bool,
    /// Being dragged right now: move the frame, but hold the client's
    /// ConfigureNotify until the drag ends.
    interactive: bool = false,
};

pub const InitialHints = struct {
    fullscreen: bool = false,
    urgent: bool = false,
    keep_above: bool = false,
    fixed_size: ?Size = null,
    fixed_aspect: bool = false,
};

/// Modifier bitmask. Bit values match the X11 core protocol so the X backend
/// maps them by identity; other backends translate.
pub const Mods = u32;

pub const mod = struct {
    pub const shift: Mods = 1 << 0;
    pub const caps_lock: Mods = 1 << 1;
    pub const ctrl: Mods = 1 << 2;
    pub const alt: Mods = 1 << 3;
    pub const num_lock: Mods = 1 << 4; // conventionally Mod2 on X
    pub const mod3: Mods = 1 << 5;
    pub const super: Mods = 1 << 6;
    pub const mod5: Mods = 1 << 7;
};

/// Pointer button. Values match X11 core buttons; other backends translate.
pub const Button = u32;

pub const button = struct {
    pub const left: Button = 1;
    pub const middle: Button = 2;
    pub const right: Button = 3;
    pub const scroll_up: Button = 4;
    pub const scroll_down: Button = 5;
};

pub const FocusModel = struct {
    /// WM_HINTS.input: may the WM call XSetInputFocus on it?
    accepts_input: bool = true,
    /// Supports WM_TAKE_FOCUS: wants to be told when it gets focus.
    takes_focus: bool = false,
};

pub const PreviewItem = struct {
    /// Position inside the preview window, in pixels.
    rect: Rect,
    /// Where the icon comes from; null for nested workspaces.
    window: ?WindowHandle,
    /// Shown when there's no icon. May be empty.
    label: []const u8,
    /// 0 = too small to draw an icon or a label.
    icon_size: u32,
};

pub const PreviewStyle = struct {
    bg: u32,
    win_bg: u32,
    border: u32,
    text: u32,
    font: []const u8,
};

pub const FrameOptions = struct {
    border_width: u32,
    border_color: u32,
    /// If the WM already knows a size for this window, tell the client via ConfigureNotify.
    configured_size: ?Size = null,
    /// When false, 32-bit clients get a normal-depth frame instead of an ARGB one.
    allow_argb: bool = true,
};

/// An XKB keymap by its RMLVO names. Empty strings mean "default".
pub const Keymap = struct {
    layout: []const u8,
    variant: []const u8 = "",
    options: []const u8 = "",
    model: []const u8 = "",
};

pub const curve_samples = 64;
/// Progress at evenly spaced times 0, 1/64, ..., 1. May leave 0..1 (overshoot).
pub const CurveTable = [curve_samples + 1]f32;

pub const linear_curve: CurveTable = blk: {
    var t: CurveTable = undefined;
    for (&t, 0..) |*v, i| v.* = @as(f32, @floatFromInt(i)) / curve_samples;
    break :blk t;
};

pub const Animation = struct {
    /// 0 disables animations.
    duration_ms: u32 = 0,
    curve: CurveTable = linear_curve,
};

/// A modifier(+button) combination the WM wants to intercept. null button = any button.
pub const PointerGrab = struct { mods: Mods, button: ?Button };

/// Keysym values are shared by X11 and xkbcommon.
pub const Keysym = u32;

pub const KeyCombo = struct { mods: Mods, keysym: Keysym };

/// A key typed into the input bar: its keysym, modifiers, and the UTF-8 text it types.
pub const PromptKey = struct {
    keysym: Keysym,
    mods: Mods,
    text_buf: [8]u8 = undefined,
    text_len: u8 = 0,

    pub fn text(k: *const PromptKey) []const u8 {
        return k.text_buf[0..k.text_len];
    }
};

pub const WindowKind = enum { normal, floating, dock };

pub const WindowHandle = u64;

pub const Point = struct { x: i32, y: i32 };

pub const BorderColors = struct { top: u32, bottom: u32, left: u32, right: u32 };

pub const Side = enum { top, bottom, left, right };
