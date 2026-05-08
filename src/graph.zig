const std = @import("std");

const c = @cImport({
    @cInclude("X11/Xlib.h");
});

pub fn row_origin(node: *Node) *Node {
    var cur = node;
    while (cur.left) |l| cur = l;
    return cur;
}

pub fn col_origin(node: *Node) *Node {
    var cur = node;
    while (cur.up) |u| cur = u;
    return cur;
}

pub fn recalculate_row_weights(row_start: *Node) void {
    var total: u32 = 0;
    var cur: ?*Node = row_start;
    while (cur) |n| { total += n.width; cur = n.right; }
    var available: u32 = total;
    cur = row_start;
    while (cur) |n| {
        if (n.right != null) {
            n.split_h = .{ .weighted = @as(f32, @floatFromInt(n.width)) / @as(f32, @floatFromInt(available)) };
        }
        available -= n.width;
        cur = n.right;
    }
}

pub fn recalculate_col_weights(col_start: *Node) void {
    var total: u32 = 0;
    var cur: ?*Node = col_start;
    while (cur) |n| { total += n.height; cur = n.down; }
    var available: u32 = total;
    cur = col_start;
    while (cur) |n| {
        if (n.down != null) {
            n.split_v = .{ .weighted = @as(f32, @floatFromInt(n.height)) / @as(f32, @floatFromInt(available)) };
        }
        available -= n.height;
        cur = n.down;
    }
}


const NodeContent = union(enum) {
    window: c.Window,
    empty,
    workspace: *Graph,
};

pub const Direction = enum {
    Left,
    Right,
    Up,
    Down,
};

const SplitStrategy = union(enum) {
    equal,
    weighted: f32,
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

    pub fn new(from: *Node, to: *Node) FocusEdge {
        return .{ .from = from, .to = to };
    }
};

