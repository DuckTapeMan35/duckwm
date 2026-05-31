const std = @import("std");
const c = @import("c").c;
const cs = @import("solver");

const NodeContent = union(enum) {
    window: c.Window,
    empty,
    workspace: *Graph,
};

pub const SplitAxis = enum {
    horizontal,
    vertical,
};

pub const GraphId = struct {
    level: u32,
    number: u32,
};

pub const Constraint = union(enum) {
    left_of:  *Node,
    right_of: *Node,
    above:    *Node,
    below:    *Node,

    align_left:   *Node,
    align_top:    *Node,
    align_right:  *Node,
    align_bottom: *Node,

    equal_width:  *Node,
    equal_height: *Node,

    fixed_ratio: f32,

    fixed_width:  u32,
    fixed_height: u32,
    fixed_x: i32,
    fixed_y: i32,

    grid_cell: struct {
        col: u32,
        row: u32,
        cols: u32,
        rows: u32,
        container: *Node,
    },
    grid_cell_abs: struct {
        x: i32,
        y: i32,
        w: u32,
        h: u32,
        container: *Node,
    },

    split: struct {
        container: *Node,
        axis: SplitAxis,
        count: u8,
        ratios: [16]f32,
        children: [16]*Node,
    },
};

pub const Direction = enum {
    Left,
    Right,
    Up,
    Down,
};

const ReparentStrategy = union(enum) {
    leave_empty,
    remove,
    promote,
    custom: *const fn(*Node) void,
    custom_l: i32,
};

const FocusEdge = struct {
    from: *Node,
    to: *Node,
    dir: Direction,

    pub fn new(from: *Node, to: *Node, dir: Direction) FocusEdge {
        return .{ .from = from, .to = to, .dir = dir };
    }
};

pub const Node = struct {
    content: NodeContent,
    owner_graph: ?*Graph,
    preview_window: ?c.Window,
    urgent: bool,
    hidden: bool,
    wants_fullscreen: bool,

    x: i32,
    y: i32,
    width: u32,
    height: u32,
    floating: bool,

    constraints: std.ArrayListUnmanaged(Constraint),

    border_color_focused: ?u32,
    border_color_unfocused: ?u32,
    border_color_top: ?u32,
    border_color_bottom: ?u32,
    border_color_left: ?u32,
    border_color_right: ?u32,

    on_remove: ?ReparentStrategy,
    dead: bool,

    pub fn init(content: NodeContent, allocator: std.mem.Allocator) !Node {
        return .{
            .content = content,
            .owner_graph = null,
            .preview_window = null,
            .urgent = false,
            .hidden = false,
            .wants_fullscreen = false,

            .x = 0,
            .y = 0,
            .width = 0,
            .height = 0,
            .floating = false,

            .border_color_focused = null,
            .border_color_unfocused = null,
            .border_color_top = null,
            .border_color_bottom = null,
            .border_color_left = null,
            .border_color_right = null,

            .constraints = try std.ArrayListUnmanaged(Constraint).initCapacity(allocator, 4),

            .on_remove = null,
            .dead = false,
        };
    }

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        self.constraints.deinit(allocator);
    }
};

pub fn get_container(node: *Node) ?*Node {
    for (node.constraints.items) |con| {
        switch (con) {
            .grid_cell => |g| return g.container,
            .grid_cell_abs => |g| return g.container,
            .split => |s| return s.container,
            else => {},
        }
    }
    return null;
}

