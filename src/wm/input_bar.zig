const std = @import("std");
const types = @import("types");
const core = @import("core.zig");
const callbacks = @import("callbacks.zig");
const WM = core.WM;

/// How long a message stays when no timeout is given.
const message_ms = 3000;

/// Open the bar under label; cb gets the line on Enter. One already open is cancelled.
/// On error cb is still the caller's.
pub fn open(wm: *WM, label: []const u8, initial: []const u8, cb: types.Callback) !void {
    cancel(wm);
    try wm.prompt.open(wm.allocator, label, initial);
    try draw(wm);
    wm.prompt_cb = cb;
}

/// A key typed while the bar holds the keyboard.
pub fn key(wm: *WM, k: types.PromptKey) void {
    if (wm.prompt_cb == null) return wm.backend.hide_prompt(); // nothing to hand a line to
    const outcome = wm.prompt.key(wm.allocator, k.keysym, k.mods, k.text()) catch return;
    switch (outcome) {
        .ignored => {},
        .changed => draw(wm) catch cancel(wm),
        .cancel => cancel(wm),
        .submit => submit(wm),
    }
}

/// Close the bar without calling back.
pub fn cancel(wm: *WM) void {
    const cb = wm.prompt_cb orelse return;
    wm.prompt_cb = null;
    wm.backend.hide_prompt();
    callbacks.release(wm, cb);
}

/// Show text in the bar for a while. Not while a line is being typed: that wins.
pub fn message(wm: *WM, text: []const u8, timeout_ms: u32) !void {
    if (wm.prompt_cb != null) {
        std.debug.print("duckwm: {s}\n", .{text});
        return;
    }
    try wm.backend.show_message(text, if (timeout_ms == 0) message_ms else timeout_ms);
}

fn submit(wm: *WM) void {
    const cb = wm.prompt_cb orelse return;
    wm.prompt_cb = null;
    wm.backend.hide_prompt(); // first: the callback may show a message or open another prompt
    defer callbacks.release(wm, cb);

    var arena = std.heap.ArenaAllocator.init(wm.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // A copy: another prompt opened by the callback reuses the editor's buffer.
    const line = a.dupe(u8, wm.prompt.finish(wm.allocator)) catch return;
    const m = wm.tx_begin();
    const ok = if (callbacks.invoke(wm, cb, .{ .line = .{ .text = line } }, a)) |_| true else |_| false;
    wm.tx_end(m, ok);
}

fn draw(wm: *WM) !void {
    const p = &wm.prompt;
    try wm.backend.show_prompt(p.label, p.text.items, p.cursor, p.mode == .normal);
}
