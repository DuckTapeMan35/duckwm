const std = @import("std");

const c = @import("c").c;

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
    // Position constraints (directed)
    left_of:  *Node,   // this.right == other.left
    right_of: *Node,   // this.left == other.right
    above:    *Node,   // this.bottom == other.top
    below:    *Node,   // this.top == other.bottom

    // Alignment (directed, but we'll treat as equality)
    align_left:   *Node,   // this.x == other.x
    align_top:    *Node,   // this.y == other.y
    align_right:  *Node,   // this.x + width == other.x + other.width
    align_bottom: *Node,   // this.y + height == other.y + other.height

    // Size constraints (symmetric, handled via union-find)
    equal_width:  *Node,   // this.width == other.width
    equal_height: *Node,   // this.height == other.height

    // Aspect ratio (self)
    fixed_ratio: f32,      // width / height == ratio

    // fixed constraints
    fixed_width:  u32,
    fixed_height: u32,
    fixed_x: i32,
    fixed_y: i32,

    // Grid placement (requires container)
    grid_cell: struct {
        col: u32,
        row: u32,
        cols: u32,
        rows: u32,
        container: *Node,   // the node that defines the grid area
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
    preview_window: ?c.Window, // non-null for workspace nodes
    urgent: bool,
    hidden: bool,

    x: i32,
    y: i32,
    width: u32,
    height: u32,
    floating: bool,

    constraints: std.ArrayListUnmanaged(Constraint),

    border_color_focused: ?u32, // ARGB
    border_color_unfocused: ?u32,

    pending_destroy: bool,
    on_remove: ?ReparentStrategy,
    dead: bool,

    pub fn init(content: NodeContent, allocator: std.mem.Allocator) !Node {
        return .{
            .content = content,
            .owner_graph = null,
            .preview_window = null,
            .urgent = false,
            .hidden = false,

            .x = 0,
            .y = 0,
            .width = 0,
            .height = 0,
            .floating = false,

            .border_color_focused = null,
            .border_color_unfocused = null,

            .constraints = try std.ArrayListUnmanaged(Constraint).initCapacity(allocator, 4), //TODO: make so no constrants don't allocate at all

            .pending_destroy = false,
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
        if (con == .grid_cell) {
            return con.grid_cell.container;
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
                    std.debug.print("promote: firing\n", .{});
                    var container: ?*Node = null;
                    for (node.constraints.items) |con| {
                        if (con == .grid_cell) {
                            container = con.grid_cell.container;
                            break;
                        }
                    }
                    std.debug.print("promote: container={}\n", .{container != null});
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
                        std.debug.print("promote: sibling={}\n", .{sibling != null});
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
                            std.debug.print("promote: grandparent={} gp_col={} gp_row={} gp_cols={} gp_rows={}\n",
                                .{grandparent != null, gp_col, gp_row, gp_cols, gp_rows});
                            // Remove sibling's old grid_cell pointing at cont
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
                                std.debug.print("promote: appended grid_cell to sibling\n", .{});
                            } else {
                                std.debug.print("promote: no grandparent, sibling left unconstrained\n", .{});
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
            .left_of => |other| other == node,
            .right_of => |other| other == node,
            .above => |other| other == node,
            .below => |other| other == node,
            .align_left => |other| other == node,
            .align_top => |other| other == node,
            .align_right => |other| other == node,
            .align_bottom => |other| other == node,
            .equal_width => |other| other == node,
            .equal_height => |other| other == node,
            .fixed_ratio => false,
            .grid_cell => |g| g.container == node,
            .grid_cell_abs => |g| g.container == node,
            .fixed_width => false,
            .fixed_height => false,
            .fixed_x => false,
            .fixed_y => false,
            .split => |s| blk: {
                if (s.container == node) break :blk true;
                for (0..s.count) |i| {
                    if (s.children[i] == node) break :blk true;
                }
                break :blk false;
            },
        };
    }

    pub fn add_constraint(self: *Graph, node: *Node, constraint: Constraint) !void {
        if (node.floating) return; // No constraints on floating nodes
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
        // 1. Initialize all nodes to a default size if they have zero area
        const default_w = screen_width;
        const default_h = screen_height;
        for (self.nodes.items) |node| {
            if (node.width == 0 and node.height == 0) {
                node.width = default_w;
                node.height = default_h;
            }
        }

        var changed = true;
        var iter: usize = 0;
        const max_iter = 50;

        while (changed and iter < max_iter) {
            changed = false;
            iter += 1;

            // Phase 1: apply all non-equality constraints (directed)
            for (self.nodes.items) |node| {
                if (node.floating) continue;
                for (node.constraints.items) |con| {
                    // Skip equalities here – handle them in phase 2
                    switch (con) {
                        .equal_width, .equal_height => continue,
                        else => {
                            if (apply_one(node, con)) changed = true;
                        },
                    }
                }
            }

            // Phase 2: enforce equalities symmetrically
            for (self.nodes.items) |node| {
                for (node.constraints.items) |con| {
                    if (node.floating) continue;
                    switch (con) {
                        .equal_width => |other| {
                            if (other.floating) continue;
                            const avg = (node.width + other.width) / 2;
                            if (node.width != avg) {
                                node.width = avg;
                                changed = true;
                            }
                            if (other.width != avg) {
                                other.width = avg;
                                changed = true;
                            }
                        },
                        .equal_height => |other| {
                            if (other.floating) continue;
                            const avg = (node.height + other.height) / 2;
                            if (node.height != avg) {
                                node.height = avg;
                                changed = true;
                            }
                            if (other.height != avg) {
                                other.height = avg;
                                changed = true;
                            }
                        },
                        else => {},
                    }
                }
            }

            for (self.nodes.items) |node| {
                if (node.floating) continue;
                const node_right = node.x + @as(i32, @intCast(node.width));
                const node_bottom = node.y + @as(i32, @intCast(node.height));
                const screen_w = @as(i32, @intCast(screen_width));
                const screen_h = @as(i32, @intCast(screen_height));

                if (node_right > screen_w) {
                    node.width = @as(u32, @intCast(@max(0, screen_w - node.x)));
                }
                if (node_bottom > screen_h) {
                    node.height = @as(u32, @intCast(@max(0, screen_h - node.y)));
                }
                if (node.x < 0) node.x = 0;
                if (node.y < 0) node.y = 0;
            }

        }

        for (self.nodes.items) |node| {
            if (node.floating) continue;
            if (node.width  < 1) node.width  = 1;
            if (node.height < 1) node.height = 1;
        }

        if (iter >= max_iter) {
            std.debug.print("Warning: constraint solver did not converge after {} iterations\n", .{max_iter});
        }
    }

    fn apply_one(src: *Node, con: Constraint) bool {
        switch (con) {
            .left_of => |dst| {
                if (dst.floating) return false;
                const new_x = src.x + @as(i32, @intCast(src.width));
                if (dst.x != new_x) { dst.x = new_x; return true; }
            },
            .right_of => |dst| {
                if (dst.floating) return false;
                const new_x = dst.x + @as(i32, @intCast(dst.width));
                if (src.x != new_x) { src.x = new_x; return true; }
            },
            .above => |dst| {
                if (dst.floating) return false;
                const new_y = src.y + @as(i32, @intCast(src.height));
                if (dst.y != new_y) { dst.y = new_y; return true; }
            },
            .below => |dst| {
                if (dst.floating) return false;
                const new_y = dst.y + @as(i32, @intCast(dst.height));
                if (src.y != new_y) { src.y = new_y; return true; }
            },
            .align_left => |dst| {
                if (dst.floating) return false;
                if (dst.x != src.x) { dst.x = src.x; return true; }
            },
            .align_top => |dst| {
                if (dst.floating) return false;
                if (dst.y != src.y) { dst.y = src.y; return true; }
            },
            .align_right => |dst| {
                if (dst.floating) return false;
                const new_x = (src.x + @as(i32, @intCast(src.width))) - @as(i32, @intCast(dst.width));
                if (dst.x != new_x) { dst.x = new_x; return true; }
            },
            .align_bottom => |dst| {
                if (dst.floating) return false;
                const new_y = (src.y + @as(i32, @intCast(src.height))) - @as(i32, @intCast(dst.height));
                if (dst.y != new_y) { dst.y = new_y; return true; }
            },
            .fixed_ratio => |ratio| {
                const new_h = @as(u32, @intFromFloat(@as(f32, @floatFromInt(src.width)) / ratio));
                if (src.height != new_h) { src.height = new_h; return true; }
            },
            .grid_cell => |g| {
                if (g.container.floating) return false;
                if (g.cols == 0 or g.rows == 0) return false;
                const base_cell_w = g.container.width  / g.cols;
                const base_cell_h = g.container.height / g.rows;
                const col_offset  = g.col * base_cell_w;
                const row_offset  = g.row * base_cell_h;
                const cell_w = @max(1, if (g.col == g.cols - 1) g.container.width  -| col_offset else base_cell_w);
                const cell_h = @max(1, if (g.row == g.rows - 1) g.container.height -| row_offset else base_cell_h);
                const new_x = g.container.x + @as(i32, @intCast(col_offset));
                const new_y = g.container.y + @as(i32, @intCast(row_offset));
                if (src.x != new_x or src.y != new_y or src.width != cell_w or src.height != cell_h) {
                    src.x = new_x; src.y = new_y; src.width = cell_w; src.height = cell_h;
                    return true;
                }
            },
            .grid_cell_abs => |g| {
                if (g.container.floating) return false;
                const new_x = g.container.x + g.x;
                const new_y = g.container.y + g.y;
                if (src.x != new_x or src.y != new_y or src.width != g.w or src.height != g.h) {
                    src.x = new_x; src.y = new_y; src.width = g.w; src.height = g.h;
                    return true;
                }
            },
            .fixed_width => |w| {
                if (src.width != w) { src.width = w; return true; }
            },
            .fixed_height => |h| {
                if (src.height != h) { src.height = h; return true; }
            },
            .fixed_x => |x| {
                if (src.x != x) { src.x = x; return true; }
            },
            .fixed_y => |y| {
                if (src.y != y) { src.y = y; return true; }
            },
            .split => |s| {
                const cont = s.container;
                if (cont.floating) return false;
                // normalize ratios
                var ratio_sum: f32 = 0;
                for (0..s.count) |i| ratio_sum += s.ratios[i];
                if (ratio_sum <= 0) return false;
                var offset: u32 = 0;
                var changed = false;
                for (0..s.count) |i| {
                    const child = s.children[i];
                    const normalized = s.ratios[i] / ratio_sum;
                    if (s.axis == .horizontal) {
                        const w: u32 = if (i == s.count - 1)
                            cont.width -| offset
                        else
                            @intFromFloat(@as(f32, @floatFromInt(cont.width)) * normalized);
                        const new_x = cont.x + @as(i32, @intCast(offset));
                        if (child.x != new_x)        { child.x = new_x;        changed = true; }
                        if (child.y != cont.y)        { child.y = cont.y;        changed = true; }
                        if (child.width  != w)        { child.width  = w;        changed = true; }
                        if (child.height != cont.height) { child.height = cont.height; changed = true; }
                        offset += w;
                    } else {
                        const h: u32 = if (i == s.count - 1)
                            cont.height -| offset
                        else
                            @intFromFloat(@as(f32, @floatFromInt(cont.height)) * normalized);
                        const new_y = cont.y + @as(i32, @intCast(offset));
                        if (child.x != cont.x)        { child.x = cont.x;        changed = true; }
                        if (child.y != new_y)          { child.y = new_y;          changed = true; }
                        if (child.width  != cont.width)  { child.width  = cont.width;  changed = true; }
                        if (child.height != h)         { child.height = h;         changed = true; }
                        offset += h;
                    }
                }
                return changed;
            },
            else => return false,
        }
        return false;
    }

};
