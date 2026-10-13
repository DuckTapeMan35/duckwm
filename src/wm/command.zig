const std = @import("std");
const graph_mod = @import("graph");
const c = @import("libc");
const core = @import("core.zig");
const types = @import("types");
const workspaces = @import("workspaces.zig");
const layout_data = @import("layout_data.zig");

const WM = core.WM;
const Node = graph_mod.Node;
const Constraint = graph_mod.Constraint;

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
pub const PreviewColors = struct { bg: u32, win_bg: u32, border: u32, text: u32 };

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
    set_workspace_switch_mode: struct { mode: core.WorkspaceSwitchMode },
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
    set_layout: struct { layout: layout_data.LayoutSpec },
    print_graph,
};

/// Apply one command. Must be called inside a transaction.
/// arena holds anything the returned Value points to.
pub fn execute(wm: *WM, cmd: Command, arena: std.mem.Allocator) !Value {
    switch (cmd) {
        .focus_left => try wm.focus_left(),
        .focus_right => try wm.focus_right(),
        .focus_up => try wm.focus_up(),
        .focus_down => try wm.focus_down(),
        .focus => |a| wm.focus(wm.get_node_by_id(a.id) orelse return error.InvalidNode),
        .get_focused => {
            const f = wm.focused orelse return .nil;
            const id = wm.get_id_for_node(f) orelse return .nil;
            return .{ .integer = id };
        },

        .exchange_left => try wm.exchange_left(),
        .exchange_right => try wm.exchange_right(),
        .exchange_up => try wm.exchange_up(),
        .exchange_down => try wm.exchange_down(),

        .kill_client => try wm.kill_client(),
        .toggle_floating => try wm.toggle_floating(),
        .toggle_fullscreen => try wm.toggle_fullscreen(),

        inline .left_of,
        .right_of,
        .above,
        .below,
        .align_left,
        .align_top,
        .align_right,
        .align_bottom,
        .equal_width,
        .equal_height,
        => |p, tag| {
            const a, const b = try pair(wm, p);
            try add(a, @unionInit(Constraint, @tagName(tag), b));
        },

        inline .float_left_of,
        .float_right_of,
        .float_above,
        .float_below,
        .float_align_left,
        .float_align_top,
        .float_align_right,
        .float_align_bottom,
        .float_equal_width,
        .float_equal_height,
        => |p, tag| {
            const rel = comptime @tagName(tag)["float_".len..];
            const a, const b = try pair(wm, p);
            if (!a.floating) return error.NotFloating;
            place_beside(wm, a, b, rel);
            try add(a, @unionInit(Constraint, rel, b));
            wm.relayout();
        },

        .float_clear_constraints => |o| {
            const n = try node(wm, o.id);
            if (!n.floating) return error.NotFloating;
            const g = n.owner_graph orelse return error.NotInGraph;
            try g.replace_constraints(n, &.{});
            wm.relayout();
        },

        // Lenient: a node that's gone is not an error for these.
        .fixed_width => |f| if (wm.get_node_by_id(f.id)) |n| try add(n, .{ .fixed_width = f.value }),
        .fixed_height => |f| if (wm.get_node_by_id(f.id)) |n| try add(n, .{ .fixed_height = f.value }),
        .fixed_x => |f| if (wm.get_node_by_id(f.id)) |n| try add(n, .{ .fixed_x = f.value }),
        .fixed_y => |f| if (wm.get_node_by_id(f.id)) |n| try add(n, .{ .fixed_y = f.value }),
        .fixed_ratio => |f| {
            if (!(f.ratio > 0)) return error.OutOfRange;
            try add(try node(wm, f.id), .{ .fixed_ratio = @floatCast(f.ratio) });
        },

        .grid_cell => |g| {
            if (g.cols == 0 or g.rows == 0 or g.col >= g.cols or g.row >= g.rows) return error.InvalidGridCell;
            try add(try node(wm, g.id), .{ .grid_cell = .{
                .col = g.col,
                .row = g.row,
                .cols = g.cols,
                .rows = g.rows,
                .container = try node(wm, g.container),
            } });
        },
        .grid_cell_abs => |g| try add(try node(wm, g.id), .{ .grid_cell_abs = .{
            .x = g.x,
            .y = g.y,
            .w = g.w,
            .h = g.h,
            .container = try node(wm, g.container),
        } }),

        .split => |s| {
            const con = try layout_data.make_split(wm, s.container, s.axis, s.ratios, s.children);
            try add(con.split.container, con);
        },

        .clear_constraints => |o| if (wm.get_node_by_id(o.id)) |n| {
            const g = n.owner_graph orelse return .nil;
            try g.replace_constraints(n, &.{});
        },
        .remove_constraint => |r| if (wm.get_node_by_id(r.id)) |n| {
            const g = n.owner_graph orelse return .nil;
            var i: usize = 0;
            while (i < n.constraints.items.len) {
                if (n.constraints.items[i] == r.kind) g.remove_constraint_at(n, i) else i += 1;
            }
        },
        .create_root_node => return new_empty(wm, true),
        .create_empty_node, .create_container => return new_empty(wm, false),

        .destroy_container => |o| if (wm.get_node_by_id(o.id)) |n| {
            if (n.content != .empty) return error.NotAContainer;
            if (n.owner_graph) |g| g.remove_node(n);
        },
        .remove_node => |o| if (wm.get_node_by_id(o.id)) |n| {
            if (n.owner_graph) |g| g.remove_node(n);
        },

        .reparent => |r| {
            const child = try node(wm, r.child);
            const parent = try node(wm, r.parent);
            const g = child.owner_graph orelse return error.NotInGraph;
            var i: usize = 0;
            while (i < child.constraints.items.len) {
                if (child.constraints.items[i] == .grid_cell) g.remove_constraint_at(child, i) else i += 1;
            }
            try g.add_constraint(child, .{
                .grid_cell = .{
                    .col = 0,
                    .row = 0,
                    .cols = 1,
                    .rows = 1,
                    .container = parent,
                },
            });
        },

        .set_reparent_strategy => |s| if (wm.get_node_by_id(s.id)) |n| {
            // Not journaled: an optional union, too large for a field entry, set at layout setup.
            n.on_remove = if (s.strategy) |st| switch (st) {
                .promote => .promote,
                .remove => .remove,
                .empty => .leave_empty,
            } else null;
        },

        .unregister_node => |o| _ = wm.node_registry.remove(o.id),
        .set_node_empty => |o| wm.set_node_empty(o.id),
        .set_node_window => |s| try wm.set_node_window(s.id, s.window),
        .move_window_to_node => |m| try wm.move_window_to_node(m.src, m.dst),

        .get_container_of => |o| {
            const n = wm.get_node_by_id(o.id) orelse return .nil;
            const cont = graph_mod.get_container(n) orelse return .nil;
            return id_value(wm, cont);
        },
        .get_node_type => |o| {
            const n = wm.get_node_by_id(o.id) orelse return .nil;
            return .{ .string = type_name(n) };
        },
        .get_node_geometry => |o| {
            const n = wm.get_node_by_id(o.id) orelse return .nil;
            return .{ .map = try arena.dupe(Value.Field, &.{
                .{ .key = "x", .value = .{ .integer = n.x } },
                .{ .key = "y", .value = .{ .integer = n.y } },
                .{ .key = "width", .value = .{ .integer = n.width } },
                .{ .key = "height", .value = .{ .integer = n.height } },
            }) };
        },
        .get_node_info => |o| {
            const n = wm.get_node_by_id(o.id) orelse return .nil;
            return .{ .map = try arena.dupe(Value.Field, &.{
                .{ .key = "x", .value = .{ .integer = n.x } },
                .{ .key = "y", .value = .{ .integer = n.y } },
                .{ .key = "width", .value = .{ .integer = n.width } },
                .{ .key = "height", .value = .{ .integer = n.height } },
                .{ .key = "floating", .value = .{ .boolean = n.floating } },
                .{ .key = "type", .value = .{ .string = type_name(n) } },
            }) };
        },
        .get_split_ratios => |o| {
            const n = wm.get_node_by_id(o.id) orelse return .nil;
            for (n.constraints.items) |con| {
                if (con != .split) continue;
                const out = try arena.alloc(Value, con.split.count);
                for (out, con.split.ratios[0..con.split.count]) |*v, r| v.* = .{ .number = r };
                return .{ .list = out };
            }
            return .nil;
        },
        .get_all_windows => {
            // Real windows and workspace-preview nodes of the current workspace.
            var out: std.ArrayListUnmanaged(Value) = .empty;
            for (wm.current_graph.nodes.items) |n| {
                const h: types.WindowHandle = switch (n.content) {
                    .window => |w| w,
                    .workspace => n.preview_window orelse continue,
                    .empty => continue,
                };
                if (wm.window_to_node_id.get(h)) |id| try out.append(arena, .{ .integer = id });
            }
            return .{ .list = out.items };
        },
        .screen_width => return .{ .integer = wm.screen_width },
        .screen_height => return .{ .integer = wm.screen_height },
        .get_work_area => {
            const w = wm.get_work_area();
            return .{ .multi = try arena.dupe(Value, &.{
                .{ .integer = w.x },
                .{ .integer = w.y },
                .{ .integer = w.width },
                .{ .integer = w.height },
            }) };
        },

        .set_pan => |p| {
            const g = wm.current_graph;
            g.set(g, "pan_x", p.x);
            g.set(g, "pan_y", p.y);
            try wm.flush(g);
        },
        .pan_by => |p| {
            const g = wm.current_graph;
            g.set(g, "pan_x", g.pan_x + p.dx);
            g.set(g, "pan_y", g.pan_y + p.dy);
            try wm.flush(g);
        },
        .get_pan => return .{ .multi = try arena.dupe(Value, &.{
            .{ .integer = wm.current_graph.pan_x },
            .{ .integer = wm.current_graph.pan_y },
        }) },
        .set_virtual_size => |s| {
            const g = wm.current_graph;
            g.set(g, "virtual_width", s.width);
            g.set(g, "virtual_height", s.height);
        },
        .set_pan_disabled => |s| wm.current_graph.set(wm.current_graph, "pan_disabled", s.disabled),
        .set_lock_horizontal_resize => |s| wm.current_graph.set(wm.current_graph, "lock_horizontal_resize", s.locked),
        .set_lock_vertical_resize => |s| wm.current_graph.set(wm.current_graph, "lock_vertical_resize", s.locked),

        .resize_edge => |r| try wm.resize_edge(try node(wm, r.id), direction(r.direction), r.delta),
        .resize_corner => |r| try wm.resize_corner(try node(wm, r.id), r.dx, r.dy),
        .resize_focused_edge => |r| if (wm.focused) |n| try wm.resize_edge(n, direction(r.direction), r.delta),
        .resize_focused_corner => |r| if (wm.focused) |n| try wm.resize_corner(n, r.dx, r.dy),
        .get_window_class => |o| {
            const n = wm.get_node_by_id(o.id) orelse return .nil;
            if (n.content != .window) return .nil;
            return .{ .multi = try arena.dupe(Value, &.{
                try text(arena, n.info.class()),
                try text(arena, n.info.instance()),
            }) };
        },
        .get_window_name => |o| {
            const n = wm.get_node_by_id(o.id) orelse return .nil;
            if (n.content != .window) return .nil;
            return text(arena, n.info.title());
        },
        .get_window_pid => |o| {
            const n = wm.get_node_by_id(o.id) orelse return .nil;
            if (n.content != .window) return .nil;
            const pid = n.info.pid orelse return .nil;
            return .{ .integer = pid };
        },

        .set_floating => |s| if (wm.get_node_by_id(s.id)) |n| try set_floating(wm, s.id, n, s.floating),
        .set_fullscreen => |s| if (wm.get_node_by_id(s.id)) |n| {
            if (n.content != .window) return .nil;
            const already = if (n.owner_graph) |og| og.fullscreen_node == n else false;
            if (s.fullscreen == already) return .nil;
            wm.journal.set(wm, "focused", n);
            try wm.toggle_fullscreen();
        },
        .get_urgent => |o| {
            const n = wm.get_node_by_id(o.id) orelse return .{ .boolean = false };
            return .{ .boolean = n.urgent };
        },
        .set_urgent => |s| if (wm.get_node_by_id(s.id)) |n| {
            wm.journal.set(n, "urgent", s.urgent);
            try wm.flush(wm.current_graph);
        },
        .hide_window => |o| if (wm.get_node_by_id(o.id)) |n| {
            wm.journal.set(n, "hidden", true);
            if (WM.node_window(n)) |h| wm.backend.hide_window(h);
            try wm.rebuild_focus_edges();
        },
        .show_window => |o| if (wm.get_node_by_id(o.id)) |n| {
            wm.journal.set(n, "hidden", false);
            try wm.flush(wm.current_graph);
            if (WM.node_window(n)) |h| wm.backend.raise_window(h);
            try wm.rebuild_focus_edges();
            wm.focus(n);
        },

        .register_swallow => |p| {
            const terminal = try wm.allocator.dupe(u8, p.terminal);
            errdefer wm.allocator.free(terminal);
            const child = try wm.allocator.dupe(u8, p.child);
            errdefer wm.allocator.free(child);
            try wm.swallow_pairs.append(wm.allocator, .{ .terminal = terminal, .child = child });
        },
        .unregister_swallow => |p| {
            var i: usize = 0;
            while (i < wm.swallow_pairs.items.len) {
                const pair_ = wm.swallow_pairs.items[i];
                if (same_pair(pair_, p.terminal, p.child)) {
                    wm.allocator.free(pair_.terminal);
                    wm.allocator.free(pair_.child);
                    _ = wm.swallow_pairs.swapRemove(i);
                } else i += 1;
            }
        },

        .scratchpad_toggle => |o| try wm.toggle_scratchpad(o.id),
        .scratchpad_show => |o| try wm.show_scratchpad(o.id),
        .scratchpad_hide => |o| try wm.hide_scratchpad(o.id),

        .set_resize_modifier => |s| {
            wm.resize_modifier = s.mods;
            wm.sync_pointer_grabs();
        },
        .set_float_modifier => |s| {
            wm.float_move_modifier = s.mods;
            wm.sync_pointer_grabs();
        },
        .set_pan_modifier => |s| {
            wm.pan_modifier = s.mods;
            wm.sync_pointer_grabs();
        },
        .set_pan_button => |s| {
            wm.pan_button = try button(s.button);
            wm.sync_pointer_grabs();
        },
        .set_float_move_button => |s| wm.float_move_button = try button(s.button),
        .set_float_resize_button => |s| wm.float_resize_button = try button(s.button),

        .set_click_to_focus => |s| wm.set_click_to_focus(s.enabled),
        .set_focus_follows_mouse => |s| {
            if (wm.ffm_suspended) wm.saved_focus_follows_mouse = s.enabled else wm.focus_follows_mouse = s.enabled;
        },

        .get_cursor_pos => return point(arena, wm.backend.pointer_position()),
        .get_cursor_relative_to_focused => {
            const f = wm.focused orelse return point(arena, .{ .x = 0, .y = 0 });
            const p = wm.backend.pointer_position();
            const cen = center(f);
            return point(arena, .{ .x = p.x - cen.x, .y = p.y - cen.y });
        },
        .warp_cursor => |w| wm.backend.warp_pointer(.{ .x = w.x, .y = w.y }),
        .warp_cursor_to_node => |o| if (wm.get_node_by_id(o.id)) |n| wm.backend.warp_pointer(center(n)),
        .get_mouse_node => {
            const n = wm.node_at(wm.backend.pointer_position()) orelse return .nil;
            return id_value(wm, n);
        },
        .set_cursor_theme => |s| wm.backend.set_cursor_theme(s.theme, s.size),

        .set_keyboard_layout => |k| {
            if (!wm.set_keyboard_layout(.{
                .layout = k.layout,
                .variant = k.variant orelse "",
                .options = k.options orelse "",
                .model = k.model orelse "",
            })) return error.InvalidKeymap;
        },
        .set_keyboard_layout_index => |s| wm.set_keyboard_layout_index(s.index),
        .set_default_focused_border_color => |s| {
            wm.default_border_color_focused = s.color;
            try repaint(wm);
        },
        .set_default_unfocused_border_color => |s| {
            wm.default_border_color_unfocused = s.color;
            try repaint(wm);
        },
        .set_default_urgent_border_color => |s| {
            wm.default_border_color_urgent = s.color;
            try repaint(wm);
        },
        .set_border_width => |s| {
            wm.border_width = @intCast(s.width);
            wm.backend.publish_frame_extents(s.width);
            wm.relayout();
        },

        .set_node_focused_border_color => |s| {
            wm.journal.set(try node(wm, s.id), "border_color_focused", s.color);
            try repaint(wm);
        },
        .set_node_unfocused_border_color => |s| {
            wm.journal.set(try node(wm, s.id), "border_color_unfocused", s.color);
            try repaint(wm);
        },
        .clear_node_focused_border_color => |o| {
            wm.journal.set(try node(wm, o.id), "border_color_focused", null);
            try repaint(wm);
        },
        .clear_node_unfocused_border_color => |o| {
            wm.journal.set(try node(wm, o.id), "border_color_unfocused", null);
            try repaint(wm);
        },
        .set_node_border_side_color => |s| {
            const n = try node(wm, s.id);
            const color: ?u32 = s.color;
            switch (s.side) {
                .top => wm.journal.set(n, "border_color_top", color),
                .bottom => wm.journal.set(n, "border_color_bottom", color),
                .left => wm.journal.set(n, "border_color_left", color),
                .right => wm.journal.set(n, "border_color_right", color),
            }
            try repaint(wm);
        },
        .clear_node_border_side_colors => |o| {
            const n = try node(wm, o.id);
            wm.journal.set(n, "border_color_top", null);
            wm.journal.set(n, "border_color_bottom", null);
            wm.journal.set(n, "border_color_left", null);
            wm.journal.set(n, "border_color_right", null);
            try repaint(wm);
        },
        .get_node_border_side_colors => |o| {
            const n = wm.get_node_by_id(o.id) orelse return .nil;
            var fields: std.ArrayListUnmanaged(Value.Field) = .empty;
            const sides = .{
                .{ "top", n.border_color_top },
                .{ "bottom", n.border_color_bottom },
                .{ "left", n.border_color_left },
                .{ "right", n.border_color_right },
            };
            inline for (sides) |s| {
                if (s[1]) |color| try fields.append(arena, .{ .key = s[0], .value = .{ .integer = color } });
            }
            return .{ .map = fields.items };
        },
        .set_border_side_colors_focused_only => |s| {
            wm.border_side_colors_focused_only = s.enabled;
            try repaint(wm);
        },

        .set_gaps => |s| {
            const gaps: Gaps = .{ .inner_h = s.inner_h, .inner_v = s.inner_v, .outer_h = s.outer_h, .outer_v = s.outer_v };
            wm.default_gap_inner_h = gaps.inner_h;
            wm.default_gap_inner_v = gaps.inner_v;
            wm.default_gap_outer_h = gaps.outer_h;
            wm.default_gap_outer_v = gaps.outer_v;
            set_gaps_recursive(&wm.graph, gaps);
            wm.relayout();
        },
        .set_gaps_workspace => |s| if (workspace_node(wm, s.id)) |n| {
            const sub = n.content.workspace;
            set_graph_gaps(sub, .{ .inner_h = s.inner_h, .inner_v = s.inner_v, .outer_h = s.outer_h, .outer_v = s.outer_v });
            if (sub == wm.current_graph) wm.relayout();
        },

        .set_preview_colors => |s| {
            wm.set_preview_colors(s.bg, s.win_bg, s.border, s.text);
            repaint_previews(wm);
        },
        .set_preview_colors_workspace => |s| if (workspace_node(wm, s.id)) |n| {
            const sub = n.content.workspace;
            sub.set(sub, "preview_bg", s.bg);
            sub.set(sub, "preview_win_bg", s.win_bg);
            sub.set(sub, "preview_border", s.border);
            sub.set(sub, "preview_text", s.text);
            wm.repaint_preview(n);
        },
        .set_preview_font => |s| {
            wm.set_preview_font(s.name);
            repaint_previews(wm);
        },
        .set_preview_font_workspace => |s| if (workspace_node(wm, s.id)) |n| {
            n.content.workspace.set_preview_font(s.name);
            wm.repaint_preview(n);
        },
        .set_preview_max_icon_size => |s| {
            wm.set_preview_max_icon_size(s.size);
            repaint_previews(wm);
        },

        .set_argb_frames => |s| wm.argb_frames = s.enabled,
        .force_rgb_frames => |s| {
            const owned = try wm.allocator.dupe(u8, s.class);
            errdefer wm.allocator.free(owned);
            try wm.rgb_frame_classes.append(wm.allocator, owned);
        },
        .switch_to_workspace => |s| {
            if (s.index < 1) return error.OutOfRange;
            try workspaces.switch_to(wm, s.index);
        },
        .send_to_workspace => |s| {
            if (s.index < 1) return error.OutOfRange;
            try workspaces.send_to(wm, s.id, s.index);
        },
        .enter_workspace_by_id => |o| {
            const n = try node(wm, o.id);
            if (n.content != .workspace) return error.NotAWorkspace;
            try workspaces.enter_or_back(wm, n, workspaces.siblings(wm));
        },
        .create_nested_workspace => return .{ .integer = try workspaces.create_nested(wm) },
        .enter_nested => if (wm.focused) |n| {
            if (n.content == .workspace) try wm.enter_workspace(n);
        },
        .enter_nested_by_id => |o| {
            const n = try node(wm, o.id);
            if (n.content != .workspace) return error.NotAWorkspace;
            try wm.enter_workspace(n);
        },
        .leave_nested => try wm.leave_workspace(),
        .set_workspace_switch_mode => |s| wm.workspace_switch_mode = s.mode,
        .set_autoclean => |s| wm.set_autoclean(s.enabled),
        .cleanup_left_behind => if (wm.pending_cleanup_graph) |og| {
            wm.cleanup_left_behind(og);
            wm.pending_cleanup_graph = null;
        },

        .get_workspace => |s| {
            const id = try workspaces.workspace_at(wm, s.index) orelse return .nil;
            return .{ .integer = id };
        },
        .get_workspace_positions => {
            const st = try workspaces.states(wm, arena);
            var out: std.ArrayListUnmanaged(Value) = .empty;
            for (st, 1..) |s, pos| {
                if (s != .inactive) try out.append(arena, .{ .integer = @intCast(pos) });
            }
            return .{ .list = out.items };
        },
        .get_workspace_states => {
            const st = try workspaces.states(wm, arena);
            const out = try arena.alloc(Value, st.len);
            for (st, out, 1..) |s, *v, pos| {
                v.* = .{ .map = try arena.dupe(Value.Field, &.{
                    .{ .key = "position", .value = .{ .integer = @intCast(pos) } },
                    .{ .key = "state", .value = .{ .string = @tagName(s) } },
                }) };
            }
            return .{ .list = out };
        },
        .get_current_workspace_position => {
            const pos = try workspaces.current_position(wm) orelse return .nil;
            return .{ .integer = @intCast(pos) };
        },
        .get_workspaces_at_level => {
            const nums = try workspaces.level_numbers(wm, arena);
            const out = try arena.alloc(Value, nums.len);
            for (nums, out) |num, *v| v.* = .{ .integer = num };
            return .{ .list = out };
        },
        .get_current_workspace => return .{ .integer = wm.current_graph.id.number + 1 },
        .get_current_level => return .{ .integer = wm.current_graph.id.level },
        .get_node_level => |o| {
            const n = wm.get_node_by_id(o.id) orelse return .nil;
            const g = n.owner_graph orelse return .nil;
            return .{ .integer = g.id.level };
        },
        .spawn => |s| {
            if (s.argv.len == 0) return error.EmptyArgv;
            try wm.spawn(s.argv); // queued: runs at commit, dropped on rollback
        },
        .setenv => |s| {
            // setenv needs NUL-terminated strings; Lua's are, but the slices don't say so.
            const key = try arena.dupeZ(u8, s.key);
            const value = try arena.dupeZ(u8, s.value);
            if (c.setenv(key.ptr, value.ptr, 1) != 0) return error.SetenvFailed;
        },
        .quit => {
            wm.end_session();
            std.process.exit(0);
        },
        .get_layout => return layout_data.describe(wm, arena),
        .set_layout => |s| try layout_data.apply(wm, s.layout, arena),
        .print_graph => return .{ .string = try layout_data.print(wm, arena) },
    }
    return .nil;
}

