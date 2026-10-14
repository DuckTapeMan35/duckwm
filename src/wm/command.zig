const std = @import("std");
const graph_mod = @import("graph");
const core = @import("core.zig");
const types = @import("types");
const layouts = @import("./commands/layouts.zig");
const navigation = @import("navigation.zig");

const WM = core.WM;
const Node = graph_mod.Node;
const Constraint = graph_mod.Constraint;

const handlers = .{
    @import("commands/windows.zig"),
    @import("commands/constraints.zig"),
    @import("commands/nodes.zig"),
    @import("commands/view.zig"),
    @import("commands/input.zig"),
    @import("commands/appearance.zig"),
    @import("commands/workspaces.zig"),
    @import("commands/system.zig"),
    @import("commands/layouts.zig"),
};

pub const NodeId = u32;

/// What happens to a node's neighbors when it's removed ("empty" leaves its slot empty).
pub const ReparentStrategy = enum { promote, remove, empty };

pub const One = struct { id: NodeId };
pub const Pair = struct { a: NodeId, b: NodeId };
pub const Axis = enum { h, v };
/// Constraint names as the API spells them ("fixed_x", "split", ...).
pub const ConstraintKind = std.meta.Tag(Constraint);

pub const Dir = enum { left, right, up, down };

pub const Side = enum { top, bottom, left, right };

pub const Gaps = struct { inner_h: u32, inner_v: u32, outer_h: u32, outer_v: u32 };

/// Result of a command. Small enough to serialize to Lua, JSON or protobuf.
pub const Value = union(enum) {
    nil,
    boolean: bool,
    integer: i64,
    number: f64,
    string: []const u8,
    list: []const Value,
    map: []const Field,
    /// Several return values: separate results in Lua, a list elsewhere.
    /// Only valid as a command's top-level result, not inside a list or map.
    multi: []const Value,

    pub const Field = struct { key: []const u8, value: Value };
};

/// One request. The payload's fields are the arguments, in order.
pub const Command = union(enum) {
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

    // window state
    kill_client,
    toggle_floating,
    toggle_fullscreen,

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
    set_node_window: struct { id: NodeId, window: types.WindowHandle },
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
    set_resize_modifier: struct { mods: types.Mods },
    set_float_modifier: struct { mods: types.Mods },
    set_pan_modifier: struct { mods: types.Mods },
    set_pan_button: struct { button: types.Button },
    set_float_move_button: struct { button: types.Button },
    set_float_resize_button: struct { button: types.Button },

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
    force_rgb_frames: struct { class: []const u8 },

    // workspaces
    switch_to_workspace: struct { index: u32 },
    send_to_workspace: struct { id: NodeId, index: u32 },
    enter_workspace_by_id: One,
    create_nested_workspace,
    enter_nested,
    enter_nested_by_id: One,
    leave_nested,
    set_workspace_switch_mode: struct { mode: navigation.WorkspaceSwitchMode },
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
    set_layout: struct { layout: layouts.LayoutSpec },
    print_graph,
};

fn count_handlers(comptime name: []const u8) usize {
    @setEvalBranchQuota(100000);
    comptime var n: usize = 0;
    inline for (handlers) |m| {
        if (@hasDecl(m, name)) n += 1;
    }
    return n;
}

/// The handler file that defines `pub fn <name>`.
fn module_for(comptime name: []const u8) type {
    @setEvalBranchQuota(100000);
    inline for (handlers) |m| {
        if (@hasDecl(m, name)) return m;
    }
    unreachable;
}

/// Apply one command. Must be called inside a transaction.
/// arena holds anything the returned Value points to.
pub fn execute(wm: *WM, cmd: Command, arena: std.mem.Allocator) !Value {
    switch (cmd) {
        inline else => |args, tag| {
            const name = @tagName(tag);
            if (comptime count_handlers(name) != 1)
                @compileError("command '" ++ name ++ "' needs exactly one handler, in one of the files in `handlers`");
            return @field(module_for(name), name)(wm, args, arena);
        },
    }
}

pub const RunError = error{Rejected};

/// Run commands as one transaction: all of them take effect, or none do.
/// results must be at least as long as cmds.
pub fn run(wm: *WM, cmds: []const Command, arena: std.mem.Allocator, results: []Value) !void {
    const tx = wm.tx_begin();
    for (cmds, 0..) |cmd, i| {
        results[i] = execute(wm, cmd, arena) catch |err| {
            wm.tx_end(tx, false);
            return err;
        };
    }
    if (!wm.tx_finish(tx, true)) return error.Rejected;
}
