const std = @import("std");
pub const wire = @import("wire.zig");
pub const json = @import("json.zig");

/// A node: by id, or a keyed container that duckwm creates on first use and
/// destroys once no layout refers to it. Keys belong to the workspace.
pub const Ref = union(enum) {
    id: NodeId,
    key: u32,

    /// JSON and Lua accept a bare number for .id
    pub const shorthand = "id";
};

pub const PromptKeys = enum { emacs, vi };

pub const Other = struct { other: Ref };

/// Constraint, with ids instead of pointers. Variant names are the API's
/// constraint type names, and must stay identical to Constraint's.
pub const ConstraintSpec = union(enum) {
    left_of: Other,
    right_of: Other,
    above: Other,
    below: Other,
    align_left: Other,
    align_top: Other,
    align_right: Other,
    align_bottom: Other,
    equal_width: Other,
    equal_height: Other,
    fixed_x: struct { value: i32 },
    fixed_y: struct { value: i32 },
    fixed_width: struct { value: u32 },
    fixed_height: struct { value: u32 },
    fixed_ratio: struct { value: f64 },
    grid_cell: struct { col: u32, row: u32, cols: u32, rows: u32, container: Ref },
    grid_cell_abs: struct { x: i32, y: i32, w: u32, h: u32, container: Ref },
    split: struct { container: Ref, axis: Axis, ratios: []const f64, children: []const Ref },
};

pub const NodeSpec = struct { id: Ref, constraints: ?[]const ConstraintSpec };
pub const LayoutSpec = struct { nodes: []const NodeSpec };

pub const NodeId = u32;

pub const WorkspaceSwitchMode = enum { none, previous };

pub const WindowHandle = u64;
pub const Mods = u32;
pub const Button = u32;

/// What happens to a node's neighbors when it's removed ("empty" leaves its slot empty).
pub const ReparentStrategy = enum { promote, remove, empty };

pub const One = struct { id: NodeId };
pub const Pair = struct { a: NodeId, b: NodeId };
pub const Axis = enum { h, v };
/// Constraint names as the API spells them. Spelled out rather than derived
/// from graph.Constraint, so reordering the graph's union can't renumber it.
pub const ConstraintKind = enum {
    left_of,
    right_of,
    above,
    below,
    align_left,
    align_top,
    align_right,
    align_bottom,
    equal_width,
    equal_height,
    fixed_ratio,
    fixed_width,
    fixed_height,
    fixed_x,
    fixed_y,
    grid_cell,
    grid_cell_abs,
    split,
};

pub const Dir = enum { left, right, up, down };

pub const Side = enum { top, bottom, left, right };

pub const Gaps = struct { inner_h: u32, inner_v: u32, outer_h: u32, outer_v: u32 };

/// A function the client keeps and duckwm calls back: a Lua function when
/// the command comes from Lua, an id the client chose when it comes from a socket.
pub const Callback = struct { id: u64 };

pub const CurvePreset = enum { linear, ease_in, ease_out, ease_in_out };

/// An animation easing curve.
pub const Curve = union(enum) {
    preset: CurvePreset,
    /// A CSS cubic-bezier; x1 and x2 within 0..1.
    bezier: struct { x1: f32, y1: f32, x2: f32, y2: f32 },
    /// Values at evenly spaced t from 0 to 1 (at least 2), resampled as needed.
    samples: struct { values: []const f32 },
};

/// Result of a command. Small enough to serialize to Lua, JSON or protobuf.
pub const Value = union(enum) {
    nil,
    boolean: bool,
    integer: i64,
    number: f64,
    str: []const u8,
    list: []const Value,
    map: []const Field,
    /// Several return values: separate results in Lua, a list elsewhere.
    /// Only valid as a command's top-level result, not inside a list or map.
    multi: []const Value,

    pub const Field = struct { key: []const u8, value: Value };
};

// beware the giant fuckyou enum and struct

