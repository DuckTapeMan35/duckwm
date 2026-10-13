const std = @import("std");
const ziglua = @import("ziglua");
const graph_mod = @import("graph");
const types = @import("types");
const util = @import("util.zig");
const Lua = ziglua.Lua;
const Graph = graph_mod.Graph;
const node_arg = util.node_arg;

// ---- general healpers ----
fn color_arg(lua: *Lua, i: i32, comptime what: []const u8) u32 {
    return util.check_color(lua, i) orelse util.luaL_error_str(lua, "invalid " ++ what ++ " color");
}

/// Repaint at commit: the scene picks up every color change, and a rollback repaints the old ones.
fn repaint() void {
    util.global_wm.flush(util.global_wm.current_graph) catch {};
}

// ---- default border colors ----
pub fn l_set_default_focused_border_color(lua: *Lua) i32 {
    util.global_wm.default_border_color_focused = color_arg(lua, 1, "border");
    repaint();
    return 0;
}

pub fn l_set_default_unfocused_border_color(lua: *Lua) i32 {
    util.global_wm.default_border_color_unfocused = color_arg(lua, 1, "border");
    repaint();
    return 0;
}

pub fn l_set_default_urgent_border_color(lua: *Lua) i32 {
    util.global_wm.default_border_color_urgent = color_arg(lua, 1, "border");
    repaint();
    return 0;
}

pub fn l_set_border_width(lua: *Lua) i32 {
    const width = util.check_u32(lua, 1) orelse util.luaL_error_str(lua, "border width must be non-negative");
    const wm = util.global_wm;
    wm.border_width = @intCast(width);
    wm.backend.publish_frame_extents(width);
    wm.relayout();
    return 0;
}

// ---- per-node border colors ----
pub fn l_set_node_focused_border_color(lua: *Lua) i32 {
    const node = node_arg(lua, 1) orelse util.luaL_error_str(lua, "invalid node id");
    util.global_wm.journal.set(node, "border_color_focused", color_arg(lua, 2, "border"));
    repaint();
    return 0;
}

pub fn l_set_node_unfocused_border_color(lua: *Lua) i32 {
    const node = node_arg(lua, 1) orelse util.luaL_error_str(lua, "invalid node id");
    util.global_wm.journal.set(node, "border_color_unfocused", color_arg(lua, 2, "border"));
    repaint();
    return 0;
}

pub fn l_clear_node_focused_border_color(lua: *Lua) i32 {
    const node = node_arg(lua, 1) orelse util.luaL_error_str(lua, "invalid node id");
    util.global_wm.journal.set(node, "border_color_focused", null);
    repaint();
    return 0;
}

pub fn l_clear_node_unfocused_border_color(lua: *Lua) i32 {
    const node = node_arg(lua, 1) orelse util.luaL_error_str(lua, "invalid node id");
    util.global_wm.journal.set(node, "border_color_unfocused", null);
    repaint();
    return 0;
}

// ---- per-node side colors ----
const Side = enum { top, bottom, left, right };

pub fn l_set_node_border_side_color(lua: *Lua) i32 {
    const node = node_arg(lua, 1) orelse util.luaL_error_str(lua, "invalid node id");
    const side = std.meta.stringToEnum(Side, lua.checkString(2)) orelse
        util.luaL_error_str(lua, "side must be top, bottom, left or right");
    const color: ?u32 = color_arg(lua, 3, "side");
    const j = &util.global_wm.journal;
    switch (side) {
        .top => j.set(node, "border_color_top", color),
        .bottom => j.set(node, "border_color_bottom", color),
        .left => j.set(node, "border_color_left", color),
        .right => j.set(node, "border_color_right", color),
    }
    repaint();
    return 0;
}

pub fn l_clear_node_border_side_colors(lua: *Lua) i32 {
    const node = node_arg(lua, 1) orelse util.luaL_error_str(lua, "invalid node id");
    const j = &util.global_wm.journal;
    j.set(node, "border_color_top", null);
    j.set(node, "border_color_bottom", null);
    j.set(node, "border_color_left", null);
    j.set(node, "border_color_right", null);
    repaint();
    return 0;
}

pub fn l_get_node_border_side_colors(lua: *Lua) i32 {
    const node = node_arg(lua, 1) orelse {
        lua.pushNil();
        return 1;
    };
    lua.newTable();
    const sides = .{
        .{ "top", node.border_color_top },
        .{ "bottom", node.border_color_bottom },
        .{ "left", node.border_color_left },
        .{ "right", node.border_color_right },
    };
    inline for (sides) |s| {
        if (s[1]) |color| {
            lua.pushInteger(@intCast(color));
            lua.setField(-2, s[0]);
        }
    }
    return 1;
}

