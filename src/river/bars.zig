const std = @import("std");
const types = @import("types");
const surface = @import("surface.zig");
const State = @import("backend.zig").State;
const util = @import("util.zig");
const now_ms = util.now_ms;
const nonneg = util.nonneg;

const error_bg: u32 = 0x8b1a1a;
const error_fg: u32 = 0xffffff;
const error_pad: i32 = 4;
const prompt_font = "monospace:size=11";
const prompt_bg: u32 = 0x1e1e2e;
const prompt_fg: u32 = 0xcdd6f4;
const prompt_pad: i32 = 4;

pub const ErrorBar = struct {
    surf: surface.ShellSurface,
    msg: []u8,
    height: u32,
    width: u32 = 0,
    dirty: bool = true,
};

/// The input bar (prompts and messages), below the error bar if there is one.
pub const PromptBar = struct {
    surf: surface.ShellSurface,
    height: u32,
    width: u32 = 0,
    dirty: bool = true,
    /// The label then the text, as drawn.
    content: std.ArrayListUnmanaged(u8) = .empty,
    label_len: usize = 0,
    cursor: ?usize = null,
    block: bool = false,
    /// Taking the keyboard: a prompt rather than a message.
    grabbed: bool = false,
    /// river has been told to focus it (only once it has a buffer).
    focused: bool = false,
    /// A message hides itself once now_ms() passes this.
    deadline: ?i64 = null,

    pub fn set(b: *PromptBar, a: std.mem.Allocator, label: []const u8, text: []const u8, cursor: ?usize, block: bool) !void {
        b.content.clearRetainingCapacity();
        try b.content.appendSlice(a, label);
        try b.content.appendSlice(a, text);
        b.label_len = label.len;
        b.cursor = cursor;
        b.block = block;
        b.dirty = true;
    }
};

// ---- error bar ----
pub fn show_error(s: *State, msg: []const u8) !void {
    std.debug.print("duckwm error: {s}\n", .{msg});
    const wm = s.wm orelse return;
    const comp = s.compositor orelse return;
    const bar = s.error_bar orelse blk: {
        const b = try s.allocator.create(ErrorBar);
        errdefer s.allocator.destroy(b);
        b.* = .{ .surf = try surface.ShellSurface.create(wm, comp), .msg = &.{}, .height = 0 };
        s.error_bar = b;
        break :blk b;
    };
    const owned = try s.allocator.dupe(u8, msg);
    s.allocator.free(bar.msg);
    bar.msg = owned;
    const font_h: i32 = if (s.fonts.get(s.allocator, "")) |f| f.height else 16;
    bar.height = @intCast(font_h + 2 * error_pad);
    bar.dirty = true;
    s.mark();
}

/// Remove the error bar; false if there was none.
pub fn hide_error(s: *State) bool {
    const bar = s.error_bar orelse return false;
    s.error_bar = null;
    bar.surf.destroy();
    s.allocator.free(bar.msg);
    s.allocator.destroy(bar);
    s.mark();
    return true;
}

/// Across the top of the usable area; reserved_insets makes room for it.
pub fn render_error(s: *State) void {
    const bar = s.error_bar orelse return;
    const shm = s.shm orelse return;
    const o = s.primary orelse return;
    const area: types.Rect = o.usable orelse
        .{ .x = o.x, .y = o.y, .width = nonneg(o.width), .height = nonneg(o.height) };
    if (bar.dirty or !bar.surf.mapped or bar.width != area.width) {
        const content: surface.ErrorContent = .{
            .msg = bar.msg,
            .font = s.fonts.get(s.allocator, ""),
            .bg = error_bg,
            .fg = error_fg,
            .pad = error_pad,
        };
        bar.surf.draw(shm, area.width, bar.height, &content, surface.paint_error) catch return;
        bar.dirty = false;
        bar.width = area.width;
    }
    bar.surf.node.setPosition(area.x, area.y);
    bar.surf.node.placeTop();
}

// ---- input bar ----
/// The input bar, taking the keyboard: keys come back as prompt_key events.
pub fn show_prompt(s: *State, label: []const u8, text: []const u8, cursor: usize, block: bool) !void {
    const bar = try open_prompt(s);
    if (!bar.grabbed) {
        bar.grabbed = true;
        bar.focused = false;
        s.focus_dirty = true;
    }
    bar.deadline = null;
    try bar.set(s.allocator, label, text, cursor, block);
    s.mark();
}

/// Text in the input bar without taking the keyboard; gone after timeout_ms.
pub fn show_message(s: *State, text: []const u8, timeout_ms: u32) !void {
    const bar = try open_prompt(s);
    if (bar.grabbed) {
        bar.grabbed = false;
        s.focus_dirty = true;
        s.repeat_key = null;
    }
    bar.deadline = now_ms() + timeout_ms;
    try bar.set(s.allocator, "", text, null, false);
    s.mark();
}

/// The input bar, created if there isn't one.
fn open_prompt(s: *State) !*PromptBar {
    if (s.prompt_bar) |b| return b;
    const wm = s.wm orelse return error.NoWindowManager;
    const comp = s.compositor orelse return error.NoCompositor;
    const b = try s.allocator.create(PromptBar);
    errdefer s.allocator.destroy(b);
    const font_h: i32 = if (s.fonts.get(s.allocator, prompt_font)) |f| f.height else 16;
    b.* = .{
        .surf = try surface.ShellSurface.create(wm, comp),
        .height = @intCast(font_h + 2 * prompt_pad),
    };
    s.prompt_bar = b;
    return b;
}

/// Remove the input bar; false if there was none.
pub fn hide_prompt(s: *State) bool {
    const b = s.prompt_bar orelse return false;
    s.prompt_bar = null;
    if (b.grabbed) s.focus_dirty = true; // back to the WM's choice
    s.repeat_key = null;
    b.surf.destroy();
    b.content.deinit(s.allocator);
    s.allocator.destroy(b);
    s.mark();
    return true;
}

/// A prompt has the keyboard.
pub fn typing(s: *const State) bool {
    const b = s.prompt_bar orelse return false;
    return b.grabbed;
}

/// Top of the usable area, under the error bar.
pub fn render_prompt(s: *State) void {
    const bar = s.prompt_bar orelse return;
    const shm = s.shm orelse return;
    const o = s.primary orelse return;
    const area: types.Rect = o.usable orelse
        .{ .x = o.x, .y = o.y, .width = nonneg(o.width), .height = nonneg(o.height) };
    const y = area.y + if (s.error_bar) |e| @as(i32, @intCast(e.height)) else 0;
    if (bar.dirty or !bar.surf.mapped or bar.width != area.width) {
        const content: surface.PromptContent = .{
            .text = bar.content.items,
            .label_len = bar.label_len,
            .cursor = bar.cursor,
            .block = bar.block,
            .font = s.fonts.get(s.allocator, prompt_font),
            .bg = prompt_bg,
            .fg = prompt_fg,
            .pad = prompt_pad,
        };
        bar.surf.draw(shm, area.width, bar.height, &content, surface.paint_prompt) catch return;
        bar.dirty = false;
        bar.width = area.width;
    }
    bar.surf.node.setPosition(area.x, y);
    bar.surf.node.placeTop();
    // It has a buffer now: the next manage can give it the keyboard.
    if (bar.grabbed and !bar.focused) s.mark();
}