fn node(wm: *WM, id: NodeId) !*Node {
    return wm.get_node_by_id(id) orelse error.InvalidNode;
}

fn pair(wm: *WM, p: Pair) !struct { *Node, *Node } {
    return .{ try node(wm, p.a), try node(wm, p.b) };
}

fn add(n: *Node, con: Constraint) !void {
    const g = n.owner_graph orelse return error.NotInGraph;
    try g.add_constraint(n, con);
}

/// Start a float next to b, so the solver begins near the answer.
fn place_beside(wm: *WM, a: *Node, b: *Node, comptime rel: []const u8) void {
    const aw: i32 = @intCast(a.width);
    const ah: i32 = @intCast(a.height);
    const bw: i32 = @intCast(b.width);
    const bh: i32 = @intCast(b.height);
    const p: [2]i32 = if (comptime std.mem.eql(u8, rel, "left_of"))
        .{ b.x - aw, b.y }
    else if (comptime std.mem.eql(u8, rel, "right_of"))
        .{ b.x + bw, b.y }
    else if (comptime std.mem.eql(u8, rel, "above"))
        .{ b.x, b.y - ah }
    else if (comptime std.mem.eql(u8, rel, "below"))
        .{ b.x, b.y + bh }
    else
        return;
    wm.journal.set(a, "x", p[0]);
    wm.journal.set(a, "y", p[1]);
}

