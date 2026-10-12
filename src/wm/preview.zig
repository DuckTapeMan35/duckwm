const std = @import("std");
const types = @import("types");
const graph_mod = @import("graph");
const Graph = graph_mod.Graph;

/// Global preview settings; individual workspaces can override them.
pub const Defaults = struct {
    bg: u32 = 0xFF1a1a2e,
    win_bg: u32 = 0xFF16213e,
    border: u32 = 0xFF4488ff,
    text: u32 = 0xe0e0e0,
    max_icon_size: ?u32 = null,
    font_buf: [256]u8 = undefined,
    font_len: usize = 0,

    pub fn font(self: *const Defaults) []const u8 {
        return if (self.font_len == 0) "sans:pixelsize=9" else self.font_buf[0..self.font_len];
    }

    pub fn set_font(self: *Defaults, name: []const u8) void {
        const n = @min(name.len, self.font_buf.len);
        @memcpy(self.font_buf[0..n], name[0..n]);
        self.font_len = n;
    }
};

pub fn style(d: *const Defaults, sub: *Graph) types.PreviewStyle {
    return .{
        .bg = sub.preview_bg orelse d.bg,
        .win_bg = sub.preview_win_bg orelse d.win_bg,
        .border = sub.preview_border orelse d.border,
        .text = sub.preview_text orelse d.text,
        .font = if (sub.preview_font_len) |len| sub.preview_font_buf[0..len] else d.font(),
    };
}

/// where each tiled node of sub appears inside a w by h preview.
pub fn layout(
    gpa: std.mem.Allocator,
    sub: *Graph,
    w: u32,
    h: u32,
    max_icon: ?u32,
    out: *std.ArrayListUnmanaged(types.PreviewItem),
) !void {
    out.clearRetainingCapacity();

    var x1: i32 = std.math.maxInt(i32);
    var y1: i32 = std.math.maxInt(i32);
    var x2: i32 = std.math.minInt(i32);
    var y2: i32 = std.math.minInt(i32);
    for (sub.nodes.items) |node| {
        if (node.floating or node.content == .empty) continue;
        x1 = @min(x1, node.x);
        y1 = @min(y1, node.y);
        x2 = @max(x2, node.x + @as(i32, @intCast(node.width)));
        y2 = @max(y2, node.y + @as(i32, @intCast(node.height)));
    }
    if (x1 == std.math.maxInt(i32)) return;
    const src_w = x2 - x1;
    const src_h = y2 - y1;
    if (src_w <= 0 or src_h <= 0) return;

    const pad: f32 = 6;
    const dst_w = @as(f32, @floatFromInt(w)) - 2 * pad;
    const dst_h = @as(f32, @floatFromInt(h)) - 2 * pad;
    const scale = @min(dst_w / @as(f32, @floatFromInt(src_w)), dst_h / @as(f32, @floatFromInt(src_h)));
    if (scale <= 0) return; // preview too small to show anything

    for (sub.nodes.items) |node| {
        if (node.floating or node.content == .empty) continue;

        const rx: i32 = @intFromFloat(@as(f32, @floatFromInt(node.x - x1)) * scale + pad);
        const ry: i32 = @intFromFloat(@as(f32, @floatFromInt(node.y - y1)) * scale + pad);
        const rw: u32 = @max(4, @as(u32, @intFromFloat(@as(f32, @floatFromInt(node.width)) * scale)));
        const rh: u32 = @max(4, @as(u32, @intFromFloat(@as(f32, @floatFromInt(node.height)) * scale)));

        var icon: u32 = 0;
        if (rw > 8 and rh > 8) {
            icon = @max(8, @min(rw, rh) * 2 / 3);
            if (max_icon) |cap| icon = @min(icon, cap);
        }

        const full: []const u8 = switch (node.content) {
            .window => if (node.info.class_len > 0) node.info.class() else "?",
            .workspace => "ws",
            .empty => unreachable,
        };

        try out.append(gpa, .{
            .rect = .{ .x = rx, .y = ry, .width = rw, .height = rh },
            .window = switch (node.content) {
                .window => |win| win,
                else => null,
            },
            .label = if (rw < 40) first_codepoint(full) else full,
            .icon_size = icon,
        });
    }
}

fn first_codepoint(s: []const u8) []const u8 {
    if (s.len == 0) return s;
    const n = std.unicode.utf8ByteSequenceLength(s[0]) catch 1;
    return s[0..@min(n, s.len)];
}
