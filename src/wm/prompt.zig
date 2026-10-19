const std = @import("std");
const types = @import("types");
const Allocator = std.mem.Allocator;

pub const Outcome = enum { ignored, changed, submit, cancel };

/// emacs: Escape cancels. vi: Escape goes to normal mode, and cancels from there.
pub const Keys = enum { emacs, vi };
pub const Mode = enum { insert, normal };

// X keysyms; xkbcommon uses the same values.
const XK = struct {
    const BackSpace = 0xff08;
    const Return = 0xff0d;
    const Escape = 0xff1b;
    const Home = 0xff50;
    const Left = 0xff51;
    const Up = 0xff52;
    const Right = 0xff53;
    const Down = 0xff54;
    const End = 0xff57;
    const KP_Enter = 0xff8d;
    const Delete = 0xffff;
};

const history_max = 100;
const undo_max = 100;
const History = std.ArrayListUnmanaged([]u8);
const Snapshot = struct { text: []u8, cursor: usize };

/// Where a motion lands, and whether an operator over it includes that character (e, f, t).
const Target = struct { pos: usize, inclusive: bool = false };

pub const Editor = struct {
    keys: Keys = .emacs,
    mode: Mode = .insert,

    label: []u8 = &.{},
    text: std.ArrayListUnmanaged(u8) = .empty,
    /// A byte offset, always at the start of a UTF-8 sequence. In normal mode
    /// it sits on a character, so never at the end unless the text is empty.
    cursor: usize = 0,
    /// Index into this label's history while stepping through it.
    browsing: ?usize = null,
    /// What was being typed before stepping into history; stepping past the newest entry brings it back.
    draft: std.ArrayListUnmanaged(u8) = .empty,
    /// One history per label, so "lua: " and "run: " don't mix.
    histories: std.StringHashMapUnmanaged(History) = .empty,

    // vi normal mode: a command being typed.
    count: u32 = 0,
    op: ?u8 = null, // d, c or y, waiting for its motion
    op_count: u32 = 1,
    pending: ?u8 = null, // f, F, t, T or r, waiting for its character
    pending_count: u32 = 1,
    last_find: ?u8 = null,
    last_needle: [4]u8 = undefined,
    last_needle_len: u3 = 0,
    /// What d, c, y, x and s took; p and P put it back.
    register: std.ArrayListUnmanaged(u8) = .empty,
    undo: std.ArrayListUnmanaged(Snapshot) = .empty,

    pub fn deinit(e: *Editor, a: Allocator) void {
        a.free(e.label);
        e.text.deinit(a);
        e.draft.deinit(a);
        e.register.deinit(a);
        e.clear_undo(a);
        e.undo.deinit(a);
        var it = e.histories.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.items) |line| a.free(line);
            entry.value_ptr.deinit(a);
            a.free(entry.key_ptr.*);
        }
        e.histories.deinit(a);
    }

    /// Start a new line under label, holding initial, in insert mode with the cursor at its end.
    pub fn open(e: *Editor, a: Allocator, label: []const u8, initial: []const u8) !void {
        const owned = try a.dupe(u8, label);
        a.free(e.label);
        e.label = owned;
        e.browsing = null;
        e.mode = .insert;
        e.reset_command();
        e.clear_undo(a);
        try e.set_text(a, initial);
        try e.save(a);
    }

    /// The finished line, added to this label's history. Valid until the next open.
    pub fn finish(e: *Editor, a: Allocator) []const u8 {
        e.remember(a) catch {};
        return e.text.items;
    }

    /// Apply one key. text is what it types (UTF-8), empty for keys that type nothing.
    pub fn key(e: *Editor, a: Allocator, keysym: u32, mods: u32, text: []const u8) !Outcome {
        if (e.keys == .vi and e.mode == .normal) return e.normal_key(a, keysym, mods, text);

        const held = mods & (types.mod.ctrl | types.mod.alt | types.mod.super);
        if (held == types.mod.ctrl) return e.ctrl_key(a, keysym);
        if (held != 0) return .ignored;
        switch (keysym) {
            XK.Return, XK.KP_Enter => return .submit,
            XK.Escape => {
                if (e.keys == .emacs) return .cancel;
                e.mode = .normal;
                e.cursor = e.prev(e.cursor); // as vim: Escape steps back onto the last character typed
                e.clamp();
                return .changed;
            },
            XK.BackSpace => return e.delete(e.prev(e.cursor), e.cursor),
            XK.Delete => return e.delete(e.cursor, e.next(e.cursor)),
            XK.Left => return e.move(e.prev(e.cursor)),
            XK.Right => return e.move(e.next(e.cursor)),
            XK.Home => return e.move(0),
            XK.End => return e.move(e.text.items.len),
            XK.Up => return e.older(a),
            XK.Down => return e.newer(a),
            else => {},
        }
        if (!printable(text)) return .ignored;
        try e.text.insertSlice(a, e.cursor, text);
        e.cursor += text.len;
        e.browsing = null;
        return .changed;
    }

    /// Emacs keys, as in StumpWM and readline; also in vi's insert mode, as in vim's.
    fn ctrl_key(e: *Editor, a: Allocator, keysym: u32) !Outcome {
        return switch (keysym) {
            'a' => e.move(0),
            'e' => e.move(e.text.items.len),
            'b' => e.move(e.prev(e.cursor)),
            'f' => e.move(e.next(e.cursor)),
            'h' => e.delete(e.prev(e.cursor), e.cursor),
            'd' => e.delete(e.cursor, e.next(e.cursor)),
            'k' => e.delete(e.cursor, e.text.items.len),
            'u' => e.delete(0, e.cursor),
            'w' => e.delete(e.word_back(e.cursor, false), e.cursor),
            'p' => e.older(a),
            'n' => e.newer(a),
            'g', 'c' => .cancel,
            'j', 'm' => .submit,
            else => .ignored,
        };
    }

    // ---- vi normal mode ----

    fn normal_key(e: *Editor, a: Allocator, keysym: u32, mods: u32, text: []const u8) !Outcome {
        const held = mods & (types.mod.ctrl | types.mod.alt | types.mod.super);
        if (held == types.mod.ctrl) return switch (keysym) {
            'c', 'g' => .cancel,
            'j', 'm' => .submit,
            else => .ignored,
        };
        if (held != 0) return .ignored;

        if (e.pending) |p| {
            e.pending = null;
            if (!printable(text) or text.len > 4) {
                e.reset_command();
                return .ignored;
            }
            if (p == 'r') return e.replace_char(a, text);
            e.last_find = p;
            @memcpy(e.last_needle[0..text.len], text);
            e.last_needle_len = @intCast(text.len);
            const tg = e.find(p, text, e.pending_count) orelse {
                e.reset_command();
                return .ignored;
            };
            return e.go(a, tg);
        }

        switch (keysym) {
            XK.Escape => {
                if (e.op != null or e.count != 0) {
                    e.reset_command();
                    return .ignored;
                }
                return .cancel;
            },
            XK.Return, XK.KP_Enter => return .submit,
            XK.Left, XK.BackSpace => return e.command(a, 'h'),
            XK.Right => return e.command(a, 'l'),
            XK.Up => return e.command(a, 'k'),
            XK.Down => return e.command(a, 'j'),
            XK.Home => return e.command(a, '0'),
            XK.End => return e.command(a, '$'),
            XK.Delete => return e.command(a, 'x'),
            else => {},
        }
        if (text.len != 1) return .ignored;
        return e.command(a, text[0]);
    }

    fn command(e: *Editor, a: Allocator, ch: u8) !Outcome {
        if ((ch >= '1' and ch <= '9') or (ch == '0' and e.count > 0)) {
            e.count = @min(e.count * 10 + (ch - '0'), 9999);
            return .ignored;
        }
        const n = @max(e.count, 1);
        e.count = 0;

        if (e.op) |op| {
            if (ch == op) { // dd, cc, yy: the whole line
                e.reset_command();
                return e.operate(a, op, 0, e.text.items.len);
            }
        }
        switch (ch) {
            'd', 'c', 'y' => {
                if (e.op != null) {
                    e.reset_command();
                    return .ignored;
                }
                e.op = ch;
                e.op_count = n;
                return .ignored;
            },
            'f', 'F', 't', 'T', 'r' => {
                e.pending = ch;
                e.pending_count = n * e.op_count;
                return .ignored;
            },
            else => {},
        }

        const total = n * e.op_count;
        // cw on a word changes to its end, as vim does: like ce.
        const m: u8 = if (e.op == 'c' and (ch == 'w' or ch == 'W') and e.cursor < e.text.items.len and
            class(e.text.items[e.cursor], false) != 0) (if (ch == 'w') 'e' else 'E') else ch;
        if (e.motion(m, total)) |tg| return e.go(a, tg);
        if (e.op != null) {
            e.reset_command();
            return .ignored;
        }

        const len = e.text.items.len;
        return switch (ch) {
            'i' => e.insert_at(a, e.cursor),
            'a' => e.insert_at(a, e.next(e.cursor)),
            'I' => e.insert_at(a, e.first_nonblank()),
            'A' => e.insert_at(a, len),
            'x' => e.with_op(a, 'd', 'l', n),
            'X' => e.with_op(a, 'd', 'h', n),
            's' => e.with_op(a, 'c', 'l', n),
            'D' => e.with_op(a, 'd', '$', 1),
            'C' => e.with_op(a, 'c', '$', 1),
            'S' => e.operate(a, 'c', 0, len),
            'Y' => e.operate(a, 'y', 0, len),
            'p' => e.paste(a, true, n),
            'P' => e.paste(a, false, n),
            '~' => e.toggle_case(a, n),
            'u' => e.undo_last(a),
            'k' => e.history_step(a, true),
            'j' => e.history_step(a, false),
            else => .ignored,
        };
    }

    fn with_op(e: *Editor, a: Allocator, op: u8, m: u8, n: u32) !Outcome {
        e.op = op;
        return e.go(a, e.motion(m, n).?);
    }

    /// Move to tg, or apply the waiting operator from the cursor to it.
    fn go(e: *Editor, a: Allocator, tg: Target) !Outcome {
        if (e.op) |op| {
            e.reset_command();
            const from = @min(tg.pos, e.cursor);
            var to = @max(tg.pos, e.cursor);
            if (tg.pos >= e.cursor and tg.inclusive) to = e.next(to);
            return e.operate(a, op, from, to);
        }
        e.reset_command();
        const before = e.cursor;
        e.cursor = tg.pos;
        e.clamp();
        return if (e.cursor == before) .ignored else .changed;
    }

    fn operate(e: *Editor, a: Allocator, op: u8, from: usize, to: usize) !Outcome {
        e.register.clearRetainingCapacity();
        try e.register.appendSlice(a, e.text.items[from..to]);
        switch (op) {
            'y' => {
                e.cursor = from;
                e.clamp();
            },
            'd' => {
                try e.save(a);
                _ = e.delete(from, to);
                e.clamp();
            },
            'c' => {
                try e.save(a);
                _ = e.delete(from, to);
                e.cursor = from;
                e.mode = .insert;
            },
            else => unreachable,
        }
        return .changed;
    }

    fn motion(e: *const Editor, ch: u8, n: u32) ?Target {
        const t = e.text.items;
        var pos = e.cursor;
        switch (ch) {
            'h' => {
                for (0..n) |_| pos = e.prev(pos);
                return .{ .pos = pos };
            },
            'l', ' ' => {
                for (0..n) |_| pos = e.next(pos);
                return .{ .pos = pos };
            },
            '0' => return .{ .pos = 0 },
            '^' => return .{ .pos = e.first_nonblank() },
            '$' => return .{ .pos = t.len },
            'w', 'W' => {
                for (0..n) |_| pos = e.word_fwd(pos, ch == 'W');
                return .{ .pos = pos };
            },
            'b', 'B' => {
                for (0..n) |_| pos = e.word_back(pos, ch == 'B');
                return .{ .pos = pos };
            },
            'e', 'E' => {
                for (0..n) |_| pos = e.prev(e.word_end(pos, ch == 'E'));
                return .{ .pos = pos, .inclusive = true };
            },
            ';', ',' => {
                const kind = e.last_find orelse return null;
                const k: u8 = if (ch == ';') kind else switch (kind) {
                    'f' => 'F',
                    'F' => 'f',
                    't' => 'T',
                    else => 't',
                };
                return e.find(k, e.last_needle[0..e.last_needle_len], n);
            },
            else => return null,
        }
    }

    /// f/F/t/T: the nth needle after (or before) the cursor.
    fn find(e: *const Editor, kind: u8, needle: []const u8, n: u32) ?Target {
        const t = e.text.items;
        var pos = e.cursor;
        for (0..n) |_| {
            pos = switch (kind) {
                'f', 't' => std.mem.indexOfPos(u8, t, e.next(pos), needle),
                else => std.mem.lastIndexOf(u8, t[0..pos], needle),
            } orelse return null;
        }
        return switch (kind) {
            'f' => .{ .pos = pos, .inclusive = true },
            't' => .{ .pos = e.prev(pos), .inclusive = true },
            'F' => .{ .pos = pos },
            else => .{ .pos = e.next(pos) },
        };
    }

    fn insert_at(e: *Editor, a: Allocator, pos: usize) !Outcome {
        try e.save(a);
        e.cursor = @min(pos, e.text.items.len);
        e.mode = .insert;
        return .changed;
    }

    fn replace_char(e: *Editor, a: Allocator, with: []const u8) !Outcome {
        e.reset_command();
        if (e.cursor >= e.text.items.len) return .ignored;
        try e.save(a);
        const end = e.next(e.cursor);
        try e.text.replaceRange(a, e.cursor, end - e.cursor, with);
        e.browsing = null;
        return .changed;
    }

    fn paste(e: *Editor, a: Allocator, after: bool, n: u32) !Outcome {
        if (e.register.items.len == 0) return .ignored;
        try e.save(a);
        var at = if (after) e.next(e.cursor) else e.cursor;
        for (0..n) |_| {
            try e.text.insertSlice(a, at, e.register.items);
            at += e.register.items.len;
        }
        e.cursor = e.prev(at);
        e.browsing = null;
        return .changed;
    }

    fn toggle_case(e: *Editor, a: Allocator, n: u32) !Outcome {
        if (e.text.items.len == 0) return .ignored;
        try e.save(a);
        for (0..n) |_| {
            if (e.cursor >= e.text.items.len) break;
            const b = &e.text.items[e.cursor];
            if (std.ascii.isLower(b.*)) b.* = std.ascii.toUpper(b.*) else if (std.ascii.isUpper(b.*)) b.* = std.ascii.toLower(b.*);
            e.cursor = e.next(e.cursor);
        }
        e.clamp();
        return .changed;
    }

    fn undo_last(e: *Editor, a: Allocator) !Outcome {
        // The newest snapshot is the line as it is now when nothing changed since.
        while (e.undo.items.len > 0) {
            const snap = e.undo.pop().?;
            defer a.free(snap.text);
            if (std.mem.eql(u8, snap.text, e.text.items)) continue;
            try e.set_text(a, snap.text);
            e.cursor = snap.cursor;
            e.clamp();
            return .changed;
        }
        return .ignored;
    }

    fn history_step(e: *Editor, a: Allocator, back: bool) !Outcome {
        const r = if (back) try e.older(a) else try e.newer(a);
        e.clamp();
        return r;
    }

    fn reset_command(e: *Editor) void {
        e.count = 0;
        e.op = null;
        e.op_count = 1;
        e.pending = null;
        e.pending_count = 1;
    }

    /// Keep the cursor on a character in normal mode.
    fn clamp(e: *Editor) void {
        if (e.mode != .normal) return;
        const len = e.text.items.len;
        if (e.cursor >= len) e.cursor = if (len == 0) 0 else e.prev(len);
    }

    fn save(e: *Editor, a: Allocator) !void {
        if (e.undo.items.len > 0 and std.mem.eql(u8, e.undo.items[e.undo.items.len - 1].text, e.text.items)) return;
        const copy = try a.dupe(u8, e.text.items);
        errdefer a.free(copy);
        if (e.undo.items.len == undo_max) a.free(e.undo.orderedRemove(0).text);
        try e.undo.append(a, .{ .text = copy, .cursor = e.cursor });
    }

    fn clear_undo(e: *Editor, a: Allocator) void {
        for (e.undo.items) |s| a.free(s.text);
        e.undo.clearRetainingCapacity();
    }

    // ---- shared ----

    fn move(e: *Editor, to: usize) Outcome {
        if (to == e.cursor) return .ignored;
        e.cursor = to;
        return .changed;
    }

    fn delete(e: *Editor, from: usize, to: usize) Outcome {
        if (from >= to) return .ignored;
        const items = e.text.items;
        std.mem.copyForwards(u8, items[from..], items[to..]);
        e.text.shrinkRetainingCapacity(items.len - (to - from));
        e.cursor = from;
        e.browsing = null;
        return .changed;
    }

    /// The start of the UTF-8 sequence before i.
    fn prev(e: *const Editor, i: usize) usize {
        var j = i;
        while (j > 0) {
            j -= 1;
            if ((e.text.items[j] & 0xc0) != 0x80) break;
        }
        return j;
    }

    /// The start of the UTF-8 sequence after the one at i.
    fn next(e: *const Editor, i: usize) usize {
        const t = e.text.items;
        if (i >= t.len) return t.len;
        var j = i + 1;
        while (j < t.len and (t[j] & 0xc0) == 0x80) j += 1;
        return j;
    }

    fn first_nonblank(e: *const Editor) usize {
        const t = e.text.items;
        var j: usize = 0;
        while (j < t.len and class(t[j], false) == 0) j += 1;
        return j;
    }

    /// w: past this word (or run of punctuation), then past blanks.
    fn word_fwd(e: *const Editor, i: usize, big: bool) usize {
        const t = e.text.items;
        if (i >= t.len) return t.len;
        var j = i;
        const k = class(t[j], big);
        if (k != 0) while (j < t.len and class(t[j], big) == k) {
            j += 1;
        };
        while (j < t.len and class(t[j], big) == 0) j += 1;
        return j;
    }

    /// b: back past blanks, then to the start of the word there.
    fn word_back(e: *const Editor, i: usize, big: bool) usize {
        const t = e.text.items;
        var j = i;
        while (j > 0 and class(t[j - 1], big) == 0) j -= 1;
        if (j == 0) return 0;
        const k = class(t[j - 1], big);
        while (j > 0 and class(t[j - 1], big) == k) j -= 1;
        return j;
    }

    /// e: the end (exclusive) of the next word to end after i.
    fn word_end(e: *const Editor, i: usize, big: bool) usize {
        const t = e.text.items;
        var j = e.next(i);
        while (j < t.len and class(t[j], big) == 0) j += 1;
        if (j >= t.len) return t.len;
        const k = class(t[j], big);
        while (j < t.len and class(t[j], big) == k) j += 1;
        return j;
    }

    fn set_text(e: *Editor, a: Allocator, s: []const u8) !void {
        e.text.clearRetainingCapacity();
        try e.text.appendSlice(a, s);
        e.cursor = e.text.items.len;
    }

    fn older(e: *Editor, a: Allocator) !Outcome {
        const h = e.histories.getPtr(e.label) orelse return .ignored;
        const i = if (e.browsing) |b| (if (b == 0) return .ignored else b - 1) else blk: {
            if (h.items.len == 0) return .ignored;
            e.draft.clearRetainingCapacity();
            try e.draft.appendSlice(a, e.text.items);
            break :blk h.items.len - 1;
        };
        try e.set_text(a, h.items[i]);
        e.browsing = i;
        return .changed;
    }

    fn newer(e: *Editor, a: Allocator) !Outcome {
        const b = e.browsing orelse return .ignored;
        const h = e.histories.getPtr(e.label) orelse return .ignored;
        if (b + 1 < h.items.len) {
            try e.set_text(a, h.items[b + 1]);
            e.browsing = b + 1;
        } else {
            try e.set_text(a, e.draft.items);
            e.browsing = null;
        }
        return .changed;
    }

    fn remember(e: *Editor, a: Allocator) !void {
        const line = e.text.items;
        if (line.len == 0) return;
        const gop = try e.histories.getOrPut(a, e.label);
        if (!gop.found_existing) {
            gop.key_ptr.* = a.dupe(u8, e.label) catch |err| {
                _ = e.histories.remove(e.label);
                return err;
            };
            gop.value_ptr.* = .empty;
        }
        const h = gop.value_ptr;
        if (h.items.len > 0 and std.mem.eql(u8, h.items[h.items.len - 1], line)) return;
        try h.ensureUnusedCapacity(a, 1);
        const copy = try a.dupe(u8, line);
        if (h.items.len == history_max) a.free(h.orderedRemove(0));
        h.appendAssumeCapacity(copy);
    }
};

