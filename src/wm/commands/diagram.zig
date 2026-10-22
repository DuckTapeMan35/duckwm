const std = @import("std");
const graph_mod = @import("graph");
const core = @import("../core.zig");
const command = @import("../command.zig");
const output = @import("../output.zig");
const util = @import("util.zig");
const WM = core.WM;
const Node = graph_mod.Node;
const Graph = graph_mod.Graph;
const Value = command.Value;
const Args = util.Args;
const Allocator = std.mem.Allocator;

const Style = enum { window, floating, group, workspace };

/// Corners (top-left, top-right, bottom-left, bottom-right), then the horizontal and vertical line.
fn lines(s: Style) [6]u21 {
    return switch (s) {
        .window => .{ '┌', '┐', '└', '┘', '─', '│' },
        .floating => .{ '┏', '┓', '┗', '┛', '━', '┃' },
        .group => .{ '╔', '╗', '╚', '╝', '═', '║' },
        .workspace => .{ '╭', '╮', '╰', '╯', '─', '│' },
    };
}

/// Canvas coordinates to character cells.
const Scale = struct {
    ox: i64,
    oy: i64,
    w: i64,
    h: i64,
    cols: i64,
    rows: i64,

    fn col(self: Scale, x: i64) i64 {
        return @divFloor((x - self.ox) * self.cols, self.w);
    }
    fn row(self: Scale, y: i64) i64 {
        return @divFloor((y - self.oy) * self.rows, self.h);
    }
};

const Grid = struct {
    cells: []u21,
    cols: usize,
    rows: usize,

    fn put(self: Grid, x: i64, y: i64, ch: u21) void {
        if (x < 0 or y < 0 or x >= self.cols or y >= self.rows) return;
        self.cells[@as(usize, @intCast(y)) * self.cols + @as(usize, @intCast(x))] = ch;
    }

    /// A box from (x0, y0) to (x1, y1), inclusive, its inside cleared, with
    /// label on its top edge.
    fn box(self: Grid, x0: i64, y0: i64, x1: i64, y1: i64, s: Style, label: []const u8) void {
        const l = lines(s);
        var y = y0 + 1;
        while (y < y1) : (y += 1) {
            var x = x0 + 1;
            while (x < x1) : (x += 1) self.put(x, y, ' ');
            self.put(x0, y, l[5]);
            self.put(x1, y, l[5]);
        }
        var x = x0 + 1;
        while (x < x1) : (x += 1) {
            self.put(x, y0, l[4]);
            self.put(x, y1, l[4]);
        }
        self.put(x0, y0, l[0]);
        self.put(x1, y0, l[1]);
        self.put(x0, y1, l[2]);
        self.put(x1, y1, l[3]);

        // " label " on the top edge, as far as it fits.
        var at = x0 + 2;
        if (at + 2 > x1) return;
        self.put(at - 1, y0, ' ');
        const view = std.unicode.Utf8View.init(label) catch return;
        var it = view.iterator();
        while (it.nextCodepoint()) |cp| {
            if (at >= x1 - 1) break;
            self.put(at, y0, cp);
            at += 1;
        }
        if (at < x1) self.put(at, y0, ' ');
    }
};

fn label_of(wm: *WM, n: *Node, a: Allocator) ![]const u8 {
    const id = wm.get_id_for_node(n) orelse 0;
    const mark: []const u8 = if (wm.focused == n) "*" else "";
    return switch (n.content) {
        .window => try std.fmt.allocPrint(a, "{s}{d} {s}", .{ mark, id, if (n.info.class_len > 0) n.info.class() else "?" }),
        .workspace => |sub| try std.fmt.allocPrint(a, "{s}{d} ws {d}.{d}", .{ mark, id, sub.id.level, sub.id.number + 1 }),
        .group => |sub| try std.fmt.allocPrint(a, "{s}{d} group {s}", .{ mark, id, if (sub.arranger_name.len > 0) sub.arranger_name else "-" }),
        .empty => "",
    };
}

/// A box's cells, inclusive.
const Cells = struct { x0: i64, y0: i64, x1: i64, y1: i64 };

/// Where n is drawn, kept inside clip (the inside of the group holding it,
/// so its group's edges and label stay visible). Null if it isn't drawn.
fn cells_of(sc: Scale, n: *const Node, clip: Cells) ?Cells {
    if (n.content == .empty or n.width == 0 or n.height == 0) return null;
    if (n.content == .workspace and n.preview_window == null) return null;
    // Neighbours meet without overlapping: one cell short of where the next starts.
    const x0 = @max(clip.x0, sc.col(n.x));
    const y0 = @max(clip.y0, sc.row(n.y));
    const x1 = @min(clip.x1, @max(x0 + 1, sc.col(n.x + @as(i64, n.width)) - 1));
    const y1 = @min(clip.y1, @max(y0 + 1, sc.row(n.y + @as(i64, n.height)) - 1));
    if (x1 <= x0 or y1 <= y0) return null;
    return .{ .x0 = x0, .y0 = y0, .x1 = x1, .y1 = y1 };
}