pub const CommandId = enum(u32) {
    // focus, exchange, window state: 1-99
    focus_left = 1,
    focus_right = 2,
    focus_up = 3,
    focus_down = 4,
    focus = 5,
    get_focused = 6,
    exchange_left = 7,
    exchange_right = 8,
    exchange_up = 9,
    exchange_down = 10,
    kill_client = 11,
    toggle_floating = 12,
    toggle_fullscreen = 13,

    // constraints: 100-199
    left_of = 100,
    right_of = 101,
    above = 102,
    below = 103,
    align_left = 104,
    align_top = 105,
    align_right = 106,
    align_bottom = 107,
    equal_width = 108,
    equal_height = 109,
    float_left_of = 110,
    float_right_of = 111,
    float_above = 112,
    float_below = 113,
    float_align_left = 114,
    float_align_top = 115,
    float_align_right = 116,
    float_align_bottom = 117,
    float_equal_width = 118,
    float_equal_height = 119,
    float_clear_constraints = 120,
    fixed_width = 121,
    fixed_height = 122,
    fixed_x = 123,
    fixed_y = 124,
    fixed_ratio = 125,
    grid_cell = 126,
    grid_cell_abs = 127,
    split = 128,
    clear_constraints = 129,
    remove_constraint = 130,

    // nodes: 200-299
    create_root_node = 200,
    create_empty_node = 201,
    create_container = 202,
    destroy_container = 203,
    remove_node = 204,
    reparent = 205,
    set_reparent_strategy = 206,
    unregister_node = 207,
    set_node_empty = 208,
    set_node_window = 209,
    move_window_to_node = 210,
    get_container_of = 211,
    get_node_type = 212,
    get_node_geometry = 213,
    get_node_info = 214,
    get_split_ratios = 215,
    get_all_windows = 216,

    // screen, pan, resizing: 300-399
    screen_width = 300,
    screen_height = 301,
    get_work_area = 302,
    set_pan = 303,
    pan_by = 304,
    get_pan = 305,
    set_virtual_size = 306,
    set_pan_disabled = 307,
    set_lock_horizontal_resize = 308,
    set_lock_vertical_resize = 309,
    resize_edge = 310,
    resize_corner = 311,
    resize_focused_edge = 312,
    resize_focused_corner = 313,
    set_zoom = 314,
    get_zoom = 315,

    // windows: 400-499
    get_window_class = 400,
    get_window_name = 401,
    get_window_pid = 402,
    set_floating = 403,
    set_fullscreen = 404,
    get_urgent = 405,
    set_urgent = 406,
    hide_window = 407,
    show_window = 408,
    register_swallow = 409,
    unregister_swallow = 410,
    scratchpad_toggle = 411,
    scratchpad_show = 412,
    scratchpad_hide = 413,
    get_scratchpad = 414,
    add_rule = 415,
    remove_rule = 416,

    // input: 500-599
    set_resize_modifier = 500,
    set_float_modifier = 501,
    set_pan_modifier = 502,
    set_pan_button = 503,
    set_float_move_button = 504,
    set_float_resize_button = 505,
    set_click_to_focus = 506,
    set_focus_follows_mouse = 507,
    get_cursor_pos = 508,
    get_cursor_relative_to_focused = 509,
    warp_cursor = 510,
    warp_cursor_to_node = 511,
    get_mouse_node = 512,
    set_cursor_theme = 513,
    set_keyboard_layout = 514,
    set_keyboard_layout_index = 515,
    bind_commands = 516,
    unbind = 517,
    bind = 518,
    get_keybinds = 519,
    read_line = 520,
    set_prompt_keys = 521,

    // appearance: 600-699
    set_default_focused_border_color = 600,
    set_default_unfocused_border_color = 601,
    set_default_urgent_border_color = 602,
    set_border_width = 603,
    set_node_focused_border_color = 604,
    set_node_unfocused_border_color = 605,
    clear_node_focused_border_color = 606,
    clear_node_unfocused_border_color = 607,
    set_node_border_side_color = 608,
    clear_node_border_side_colors = 609,
    get_node_border_side_colors = 610,
    set_border_side_colors_focused_only = 611,
    set_gaps = 612,
    set_gaps_workspace = 613,
    set_preview_colors = 614,
    set_preview_colors_workspace = 615,
    set_preview_font = 616,
    set_preview_font_workspace = 617,
    set_preview_max_icon_size = 618,
    set_argb_frames = 619,
    force_rgb_frames = 620,
    set_indicator_color = 621,
    set_node_indicator = 622,
    clear_node_indicator = 623,
    set_animation = 624,
    message = 625,

    // workspaces: 700-799
    switch_to_workspace = 700,
    send_to_workspace = 701,
    enter_workspace_by_id = 702,
    create_nested_workspace = 703,
    enter_nested = 704,
    enter_nested_by_id = 705,
    leave_nested = 706,
    set_workspace_switch_mode = 707,
    set_autoclean = 708,
    cleanup_left_behind = 709,
    get_workspace = 710,
    get_workspace_positions = 711,
    get_workspace_states = 712,
    get_current_workspace_position = 713,
    get_workspaces_at_level = 714,
    get_current_workspace = 715,
    get_current_level = 716,
    get_node_level = 717,

    // processes: 800-899
    spawn = 800,
    setenv = 801,
    quit = 802,
    exec_once = 803,
    reload_config = 804,
    eval = 805,

    // layouts: 900-999
    get_layout = 900,
    set_layout = 901,
    print_graph = 902,
    set_arranger = 903,
    register_arranger = 904,
    set_default_arranger = 905,
    get_arranger_name = 906,
    get_arranger_index = 907,
    set_arranger_index = 908,
    print_graph_pretty = 909,

    // outputs: 1000-1099
    get_outputs = 1000,
    focus_output = 1001,
    send_to_output = 1002,
    get_output_states = 1003,

    // groups: 1100-1199
    create_group = 1100,
    ungroup = 1101,
    move_to_group = 1102,
    get_group = 1103,
    get_group_members = 1104,
    set_group_outline = 1105,
    set_group_outline_of = 1106,
    focus_parent = 1107,
    focus_child = 1108,
};

