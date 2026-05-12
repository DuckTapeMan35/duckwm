const std = @import("std");

const c = @cImport({
    @cInclude("X11/Xlib.h");
});

const NodeContent = union(enum) {
    window: c.Window,
    empty,
    workspace: *Graph,
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

    // Grid placement (requires container)
    grid_cell: struct {
        col: u32,
        row: u32,
        cols: u32,
        rows: u32,
        container: *Node,   // the node that defines the grid area
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
    promote: Direction,
    custom: *const fn(*Node) void,
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

    x: i32,
    y: i32,
    width: u32,
    height: u32,
    floating: bool,

    constraints: std.ArrayListUnmanaged(Constraint),

    border_color_focused: ?u32, // ARGB
    border_color_unfocused: ?u32,

    on_remove: ?ReparentStrategy,
    dead: bool,

    pub fn init(content: NodeContent, allocator: std.mem.Allocator) !Node {
        return .{
            .content = content,
            .x = 0,
            .y = 0,
            .width = 0,
            .height = 0,
            .floating = false,
            .on_remove = null,
            .dead = false,
            .constraints = try std.ArrayListUnmanaged(Constraint).initCapacity(allocator, 4), //TODO: make so no constrants don't allocate at all
            .border_color_focused = null,
            .border_color_unfocused = null,
        };
    }

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        self.constraints.deinit(allocator);
    }
};

pub const Graph = struct {
    nodes: std.ArrayListUnmanaged(*Node),
    focus_edges: std.ArrayListUnmanaged(FocusEdge),
    active_workspace: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Graph {
        return .{
            .nodes = .{ .items = &.{}, .capacity = 0 },
            .focus_edges = .{ .items = &.{}, .capacity = 0 },
            .active_workspace = 0,
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
        try self.nodes.append(self.allocator, node);
        return node;
    }

    pub fn remove_node(self: *Graph, node: *Node) void {
        if (node.dead) return; // Already removed
        node.dead = true;
        // 1. Remove any constraint from any node that references `node`
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

        // 2. Remove node from nodes list
        for (self.nodes.items, 0..) |n, idx| {
            if (n == node) {
                _ = self.nodes.swapRemove(idx);
                break;
            }
        }

        // 3. Deinit and free node
        node.deinit(self.allocator);
        self.allocator.destroy(node);
    }

    fn constraint_involves_node(con: Constraint, node: *Node) bool {
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

    pub fn modify_geometry(_: *Graph, node: *Node, x: i32, y: i32, width: u32, height: u32) void {
        node.x = x;
        node.y = y;
        node.width = width;
        node.height = height;
    }

    pub fn solve(self: *Graph, screen_width: u32, screen_height: u32, border_width: i32) !void {
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
                            if (apply_one(node, con, border_width)) changed = true;
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

        if (iter >= max_iter) {
            std.debug.print("Warning: constraint solver did not converge after {} iterations\n", .{max_iter});
        }
    }

    fn apply_one(src: *Node, con: Constraint, border_width: i32) bool {
        const gap = 2*border_width;
        switch (con) {
            .left_of => |dst| {
                if (dst.floating) return false;
                const new_x = src.x + @as(i32, @intCast(src.width)) + gap;
                if (dst.x != new_x) {
                    dst.x = new_x;
                    return true;
                }
            },
            .right_of => |dst| {
                if (dst.floating) return false;
                const new_x = dst.x + @as(i32, @intCast(dst.width)) + gap;
                if (src.x != new_x) {
                    src.x = new_x;
                    return true;
                }
            },
            .above => |dst| {
                if (dst.floating) return false;
                const new_y = src.y + @as(i32, @intCast(src.height)) + gap;
                if (dst.y != new_y) {
                    dst.y = new_y;
                    return true;
                }
            },
            .below => |dst| {
                if (dst.floating) return false;
                const new_y = dst.y + @as(i32, @intCast(dst.height)) + gap;
                if (src.y != new_y) {
                    src.y = new_y;
                    return true;
                }
            },
            .align_left => |dst| {
                if (dst.floating) return false;
                if (dst.x != src.x) {
                    dst.x = src.x;
                    return true;
                }
            },
            .align_top => |dst| {
                if (dst.floating) return false;
                if (dst.y != src.y) {
                    dst.y = src.y;
                    return true;
                }
            },
            .align_right => |dst| {
                if (dst.floating) return false;
                const new_x = (src.x + @as(i32, @intCast(src.width))) - @as(i32, @intCast(dst.width));
                if (dst.x != new_x) {
                    dst.x = new_x;
                    return true;
                }
            },
            .align_bottom => |dst| {
                if (dst.floating) return false;
                const new_y = (src.y + @as(i32, @intCast(src.height))) - @as(i32, @intCast(dst.height));
                if (dst.y != new_y) {
                    dst.y = new_y;
                    return true;
                }
            },
            .fixed_ratio => |ratio| {
                // Maintain width, adjust height (could also be the other way)
                const new_h = @as(u32, @intFromFloat(@as(f32, @floatFromInt(src.width)) / ratio));
                if (src.height != new_h) {
                    src.height = new_h;
                    return true;
                }
            },
            .grid_cell => |g| {
                if (g.container.floating) return false;

                const gap_u32: u32 = @intCast(gap);

                // Reserve space for gaps between columns and rows
                const total_gap_w = gap_u32 * (g.cols - 1);
                const total_gap_h = gap_u32 * (g.rows - 1);

                // Cell outer width/height
                const cell_w = (g.container.width - total_gap_w) / g.cols;
                const cell_h = (g.container.height - total_gap_h) / g.rows;

                const col_offset = g.col * (cell_w + gap_u32);
                const row_offset = g.row * (cell_h + gap_u32);

                const new_x = g.container.x + @as(i32, @intCast(col_offset));
                const new_y = g.container.y + @as(i32, @intCast(row_offset));

                if (src.x != new_x or src.y != new_y or src.width != cell_w or src.height != cell_h) {
                    src.x = new_x;
                    src.y = new_y;
                    src.width = cell_w;
                    src.height = cell_h;
                    return true;
                }
            },
            else => { return false; }, // equal_width and equal_height are handled in phase 2
        }
        return false;
    }

};