pub fn l_set_border_side_colors_focused_only(lua: *Lua) i32 {
    util.global_wm.border_side_colors_focused_only = lua.toBoolean(1);
    repaint();
    return 0;
}

// ---- gaps ----
const Gaps = struct { ih: u32, iv: u32, oh: u32, ov: u32 };

fn gaps_args(lua: *Lua, first: i32) Gaps {
    return .{
        .ih = util.check_u32(lua, first) orelse util.luaL_error_str(lua, "invalid inner_h"),
        .iv = util.check_u32(lua, first + 1) orelse util.luaL_error_str(lua, "invalid inner_v"),
        .oh = util.check_u32(lua, first + 2) orelse util.luaL_error_str(lua, "invalid outer_h"),
        .ov = util.check_u32(lua, first + 3) orelse util.luaL_error_str(lua, "invalid outer_v"),
    };
}

fn set_graph_gaps(g: *Graph, gaps: Gaps) void {
    g.set(g, "gap_inner_h", gaps.ih);
    g.set(g, "gap_inner_v", gaps.iv);
    g.set(g, "gap_outer_h", gaps.oh);
    g.set(g, "gap_outer_v", gaps.ov);
}

fn apply_gaps_recursive(g: *Graph, gaps: Gaps) void {
    set_graph_gaps(g, gaps);
    for (g.nodes.items) |node| {
        if (node.content == .workspace) apply_gaps_recursive(node.content.workspace, gaps);
    }
}

pub fn l_set_gaps(lua: *Lua) i32 {
    const gaps = gaps_args(lua, 1);
    const wm = util.global_wm;
    wm.default_gap_inner_h = gaps.ih;
    wm.default_gap_inner_v = gaps.iv;
    wm.default_gap_outer_h = gaps.oh;
    wm.default_gap_outer_v = gaps.ov;
    apply_gaps_recursive(&wm.graph, gaps);
    wm.relayout();
    return 0;
}

pub fn l_set_gaps_workspace(lua: *Lua) i32 {
    const node = node_arg(lua, 1) orelse return 0;
    if (node.content != .workspace) return 0;
    const gaps = gaps_args(lua, 2);
    set_graph_gaps(node.content.workspace, gaps);
    if (node.content.workspace == util.global_wm.current_graph) util.global_wm.relayout();
    return 0;
}

// ---- previews ----
/// Repaint every visible preview in the current graph after a global style change.
fn repaint_previews() void {
    const wm = util.global_wm;
    for (wm.current_graph.nodes.items) |node| {
        if (node.content == .workspace and !node.hidden) wm.repaint_preview(node);
    }
}

pub fn l_set_preview_colors(lua: *Lua) i32 {
    util.global_wm.set_preview_colors(
        color_arg(lua, 1, "bg"),
        color_arg(lua, 2, "win_bg"),
        color_arg(lua, 3, "border"),
        color_arg(lua, 4, "text"),
    );
    repaint_previews();
    return 0;
}

pub fn l_set_preview_colors_workspace(lua: *Lua) i32 {
    const node = node_arg(lua, 1) orelse return 0;
    if (node.content != .workspace) return 0;
    const sub = node.content.workspace;
    sub.set(sub, "preview_bg", color_arg(lua, 2, "bg"));
    sub.set(sub, "preview_win_bg", color_arg(lua, 3, "win_bg"));
    sub.set(sub, "preview_border", color_arg(lua, 4, "border"));
    sub.set(sub, "preview_text", color_arg(lua, 5, "text"));
    util.global_wm.repaint_preview(node);
    return 0;
}

pub fn l_set_preview_font(lua: *Lua) i32 {
    const name = lua.toString(1) catch util.luaL_error_str(lua, "expected font name string");
    util.global_wm.set_preview_font(name);
    repaint_previews();
    return 0;
}

pub fn l_set_preview_font_workspace(lua: *Lua) i32 {
    const node = node_arg(lua, 1) orelse return 0;
    const name = lua.toString(2) catch util.luaL_error_str(lua, "expected font name string");
    if (node.content != .workspace) return 0;
    node.content.workspace.set_preview_font(name);
    util.global_wm.repaint_preview(node);
    return 0;
}

pub fn l_set_preview_max_icon_size(lua: *Lua) i32 {
    const size = lua.toInteger(1) catch util.luaL_error_str(lua, "expected integer size");
    util.global_wm.set_preview_max_icon_size(@intCast(@max(0, size)));
    repaint_previews();
    return 0;
}

