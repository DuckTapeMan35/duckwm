const std = @import("std");
const types = @import("types");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;
const xkb = @import("xkbcommon");
const surface = @import("surface.zig");
const output = @import("outputs.zig");
const windows = @import("windows.zig");
const Window = windows.Window;
const bars = @import("bars.zig");
const previews = @import("previews.zig");
const outlines = @import("outlines.zig");
const input = @import("input.zig");
const sequence = @import("sequence.zig");

/// Something core places under a window handle. Both kinds share the fields
/// core sets (in_scene, raise_serial, want_border_*), so `inline else` can
/// set them without caring which it is.
pub const Placed = union(enum) {
    window: *Window,
    preview: *previews.Preview,
};

// State is heap-allocated, because libwayland keeps pointers to it in listeners
// and the Backend value itself gets copied into WM.
pub const State = struct {
    allocator: std.mem.Allocator,
    display: *wl.Display,
    next_output_id: u32 = 1,
    registry: *wl.Registry,

    wm: ?*river.WindowManagerV1 = null,
    xkb_bindings: ?*river.XkbBindingsV1 = null,
    layout_index: ?u32 = null,
    layer_shell: ?*river.LayerShellV1 = null,
    seat: ?*river.SeatV1 = null,
    layer_seat: ?*river.LayerShellSeatV1 = null,
    outputs: std.ArrayListUnmanaged(*output.Output) = .empty,
    /// The output the pointer was last on, to report crossings.
    pointer_output: u32 = 0,
    /// Until multimonitor: the first output is "the screen".
    primary: ?*output.Output = null,

    unavailable: bool = false,
    finished: bool = false,

    // Sequence bookkeeping.
    in_manage: bool = false,
    render_pending: bool = false,
    want_manage: bool = false,
    dirty_sent: bool = false,
    pumped: bool = false,

    // Events for core, in order.
    events: std.ArrayListUnmanaged(types.Event) = .empty,
    event_head: usize = 0,

    // Windows.
    next_handle: types.WindowHandle = 1,
    windows: std.AutoHashMapUnmanaged(types.WindowHandle, *Window) = .empty,
    by_obj: std.AutoHashMapUnmanaged(*river.WindowV1, *Window) = .empty,
    /// Created, properties still arriving: announced at the next manage_start.
    fresh: std.ArrayListUnmanaged(*Window) = .empty,
    /// Closed this dispatch: destroyed once dispatching is done.
    dead: std.ArrayListUnmanaged(*Window) = .empty,

    // Desired state recorded from core.
    order: std.ArrayListUnmanaged(types.WindowHandle) = .empty,
    fullscreen: ?types.WindowHandle = null,
    focus: ?types.WindowHandle = null,
    focus_dirty: bool = false,
    closes: std.ArrayListUnmanaged(types.WindowHandle) = .empty,
    raise_clock: u64 = 0,
    compositor: ?*wl.Compositor = null,
    shm: ?*wl.Shm = null,
    fonts: surface.Fonts = .{},
    previews: std.AutoHashMapUnmanaged(types.WindowHandle, *previews.Preview) = .empty,
    /// Group outlines, by core's key.
    outlines: std.AutoHashMapUnmanaged(u64, *outlines.Outline) = .empty,
    error_bar: ?*bars.ErrorBar = null,
    prompt_bar: ?*bars.PromptBar = null,
    scratch: std.ArrayListUnmanaged(sequence.Stacked) = .empty,

    // Input.
    keys: std.ArrayListUnmanaged(*input.KeyBinding) = .empty,
    buttons: std.ArrayListUnmanaged(*input.ButtonBinding) = .empty,
    click_to_focus: bool = false,
    hovered: ?types.WindowHandle = null,
    pointer_pos: types.Point = .{ .x = 0, .y = 0 },
    op_active: bool = false,
    op_start_pending: bool = false,
    op_end_pending: bool = false,
    op_origin: types.Point = .{ .x = 0, .y = 0 },
    op_button: types.Button = 1,
    /// op_release already reported the release; swallow the binding's own.
    suppress_release: bool = false,
    warp: ?types.Point = null,
    layer_focus_exclusive: bool = false,
    cursor_theme: ?[:0]u8 = null,
    cursor_size: u32 = 24,
    xkb_config: ?*river.XkbConfigV1 = null,
    keyboards: std.ArrayListUnmanaged(*river.XkbKeyboardV1) = .empty,
    /// Accepted by river and applied to every keyboard, including new ones.
    keymap: ?*river.XkbKeymapV1 = null,
    /// Sent, waiting for river's success/failure.
    pending_keymap: ?*river.XkbKeymapV1 = null,
    // The keyboard as a plain Wayland client sees it: keys typed into the input bar.
    wl_seat: ?*wl.Seat = null,
    keyboard: ?*wl.Keyboard = null,
    xkb_ctx: ?*xkb.Context = null,
    xkb_keymap: ?*xkb.Keymap = null,
    xkb_state: ?*xkb.State = null,
    repeat_rate: i32 = 25,
    repeat_delay: i32 = 600,
    /// The held key being repeated into the bar (an xkb keycode).
    repeat_key: ?u32 = null,
    repeat_next_ms: i64 = 0,

    // Animations.
    anim: types.Animation = .{},
    /// Some window is mid-animation: keep requesting frames.
    animating: bool = false,
    last_frame_ms: i64 = 0,
    /// An animation just ended: final sizes must be proposed.
    settle: bool = false,
    /// Hovered window reported this batch; acted on at manage_start.
    pending_enter: ?types.WindowHandle = null,
    pos_at_last_manage: types.Point = .{ .x = 0, .y = 0 },

    /// Queue an event for core.
    pub fn push(s: *State, ev: types.Event) void {
        // Coalesce: only the latest pointer position and one relayout matter.
        if (s.events.items.len > s.event_head) {
            const last = &s.events.items[s.events.items.len - 1];
            if (ev == .pointer_motion and last.* == .pointer_motion) {
                last.* = ev;
                return;
            }
            if (ev == .reserved_area_changed and last.* == .reserved_area_changed) return;
        }
        s.events.append(s.allocator, ev) catch {};
    }

    /// Core changed something that river must hear about.
    pub fn mark(s: *State) void {
        if (!s.in_manage) s.want_manage = true;
    }

    /// A window core may still act on: known, and not closed.
    pub fn live(s: *State, h: types.WindowHandle) ?*Window {
        const w = s.windows.get(h) orelse return null;
        return if (w.closed) null else w;
    }

    /// What a handle core placed stands for: a live window or a preview.
    pub fn placed(s: *State, h: types.WindowHandle) ?Placed {
        if (s.previews.get(h)) |p| return .{ .preview = p };
        if (s.live(h)) |w| return .{ .window = w };
        return null;
    }

    /// A new duckwm-drawn surface. One that takes no input lets clicks through
    /// to whatever is under it.
    pub fn new_surface(s: *State, takes_input: bool) !surface.ShellSurface {
        const wm = s.wm orelse return error.NoWindowManager;
        const comp = s.compositor orelse return error.NoCompositor;
        var surf = try surface.ShellSurface.create(wm, comp);
        if (!takes_input) {
            errdefer surf.destroy();
            // An empty input region (applied with its first buffer).
            const region = try comp.createRegion();
            defer region.destroy();
            surf.surface.setInputRegion(region);
        }
        return surf;
    }

    // ---- reading the socket ----
    /// Read whatever the socket has, without blocking, and dispatch it.
    pub fn pump(s: *State) void {
        const d = s.display;
        while (!d.prepareRead()) {
            if (d.dispatchPending() != .SUCCESS) return s.lost_connection();
        }
        _ = d.flush();

        // The main loop's poll may have woken for IPC or inotify, so the
        // socket isn't necessarily readable; readEvents would block.
        var pfd = [1]std.posix.pollfd{.{ .fd = d.getFd(), .events = std.posix.POLL.IN, .revents = 0 }};
        const ready = std.posix.poll(&pfd, 0) catch 0;
        if (ready > 0) {
            if (d.readEvents() != .SUCCESS) return s.lost_connection();
        } else {
            d.cancelRead();
        }
        if (d.dispatchPending() != .SUCCESS) return s.lost_connection();
        windows.destroy_dead(s);
    }

    fn lost_connection(s: *State) void {
        _ = s;
        // river exited (or killed us). Nothing left to manage.
        std.debug.print("duckwm: lost connection to river, exiting\n", .{});
        std.process.exit(0);
    }
};