fn printable(text: []const u8) bool {
    return text.len > 0 and text[0] >= 0x20 and text[0] != 0x7f;
}

/// 0 blank, 1 word, 2 punctuation; WORD motions (big) only tell blanks apart.
/// Bytes past ASCII count as word characters, so a UTF-8 sequence stays whole.
fn class(b: u8, big: bool) u2 {
    if (b == ' ' or b == '\t') return 0;
    if (big or b >= 0x80 or std.ascii.isAlphanumeric(b) or b == '_') return 1;
    return 2;
}

// ---- tests ----

const testing = std.testing;

fn typed(e: *Editor, s: []const u8) !void {
    for (s) |ch| _ = try e.key(testing.allocator, ch, 0, &.{ch});
}

fn esc(e: *Editor) !Outcome {
    return e.key(testing.allocator, XK.Escape, 0, "\x1b");
}

test "editing" {
    const a = testing.allocator;
    var e: Editor = .{};
    defer e.deinit(a);
    try e.open(a, "lua: ", "");
    _ = try e.key(a, 'h', 0, "h");
    _ = try e.key(a, 0xe9, 0, "é");
    _ = try e.key(a, 'y', 0, "y");
    try testing.expectEqualStrings("héy", e.text.items);
    _ = try e.key(a, XK.Left, 0, "");
    _ = try e.key(a, XK.BackSpace, 0, ""); // the whole é, both bytes
    try testing.expectEqualStrings("hy", e.text.items);
    _ = try e.key(a, 'w', types.mod.ctrl, "\x17");
    try testing.expectEqualStrings("y", e.text.items);
    try testing.expect(try e.key(a, XK.Return, 0, "\r") == .submit);
    try testing.expectEqualStrings("y", e.finish(a));

    try e.open(a, "lua: ", "");
    _ = try e.key(a, 'x', 0, "x");
    _ = try e.key(a, XK.Up, 0, "");
    try testing.expectEqualStrings("y", e.text.items);
    _ = try e.key(a, XK.Down, 0, "");
    try testing.expectEqualStrings("x", e.text.items);
    try testing.expect(try e.key(a, 'g', types.mod.ctrl, "\x07") == .cancel);
    try testing.expect(try esc(&e) == .cancel); // emacs keys: Escape cancels
}