pub const Graph = struct {
    id: GraphId,
    nodes: std.ArrayListUnmanaged(*Node),
    focus_edges: std.ArrayListUnmanaged(FocusEdge),
    active_workspace: usize,
    gap_inner_h: u32,
    gap_inner_v: u32,
    gap_outer_h: u32,
    gap_outer_v: u32,
    pan_x: i32,
    pan_y: i32,
    work_x: i32,
    work_y: i32,
    pan_disabled: bool,
    virtual_width: u32,
    virtual_height: u32,
    lock_horizontal_resize: bool,
    lock_vertical_resize: bool,
    parent_node: ?*Node,
    arranger_ref: i32,
    arranger_index: i32,
    arranger_name: []const u8,
    preview_bg: ?u32,
    preview_win_bg: ?u32,
    preview_border: ?u32,
    preview_text: ?u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Graph {
        return .{
            .id = .{ .level = 0, .number = 0 },
            .nodes = .{ .items = &.{}, .capacity = 0 },
            .focus_edges = .{ .items = &.{}, .capacity = 0 },
            .active_workspace = 0,
            .gap_inner_h = 0,
            .gap_inner_v = 0,
            .gap_outer_h = 0,
            .gap_outer_v = 0,
            .pan_x = 0,
            .pan_y = 0,
            .work_x = 0,
            .work_y = 0,
            .pan_disabled = false,
            .virtual_width  = 0,
            .virtual_height = 0,
            .lock_horizontal_resize = false,
            .lock_vertical_resize = false,
            .parent_node = null,
            .arranger_ref = 0,
            .arranger_index = 0,
            .arranger_name = "",
            .preview_bg     = null,
            .preview_win_bg = null,
            .preview_border = null,
            .preview_text   = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Graph) void {
        for (self.nodes.items) |node| {
            node.deinit(self.allocator);
            self.allocator.destroy(node);
        }
        self.nodes.deinit(self.allocator);
        self.focus_edges.deinit(self.allocator);
    }

    pub fn add_node(self: *Graph, content: NodeContent) !*Node {
        const node = try self.allocator.create(Node);
        node.* = try Node.init(content, self.allocator);
        node.owner_graph = self;
        try self.nodes.append(self.allocator, node);
        return node;
    }

    fn free_subgraph(self: *Graph, sub: *Graph) void {
        for (sub.nodes.items) |child| {
            if (child.content == .workspace) {
                self.free_subgraph(child.content.workspace);
            }
            child.deinit(self.allocator);
            self.allocator.destroy(child);
        }
        sub.nodes.deinit(self.allocator);
        sub.focus_edges.deinit(self.allocator);
    }

    pub fn remove_node(self: *Graph, node: *Node) void {
        std.debug.assert(node.owner_graph == self);
        if (node.dead) return;
        node.dead = true;

        if (node.on_remove) |strategy| {
            switch (strategy) {
                .promote => {
                    var container: ?*Node = null;
                    for (node.constraints.items) |con| {
                        if (con == .grid_cell) {
                            container = con.grid_cell.container;
                            break;
                        }
                    }
                    if (container) |cont| {
                        var sibling: ?*Node = null;
                        for (self.nodes.items) |n| {
                            if (n == node) continue;
                            for (n.constraints.items) |con| {
                                if (con == .grid_cell and con.grid_cell.container == cont) {
                                    sibling = n;
                                    break;
                                }
                            }
                            if (sibling != null) break;
                        }
                        if (sibling) |sib| {
                            var grandparent: ?*Node = null;
                            var gp_col:  u32 = 0;
                            var gp_row:  u32 = 0;
                            var gp_cols: u32 = 1;
                            var gp_rows: u32 = 1;
                            for (cont.constraints.items) |con| {
                                if (con == .grid_cell) {
                                    grandparent = con.grid_cell.container;
                                    gp_col  = con.grid_cell.col;
                                    gp_row  = con.grid_cell.row;
                                    gp_cols = con.grid_cell.cols;
                                    gp_rows = con.grid_cell.rows;
                                    break;
                                }
                            }
                            var i: usize = 0;
                            while (i < sib.constraints.items.len) {
                                if (sib.constraints.items[i] == .grid_cell and
                                    sib.constraints.items[i].grid_cell.container == cont)
                                {
                                    _ = sib.constraints.swapRemove(i);
                                } else {
                                    i += 1;
                                }
                            }
                            if (grandparent) |gp| {
                                sib.constraints.append(self.allocator, .{ .grid_cell = .{
                                    .col = gp_col,
                                    .row = gp_row,
                                    .cols = gp_cols,
                                    .rows = gp_rows,
                                    .container = gp,
                                }}) catch {};
                            } else {
                            }
                        }
                    }
                },
                else => {},
            }
        }

        for (self.nodes.items) |n| {
            var i: usize = 0;
            while (i < n.constraints.items.len) {
                if (constraint_involves_node(n.constraints.items[i], node)) {
                    _ = n.constraints.swapRemove(i);
                } else {
                    i += 1;
                }
            }
        }

        for (self.nodes.items, 0..) |n, idx| {
            if (n == node) {
                _ = self.nodes.swapRemove(idx);
                break;
            }
        }

        if (node.content == .workspace) {
            self.free_subgraph(node.content.workspace);
        }
        node.deinit(self.allocator);
        self.allocator.destroy(node);
    }

    pub fn constraint_involves_node(con: Constraint, node: *Node) bool {
        return switch (con) {
            .left_of      => |other| other == node,
            .right_of     => |other| other == node,
            .above        => |other| other == node,
            .below        => |other| other == node,
            .align_left   => |other| other == node,
            .align_top    => |other| other == node,
            .align_right  => |other| other == node,
            .align_bottom => |other| other == node,
            .equal_width  => |other| other == node,
            .equal_height => |other| other == node,
            .fixed_ratio  => false,
            .grid_cell    => |g| g.container == node,
            .grid_cell_abs=> |g| g.container == node,
            .fixed_width  => false,
            .fixed_height => false,
            .fixed_x      => false,
            .fixed_y      => false,
            .split        => |s| blk: {
                if (s.container == node) break :blk true;
                for (0..s.count) |i| {
                    if (s.children[i] == node) break :blk true;
                }
                break :blk false;
            },
        };
    }

    pub fn add_constraint(self: *Graph, node: *Node, constraint: Constraint) !void {
        try node.constraints.append(self.allocator, constraint);
    }

    pub fn remove_constraint(_: *Graph, node: *Node, constraint: Constraint) void {
        for (node.constraints.items, 0..) |con, i| {
            if (con == constraint) {
                _ = node.constraints.swapRemove(i);
                break;
            }
        }
    }

    pub fn add_focus_edge(self: *Graph, from: *Node, to: *Node, dir: Direction) !void {
        try self.focus_edges.append(self.allocator, FocusEdge.new(from, to, dir));
    }

    pub fn remove_focus_edge(self: *Graph, from: *Node, to: *Node) void {
        for (self.focus_edges.items, 0..) |edge, i| {
            if (edge.from == from and edge.to == to) {
                _ = self.focus_edges.swapRemove(i);
                break;
            }
        }
    }

    pub fn solve(self: *Graph, screen_width: u32, screen_height: u32) !void {
        const n = self.nodes.items.len;
        if (n == 0) return;

        // Map node pointer -> index
        var node_idx = std.AutoHashMapUnmanaged(*Node, usize){};
        defer node_idx.deinit(self.allocator);
        for (self.nodes.items, 0..) |nd, i| {
            try node_idx.put(self.allocator, nd, i);
        }

        const n_vars = n * 4;
        var solver = try cs.Solver.init(self.allocator, n_vars);
        defer solver.deinit();

        // Seed solver with current node values so underdetermined variables
        // stay at their current position rather than snapping to zero.
        for (self.nodes.items, 0..) |nd, i| {
            solver.vals[cs.var_x(i)] = @floatFromInt(nd.x);
            solver.vals[cs.var_y(i)] = @floatFromInt(nd.y);
            solver.vals[cs.var_w(i)] = @floatFromInt(
                if (nd.width  > 0) nd.width  else screen_width);
            solver.vals[cs.var_h(i)] = @floatFromInt(
                if (nd.height > 0) nd.height else screen_height);
        }

        // Default: fill screen for tiled, stay in place for floating
        for (0..n) |i| {
            const nd = self.nodes.items[i];
            if (nd.floating) {
                // anchor floating nodes at their current position/size as weak defaults
                // so relational constraints have a stable reference point
                try solver.add_fixed(cs.var_x(i), @floatFromInt(nd.x),                                    cs.WEAK);
                try solver.add_fixed(cs.var_y(i), @floatFromInt(nd.y),                                    cs.WEAK);
                try solver.add_fixed(cs.var_w(i), @floatFromInt(if (nd.width  > 0) nd.width  else 100),   cs.MEDIUM);
                try solver.add_fixed(cs.var_h(i), @floatFromInt(if (nd.height > 0) nd.height else 100),   cs.MEDIUM);
            } else {
                try solver.add_fixed(cs.var_x(i), 0,                            cs.WEAK);
                try solver.add_fixed(cs.var_y(i), 0,                            cs.WEAK);
                try solver.add_fixed(cs.var_w(i), @floatFromInt(screen_width),  cs.WEAK);
                try solver.add_fixed(cs.var_h(i), @floatFromInt(screen_height), cs.WEAK);
            }
        }

        for (self.nodes.items, 0..) |nd, i| {
            for (nd.constraints.items) |con| {
                // skip absolute position/size constraints for floating nodes
                // but allow relational constraints
                if (nd.floating) {
                    switch (con) {
                        .fixed_x, .fixed_y, .fixed_width, .fixed_height,
                        .grid_cell, .grid_cell_abs, .split, .fixed_ratio => continue,
                        else => {},
                    }
                }
                switch (con) {

                    .fixed_x => |v| {
                        try solver.add_fixed(cs.var_x(i), @floatFromInt(v), cs.REQUIRED);
                    },
                    .fixed_y => |v| {
                        try solver.add_fixed(cs.var_y(i), @floatFromInt(v), cs.REQUIRED);
                    },
                    .fixed_width => |v| {
                        try solver.add_fixed(cs.var_w(i), @floatFromInt(v), cs.REQUIRED);
                    },
                    .fixed_height => |v| {
                        try solver.add_fixed(cs.var_h(i), @floatFromInt(v), cs.REQUIRED);
                    },

                    // w = ratio * h  =>  w - ratio*h = 0
                    .fixed_ratio => |r| {
                        try solver.add(.{
                            .vars   = [8]u32{ @intCast(cs.var_w(i)), @intCast(cs.var_h(i)), 0,0,0,0,0,0 },
                            .coeffs = [8]f64{ 1.0, -@as(f64, r),                            0,0,0,0,0,0 },
                            .n = 2, .rhs = 0, .weight = cs.STRONG,
                        });
                    },

                    .grid_cell => |g| {
                        const j = node_idx.get(g.container) orelse continue;
                        if (g.cols == 0 or g.rows == 0) continue;
                        const cw: f64 = 1.0 / @as(f64, @floatFromInt(g.cols));
                        const ch: f64 = 1.0 / @as(f64, @floatFromInt(g.rows));
                        const col: f64 = @floatFromInt(g.col);
                        const row: f64 = @floatFromInt(g.row);

                        // x_i = x_cont + col * (w_cont / cols)
                        // => x_i - x_cont - (col/cols)*w_cont = 0
                        try solver.add(.{
                            .vars   = [8]u32{ @intCast(cs.var_x(i)), @intCast(cs.var_x(j)), @intCast(cs.var_w(j)), 0,0,0,0,0 },
                            .coeffs = [8]f64{ 1.0, -1.0, -(col * cw), 0,0,0,0,0 },
                            .n = 3, .rhs = 0, .weight = cs.REQUIRED,
                        });
                        // y_i = y_cont + row * (h_cont / rows)
                        try solver.add(.{
                            .vars   = [8]u32{ @intCast(cs.var_y(i)), @intCast(cs.var_y(j)), @intCast(cs.var_h(j)), 0,0,0,0,0 },
                            .coeffs = [8]f64{ 1.0, -1.0, -(row * ch), 0,0,0,0,0 },
                            .n = 3, .rhs = 0, .weight = cs.REQUIRED,
                        });
                        // w_i = w_cont / cols
                        try solver.add(.{
                            .vars   = [8]u32{ @intCast(cs.var_w(i)), @intCast(cs.var_w(j)), 0,0,0,0,0,0 },
                            .coeffs = [8]f64{ 1.0, -cw, 0,0,0,0,0,0 },
                            .n = 2, .rhs = 0, .weight = cs.REQUIRED,
                        });
                        // h_i = h_cont / rows
                        try solver.add(.{
                            .vars   = [8]u32{ @intCast(cs.var_h(i)), @intCast(cs.var_h(j)), 0,0,0,0,0,0 },
                            .coeffs = [8]f64{ 1.0, -ch, 0,0,0,0,0,0 },
                            .n = 2, .rhs = 0, .weight = cs.REQUIRED,
                        });
                    },

                    .grid_cell_abs => |g| {
                        const j = node_idx.get(g.container) orelse continue;
                        // x_i = x_cont + g.x
                        try solver.add(.{
                            .vars   = [8]u32{ @intCast(cs.var_x(i)), @intCast(cs.var_x(j)), 0,0,0,0,0,0 },
                            .coeffs = [8]f64{ 1.0, -1.0, 0,0,0,0,0,0 },
                            .n = 2, .rhs = @floatFromInt(g.x), .weight = cs.REQUIRED,
                        });
                        // y_i = y_cont + g.y
                        try solver.add(.{
                            .vars   = [8]u32{ @intCast(cs.var_y(i)), @intCast(cs.var_y(j)), 0,0,0,0,0,0 },
                            .coeffs = [8]f64{ 1.0, -1.0, 0,0,0,0,0,0 },
                            .n = 2, .rhs = @floatFromInt(g.y), .weight = cs.REQUIRED,
                        });
                        try solver.add_fixed(cs.var_w(i), @floatFromInt(g.w), cs.REQUIRED);
                        try solver.add_fixed(cs.var_h(i), @floatFromInt(g.h), cs.REQUIRED);
                    },

                    .split => |s| {
                        const j = node_idx.get(s.container) orelse continue;
                        var ratio_sum: f64 = 0;
                        for (0..s.count) |k| ratio_sum += s.ratios[k];
                        if (ratio_sum <= 0) continue;

                        var offset: f64 = 0;
                        for (0..s.count) |k| {
                            const child = s.children[k];
                            const ck = node_idx.get(child) orelse continue;
                            const r: f64 = @as(f64, s.ratios[k]) / ratio_sum;

                            if (s.axis == .horizontal) {
                                // x_child = x_cont + offset * w_cont
                                try solver.add(.{
                                    .vars   = [8]u32{ @intCast(cs.var_x(ck)), @intCast(cs.var_x(j)), @intCast(cs.var_w(j)), 0,0,0,0,0 },
                                    .coeffs = [8]f64{ 1.0, -1.0, -offset, 0,0,0,0,0 },
                                    .n = 3, .rhs = 0, .weight = cs.REQUIRED,
                                });
                                // w_child = r * w_cont
                                try solver.add(.{
                                    .vars   = [8]u32{ @intCast(cs.var_w(ck)), @intCast(cs.var_w(j)), 0,0,0,0,0,0 },
                                    .coeffs = [8]f64{ 1.0, -r, 0,0,0,0,0,0 },
                                    .n = 2, .rhs = 0, .weight = cs.REQUIRED,
                                });
                                // y_child = y_cont
                                try solver.add_diff(cs.var_y(ck), cs.var_y(j), 0, cs.REQUIRED);
                                // h_child = h_cont
                                try solver.add_diff(cs.var_h(ck), cs.var_h(j), 0, cs.REQUIRED);
                            } else {
                                // y_child = y_cont + offset * h_cont
                                try solver.add(.{
                                    .vars   = [8]u32{ @intCast(cs.var_y(ck)), @intCast(cs.var_y(j)), @intCast(cs.var_h(j)), 0,0,0,0,0 },
                                    .coeffs = [8]f64{ 1.0, -1.0, -offset, 0,0,0,0,0 },
                                    .n = 3, .rhs = 0, .weight = cs.REQUIRED,
                                });
                                // h_child = r * h_cont
                                try solver.add(.{
                                    .vars   = [8]u32{ @intCast(cs.var_h(ck)), @intCast(cs.var_h(j)), 0,0,0,0,0,0 },
                                    .coeffs = [8]f64{ 1.0, -r, 0,0,0,0,0,0 },
                                    .n = 2, .rhs = 0, .weight = cs.REQUIRED,
                                });
                                // x_child = x_cont
                                try solver.add_diff(cs.var_x(ck), cs.var_x(j), 0, cs.REQUIRED);
                                // w_child = w_cont
                                try solver.add_diff(cs.var_w(ck), cs.var_w(j), 0, cs.REQUIRED);
                            }
                            offset += r;
                        }
                    },

                    // Positional — STRONG not REQUIRED so over-constrained
                    // systems relax gracefully instead of producing garbage.

                    .left_of => |other| {
                        const j = node_idx.get(other) orelse continue;
                        // x_other = x_i + w_i  =>  x_other - x_i - w_i = 0
                        try solver.add(.{
                            .vars   = [8]u32{ @intCast(cs.var_x(j)), @intCast(cs.var_x(i)), @intCast(cs.var_w(i)), 0,0,0,0,0 },
                            .coeffs = [8]f64{ 1.0, -1.0, -1.0, 0,0,0,0,0 },
                            .n = 3, .rhs = 0, .weight = cs.STRONG,
                        });
                    },
                    .right_of => |other| {
                        const j = node_idx.get(other) orelse continue;
                        // x_i = x_other + w_other  =>  x_i - x_other - w_other = 0
                        try solver.add(.{
                            .vars   = [8]u32{ @intCast(cs.var_x(i)), @intCast(cs.var_x(j)), @intCast(cs.var_w(j)), 0,0,0,0,0 },
                            .coeffs = [8]f64{ 1.0, -1.0, -1.0, 0,0,0,0,0 },
                            .n = 3, .rhs = 0, .weight = cs.STRONG,
                        });
                    },
                    .above => |other| {
                        const j = node_idx.get(other) orelse continue;
                        // y_other = y_i + h_i  =>  y_other - y_i - h_i = 0
                        try solver.add(.{
                            .vars   = [8]u32{ @intCast(cs.var_y(j)), @intCast(cs.var_y(i)), @intCast(cs.var_h(i)), 0,0,0,0,0 },
                            .coeffs = [8]f64{ 1.0, -1.0, -1.0, 0,0,0,0,0 },
                            .n = 3, .rhs = 0, .weight = cs.STRONG,
                        });
                    },
                    .below => |other| {
                        const j = node_idx.get(other) orelse continue;
                        // y_i = y_other + h_other  =>  y_i - y_other - h_other = 0
                        try solver.add(.{
                            .vars   = [8]u32{ @intCast(cs.var_y(i)), @intCast(cs.var_y(j)), @intCast(cs.var_h(j)), 0,0,0,0,0 },
                            .coeffs = [8]f64{ 1.0, -1.0, -1.0, 0,0,0,0,0 },
                            .n = 3, .rhs = 0, .weight = cs.STRONG,
                        });
                    },

                    .align_left => |other| {
                        const j = node_idx.get(other) orelse continue;
                        try solver.add_diff(cs.var_x(i), cs.var_x(j), 0, cs.STRONG);
                    },
                    .align_top => |other| {
                        const j = node_idx.get(other) orelse continue;
                        try solver.add_diff(cs.var_y(i), cs.var_y(j), 0, cs.STRONG);
                    },
                    .align_right => |other| {
                        const j = node_idx.get(other) orelse continue;
                        // x_i + w_i = x_other + w_other
                        try solver.add(.{
                            .vars   = [8]u32{ @intCast(cs.var_x(i)), @intCast(cs.var_w(i)), @intCast(cs.var_x(j)), @intCast(cs.var_w(j)), 0,0,0,0 },
                            .coeffs = [8]f64{ 1.0, 1.0, -1.0, -1.0, 0,0,0,0 },
                            .n = 4, .rhs = 0, .weight = cs.STRONG,
                        });
                    },
                    .align_bottom => |other| {
                        const j = node_idx.get(other) orelse continue;
                        // y_i + h_i = y_other + h_other
                        try solver.add(.{
                            .vars   = [8]u32{ @intCast(cs.var_y(i)), @intCast(cs.var_h(i)), @intCast(cs.var_y(j)), @intCast(cs.var_h(j)), 0,0,0,0 },
                            .coeffs = [8]f64{ 1.0, 1.0, -1.0, -1.0, 0,0,0,0 },
                            .n = 4, .rhs = 0, .weight = cs.STRONG,
                        });
                    },

                    .equal_width => |other| {
                        const j = node_idx.get(other) orelse continue;
                        try solver.add_diff(cs.var_w(i), cs.var_w(j), 0, cs.STRONG);
                    },
                    .equal_height => |other| {
                        const j = node_idx.get(other) orelse continue;
                        try solver.add_diff(cs.var_h(i), cs.var_h(j), 0, cs.STRONG);
                    },
                }
            }
        }

        try solver.solve();

        // Write results back, clamping to valid pixel ranges.
        // We clamp AFTER solving so the solver itself sees unclamped
        // values — clamping inside the solver would break constraints
        // that depend on nodes near screen edges.
        const sw: f64 = @floatFromInt(screen_width);
        const sh: f64 = @floatFromInt(screen_height);
        for (self.nodes.items, 0..) |nd, i| {
            if (nd.floating) {
                // only update x/y from solver for floating nodes, not w/h
                // unless equal_width/equal_height constraints exist
                const has_size_con = for (nd.constraints.items) |con| {
                    switch (con) {
                        .equal_width, .equal_height => break true,
                        else => {},
                    }
                } else false;
                nd.x = @intFromFloat(@round(solver.vals[cs.var_x(i)]));
                nd.y = @intFromFloat(@round(solver.vals[cs.var_y(i)]));
                if (has_size_con) {
                    nd.width  = @intFromFloat(@round(solver.vals[cs.var_w(i)]));
                    nd.height = @intFromFloat(@round(solver.vals[cs.var_h(i)]));
                }
                continue;
            }
            const x_f = @max(0.0, @min(sw,     solver.vals[cs.var_x(i)]));
            const y_f = @max(0.0, @min(sh,     solver.vals[cs.var_y(i)]));
            const w_f = @max(1.0, @min(sw - x_f, solver.vals[cs.var_w(i)]));
            const h_f = @max(1.0, @min(sh - y_f, solver.vals[cs.var_h(i)]));
            const xi: i32 = @intFromFloat(@round(x_f));
            const yi: i32 = @intFromFloat(@round(y_f));
            const wi: u32 = @intCast(@max(1, @as(i32, @intFromFloat(@round(w_f)))));
            const hi: u32 = @intCast(@max(1, @as(i32, @intFromFloat(@round(h_f)))));
            const sw_i: i32 = @intCast(screen_width);
            const sh_i: i32 = @intCast(screen_height);
            nd.x      = xi;
            nd.y      = yi;
            nd.width  = @intCast(@max(1, @min(sw_i - xi, @as(i32, @intCast(wi)))));
            nd.height = @intCast(@max(1, @min(sh_i - yi, @as(i32, @intCast(hi)))));
        }
    }
};
