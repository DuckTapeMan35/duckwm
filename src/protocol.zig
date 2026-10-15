const std = @import("std");
pub const wire = @import("wire.zig");

pub const Other = struct { other: NodeId };

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
    grid_cell: struct { col: u32, row: u32, cols: u32, rows: u32, container: NodeId },
    grid_cell_abs: struct { x: i32, y: i32, w: u32, h: u32, container: NodeId },
    split: struct { container: NodeId, axis: Axis, ratios: []const f64, children: []const NodeId },
};

pub const NodeSpec = struct { id: NodeId, constraints: ?[]const ConstraintSpec };
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

    // layouts: 900-999
    get_layout = 900,
    set_layout = 901,
    print_graph = 902,
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

    // keyboard layout
    set_keyboard_layout: struct { layout: []const u8, variant: ?[]const u8, options: ?[]const u8, model: ?[]const u8 },
    set_keyboard_layout_index: struct { index: u32 },

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

    // layouts
    get_layout,
    set_layout: struct { layout: LayoutSpec },
    print_graph,
};

test {
    _ = wire;
}