test "history per label, capped, no repeats" {
    const a = testing.allocator;
    var e: Editor = .{};
    defer e.deinit(a);
    for (0..history_max + 5) |i| {
        var buf: [8]u8 = undefined;
        try e.open(a, "run: ", try std.fmt.bufPrint(&buf, "{d}", .{i}));
        _ = e.finish(a);
        _ = e.finish(a); // a repeat isn't stored twice
    }
    try testing.expectEqual(@as(usize, history_max), e.histories.getPtr("run: ").?.items.len);
    try e.open(a, "lua: ", "");
    try testing.expect(try e.key(a, XK.Up, 0, "") == .ignored);
}

test "vi: modes, motions, operators" {
    const a = testing.allocator;
    var e: Editor = .{ .keys = .vi };
    defer e.deinit(a);
    try e.open(a, "lua: ", "");
    try typed(&e, "wm.focus(3) -- go");
    try testing.expect(try esc(&e) == .changed);
    try testing.expectEqual(Mode.normal, e.mode);
    try testing.expectEqual(e.text.items.len - 1, e.cursor); // stepped back onto the 'o'

    try typed(&e, "0");
    try testing.expectEqual(@as(usize, 0), e.cursor);
    try typed(&e, "w");
    try testing.expectEqual(@as(usize, 2), e.cursor); // "wm" | "." punctuation
    try typed(&e, "2w");
    try testing.expectEqual(@as(usize, 8), e.cursor); // "." "focus" -> "("
    try typed(&e, "$");
    try testing.expectEqual(e.text.items.len - 1, e.cursor);
    try typed(&e, "b");
    try testing.expectEqual(@as(usize, 15), e.cursor); // "go"

    try typed(&e, "0f(");
    try testing.expectEqual(@as(usize, 8), e.cursor);
    try typed(&e, "ldt)");
    try testing.expectEqualStrings("wm.focus() -- go", e.text.items);
    try typed(&e, "P");
    try testing.expectEqualStrings("wm.focus(3) -- go", e.text.items);

    try typed(&e, "0cwxx");
    try testing.expectEqual(Mode.insert, e.mode);
    try testing.expectEqualStrings("xx.focus(3) -- go", e.text.items);
    _ = try esc(&e);
    try typed(&e, "u");
    try testing.expectEqualStrings("wm.focus(3) -- go", e.text.items);

    try typed(&e, "$F-D");
    try testing.expectEqualStrings("wm.focus(3) -", e.text.items);
    try typed(&e, "Xx");
    try testing.expectEqualStrings("wm.focus(3)", e.text.items);
    try typed(&e, "0de");
    try testing.expectEqualStrings(".focus(3)", e.text.items);
    try typed(&e, "x~");
    try testing.expectEqualStrings("Focus(3)", e.text.items);
    try typed(&e, "A!");
    try testing.expectEqualStrings("Focus(3)!", e.text.items);
    _ = try esc(&e);
    try typed(&e, "dd");
    try testing.expectEqualStrings("", e.text.items);
    try typed(&e, "uu");
    try testing.expectEqualStrings("Focus(3)", e.text.items);
    try typed(&e, "$r#");
    try testing.expectEqualStrings("Focus(3#", e.text.items);

    try testing.expect(try e.key(a, XK.Return, 0, "\r") == .submit);
    try testing.expect(try esc(&e) == .cancel); // Escape from normal mode cancels
}

test "vi: counts, ; and cc" {
    const a = testing.allocator;
    var e: Editor = .{ .keys = .vi };
    defer e.deinit(a);
    try e.open(a, "run: ", "a,b,c,d");
    _ = try esc(&e);
    try typed(&e, "0f,;");
    try testing.expectEqual(@as(usize, 3), e.cursor);
    try typed(&e, ",");
    try testing.expectEqual(@as(usize, 1), e.cursor);
    try typed(&e, "02x");
    try testing.expectEqualStrings("b,c,d", e.text.items);
    try typed(&e, "d2f,");
    try testing.expectEqualStrings("d", e.text.items);
    try typed(&e, "ccnew");
    try testing.expectEqualStrings("new", e.text.items);
    try testing.expectEqual(Mode.insert, e.mode);
}
