const std = @import("std");
const graph_mod = @import("graph");
const protocol = @import("protocol");
const core = @import("core.zig");
const scopes = @import("scopes.zig");
const settings = @import("settings.zig");
const paths = @import("paths.zig");
const WM = core.WM;
const Node = graph_mod.Node;
const Graph = graph_mod.Graph;

pub const Setting = union(enum) {
    gaps: protocol.Gaps,
    preview_colors: struct { bg: u32, win_bg: u32, border: u32, text: u32 },
    /// Owned.
    preview_font: []const u8,
};

pub const Entry = struct { scope: scopes.Scope, layer: settings.Layer, setting: Setting };

/// Keep s for the current scope, and lay it over the workspaces in it now.
pub fn add(wm: *WM, s: Setting) !void {
    var owned = s;
    if (s == .preview_font) owned = .{ .preview_font = try wm.allocator.dupe(u8, s.preview_font) };
    errdefer free(wm, owned);
    try wm.workspace_settings.append(wm.allocator, .{
        .scope = scopes.current(wm),
        .layer = .of(wm.callback_source),
        .setting = owned,
    });
    apply_all(wm);
}

/// Lay the settings over every workspace in their paths.
pub fn apply_all(wm: *WM) void {
    if (wm.workspace_settings.items.len == 0) return;
    for (wm.outputs.items) |o| apply_in(wm, &o.root);
    wm.relayout();
}

fn apply_in(wm: *WM, g: *Graph) void {
    for (g.nodes.items) |n| {
        if (n.content != .workspace) continue;
        apply_to(wm, n);
        apply_in(wm, n.content.workspace);
    }
}

const Match = struct { index: usize, depth: usize };

/// Lay the settings whose path ws is in over it, the farthest match first.
pub fn apply_to(wm: *WM, ws: *Node) void {
    if (wm.workspace_settings.items.len == 0) return;
    var matches: std.ArrayListUnmanaged(Match) = .empty;
    defer matches.deinit(wm.allocator);
    for (wm.workspace_settings.items, 0..) |e, i| {
        const depth: usize = if (e.scope == scopes.everywhere) std.math.maxInt(usize) else blk: {
            var buf: [paths.max_depth][]const u8 = undefined;
            const segs = paths.split(scopes.path_of(wm, e.scope), &buf) catch continue;
            break :blk paths.depth_under(wm, .{ .node = ws }, segs) orelse continue;
        };
        matches.append(wm.allocator, .{ .index = i, .depth = depth }) catch return;
    }
    if (matches.items.len == 0) return;
    // Farthest first, and for the same distance, in the order they were made.
    std.mem.sort(Match, matches.items, {}, struct {
        fn lt(_: void, a: Match, b: Match) bool {
            return if (a.depth != b.depth) a.depth > b.depth else a.index < b.index;
        }
    }.lt);

    const g = ws.content.workspace;
    var previews = false;
    for (matches.items) |m| switch (wm.workspace_settings.items[m.index].setting) {
        .gaps => |gaps| {
            g.set(g, "gap_inner_h", gaps.inner_h);
            g.set(g, "gap_inner_v", gaps.inner_v);
            g.set(g, "gap_outer_h", gaps.outer_h);
            g.set(g, "gap_outer_v", gaps.outer_v);
        },
        .preview_colors => |c| {
            g.set(g, "preview_bg", c.bg);
            g.set(g, "preview_win_bg", c.win_bg);
            g.set(g, "preview_border", c.border);
            g.set(g, "preview_text", c.text);
            previews = true;
        },
        .preview_font => |name| {
            g.set_preview_font(name);
            previews = true;
        },
    };
    if (previews) wm.repaint_preview(ws);
}

/// Forget the settings made from one layer: the config's, before it's run again.
pub fn clear_layer(wm: *WM, layer: settings.Layer) void {
    var i = wm.workspace_settings.items.len;
    while (i > 0) {
        i -= 1;
        if (wm.workspace_settings.items[i].layer != layer) continue;
        free(wm, wm.workspace_settings.orderedRemove(i).setting);
    }
}

pub fn deinit(wm: *WM) void {
    for (wm.workspace_settings.items) |e| free(wm, e.setting);
    wm.workspace_settings.deinit(wm.allocator);
}

fn free(wm: *WM, s: Setting) void {
    if (s == .preview_font) wm.allocator.free(s.preview_font);
}