fn new_empty(wm: *WM, fill_screen: bool) !Value {
    const n = try wm.current_graph.add_node(.empty);
    if (fill_screen) {
        // A new node: no journal entries needed for its own fields.
        n.width = wm.screen_width;
        n.height = wm.screen_height;
    }
    return .{ .integer = try wm.register_node(null, n) };
}

fn type_name(n: *const Node) []const u8 {
    return switch (n.content) {
        .window => "window",
        .empty => "empty",
        .workspace => "workspace",
    };
}

fn id_value(wm: *WM, n: *Node) Value {
    return if (wm.get_id_for_node(n)) |id| .{ .integer = id } else .nil;
}

fn direction(d: Dir) graph_mod.Direction {
    return switch (d) {
        .left => .Left,
        .right => .Right,
        .up => .Up,
        .down => .Down,
    };
}

/// A copy in the arena: results must not point into nodes the batch may free at commit.
fn text(arena: std.mem.Allocator, s: []const u8) !Value {
    if (s.len == 0) return .nil;
    return .{ .string = try arena.dupe(u8, s) };
}

fn set_floating(wm: *WM, id: NodeId, n: *Node, val: bool) !void {
    if (n.content != .window or n.floating == val) return;
    const g = n.owner_graph orelse return error.NotInGraph;
    try g.replace_constraints(n, &.{});
    if (val) {
        wm.call_arranger(wm.current_graph, "unmap", id, null);
        wm.journal.set(n, "floating", true);
        wm.center_node(n);
    } else {
        wm.journal.set(n, "floating", false);
        const prev_id: ?u32 = if (wm.focused) |f|
            (if (f != n) wm.get_id_for_node(f) else null)
        else
            null;
        wm.call_arranger(wm.current_graph, "map", id, prev_id);
    }
    wm.relayout();
}

