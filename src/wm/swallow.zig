const std = @import("std");
const c = @import("c").c;
const WM = @import("core.zig").WM;
const graph_mod = @import("graph");

fn read_ppid(pid: u32) ?u32 {
    var buf: [64]u8 = undefined;
    const path = std.fmt.bufPrintZ(&buf, "/proc/{d}/status", .{pid}) catch return null;
    const f = c.fopen(path.ptr, "r") orelse return null;
    defer _ = c.fclose(f);
    var line: [256]u8 = undefined;
    while (c.fgets(&line, line.len, f) != null) {
        const s = std.mem.sliceTo(&line, 0);
        if (std.mem.startsWith(u8, s, "PPid:")) {
            const val = std.mem.trim(u8, s["PPid:".len..], " \t\n");
            return std.fmt.parseInt(u32, val, 10) catch null;
        }
    }
    return null;
}

fn is_ancestor(ancestor_pid: u32, child_pid: u32) bool {
    var cur = child_pid;
    for (0..8) |_| {
        const p = read_ppid(cur) orelse return false;
        if (p <= 1) return false;
        if (p == ancestor_pid) return true;
        cur = p;
    }
    return false;
}

fn get_wm_class(display: *c.Display, win: c.Window, buf: []u8) ?[]const u8 {
    var hint: c.XClassHint = std.mem.zeroes(c.XClassHint);
    if (c.XGetClassHint(display, win, &hint) == 0) return null;
    defer {
        if (hint.res_name)  |n|  _ = c.XFree(n);
        if (hint.res_class) |cl| _ = c.XFree(cl);
    }
    const cl = hint.res_class orelse return null;
    const span = std.mem.span(cl);
    if (span.len > buf.len) return null;
    @memcpy(buf[0..span.len], span);
    return buf[0..span.len];
}

fn get_net_wm_pid(display: *c.Display, win: c.Window) ?u32 {
    const net_wm_pid = c.XInternAtom(display, "_NET_WM_PID", 0);
    var actual_type: c.Atom = undefined;
    var actual_format: c_int = undefined;
    var nitems: c_ulong = undefined;
    var bytes_after: c_ulong = undefined;
    var prop: [*c]u8 = null;
    const result = c.XGetWindowProperty(
        display, win, net_wm_pid,
        0, 1, 0, c.AnyPropertyType,
        &actual_type, &actual_format, &nitems, &bytes_after, &prop,
    );
    if (result != c.Success or prop == null or nitems == 0) {
        if (prop != null) _ = c.XFree(prop);
        return null;
    }
    defer _ = c.XFree(prop);
    const pid: c_ulong = @as(*c_ulong, @ptrCast(@alignCast(prop))).*;
    return @intCast(pid);
}

pub fn try_swallow(wm: *WM, child_id: u32) void {
    if (wm.swallow_classes.count() == 0) return;

    const child_node = wm.node_registry.get(child_id) orelse return;
    const child_win = switch (child_node.content) {
        .window => |w| w,
        else => return,
    };

    const child_pid = get_net_wm_pid(wm.display, child_win) orelse return;

    var class_buf: [256]u8 = undefined;

    var it = wm.node_registry.iterator();
    while (it.next()) |entry| {
        const term_id = entry.key_ptr.*;
        if (term_id == child_id) continue;
        const term_node = entry.value_ptr.*;
        if (term_node.owner_graph != wm.current_graph) continue;
        const term_win = switch (term_node.content) {
            .window => |w| w,
            else => continue,
        };

        const term_pid = get_net_wm_pid(wm.display, term_win) orelse continue;
        if (!is_ancestor(term_pid, child_pid)) continue;

        const cls = get_wm_class(wm.display, term_win, &class_buf) orelse continue;
        if (!wm.swallow_classes.contains(cls)) continue;

        // Found a match — do the swallow
        do_swallow(wm, term_id, term_node, child_id, child_node);
        return;
    }
}