/// One request. The payload's fields are the arguments, in order.
pub const Command = union(CommandId) {
    // focus
    focus_left,
    focus_right,
    focus_up,
    focus_down,
    focus: struct { id: NodeId },
    get_focused,

    // exchange
    exchange_left,
    exchange_right,
    exchange_up,
    exchange_down,

    // window state
    kill_client,
    toggle_floating,
    toggle_fullscreen,

    // constraints between two nodes
    left_of: Pair,
    right_of: Pair,
    above: Pair,
    below: Pair,
    align_left: Pair,
    align_top: Pair,
    align_right: Pair,
    align_bottom: Pair,
    equal_width: Pair,
    equal_height: Pair,

    // the same for floats: placed next to b first, then solved right away
    float_left_of: Pair,
    float_right_of: Pair,
    float_above: Pair,
    float_below: Pair,
    float_align_left: Pair,
    float_align_top: Pair,
    float_align_right: Pair,
    float_align_bottom: Pair,
    float_equal_width: Pair,
    float_equal_height: Pair,
    float_clear_constraints: One,

    // fixed values
    fixed_width: struct { id: NodeId, value: u32 },
    fixed_height: struct { id: NodeId, value: u32 },
    fixed_x: struct { id: NodeId, value: i32 },
    fixed_y: struct { id: NodeId, value: i32 },
    fixed_ratio: struct { id: NodeId, ratio: f64 },

    // containers
    grid_cell: struct { id: NodeId, col: u32, row: u32, cols: u32, rows: u32, container: NodeId },
    grid_cell_abs: struct { id: NodeId, x: i32, y: i32, w: u32, h: u32, container: NodeId },
    split: struct { container: NodeId, axis: Axis, ratios: []const f64, children: []const NodeId },

    // removal
    clear_constraints: One,
    remove_constraint: struct { id: NodeId, kind: ConstraintKind },

    // nodes
    create_root_node,
    create_empty_node,
    create_container,
    destroy_container: One,
    remove_node: One,
    reparent: struct { child: NodeId, parent: NodeId },
    set_reparent_strategy: struct { id: NodeId, strategy: ?ReparentStrategy },
    unregister_node: One,
    set_node_empty: One,
    set_node_window: struct { id: NodeId, window: WindowHandle },
    move_window_to_node: struct { src: NodeId, dst: NodeId },

    // node queries
    get_container_of: One,
    get_node_type: One,
    get_node_geometry: One,
    get_node_info: One,
    get_split_ratios: One,
    get_all_windows,

    // screen and work area
    screen_width,
    screen_height,
    get_work_area,

    // pan and virtual size (current workspace)
    set_pan: struct { x: i32, y: i32 },
    pan_by: struct { dx: i32, dy: i32 },
    get_pan,
    set_virtual_size: struct { width: u32, height: u32 },
    set_pan_disabled: struct { disabled: bool },
    set_lock_horizontal_resize: struct { locked: bool },
    set_lock_vertical_resize: struct { locked: bool },

    // resizing
    resize_edge: struct { id: NodeId, direction: Dir, delta: i32 },
    resize_corner: struct { id: NodeId, dx: i32, dy: i32 },
    resize_focused_edge: struct { direction: Dir, delta: i32 },
    resize_focused_corner: struct { dx: i32, dy: i32 },

    /// zoom
    set_zoom: struct { zoom: f64 },
    get_zoom,

    // window info
    get_window_class: One,
    get_window_name: One,
    get_window_pid: One,

    // window state
    set_floating: struct { id: NodeId, floating: bool },
    set_fullscreen: struct { id: NodeId, fullscreen: bool },
    get_urgent: One,
    set_urgent: struct { id: NodeId, urgent: bool },
    hide_window: One,
    show_window: One,

    // swallowing
    register_swallow: struct { terminal: []const u8, child: []const u8 },
    unregister_swallow: struct { terminal: []const u8, child: []const u8 },

    // scratchpad
    scratchpad_toggle: One,
    scratchpad_show: One,
    scratchpad_hide: One,
    get_scratchpad,

    // rules
    add_rule: struct { callback: Callback },
    remove_rule: struct { id: u32 },

    // pointer bindings
    set_resize_modifier: struct { mods: Mods },
    set_float_modifier: struct { mods: Mods },
    set_pan_modifier: struct { mods: Mods },
    set_pan_button: struct { button: Button },
    set_float_move_button: struct { button: Button },
    set_float_resize_button: struct { button: Button },

    // focus behavior
    set_click_to_focus: struct { enabled: bool },
    set_focus_follows_mouse: struct { enabled: bool },

    // cursor
    get_cursor_pos,
    get_cursor_relative_to_focused,
    warp_cursor: struct { x: i32, y: i32 },
    warp_cursor_to_node: One,
    get_mouse_node,
    set_cursor_theme: struct { theme: []const u8, size: u32 },

    // input
    set_keyboard_layout: struct { layout: []const u8, variant: ?[]const u8, options: ?[]const u8, model: ?[]const u8 },
    set_keyboard_layout_index: struct { index: u32 },
    bind_commands: struct { mods: Mods, key: []const u8, commands: []const Command },
    unbind: struct { mods: Mods, key: []const u8 },
    bind: struct { mods: Mods, key: []const u8, callback: Callback },
    get_keybinds,
    read_line: struct { prompt: []const u8, callback: Callback, initial: ?[]const u8 },
    set_prompt_keys: struct { keys: PromptKeys },

    // border colors and width
    set_default_focused_border_color: struct { color: u32 },
    set_default_unfocused_border_color: struct { color: u32 },
    set_default_urgent_border_color: struct { color: u32 },
    set_border_width: struct { width: u32 },
    set_node_focused_border_color: struct { id: NodeId, color: u32 },
    set_node_unfocused_border_color: struct { id: NodeId, color: u32 },
    clear_node_focused_border_color: One,
    clear_node_unfocused_border_color: One,
    set_node_border_side_color: struct { id: NodeId, side: Side, color: u32 },
    clear_node_border_side_colors: One,
    get_node_border_side_colors: One,
    set_border_side_colors_focused_only: struct { enabled: bool },

    // gaps
    set_gaps: struct { inner_h: u32, inner_v: u32, outer_h: u32, outer_v: u32 },
    set_gaps_workspace: struct { id: NodeId, inner_h: u32, inner_v: u32, outer_h: u32, outer_v: u32 },

    // previews
    set_preview_colors: struct { bg: u32, win_bg: u32, border: u32, text: u32 },
    set_preview_colors_workspace: struct { id: NodeId, bg: u32, win_bg: u32, border: u32, text: u32 },
    set_preview_font: struct { name: []const u8 },
    set_preview_font_workspace: struct { id: NodeId, name: []const u8 },
    set_preview_max_icon_size: struct { size: u32 },

    // frames
    set_argb_frames: struct { enabled: bool },
    force_rgb_frames: struct { class_name: []const u8 },
    set_indicator_color: struct { color: u32 },
    set_node_indicator: struct { id: NodeId, side: Side },
    clear_node_indicator: One,
    // animation: null curve is ease_out; duration 0 turns animation off
    set_animation: struct { duration_ms: u32, curve: ?Curve },
    /// Text in the input bar for timeout_ms (0: 3s).
    message: struct { text: []const u8, timeout_ms: u32 },

    // workspaces
    switch_to_workspace: struct { index: u32 },
    send_to_workspace: struct { id: NodeId, index: u32 },
    enter_workspace_by_id: One,
    create_nested_workspace,
    enter_nested,
    enter_nested_by_id: One,
    leave_nested,
    set_workspace_switch_mode: struct { mode: WorkspaceSwitchMode },
    set_autoclean: struct { enabled: bool },
    cleanup_left_behind,

    // workspace queries
    get_workspace: struct { index: u32 },
    get_workspace_positions,
    get_workspace_states,
    get_current_workspace_position,
    get_workspaces_at_level,
    get_current_workspace,
    get_current_level,
    get_node_level: One,

    // processes and environment
    spawn: struct { argv: []const []const u8 },
    setenv: struct { key: []const u8, value: []const u8 },
    quit,
    exec_once: struct { argv: []const []const u8 },
    reload_config,
    eval: struct { source: []const u8 },

    // layouts
    get_layout,
    set_layout: struct { layout: LayoutSpec },
    print_graph,

    // arrangers
    set_arranger: struct { factory: Callback, name: ?[]const u8 },
    register_arranger: struct { id: NodeId, factory: Callback, name: ?[]const u8 },
    set_default_arranger: struct { factory: Callback, name: ?[]const u8 },
    get_arranger_name,
    get_arranger_index,
    set_arranger_index: struct { index: i32 },
    print_graph_pretty: struct { cols: ?u32, rows: ?u32 },

    // outputs
    get_outputs,
    focus_output: struct { dir: Dir },
    send_to_output: struct { id: NodeId, dir: Dir },
    get_output_states,

    // groups
    create_group: struct { ids: ?[]const NodeId },
    ungroup: One,
    move_to_group: struct { id: NodeId, group: ?NodeId },
    get_group: One,
    get_group_members: One,
    set_group_outline: struct { width: u32, color: u32 },
    set_group_outline_of: struct { id: NodeId, width: ?u32, color: ?u32 },
    focus_parent,
    focus_child,
};