pub const Node = struct {
    content: NodeContent,

    x: i32,
    y: i32,
    width: u32,
    height: u32,

    split_h: ?SplitStrategy,
    split_v: ?SplitStrategy,

    on_remove: ?ReparentStrategy,

    left:  ?*Node,
    right: ?*Node,
    up:    ?*Node,
    down:  ?*Node,

    pub fn init(content: NodeContent) Node {
        return .{
            .content = content,
            .x = 0,
            .y = 0,
            .width = 0,
            .height = 0,
            .split_h = null,
            .split_v = null,
            .on_remove = null,
            .left = null,
            .right = null,
            .up = null,
            .down = null,
        };
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
            self.allocator.destroy(node);
        }
        self.nodes.deinit(self.allocator);
        self.focus_edges.deinit(self.allocator);
    }

    pub fn add_node(self: *Graph, content: NodeContent) !*Node {
        const node = try self.allocator.create(Node);
        node.* = Node.init(content);
        try self.nodes.append(self.allocator, node);
        return node;
    }

    pub fn can_reach(self: *Graph, start: *Node, target: *Node) !bool {
        var visited = std.AutoHashMap(*Node, void).init(self.allocator);
        defer visited.deinit();

        var stack: std.ArrayListUnmanaged(*Node) = .{ .items = &.{}, .capacity = 0 };
        defer stack.deinit(self.allocator);
        try stack.append(self.allocator, start);

        while (stack.items.len > 0) {
            const node = stack.pop();
            if (node == target) return true;
            if (visited.contains(node)) continue;
            try visited.put(node, {});

            if (node.left)  |n| try stack.append(self.allocator, n);
            if (node.right) |n| try stack.append(self.allocator, n);
            if (node.up)    |n| try stack.append(self.allocator, n);
            if (node.down)  |n| try stack.append(self.allocator, n);
        }
        return false;
    }

    pub fn add_edge(self: *Graph, from: *Node, to: *Node, direction: Direction) !void {
        if (try self.can_reach(to, from)) return;
        switch (direction) {
            .Left  => { from.left  = to; to.right = from; },
            .Right => { from.right = to; to.left  = from; },
            .Up    => { from.up    = to; to.down  = from; },
            .Down  => { from.down  = to; to.up    = from; },
        }
    }

    pub fn remove_node(self: *Graph, node: *Node) void {
        const left = node.left;
        const right = node.right;
        const up = node.up;
        const down = node.down;

        if (right != null and down != null) {
            // down promotes into node's slot — connect left/up to down
            if (left) |l| { l.right = down; down.?.left = l; } else { down.?.left = null; }
            if (up)   |u| { u.down  = down; down.?.up   = u; } else { down.?.up   = null; }
            // append right to the tail of down's row
            var tail = down.?;
            while (tail.right) |r| tail = r;
            tail.right = right;
            right.?.left = tail;
            recalculate_row_weights(down.?);
        } else {
            // standard horizontal stitch
            if (left)  |l| l.right = right;
            if (right) |r| r.left  = left;
            // standard vertical stitch
            if (up)   |u| u.down = down;
            if (down) |d| d.up   = up;

            // cross-axis: horizontal parent, no horizontal child, only vertical child
            // e.g. A→B, B↓C  →  A→C
            if (left != null and right == null and down != null) {
                left.?.right = down;
                down.?.left  = left;
                down.?.up    = null;
            }

            // cross-axis: vertical parent, no vertical child, only horizontal child
            // e.g. B↓C, C→D  →  B↓D
            if (up != null and down == null and right != null) {
                up.?.down    = right;
                right.?.up   = up;
                right.?.left = null;
            }
        }

        for (self.nodes.items, 0..) |n, i| {
            if (n == node) {
                _ = self.nodes.swapRemove(i);
                break;
            }
        }
        self.allocator.destroy(node);
    }

    pub fn remove_edge(_: *Graph, from: *Node, direction: Direction) void {
        switch (direction) {
            .Left  => { if (from.left)  |to| { to.right = null; } from.left  = null; },
            .Right => { if (from.right) |to| { to.left  = null; } from.right = null; },
            .Up    => { if (from.up)    |to| { to.down  = null; } from.up    = null; },
            .Down  => { if (from.down)  |to| { to.up    = null; } from.down  = null; },
        }
    }

    pub fn add_focus_edge(self: *Graph, from: *Node, to: *Node) !void {
        try self.focus_edges.append(self.allocator, FocusEdge.new(from, to));
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

    pub fn get_neighbors(self: *Graph, node: *Node) !std.ArrayListUnmanaged(*Node) {
        var neighbors: std.ArrayListUnmanaged(*Node) = .{ .items = &.{}, .capacity = 0 };
        for (self.nodes.items) |n| {
            if (n.left == node or n.right == node or n.up == node or n.down == node) {
                try neighbors.append(self.allocator, n);
            }
        }
        return neighbors;
    }

    pub fn get_origins(self: *Graph) !std.ArrayListUnmanaged(*Node) {
        var origins: std.ArrayListUnmanaged(*Node) = .{ .items = &.{}, .capacity = 0 };
        for (self.nodes.items) |n| {
            if (n.left == null and n.up == null) {
                try origins.append(self.allocator, n);
            }
        }
        return origins;
    }

    pub fn print_ascii(self: *Graph) void {
        std.debug.print("=== Graph ===\n", .{});

        const origins = self.get_origins() catch return;
        defer origins.deinit(self.allocator);

        var visited = std.AutoHashMap(*Node, usize).init(self.allocator);
        defer visited.deinit();

        var next_id: usize = 0;

        // assign stable IDs
        for (self.nodes.items) |n| {
            visited.put(n, next_id) catch {};
            next_id += 1;
        }

        for (origins.items) |origin| {
            print_ascii_row(origin, &visited);
            std.debug.print("\n", .{});
        }

        std.debug.print("===============\n", .{});
    }

    fn print_ascii_row(
        start: *Node,
        ids: *std.AutoHashMap(*Node, usize),
    ) void {
        var row: ?*Node = start;

        // first line: A - B - C
        while (row) |n| {
            const id = ids.get(n).?;
            print_node_name(id);

            if (n.right != null) {
                std.debug.print(" - ", .{});
            }

            row = n.right;
        }

        std.debug.print("\n", .{});

        // second line(s): vertical connectors
        row = start;

        var has_down = false;
        while (row) |n| {
            if (n.down != null) {
                has_down = true;
                break;
            }
            row = n.right;
        }

        if (!has_down) return;

        row = start;

        // connector row
        while (row) |n| {
            const id = ids.get(n).?;
            const width: usize = node_name_len(id);

            if (n.down != null) {
                pad_center(width);
                std.debug.print("|", .{});
                pad_center(width);
            } else {
                for (0..(width * 2 + 1)) |_| {
                    std.debug.print(" ", .{});
                }
            }

            if (n.right != null) {
                std.debug.print("   ", .{});
            }

            row = n.right;
        }

        std.debug.print("\n", .{});

        // recurse into child rows
        row = start;
        while (row) |n| {
            if (n.down) |d| {
                print_ascii_row(d, ids);
            }
            row = n.right;
        }
    }

    fn print_node_name(id: usize) void {
        const s: u8 = @intCast('A' + id);
        std.debug.print("{s}", .{s});
    }

    fn node_name_len(_: usize) usize {
        return 1;
    }

    fn pad_center(_: usize) void {}
};
