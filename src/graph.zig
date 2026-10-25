const std = @import("std");
const sol = @import("solver");
const types = @import("types");

const NodeContent = union(enum) {
    window: types.WindowHandle,
    empty,
    workspace: *Graph,
    group: *Graph,
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
    left_of: *Node,
    right_of: *Node,
    above: *Node,
    below: *Node,

    align_left: *Node,
    align_top: *Node,
    align_right: *Node,
    align_bottom: *Node,

    equal_width: *Node,
    equal_height: *Node,

    fixed_ratio: f32,

    fixed_width: u32,
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
    custom: *const fn (*Node) void,
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
    preview_window: ?types.WindowHandle = null,
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
    /// The border side drawn in the WM's indicator color, if any.
    indicator_side: ?types.Side,

    on_remove: ?ReparentStrategy,
    dead: bool,
    parked_term: ?*Node,
    focus_serial: u64,
    /// A container named by a layout (protocol.Ref.key): duckwm creates it
    /// when a layout first mentions the key, and destroys it once one doesn't.
    key: ?u32 = null,

    info: types.WindowInfo,

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
            .indicator_side = null,

            .constraints = try std.ArrayListUnmanaged(Constraint).initCapacity(allocator, 4),

            .on_remove = null,
            .dead = false,
            .parked_term = null,
            .focus_serial = 0,

            .info = .{},
        };
    }

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        self.constraints.deinit(allocator);
    }

    /// The window shown for this node: its own, or a workspace's preview.
    pub fn window(self: *const Node) ?types.WindowHandle {
        return switch (self.content) {
            .window => |w| w,
            .workspace => self.preview_window,
            .empty, .group => null,
        };
    }

    pub fn inner(self: *const Node) ?*Graph {
        return switch (self.content) {
            .workspace, .group => |g| g,
            else => null,
        };
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

/// Undo log for the graph's inputs (constraints, membership, flags, float
/// geometry). Solver output isn't logged: a rollback re-solves instead.
/// The same entries are what an incremental solver will read as its dirty set.
pub const Journal = struct {
    allocator: std.mem.Allocator,
    /// > 0 while inside a transaction; mutations are only logged then.
    depth: u32 = 0,
    entries: std.ArrayListUnmanaged(Entry) = .empty,
    /// Removed nodes, kept alive until commit so a rollback can reinsert them.
    graveyard: std.ArrayListUnmanaged(*Node) = .empty,
    /// An entry couldn't be recorded (out of memory): rollback isn't safe.
    incomplete: bool = false,

    pub const Mark = struct { entries: usize, graveyard: usize };

    pub const Entry = union(enum) {
        node_added: struct { graph: *Graph, node: *Node },
        node_removed: struct { graph: *Graph, node: *Node, index: usize },
        constraint_added: *Node,
        constraint_removed: struct { node: *Node, index: usize, value: Constraint },
        constraint_changed: struct { node: *Node, index: usize, old: Constraint },
        /// The old list itself, moved in rather than copied.
        constraints_replaced: struct { node: *Node, old: std.ArrayListUnmanaged(Constraint) },
        /// Any small field of a Node or Graph, by offset.
        field: struct { base: *anyopaque, offset: u16, len: u8, old: [16]u8 },
        /// State outside the graph (core's registry): undone by a callback.
        external: struct { undo: *const fn (*anyopaque, u64) void, ctx: *anyopaque, arg: u64 },
        /// Undo: take the node back out of the graph, without destroying it.
        node_attached: struct { graph: *Graph, node: *Node },
        /// An owned byte buffer replaced (an arranger's state): the old one, freed at commit.
        bytes_replaced: struct { slot: *[]const u8, old: []const u8 },
    };

    pub fn init(allocator: std.mem.Allocator) Journal {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Journal) void {
        self.depth = 0;
        self.finish();
        self.entries.deinit(self.allocator);
        self.graveyard.deinit(self.allocator);
    }

    pub fn active(self: *const Journal) bool {
        return self.depth > 0;
    }

    pub fn set(self: *Journal, obj: anytype, comptime field: []const u8, value: @TypeOf(@field(obj.*, field))) void {
        if (self.active()) self.record_field(obj, field);
        @field(obj.*, field) = value;
    }

    pub fn push(self: *Journal, e: Entry) void {
        self.entries.append(self.allocator, e) catch {
            self.incomplete = true;
        };
    }

    pub fn begin(self: *Journal) Mark {
        self.depth += 1;
        return .{ .entries = self.entries.items.len, .graveyard = self.graveyard.items.len };
    }

    /// Keep everything since m. The outermost release commits.
    pub fn release(self: *Journal, m: Mark) void {
        _ = m;
        self.depth -= 1;
        if (self.depth == 0) self.finish();
    }

    /// Undo everything since m. Returns false if the log was incomplete.
    pub fn rollback(self: *Journal, m: Mark) bool {
        defer {
            self.depth -= 1;
            if (self.depth == 0) self.finish();
        }
        if (self.incomplete) return false;
        while (self.entries.items.len > m.entries) undo(self.allocator, self.entries.pop().?);
        // Everything removed after the mark has just been reinserted.
        self.graveyard.shrinkRetainingCapacity(m.graveyard);
        return true;
    }

    pub fn record_field(self: *Journal, obj: anytype, comptime field: []const u8) void {
        const T = @TypeOf(@field(obj.*, field));
        if (@sizeOf(T) > 16) @compileError("journal: field '" ++ field ++ "' is too large; give it a dedicated entry");
        var e: Entry = .{ .field = .{
            .base = @as(*anyopaque, @ptrCast(obj)),
            .offset = @offsetOf(@TypeOf(obj.*), field),
            .len = @sizeOf(T),
            .old = undefined,
        } };
        @memcpy(e.field.old[0..@sizeOf(T)], std.mem.asBytes(&@field(obj.*, field)));
        self.push(e);
    }

    pub fn external(self: *Journal, undo_fn: *const fn (*anyopaque, u64) void, ctx: *anyopaque, arg: u64) void {
        if (self.active()) self.push(.{ .external = .{ .undo = undo_fn, .ctx = ctx, .arg = arg } });
    }

    fn undo(allocator: std.mem.Allocator, e: Entry) void {
        switch (e) {
            .node_added => |a| {
                for (a.graph.nodes.items, 0..) |n, i| {
                    if (n == a.node) {
                        _ = a.graph.nodes.orderedRemove(i);
                        break;
                    }
                }
                a.node.deinit(allocator);
                allocator.destroy(a.node);
            },
            .node_removed => |r| r.graph.nodes.insert(allocator, r.index, r.node) catch {},
            .constraint_added => |node| _ = node.constraints.pop(),
            .constraint_removed => |r| r.node.constraints.insert(allocator, r.index, r.value) catch {},
            .constraint_changed => |c| c.node.constraints.items[c.index] = c.old,
            .constraints_replaced => |r| {
                var cur = r.node.constraints;
                cur.deinit(allocator);
                r.node.constraints = r.old;
            },
            .field => |f| {
                const dst: [*]u8 = @ptrCast(f.base);
                @memcpy(dst[f.offset..][0..f.len], f.old[0..f.len]);
            },
            .external => |x| x.undo(x.ctx, x.arg),
            .node_attached => |a| {
                for (a.graph.nodes.items, 0..) |n, i| {
                    if (n == a.node) {
                        _ = a.graph.nodes.orderedRemove(i);
                        break;
                    }
                }
            },
            .bytes_replaced => |b| {
                allocator.free(b.slot.*);
                b.slot.* = b.old;
            },
        }
    }

    /// Commit: free what the transaction removed or replaced.
    fn finish(self: *Journal) void {
        for (self.entries.items) |*e| switch (e.*) {
            .constraints_replaced => |*r| r.old.deinit(self.allocator),
            .bytes_replaced => |b| self.allocator.free(b.old),
            else => {},
        };
        self.entries.clearRetainingCapacity();
        for (self.graveyard.items) |node| node.owner_graph.?.destroy_node(node);
        self.graveyard.clearRetainingCapacity();
        self.incomplete = false;
    }
};

pub const Graph = struct {
    id: GraphId = .{ .level = 0, .number = 0 },
    output: u32 = 0,
    nodes: std.ArrayListUnmanaged(*Node) = .empty,
    focus_edges: std.ArrayListUnmanaged(FocusEdge) = .empty,
    active_workspace: usize = 0,
    gap_inner_h: u32 = 0,
    gap_inner_v: u32 = 0,
    gap_outer_h: u32 = 0,
    gap_outer_v: u32 = 0,
    /// A group's outline, overriding the WM-wide one (width 0: none).
    outline_width: ?u32 = null,
    outline_color: ?u32 = null,
    pan_x: i32 = 0,
    pan_y: i32 = 0,
    work_x: i32 = 0,
    work_y: i32 = 0,
    zoom: f64 = 1.0,
    pan_disabled: bool = false,
    fullscreen_node: ?*Node = null,
    fullscreen_saved_x: i32 = 0,
    fullscreen_saved_y: i32 = 0,
    fullscreen_saved_w: u32 = 0,
    fullscreen_saved_h: u32 = 0,
    virtual_width: u32 = 0,
    virtual_height: u32 = 0,
    lock_horizontal_resize: bool = false,
    lock_vertical_resize: bool = false,
    parent_node: ?*Node = null,
    arranger: ?types.Callback = null,
    arranger_index: i32 = 0,
    arranger_name: []const u8 = "",
    /// The arranger's state (an encoded protocol.Value; empty: none yet).
    arranger_state: []const u8 = "",
    is_group: bool = false,
    /// The size a group's arranger last laid it out for (to tell when it must again).
    arranged_w: u32 = 0,
    arranged_h: u32 = 0,
    preview_bg: ?u32 = null,
    preview_win_bg: ?u32 = null,
    preview_border: ?u32 = null,
    preview_text: ?u32 = null,
    preview_font_buf: [256]u8 = undefined,
    preview_font_len: ?usize = null,
    on_node_free: ?*const fn (*anyopaque, *Node) void = null,
    on_node_free_ctx: *anyopaque = undefined,
    journal: ?*Journal = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Graph {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Graph) void {
        for (self.nodes.items) |node| {
            node.deinit(self.allocator);
            self.allocator.destroy(node);
        }
        self.nodes.deinit(self.allocator);
        self.allocator.free(self.arranger_state);
        self.focus_edges.deinit(self.allocator);
    }

    fn free_subgraph(self: *Graph, sub: *Graph) void {
        for (sub.nodes.items) |child| {
            if (child.inner()) |inner| {
                self.free_subgraph(inner);
            }
            if (self.on_node_free) |cb| cb(self.on_node_free_ctx, child);
            child.deinit(self.allocator);
            self.allocator.destroy(child);
        }
        sub.nodes.deinit(self.allocator);
        self.allocator.free(sub.arranger_state);
        sub.focus_edges.deinit(self.allocator);
    }

    fn jr(self: *Graph) ?*Journal {
        const j = self.journal orelse return null;
        return if (j.active()) j else null;
    }

    /// Replace an owned buffer of this graph with a copy of new, journaled.
    pub fn replace_bytes(self: *Graph, slot: *[]const u8, new: []const u8) !void {
        const copy = try self.allocator.dupe(u8, new);
        const old = slot.*;
        slot.* = copy;
        if (self.jr()) |j| j.push(.{ .bytes_replaced = .{ .slot = slot, .old = old } }) else self.allocator.free(old);
    }

    /// Set any field of a Node or Graph, recording the old value.
    pub fn set(self: *Graph, obj: anytype, comptime field: []const u8, value: @TypeOf(@field(obj.*, field))) void {
        if (self.jr()) |j| j.record_field(obj, field);
        @field(obj.*, field) = value;
    }

    pub fn add_constraint(self: *Graph, node: *Node, constraint: Constraint) !void {
        try node.constraints.append(self.allocator, constraint);
        if (self.jr()) |j| j.push(.{ .constraint_added = node });
    }

    pub fn remove_constraint(self: *Graph, node: *Node, constraint: Constraint) void {
        for (node.constraints.items, 0..) |con, i| {
            if (std.meta.eql(con, constraint)) return self.remove_constraint_at(node, i);
        }
    }

    pub fn remove_constraint_at(self: *Graph, node: *Node, i: usize) void {
        const old = node.constraints.orderedRemove(i);
        if (self.jr()) |j| j.push(.{ .constraint_removed = .{
            .node = node,
            .index = i,
            .value = old,
        } });
    }

    pub fn change_constraint_at(self: *Graph, node: *Node, i: usize, new: Constraint) void {
        if (self.jr()) |j| j.push(.{ .constraint_changed = .{
            .node = node,
            .index = i,
            .old = node.constraints.items[i],
        } });
        node.constraints.items[i] = new;
    }

    pub fn check_constraint(node: *const Node, con: Constraint) !void {
        const ok = struct {
            fn f(n: *const Node, other: *const Node) bool {
                return !other.dead and other.owner_graph == n.owner_graph and other != n;
            }
        }.f;
        switch (con) {
            .left_of, .right_of, .above, .below, .align_left, .align_top, .align_right, .align_bottom, .equal_width, .equal_height => |o| {
                if (!ok(node, o)) return error.InvalidConstraint;
            },
            .grid_cell => |g| {
                if (!ok(node, g.container)) return error.InvalidConstraint;
                if (g.cols == 0 or g.rows == 0 or g.col >= g.cols or g.row >= g.rows) return error.InvalidConstraint;
            },
            .grid_cell_abs => |g| if (!ok(node, g.container)) return error.InvalidConstraint,
            .split => |s| {
                // A container holds its own split, so the container may be the node itself.
                if (s.container.dead or s.container.owner_graph != node.owner_graph) return error.InvalidConstraint;
                if (s.count == 0 or s.count > s.children.len) return error.InvalidConstraint;
                for (0..s.count) |k| {
                    if (!ok(node, s.children[k])) return error.InvalidConstraint;
                    if (!std.math.isFinite(s.ratios[k]) or s.ratios[k] < 0) return error.InvalidConstraint;
                }
            },
            .fixed_ratio => |r| if (!std.math.isFinite(r) or r <= 0) return error.InvalidConstraint,
            else => {},
        }
    }

    /// Bulk rewrite: the old list is moved into the log, not copied.
    pub fn replace_constraints(self: *Graph, node: *Node, new: []const Constraint) !void {
        var list = try std.ArrayListUnmanaged(Constraint).initCapacity(self.allocator, new.len);
        list.appendSliceAssumeCapacity(new);
        var old = node.constraints;
        node.constraints = list;
        if (self.jr()) |j| j.push(.{
            .constraints_replaced = .{ .node = node, .old = old },
        }) else old.deinit(self.allocator);
    }

    pub fn add_node(self: *Graph, content: NodeContent) !*Node {
        const node = try self.allocator.create(Node);
        node.* = try Node.init(content, self.allocator);
        node.owner_graph = self;
        try self.nodes.append(self.allocator, node);
        if (self.jr()) |j| j.push(.{ .node_added = .{ .graph = self, .node = node } });
        return node;
    }

    pub fn remove_node(self: *Graph, node: *Node) void {
        std.debug.assert(node.owner_graph == self);
        if (node.dead) return;
        self.set(node, "dead", true);

        if (node.on_remove) |strategy| switch (strategy) {
            .promote => self.promote_sibling(node),
            else => {},
        };

        self.strip_references(node);

        for (self.nodes.items, 0..) |n, idx| {
            if (n != node) continue;
            _ = self.nodes.orderedRemove(idx);
            if (self.jr()) |j| j.push(.{ .node_removed = .{ .graph = self, .node = node, .index = idx } });
            break;
        }

        if (self.jr()) |j| {
            j.graveyard.append(j.allocator, node) catch {
                j.incomplete = true;
                self.destroy_node(node);
            };
        } else {
            self.destroy_node(node);
        }
    }

    /// The workspace g is in: g itself, unless it's a group.
    pub fn workspace(self: *const Graph) *Graph {
        var g = @constCast(self);
        while (g.is_group) g = g.parent_node.?.owner_graph.?;
        return g;
    }

    /// Is self g, or a group somewhere inside g?
    pub fn within(self: *const Graph, g: *const Graph) bool {
        var cur = self;
        while (true) {
            if (cur == g) return true;
            if (!cur.is_group) return false;
            cur = cur.parent_node.?.owner_graph.?;
        }
    }

    /// Drop or shrink every constraint in this graph that refers to node.
    fn strip_references(self: *Graph, node: *Node) void {
        for (self.nodes.items) |n| {
            var i: usize = 0;
            while (i < n.constraints.items.len) {
                const con = n.constraints.items[i];
                if (!constraint_involves_node(con, node)) {
                    i += 1;
                    continue;
                }
                if (con == .split) {
                    var s = con.split;
                    var new_count: u8 = 0;
                    for (0..s.count) |k| {
                        if (s.children[k] == node) continue;
                        s.children[new_count] = s.children[k];
                        s.ratios[new_count] = s.ratios[k];
                        new_count += 1;
                    }
                    if (new_count > 1) {
                        s.count = new_count;
                        var sum: f32 = 0;
                        for (0..new_count) |k| sum += s.ratios[k];
                        if (sum > 0) {
                            for (0..new_count) |k| s.ratios[k] /= sum;
                        }
                        self.change_constraint_at(n, i, .{ .split = s });
                        i += 1;
                        continue;
                    }
                }
                self.remove_constraint_at(n, i);
            }
        }
    }

    /// Take a node out of this graph without destroying it (for moving it elsewhere).
    pub fn detach_node(self: *Graph, node: *Node) void {
        self.strip_references(node);
        for (self.nodes.items, 0..) |n, idx| {
            if (n != node) continue;
            _ = self.nodes.orderedRemove(idx);
            if (self.jr()) |j| j.push(.{ .node_removed = .{ .graph = self, .node = node, .index = idx } });
            return;
        }
    }

    /// Put a detached node into this graph.
    pub fn attach_node(self: *Graph, node: *Node) !void {
        try self.nodes.append(self.allocator, node);
        if (self.jr()) |j| {
            j.record_field(node, "owner_graph");
            j.push(.{ .node_attached = .{ .graph = self, .node = node } });
        }
        node.owner_graph = self;
    }

    /// Final teardown of a removed node (immediately, or at commit).
    pub fn destroy_node(self: *Graph, node: *Node) void {
        if (node.inner()) |sub| self.free_subgraph(sub);
        if (self.on_node_free) |cb| cb(self.on_node_free_ctx, node);
        node.deinit(self.allocator);
        self.allocator.destroy(node);
    }

    /// on_remove = .promote: the sibling sharing node's grid cell takes over
    /// the container's own cell in the grandparent.
    fn promote_sibling(self: *Graph, node: *Node) void {
        const cont = for (node.constraints.items) |con| {
            if (con == .grid_cell) break con.grid_cell.container;
        } else return;

        const sib = for (self.nodes.items) |n| {
            if (n == node) continue;
            const shares = for (n.constraints.items) |con| {
                if (con == .grid_cell and con.grid_cell.container == cont) break true;
            } else false;
            if (shares) break n;
        } else return;

        const gp_cell = for (cont.constraints.items) |con| {
            if (con == .grid_cell) break con.grid_cell;
        } else null;

        var i: usize = 0;
        while (i < sib.constraints.items.len) {
            const con = sib.constraints.items[i];
            if (con == .grid_cell and con.grid_cell.container == cont) {
                self.remove_constraint_at(sib, i);
            } else i += 1;
        }
        if (gp_cell) |g| self.add_constraint(sib, .{ .grid_cell = g }) catch {};
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

    /// This workspace's container named key, if it has one.
    pub fn keyed(self: *Graph, key: u32) ?*Node {
        for (self.nodes.items) |n| {
            if (n.key == key and !n.dead) return n;
        }
        return null;
    }

    pub fn set_preview_font(self: *Graph, name: []const u8) void {
        if (name.len == 0) {
            self.preview_font_len = null; // empty clears the override
            return;
        }
        const len = @min(name.len, self.preview_font_buf.len - 1);
        @memcpy(self.preview_font_buf[0..len], name[0..len]);
        self.preview_font_buf[len] = 0;
        self.preview_font_len = len;
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
            if (nd.content == .workspace and nd.preview_window == null) continue;
            try node_idx.put(self.allocator, nd, i);
        }

        const n_vars = n * 4;
        var solver = try sol.Solver.init(self.allocator, n_vars);
        defer solver.deinit();

        // Seed solver with current node values so underdetermined variables
        // stay at their current position rather than snapping to zero.
        for (self.nodes.items, 0..) |nd, i| {
            if (!node_idx.contains(nd)) continue;
            solver.vals[sol.var_x(i)] = @floatFromInt(nd.x);
            solver.vals[sol.var_y(i)] = @floatFromInt(nd.y);
            solver.vals[sol.var_w(i)] = @floatFromInt(if (nd.width > 0) nd.width else screen_width);
            solver.vals[sol.var_h(i)] = @floatFromInt(if (nd.height > 0) nd.height else screen_height);
        }

        // Default: fill screen for tiled, stay in place for floating
        for (0..n) |i| {
            const nd = self.nodes.items[i];
            if (nd.floating) {
                // anchor floating nodes at their current position/size as weak defaults
                // so relational constraints have a stable reference point
                try solver.add_fixed(sol.var_x(i), @floatFromInt(nd.x), sol.WEAK);
                try solver.add_fixed(sol.var_y(i), @floatFromInt(nd.y), sol.WEAK);
                try solver.add_fixed(sol.var_w(i), @floatFromInt(if (nd.width > 0) nd.width else 100), sol.MEDIUM);
                try solver.add_fixed(sol.var_h(i), @floatFromInt(if (nd.height > 0) nd.height else 100), sol.MEDIUM);
            } else {
                try solver.add_fixed(sol.var_x(i), 0, sol.WEAK);
                try solver.add_fixed(sol.var_y(i), 0, sol.WEAK);
                try solver.add_fixed(sol.var_w(i), @floatFromInt(screen_width), sol.WEAK);
                try solver.add_fixed(sol.var_h(i), @floatFromInt(screen_height), sol.WEAK);
            }
        }

        for (self.nodes.items, 0..) |nd, i| {
            for (nd.constraints.items) |con| {
                // skip absolute position/size constraints for floating nodes
                // but allow relational constraints
                if (nd.floating) {
                    switch (con) {
                        .fixed_x,
                        .fixed_y,
                        .fixed_width,
                        .fixed_height,
                        .grid_cell,
                        .grid_cell_abs,
                        .split,
                        .fixed_ratio,
                        => continue,
                        else => {},
                    }
                }
                switch (con) {
                    .fixed_x => |v| {
                        try solver.add_fixed(sol.var_x(i), @floatFromInt(v), sol.REQUIRED);
                    },
                    .fixed_y => |v| {
                        try solver.add_fixed(sol.var_y(i), @floatFromInt(v), sol.REQUIRED);
                    },
                    .fixed_width => |v| {
                        try solver.add_fixed(sol.var_w(i), @floatFromInt(v), sol.REQUIRED);
                    },
                    .fixed_height => |v| {
                        try solver.add_fixed(sol.var_h(i), @floatFromInt(v), sol.REQUIRED);
                    },

                    // w = ratio * h  =>  w - ratio*h = 0
                    .fixed_ratio => |r| {
                        try solver.add(.{
                            .vars = [8]u32{ @intCast(sol.var_w(i)), @intCast(sol.var_h(i)), 0, 0, 0, 0, 0, 0 },
                            .coeffs = [8]f64{ 1.0, -@as(f64, r), 0, 0, 0, 0, 0, 0 },
                            .n = 2,
                            .rhs = 0,
                            .weight = sol.STRONG,
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
                            .vars = [8]u32{ @intCast(sol.var_x(i)), @intCast(sol.var_x(j)), @intCast(sol.var_w(j)), 0, 0, 0, 0, 0 },
                            .coeffs = [8]f64{ 1.0, -1.0, -(col * cw), 0, 0, 0, 0, 0 },
                            .n = 3,
                            .rhs = 0,
                            .weight = sol.REQUIRED,
                        });
                        // y_i = y_cont + row * (h_cont / rows)
                        try solver.add(.{
                            .vars = [8]u32{ @intCast(sol.var_y(i)), @intCast(sol.var_y(j)), @intCast(sol.var_h(j)), 0, 0, 0, 0, 0 },
                            .coeffs = [8]f64{ 1.0, -1.0, -(row * ch), 0, 0, 0, 0, 0 },
                            .n = 3,
                            .rhs = 0,
                            .weight = sol.REQUIRED,
                        });
                        // w_i = w_cont / cols
                        try solver.add(.{
                            .vars = [8]u32{ @intCast(sol.var_w(i)), @intCast(sol.var_w(j)), 0, 0, 0, 0, 0, 0 },
                            .coeffs = [8]f64{ 1.0, -cw, 0, 0, 0, 0, 0, 0 },
                            .n = 2,
                            .rhs = 0,
                            .weight = sol.REQUIRED,
                        });
                        // h_i = h_cont / rows
                        try solver.add(.{
                            .vars = [8]u32{ @intCast(sol.var_h(i)), @intCast(sol.var_h(j)), 0, 0, 0, 0, 0, 0 },
                            .coeffs = [8]f64{ 1.0, -ch, 0, 0, 0, 0, 0, 0 },
                            .n = 2,
                            .rhs = 0,
                            .weight = sol.REQUIRED,
                        });
                    },

                    .grid_cell_abs => |g| {
                        const j = node_idx.get(g.container) orelse continue;
                        // x_i = x_cont + g.x
                        try solver.add(.{
                            .vars = [8]u32{ @intCast(sol.var_x(i)), @intCast(sol.var_x(j)), 0, 0, 0, 0, 0, 0 },
                            .coeffs = [8]f64{ 1.0, -1.0, 0, 0, 0, 0, 0, 0 },
                            .n = 2,
                            .rhs = @floatFromInt(g.x),
                            .weight = sol.REQUIRED,
                        });
                        // y_i = y_cont + g.y
                        try solver.add(.{
                            .vars = [8]u32{ @intCast(sol.var_y(i)), @intCast(sol.var_y(j)), 0, 0, 0, 0, 0, 0 },
                            .coeffs = [8]f64{ 1.0, -1.0, 0, 0, 0, 0, 0, 0 },
                            .n = 2,
                            .rhs = @floatFromInt(g.y),
                            .weight = sol.REQUIRED,
                        });
                        try solver.add_fixed(sol.var_w(i), @floatFromInt(g.w), sol.REQUIRED);
                        try solver.add_fixed(sol.var_h(i), @floatFromInt(g.h), sol.REQUIRED);
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
                                    .vars = [8]u32{ @intCast(sol.var_x(ck)), @intCast(sol.var_x(j)), @intCast(sol.var_w(j)), 0, 0, 0, 0, 0 },
                                    .coeffs = [8]f64{ 1.0, -1.0, -offset, 0, 0, 0, 0, 0 },
                                    .n = 3,
                                    .rhs = 0,
                                    .weight = sol.REQUIRED,
                                });
                                // w_child = r * w_cont
                                try solver.add(.{
                                    .vars = [8]u32{ @intCast(sol.var_w(ck)), @intCast(sol.var_w(j)), 0, 0, 0, 0, 0, 0 },
                                    .coeffs = [8]f64{ 1.0, -r, 0, 0, 0, 0, 0, 0 },
                                    .n = 2,
                                    .rhs = 0,
                                    .weight = sol.REQUIRED,
                                });
                                // y_child = y_cont
                                try solver.add_diff(sol.var_y(ck), sol.var_y(j), 0, sol.REQUIRED);
                                // h_child = h_cont
                                try solver.add_diff(sol.var_h(ck), sol.var_h(j), 0, sol.REQUIRED);
                            } else {
                                // y_child = y_cont + offset * h_cont
                                try solver.add(.{
                                    .vars = [8]u32{ @intCast(sol.var_y(ck)), @intCast(sol.var_y(j)), @intCast(sol.var_h(j)), 0, 0, 0, 0, 0 },
                                    .coeffs = [8]f64{ 1.0, -1.0, -offset, 0, 0, 0, 0, 0 },
                                    .n = 3,
                                    .rhs = 0,
                                    .weight = sol.REQUIRED,
                                });
                                // h_child = r * h_cont
                                try solver.add(.{
                                    .vars = [8]u32{ @intCast(sol.var_h(ck)), @intCast(sol.var_h(j)), 0, 0, 0, 0, 0, 0 },
                                    .coeffs = [8]f64{ 1.0, -r, 0, 0, 0, 0, 0, 0 },
                                    .n = 2,
                                    .rhs = 0,
                                    .weight = sol.REQUIRED,
                                });
                                // x_child = x_cont
                                try solver.add_diff(sol.var_x(ck), sol.var_x(j), 0, sol.REQUIRED);
                                // w_child = w_cont
                                try solver.add_diff(sol.var_w(ck), sol.var_w(j), 0, sol.REQUIRED);
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
                            .vars = [8]u32{ @intCast(sol.var_x(j)), @intCast(sol.var_x(i)), @intCast(sol.var_w(i)), 0, 0, 0, 0, 0 },
                            .coeffs = [8]f64{ 1.0, -1.0, -1.0, 0, 0, 0, 0, 0 },
                            .n = 3,
                            .rhs = 0,
                            .weight = sol.STRONG,
                        });
                    },
                    .right_of => |other| {
                        const j = node_idx.get(other) orelse continue;
                        // x_i = x_other + w_other  =>  x_i - x_other - w_other = 0
                        try solver.add(.{
                            .vars = [8]u32{ @intCast(sol.var_x(i)), @intCast(sol.var_x(j)), @intCast(sol.var_w(j)), 0, 0, 0, 0, 0 },
                            .coeffs = [8]f64{ 1.0, -1.0, -1.0, 0, 0, 0, 0, 0 },
                            .n = 3,
                            .rhs = 0,
                            .weight = sol.STRONG,
                        });
                    },
                    .above => |other| {
                        const j = node_idx.get(other) orelse continue;
                        // y_other = y_i + h_i  =>  y_other - y_i - h_i = 0
                        try solver.add(.{
                            .vars = [8]u32{ @intCast(sol.var_y(j)), @intCast(sol.var_y(i)), @intCast(sol.var_h(i)), 0, 0, 0, 0, 0 },
                            .coeffs = [8]f64{ 1.0, -1.0, -1.0, 0, 0, 0, 0, 0 },
                            .n = 3,
                            .rhs = 0,
                            .weight = sol.STRONG,
                        });
                    },
                    .below => |other| {
                        const j = node_idx.get(other) orelse continue;
                        // y_i = y_other + h_other  =>  y_i - y_other - h_other = 0
                        try solver.add(.{
                            .vars = [8]u32{ @intCast(sol.var_y(i)), @intCast(sol.var_y(j)), @intCast(sol.var_h(j)), 0, 0, 0, 0, 0 },
                            .coeffs = [8]f64{ 1.0, -1.0, -1.0, 0, 0, 0, 0, 0 },
                            .n = 3,
                            .rhs = 0,
                            .weight = sol.STRONG,
                        });
                    },

                    .align_left => |other| {
                        const j = node_idx.get(other) orelse continue;
                        try solver.add_diff(sol.var_x(i), sol.var_x(j), 0, sol.STRONG);
                    },
                    .align_top => |other| {
                        const j = node_idx.get(other) orelse continue;
                        try solver.add_diff(sol.var_y(i), sol.var_y(j), 0, sol.STRONG);
                    },
                    .align_right => |other| {
                        const j = node_idx.get(other) orelse continue;
                        // x_i + w_i = x_other + w_other
                        try solver.add(.{
                            .vars = [8]u32{
                                @intCast(sol.var_x(i)),
                                @intCast(sol.var_w(i)),
                                @intCast(sol.var_x(j)),
                                @intCast(sol.var_w(j)),
                                0,
                                0,
                                0,
                                0,
                            },
                            .coeffs = [8]f64{ 1.0, 1.0, -1.0, -1.0, 0, 0, 0, 0 },
                            .n = 4,
                            .rhs = 0,
                            .weight = sol.STRONG,
                        });
                    },
                    .align_bottom => |other| {
                        const j = node_idx.get(other) orelse continue;
                        // y_i + h_i = y_other + h_other
                        try solver.add(.{
                            .vars = [8]u32{
                                @intCast(sol.var_y(i)),
                                @intCast(sol.var_h(i)),
                                @intCast(sol.var_y(j)),
                                @intCast(sol.var_h(j)),
                                0,
                                0,
                                0,
                                0,
                            },
                            .coeffs = [8]f64{ 1.0, 1.0, -1.0, -1.0, 0, 0, 0, 0 },
                            .n = 4,
                            .rhs = 0,
                            .weight = sol.STRONG,
                        });
                    },

                    .equal_width => |other| {
                        const j = node_idx.get(other) orelse continue;
                        try solver.add_diff(sol.var_w(i), sol.var_w(j), 0, sol.STRONG);
                    },
                    .equal_height => |other| {
                        const j = node_idx.get(other) orelse continue;
                        try solver.add_diff(sol.var_h(i), sol.var_h(j), 0, sol.STRONG);
                    },
                }
            }
        }

        try solver.solve();
        for (solver.vals) |v| {
            if (!std.math.isFinite(v)) return error.Unsolvable;
        }

        // Write results back, clamping to valid pixel ranges.
        // We clamp AFTER solving so the solver itself sees unclamped
        // values — clamping inside the solver would break constraints
        // that depend on nodes near screen edges.
        const sw: f64 = @floatFromInt(screen_width);
        const sh: f64 = @floatFromInt(screen_height);
        for (self.nodes.items, 0..) |nd, i| {
            if (!node_idx.contains(nd)) continue;
            if (nd.floating) {
                // only update x/y from solver for floating nodes, not w/h
                // unless equal_width/equal_height constraints exist
                const has_size_con = for (nd.constraints.items) |con| {
                    switch (con) {
                        .equal_width, .equal_height => break true,
                        else => {},
                    }
                } else false;
                nd.x = @intFromFloat(@round(solver.vals[sol.var_x(i)]));
                nd.y = @intFromFloat(@round(solver.vals[sol.var_y(i)]));
                if (has_size_con) {
                    nd.width = @intFromFloat(@round(solver.vals[sol.var_w(i)]));
                    nd.height = @intFromFloat(@round(solver.vals[sol.var_h(i)]));
                }
                continue;
            }
            const x_f = @max(0.0, @min(sw, solver.vals[sol.var_x(i)]));
            const y_f = @max(0.0, @min(sh, solver.vals[sol.var_y(i)]));
            const w_f = @max(1.0, @min(sw - x_f, solver.vals[sol.var_w(i)]));
            const h_f = @max(1.0, @min(sh - y_f, solver.vals[sol.var_h(i)]));
            const xi: i32 = @intFromFloat(@round(x_f));
            const yi: i32 = @intFromFloat(@round(y_f));
            const wi: u32 = @intCast(@max(1, @as(i32, @intFromFloat(@round(w_f)))));
            const hi: u32 = @intCast(@max(1, @as(i32, @intFromFloat(@round(h_f)))));
            const sw_i: i32 = @intCast(screen_width);
            const sh_i: i32 = @intCast(screen_height);
            nd.x = xi;
            nd.y = yi;
            nd.width = @intCast(@max(1, @min(sw_i - xi, @as(i32, @intCast(wi)))));
            nd.height = @intCast(@max(1, @min(sh_i - yi, @as(i32, @intCast(hi)))));
        }
    }
};
