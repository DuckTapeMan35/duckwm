const std = @import("std");
const ziglua = @import("ziglua");
const graph_mod = @import("graph");
const types = @import("types");
const c = @import("libc");
const core = @import("core.zig");
const settings = @import("settings.zig");
const subscriptions = @import("subscriptions.zig");
const WM = core.WM;

pub const Effect = union(enum) {
    spawn: [][:0]u8,
    close_window: types.WindowHandle,
    bind: struct { key: settings.BindKey, action: settings.Keybind },
    unbind: settings.BindKey,
    sync_pointer_grabs,
    /// Something for subscribers (names, outputs), told after the commit.
    notice: subscriptions.Pending,
};

/// A transaction: the journal position plus the effect queue position.
pub const Tx = struct { mark: graph_mod.Journal.Mark, effects: usize };

pub fn tx_begin(wm: *WM) Tx {
    return .{ .mark = wm.journal.begin(), .effects = wm.effects.items.len };
}

pub fn tx_end(wm: *WM, tx: Tx, ok: bool) void {
    _ = tx_finish(wm, tx, ok);
}

/// Commit (ok) or roll back everything since t. Reports whether the
/// changes were kept: the outermost commit can still be rejected by validation.
pub fn tx_finish(wm: *WM, tx: Tx, ok: bool) bool {
    var keep = ok;
    if (keep and wm.journal.depth == 1) {
        validate(wm) catch |err| {
            std.debug.print("duckwm: transaction rejected: {}\n", .{err});
            keep = false;
        };
    }

    if (keep) {
        wm.journal.release(tx.mark);
    } else {
        while (wm.effects.items.len > tx.effects) drop_effect(wm, wm.effects.pop().?);
        if (wm.journal.rollback(tx.mark)) {
            if (wm.focused) |f| if (wm.get_id_for_node(f) == null) {
                wm.focused = null;
            };
            wm.focus_dirty = true;
            wm.relayout();
        } else {
            std.debug.print("duckwm: could not roll back (out of memory); state may be partial\n", .{});
        }
    }

    if (!wm.journal.active()) {
        // Index loop: running one effect can't invalidate the slice, but keep it simple.
        var i: usize = 0;
        while (i < wm.effects.items.len) : (i += 1) run_effect(wm, wm.effects.items[i]);
        wm.effects.clearRetainingCapacity();
    }

    return keep;
}

fn validate(wm: *WM) !void {
    if (wm.journal.entries.items.len == 0) return; // nothing changed
    for (wm.journal.entries.items) |e| {
        const node = switch (e) {
            .constraint_added => |n| n,
            .constraint_changed => |ch| ch.node,
            .constraints_replaced => |r| r.node,
            else => continue,
        };
        if (node.dead) continue;
        for (node.constraints.items) |con| try graph_mod.Graph.check_constraint(node, con);
    }
    try wm.resolve(wm.current_graph);
}

/// Run now outside a transaction; otherwise at the outermost commit.
pub fn effect(wm: *WM, e: Effect) void {
    if (!wm.journal.active()) return run_effect(wm, e);
    // Out of memory: doing it now beats losing it.
    wm.effects.append(wm.allocator, e) catch run_effect(wm, e);
}

fn run_effect(wm: *WM, e: Effect) void {
    switch (e) {
        .spawn => |argv| {
            spawn_now(argv) catch |err| std.debug.print("spawn: {}\n", .{err});
            free_argv(wm.allocator, argv);
        },
        .close_window => |h| wm.backend.close_window(h),
        .bind => |b| wm.put_keybind(b.key, b.action),
        .unbind => |key| wm.remove_keybind(key),
        .sync_pointer_grabs => settings.apply_pointer_grabs(wm),
        .notice => |n| wm.pending_notices.append(wm.allocator, n) catch {},
    }
}

/// Release what a dropped effect owns. Public for WM.deinit.
pub fn drop_effect(wm: *WM, e: Effect) void {
    switch (e) {
        .spawn => |argv| free_argv(wm.allocator, argv),
        .bind => |b| wm.free_keybind(b.action),
        .unbind => {},
        .close_window, .sync_pointer_grabs, .notice => {},
    }
}

fn free_argv(allocator: std.mem.Allocator, argv: [][:0]u8) void {
    for (argv) |a| allocator.free(a);
    allocator.free(argv);
}

/// Queue a process to start when the current transaction commits.
pub fn spawn(wm: *WM, argv: []const []const u8) !void {
    const owned = try wm.allocator.alloc([:0]u8, argv.len);
    var n: usize = 0;
    errdefer {
        for (owned[0..n]) |a| wm.allocator.free(a);
        wm.allocator.free(owned);
    }
    for (argv) |arg| {
        owned[n] = try wm.allocator.dupeSentinel(u8, arg, 0);
        n += 1;
    }
    effect(wm, .{ .spawn = owned });
}

fn spawn_now(argv: []const [:0]u8) !void {
    var argv_buf: [64:null]?[*:0]const u8 = undefined;
    if (argv.len >= argv_buf.len) return error.TooManyArguments;
    for (argv, 0..) |arg, i| argv_buf[i] = arg.ptr;
    argv_buf[argv.len] = null;

    const pid = c.fork();
    if (pid == 0) {
        _ = c.setsid();
        const pid2 = c.fork();
        if (pid2 == 0) {
            _ = c.execvp(argv_buf[0].?, @ptrCast(&argv_buf));
            c.exit(1);
        }
        c.exit(0);
    } else if (pid < 0) {
        return error.ForkFailed;
    }
    var status: i32 = 0;
    _ = std.os.linux.waitpid(pid, &status, 0);
}