fn do_swallow(
    wm: *WM,
    term_id: u32, term_node: *graph_mod.Node,
    child_id: u32, child_node: *graph_mod.Node,
) void {
    const g = wm.current_graph;

    child_node.constraints.deinit(wm.allocator);
    child_node.constraints = term_node.constraints;
    term_node.constraints  = .{ .items = &.{}, .capacity = 0 };

    rewrite_refs(g, term_node, child_node);

    var term_idx: ?usize = null;
    var child_idx: ?usize = null;
    for (g.nodes.items, 0..) |n, i| {
        if (n == term_node)  term_idx  = i;
        if (n == child_node) child_idx = i;
    }

    if (term_idx) |ti| g.nodes.items[ti] = child_node;
    if (child_idx) |ci| _ = g.nodes.swapRemove(ci);

    child_node.owner_graph = g;
    term_node.owner_graph  = null;

    child_node.hidden = false;

    switch (term_node.content) {
        .window => |win| {
            if (wm.frames.get(win)) |frame| {
                _ = c.XUnmapWindow(wm.display, frame);
                _ = c.XFlush(wm.display);
            }
        },
        else => {},
    }

    wm.swallowed.put(wm.allocator, child_id, term_id) catch {};

    // Notify arranger the terminal unmapped so its internal list is correct
    wm.call_arranger(g, "unmap", term_id, null);

    wm.resolve(g) catch {};
    wm.rebuild_focus_edges() catch {};
    wm.flush(g) catch {};
    wm.focus(child_node);
}

pub fn try_unswallow(wm: *WM, child_id: u32) bool {
    const term_id = wm.swallowed.get(child_id) orelse return false;
    _ = wm.swallowed.remove(child_id);

    const child_node = wm.node_registry.get(child_id) orelse return false;
    const term_node  = wm.node_registry.get(term_id)  orelse return false;
    const g = wm.current_graph;

    // Transfer constraints back: child -> term
    term_node.constraints.deinit(wm.allocator);
    term_node.constraints  = child_node.constraints;
    child_node.constraints = .{ .items = &.{}, .capacity = 0 };

    // Rewrite graph-wide constraint references: child -> term
    rewrite_refs(g, child_node, term_node);

    // Find child's slot and replace with term
    for (g.nodes.items, 0..) |n, i| {
        if (n == child_node) {
            g.nodes.items[i] = term_node;
            break;
        }
    }

    term_node.owner_graph  = g;
    child_node.owner_graph = null;

    // Fully destroy the child's frame and clean up registries
    switch (child_node.content) {
        .window => |win| {
            if (wm.frames.get(win)) |frame| {
                _ = c.XUnmapWindow(wm.display, frame);
                _ = c.XDestroyWindow(wm.display, frame);
                _ = wm.frames.remove(win);
            }
            _ = wm.window_to_node_id.remove(win);
        },
        else => {},
    }
    _ = wm.node_registry.remove(child_id);

    // Free the child node itself
    child_node.deinit(wm.allocator);
    wm.allocator.destroy(child_node);

    // Remap terminal's frame
    switch (term_node.content) {
        .window => |win| {
            if (wm.frames.get(win)) |frame| {
                _ = c.XMapWindow(wm.display, frame);
                _ = c.XMapWindow(wm.display, win);
                _ = c.XRaiseWindow(wm.display, frame);
                _ = c.XFlush(wm.display);
            }
        },
        else => {},
    }

    if (wm.focused == child_node) wm.focused = null;

    wm.resolve(g) catch {};
    wm.rebuild_focus_edges() catch {};
    wm.flush(g) catch {};
    wm.focus(term_node);

    return true;
}

fn rewrite_refs(g: *graph_mod.Graph, old: *graph_mod.Node, new: *graph_mod.Node) void {
    for (g.nodes.items) |n| {
        for (n.constraints.items) |*con| {
            switch (con.*) {
                .left_of      => |*o| if (o.* == old) { o.* = new; },
                .right_of     => |*o| if (o.* == old) { o.* = new; },
                .above        => |*o| if (o.* == old) { o.* = new; },
                .below        => |*o| if (o.* == old) { o.* = new; },
                .align_left   => |*o| if (o.* == old) { o.* = new; },
                .align_top    => |*o| if (o.* == old) { o.* = new; },
                .align_right  => |*o| if (o.* == old) { o.* = new; },
                .align_bottom => |*o| if (o.* == old) { o.* = new; },
                .equal_width  => |*o| if (o.* == old) { o.* = new; },
                .equal_height => |*o| if (o.* == old) { o.* = new; },
                .grid_cell     => |*gc| {
                    if (gc.container == old) gc.container = new;
                },
                .grid_cell_abs => |*gc| {
                    if (gc.container == old) gc.container = new;
                },
                .split => |*s| {
                    if (s.container == old) s.container = new;
                    for (0..s.count) |i| {
                        if (s.children[i] == old) s.children[i] = new;
                    }
                },
                else => {},
            }
        }
    }
}