fn same_pair(p: core.SwallowPair, terminal: []const u8, child: []const u8) bool {
    return std.mem.eql(u8, p.terminal, terminal) and std.mem.eql(u8, p.child, child);
}

fn button(b: types.Button) !types.Button {
    return if (b == 0 or b > 255) error.InvalidButton else b;
}

fn center(n: *const Node) types.Point {
    return .{
        .x = n.x + @divTrunc(@as(i32, @intCast(n.width)), 2),
        .y = n.y + @divTrunc(@as(i32, @intCast(n.height)), 2),
    };
}

fn point(arena: std.mem.Allocator, p: types.Point) !Value {
    return .{ .multi = try arena.dupe(Value, &.{ .{ .integer = p.x }, .{ .integer = p.y } }) };
}

/// Repaint at commit: the scene picks up color changes, and a rollback repaints the old ones.
fn repaint(wm: *WM) !void {
    try wm.flush(wm.current_graph);
}

fn set_graph_gaps(g: *graph_mod.Graph, gaps: Gaps) void {
    g.set(g, "gap_inner_h", gaps.inner_h);
    g.set(g, "gap_inner_v", gaps.inner_v);
    g.set(g, "gap_outer_h", gaps.outer_h);
    g.set(g, "gap_outer_v", gaps.outer_v);
}

fn set_gaps_recursive(g: *graph_mod.Graph, gaps: Gaps) void {
    set_graph_gaps(g, gaps);
    for (g.nodes.items) |n| {
        if (n.content == .workspace) set_gaps_recursive(n.content.workspace, gaps);
    }
}

/// Repaint the visible previews in the current workspace after a global style change.
fn repaint_previews(wm: *WM) void {
    for (wm.current_graph.nodes.items) |n| {
        if (n.content == .workspace and !n.hidden) wm.repaint_preview(n);
    }
}

fn workspace_node(wm: *WM, id: NodeId) ?*Node {
    const n = wm.get_node_by_id(id) orelse return null;
    return if (n.content == .workspace) n else null;
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
