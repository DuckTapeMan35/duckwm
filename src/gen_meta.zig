const std = @import("std");
const api = @import("api_docs.zig");

pub fn main(init: std.process.Init) !void {
    @setEvalBranchQuota(100000);
    const a = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(a);
    if (args.len != 4) return error.Usage;
    const lua_path, const md_path, const norg_path = .{ args[1], args[2], args[3] };
    const cwd = std.Io.Dir.cwd();

    // LuaLS meta
    {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        defer buf.deinit(a);
        try buf.appendSlice(a, "---@meta\nwm = {}\n\n");
        inline for (api.constants) |con| {
            try buf.print(a, "--- {s}\n---@type integer\nwm.{s} = 0\n\n", .{ con.desc, con.name });
        }
        inline for (api.entries) |entry| {
            try doc_comment(a, &buf, entry.desc);
            inline for (entry.params) |p| {
                try buf.print(a, "---@param {s} {s}\n", .{ p.name, p.typ });
            }
            if (!std.mem.eql(u8, entry.ret, "nil")) {
                try buf.print(a, "---@return {s}\n", .{entry.ret});
            }
            try buf.print(a, "function wm.{s}(", .{entry.name});
            inline for (entry.params, 0..) |p, i| {
                if (i > 0) try buf.appendSlice(a, ", ");
                try buf.appendSlice(a, p.name);
            }
            try buf.appendSlice(a, ") end\n\n");
        }
        try cwd.writeFile(io, .{ .sub_path = lua_path, .data = buf.items });
    }

    // Markdown
    {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        defer buf.deinit(a);
        try buf.appendSlice(a, "# duckwm Lua API\n\n");

        try buf.appendSlice(a, "## Contents\n\n");
        try buf.appendSlice(a, "- [Constants](#constants)\n");
        inline for (api.categories) |cat| {
            var anchor: [128]u8 = undefined;
            var ai: usize = 0;
            for (cat) |ch| {
                anchor[ai] = if (ch == ' ' or ch == '&') '-' else std.ascii.toLower(ch);
                ai += 1;
            }
            try buf.print(a, "- [{s}](#{s})\n", .{ cat, anchor[0..ai] });
        }
        try buf.appendSlice(a, "\n");

        try buf.appendSlice(a, "## Constants\n\n");
        inline for (api.constants) |con| {
            try buf.print(a, "- **`wm.{s}`** — {s}\n", .{ con.name, con.desc });
        }
        try buf.appendSlice(a, "\n");

        inline for (api.categories) |cat| {
            try buf.print(a, "## {s}\n\n", .{cat});
            inline for (api.entries) |entry| {
                if (comptime !std.mem.eql(u8, entry.category, cat)) continue;
                var sig: std.ArrayListUnmanaged(u8) = .empty;
                defer sig.deinit(a);
                inline for (entry.params, 0..) |p, i| {
                    if (i > 0) try sig.appendSlice(a, ", ");
                    try sig.print(a, "{s}: {s}", .{ p.name, p.typ });
                }
                try buf.print(a, "### `wm.{s}({s})`\n\n{s}\n\n", .{ entry.name, sig.items, entry.desc });
                if (entry.params.len > 0) {
                    inline for (entry.params) |p| {
                        try buf.print(a, "- **{s}** `{s}`\n", .{ p.name, p.typ });
                    }
                    try buf.appendSlice(a, "\n");
                }
                if (!std.mem.eql(u8, entry.ret, "nil")) {
                    try buf.print(a, "**Returns:** `{s}`\n\n", .{entry.ret});
                }
            }
        }
        try cwd.writeFile(io, .{ .sub_path = md_path, .data = buf.items });
    }

    // Norg
    {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        defer buf.deinit(a);
        try buf.appendSlice(a,
            \\@document.meta
            \\title: duckwm Lua API
            \\categories: api reference
            \\@end
            \\
            \\* Contents
            \\
        );
        try buf.appendSlice(a, "  - {* Constants}\n");
        inline for (api.categories) |cat| {
            try buf.print(a, "  - {{* {s}}}\n", .{cat});
        }
        try buf.appendSlice(a, "\n");

        try buf.appendSlice(a, "* Constants\n\n");
        inline for (api.constants) |con| {
            try buf.print(a, "  - `wm.{s}` — {s}\n", .{ con.name, con.desc });
        }
        try buf.appendSlice(a, "\n");

        inline for (api.categories) |cat| {
            try buf.print(a, "* {s}\n\n", .{cat});
            inline for (api.entries) |entry| {
                if (comptime !std.mem.eql(u8, entry.category, cat)) continue;
                var sig: std.ArrayListUnmanaged(u8) = .empty;
                defer sig.deinit(a);
                inline for (entry.params, 0..) |p, i| {
                    if (i > 0) try sig.appendSlice(a, ", ");
                    try sig.print(a, "{s}: {s}", .{ p.name, p.typ });
                }
                try buf.print(a, "** `wm.{s}({s})`\n", .{ entry.name, sig.items });
                var lines = std.mem.splitScalar(u8, entry.desc, '\n');
                while (lines.next()) |line| {
                    const trimmed = std.mem.trim(u8, line, " \t");
                    if (trimmed.len == 0) {
                        try buf.appendSlice(a, "\n");
                    } else {
                        try buf.print(a, "   {s}\n", .{trimmed});
                    }
                }
                if (entry.params.len > 0) {
                    try buf.appendSlice(a, "\n");
                    inline for (entry.params) |p| {
                        try buf.print(a, "   - *{s}* `{s}`\n", .{ p.name, p.typ });
                    }
                }
                if (!std.mem.eql(u8, entry.ret, "nil")) {
                    try buf.print(a, "   - *Returns:* `{s}`\n", .{entry.ret});
                }
                try buf.appendSlice(a, "\n");
            }
        }
        try cwd.writeFile(io, .{ .sub_path = norg_path, .data = buf.items });
    }
}

/// A description as LuaLS doc comments: every line prefixed, blank lines
/// kept as bare "---" so paragraphs and code blocks survive.
fn doc_comment(a: std.mem.Allocator, buf: *std.ArrayListUnmanaged(u8), text: []const u8) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const l = std.mem.trimEnd(u8, line, " \t\r");
        if (l.len == 0) {
            try buf.appendSlice(a, "---\n");
        } else {
            try buf.print(a, "--- {s}\n", .{l});
        }
    }
}