/// g's nodes, groups before what's in them. Tiled ones in one pass, floating
/// ones (and everything in a floating group) in a second, on top.
fn draw(grid: Grid, sc: Scale, wm: *WM, g: *Graph, floating_pass: bool, in_float: bool, clip: Cells, a: Allocator) anyerror!void {
    for (g.nodes.items) |n| {
        if (n.hidden) continue;
        const fl = in_float or n.floating;
        const c = cells_of(sc, n, clip) orelse continue;
        if (fl == floating_pass) {
            const style: Style = switch (n.content) {
                .group => .group,
                .workspace => .workspace,
                else => if (fl) .floating else .window,
            };
            grid.box(c.x0, c.y0, c.x1, c.y1, style, try label_of(wm, n, a));
        }
        // Into a group when it's drawn in this pass, or (tiled) to find floating ones in it.
        if (n.content == .group and (fl == floating_pass or !fl)) {
            const inside: Cells = .{ .x0 = c.x0 + 1, .y0 = c.y0 + 1, .x1 = c.x1 - 1, .y1 = c.y1 - 1 };
            if (inside.x1 > inside.x0 and inside.y1 > inside.y0)
                try draw(grid, sc, wm, n.content.group, floating_pass, fl, inside, a);
        }
    }
}

/// Grow the bounds to hold everything in g.
fn extend(g: *Graph, b: *[4]i64) void {
    for (g.nodes.items) |n| {
        if (n.hidden or n.content == .empty or n.width == 0 or n.height == 0) continue;
        b[0] = @min(b[0], n.x);
        b[1] = @min(b[1], n.y);
        b[2] = @max(b[2], n.x + @as(i64, n.width));
        b[3] = @max(b[3], n.y + @as(i64, n.height));
        if (n.content == .group) extend(n.content.group, b);
    }
}

/// The current workspace drawn to scale: ┌ windows, ┏ floating, ╔ groups,
/// ╭ workspace previews, * focused. cols defaults to 120; rows to the
/// workspace's proportions (characters are about twice as tall as wide).
pub fn print_graph_pretty(wm: *WM, args: Args(.print_graph_pretty), arena: Allocator) !Value {
    const g = wm.current_graph.workspace();
    const work = output.work_area_of(wm, g);

    // Everything, off-screen parts of a scrolling layout included.
    var b = [4]i64{ work.x, work.y, work.x + @as(i64, work.width), work.y + @as(i64, work.height) };
    extend(g, &b);
    const w = @max(1, b[2] - b[0]);
    const h = @max(1, b[3] - b[1]);

    const cols: i64 = @max(16, @as(i64, args.cols orelse 120));
    const rows: i64 = if (args.rows) |r| @max(6, @as(i64, r)) else @max(6, @divFloor(cols * h, w * 2));
    const sc: Scale = .{ .ox = b[0], .oy = b[1], .w = w, .h = h, .cols = cols, .rows = rows };

    const grid: Grid = .{
        .cells = try arena.alloc(u21, @intCast(cols * rows)),
        .cols = @intCast(cols),
        .rows = @intCast(rows),
    };
    @memset(grid.cells, ' ');
    const all: Cells = .{ .x0 = 0, .y0 = 0, .x1 = cols - 1, .y1 = rows - 1 };
    try draw(grid, sc, wm, g, false, false, all, arena);
    try draw(grid, sc, wm, g, true, false, all, arena);

    var out: std.ArrayListUnmanaged(u8) = .empty;
    try out.print(arena, "workspace {d}.{d} ({s}), canvas {d}x{d} at {d},{d}\n", .{
        g.id.level,                                            g.id.number + 1,
        if (g.arranger_name.len > 0) g.arranger_name else "-", w,
        h,                                                     b[0],
        b[1],
    });
    var buf: [4]u8 = undefined;
    for (0..grid.rows) |r| {
        const row = grid.cells[r * grid.cols ..][0..grid.cols];
        var end = row.len;
        while (end > 0 and row[end - 1] == ' ') end -= 1;
        for (row[0..end]) |cp| {
            const n = std.unicode.utf8Encode(cp, &buf) catch continue;
            try out.appendSlice(arena, buf[0..n]);
        }
        try out.append(arena, '\n');
    }
    try out.appendSlice(arena, "┌ window  ┏ floating  ╔ group  ╭ workspace  * focused\n");
    return .{ .str = out.items };
}