// ---- frames ----
pub fn l_set_argb_frames(lua: *Lua) i32 {
    util.global_wm.argb_frames = lua.toBoolean(1);
    return 0;
}

pub fn l_force_rgb_frames(lua: *Lua) i32 {
    const name = lua.checkString(1);
    const wm = util.global_wm;
    const owned = wm.allocator.dupe(u8, name) catch
        util.luaL_error_str(lua, "force_rgb_frames: out of memory");
    wm.rgb_frame_classes.append(wm.allocator, owned) catch {
        wm.allocator.free(owned);
        util.luaL_error_str(lua, "force_rgb_frames: out of memory");
    };
    return 0;
}

// ---- animation ----
fn sample(comptime f: fn (f32) f32) types.CurveTable {
    var out: types.CurveTable = undefined;
    for (&out, 0..) |*v, i| v.* = f(@as(f32, @floatFromInt(i)) / types.curve_samples);
    return out;
}

fn ease_out(t: f32) f32 {
    return 1 - std.math.pow(f32, 1 - t, 3);
}
fn ease_in(t: f32) f32 {
    return t * t * t;
}
fn ease_in_out(t: f32) f32 {
    return if (t < 0.5) 4 * t * t * t else 1 - std.math.pow(f32, -2 * t + 2, 3) / 2;
}

fn preset_curve(name: []const u8) ?types.CurveTable {
    if (std.mem.eql(u8, name, "linear")) return types.linear_curve;
    if (std.mem.eql(u8, name, "ease_out")) return sample(ease_out);
    if (std.mem.eql(u8, name, "ease_in")) return sample(ease_in);
    if (std.mem.eql(u8, name, "ease_in_out")) return sample(ease_in_out);
    return null;
}

/// One axis of a CSS cubic-bezier: endpoints fixed at 0 and 1.
fn bez(a: f32, b: f32, s: f32) f32 {
    const u = 1 - s;
    return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s;
}

fn bezier_curve(x1: f32, y1: f32, x2: f32, y2: f32) types.CurveTable {
    var out: types.CurveTable = undefined;
    for (&out, 0..) |*v, i| {
        const t = @as(f32, @floatFromInt(i)) / types.curve_samples;
        // x(s) is monotonic for x1, x2 in [0, 1]: find s with x(s) = t.
        var lo: f32 = 0;
        var hi: f32 = 1;
        for (0..30) |_| {
            const mid = (lo + hi) / 2;
            if (bez(x1, x2, mid) < t) lo = mid else hi = mid;
        }
        v.* = bez(y1, y2, (lo + hi) / 2);
    }
    return out;
}

pub fn l_set_animation(lua: *Lua) i32 {
    const ms = lua.checkInteger(1);
    if (ms < 0) return util.luaL_error_str(lua, "set_animation: duration must be >= 0");

    var curve = sample(ease_out);
    switch (lua.typeOf(2)) {
        .none, .nil => {},
        .string => curve = preset_curve(lua.checkString(2)) orelse
            return util.luaL_error_str(lua, "set_animation: unknown curve (linear, ease_in, ease_out, ease_in_out)"),
        .table => {
            var p: [4]f32 = undefined;
            for (&p, 1..) |*v, i| {
                _ = lua.getIndexRaw(2, @intCast(i));
                v.* = @floatCast(lua.toNumber(-1) catch
                    return util.luaL_error_str(lua, "set_animation: bezier needs 4 numbers {x1, y1, x2, y2}"));
                lua.pop(1);
            }
            if (p[0] < 0 or p[0] > 1 or p[2] < 0 or p[2] > 1)
                return util.luaL_error_str(lua, "set_animation: bezier x1 and x2 must be within 0..1");
            curve = bezier_curve(p[0], p[1], p[2], p[3]);
        },
        .function => {
            for (&curve, 0..) |*v, i| {
                lua.pushValue(2);
                lua.pushNumber(@as(f64, @floatFromInt(i)) / types.curve_samples);
                lua.protectedCall(.{ .args = 1, .results = 1 }) catch
                    return util.luaL_error_str(lua, "set_animation: curve function raised an error");
                v.* = @floatCast(lua.toNumber(-1) catch
                    return util.luaL_error_str(lua, "set_animation: curve function must return a number"));
                lua.pop(1);
            }
        },
        else => return util.luaL_error_str(lua, "set_animation: curve must be a name, {x1, y1, x2, y2} or a function"),
    }
    util.global_wm.backend.set_animation(.{ .duration_ms = @intCast(ms), .curve = curve });
    return 0;
}