/// A batch of commands, run as one transaction: all of them take effect, or none do.
pub const Request = struct { commands: []const Command };

/// What duckwm calls a callback with.
pub const CallArgs = union(enum) {
    /// A bound key was pressed.
    key,
    /// A rule, for one window event.
    rule: struct { event: []const u8, id: NodeId },
    /// An arranger, for one event in its workspace.
    arranger: Snapshot,
    /// A factory (set_arranger, set_default_arranger): Return.callback is the arranger it made.
    factory,
    /// read_line's callback: the line that was typed.
    line: struct { text: []const u8 },
};

/// duckwm calling one of the client's callbacks, inside a transaction. The
/// client may send requests (they run in that transaction), then a Return.
pub const Call = struct {
    callback: u64,
    args: CallArgs,
    /// Set off by a request of this client's that's still running. A call that
    /// isn't, arriving while the client waits on a response, crossed that
    /// request on the wire: duckwm runs the request inside this call, and
    /// answers it before anything the callback sends.
    nested: bool = false,
};

/// The end of a Call: commands to run in the same transaction, or an error
/// that rolls it back. A factory sets callback to the arranger it made; an
/// arranger may return the workspace's whole layout and its next state.
pub const Return = struct {
    commands: []const Command,
    err: ?[]const u8,
    callback: ?u64,
    layout: ?LayoutSpec,
    state: ?Value,
};

/// Everything a client sends.
pub const ClientMessage = union(enum) {
    request: Request,
    ret: Return,
};

pub const Rect = struct { x: i32, y: i32, width: u32, height: u32 };

pub const ArrangerEvent = enum { pre_map, map, unmap, focus, resize, area };

pub const WindowInfo = struct { id: NodeId, geometry: Rect };

/// Everything an arranger needs for one event, so it can answer without queries.
pub const Snapshot = struct {
    event: ArrangerEvent,
    id: NodeId,
    prev_id: ?NodeId,
    work_area: Rect,
    /// The cursor relative to the focused window, as get_cursor_relative_to_focused.
    cursor_dx: i32,
    cursor_dy: i32,
    focused: ?NodeId,
    /// This workspace's tiled windows, in order.
    windows: []const WindowInfo,
    /// The layout as duckwm has it now, keyed containers by key, ratios after resizes.
    layout: LayoutSpec,
    /// What this arranger returned last time, null at first.
    state: ?Value,
};

test {
    _ = wire;
    _ = json;
}
