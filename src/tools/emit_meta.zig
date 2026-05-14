const std = @import("std");
const api = @import("api");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const argv = std.posix.argv;
    if (argv.len < 3) {
        std.debug.print("usage: emit_meta <wm.lua output> <API.md output>\n", .{});
        return error.BadArgs;
    }

    const lua_path: []const u8 = std.mem.span(argv[1]);
    const md_path:  []const u8 = std.mem.span(argv[2]);

    try emit_lua(lua_path);
    try emit_md(allocator, md_path);
}

fn emit_lua(path: []const u8) !void {
    const file = try std.fs.createFileAbsolute(path, .{});
    defer file.close();
    const w = file.writer();

    try w.writeAll(
        \\-- Auto-generated LuaLS meta for duckwm wm API
        \\-- Do not edit; regenerate with `zig build meta`
        \\
        \\---@meta
        \\
        \\---The duckwm window manager API.
        \\wm = {}
        \\
        \\
    );

    inline for (api.constants) |con| {
        try w.print("--- {s}\n---@type integer\nwm.{s} = 0\n\n", .{ con.desc, con.name });
    }

    inline for (api.entries) |entry| {
        try w.print("--- {s}\n", .{entry.desc});
        inline for (entry.params) |p| {
            try w.print("---@param {s} {s}\n", .{ p.name, p.typ });
        }
        if (!std.mem.eql(u8, entry.ret, "nil")) {
            try w.print("---@return {s}\n", .{entry.ret});
        }
        try w.writeAll("function wm.");
        try w.writeAll(entry.name);
        try w.writeAll("(");
        inline for (entry.params, 0..) |p, i| {
            if (i > 0) try w.writeAll(", ");
            try w.writeAll(p.name);
        }
        try w.writeAll(") end\n\n");
    }
}

fn emit_md(allocator: std.mem.Allocator, path: []const u8) !void {
    const file = try std.fs.createFileAbsolute(path, .{});
    defer file.close();
    const w = file.writer();

    try w.writeAll("# duckwm Lua API\n\n## Constants\n\n");
    inline for (api.constants) |con| {
        try w.print("- **`wm.{s}`** — {s}\n", .{ con.name, con.desc });
    }
    try w.writeAll("\n## Functions\n\n");
    inline for (api.entries) |entry| {
        var sig = std.ArrayList(u8).init(allocator);
        defer sig.deinit();
        inline for (entry.params, 0..) |p, i| {
            if (i > 0) try sig.appendSlice(", ");
            try sig.writer().print("{s}: {s}", .{ p.name, p.typ });
        }
        try w.print("### `wm.{s}({s})`\n\n{s}\n\n", .{ entry.name, sig.items, entry.desc });
        if (!std.mem.eql(u8, entry.ret, "nil")) {
            try w.print("**Returns:** `{s}`\n\n", .{entry.ret});
        }
    }
}
