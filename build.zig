const std = @import("std");
const api = @import("src/api_docs.zig");
const Scanner = @import("wayland").Scanner;
const protogen = @import("src/protogen.zig");

const MetaStep = struct {
    step: std.Build.Step,
    b: *std.Build,

    pub fn create(b: *std.Build) *MetaStep {
        const self = b.allocator.create(MetaStep) catch unreachable;
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "generate meta",
                .owner = b,
                .makeFn = make,
            }),
            .b = b,
        };
        return self;
    }

    /// A description as LuaLS doc comments: every line prefixed, blank lines
    /// kept as bare "---" so paragraphs and code blocks survive.
    fn doc_comment(b: *std.Build, buf: *std.ArrayListUnmanaged(u8), text: []const u8) !void {
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            const l = std.mem.trimEnd(u8, line, " \t\r");
            if (l.len == 0) {
                try buf.appendSlice(b.allocator, "---\n");
            } else {
                try buf.print(b.allocator, "--- {s}\n", .{l});
            }
        }
    }

    fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
        @setEvalBranchQuota(100000);
        const self: *MetaStep = @fieldParentPtr("step", step);
        const b = self.b;
        const io = b.graph.io;
        const root = b.build_root.handle;

        root.createDirPath(io, "meta") catch |e| if (e != error.PathAlreadyExists) return e;

        // LuaLS meta
        {
            var buf: std.ArrayListUnmanaged(u8) = .empty;
            defer buf.deinit(b.allocator);
            try buf.appendSlice(b.allocator, "---@meta\nwm = {}\n\n");
            inline for (api.constants) |con| {
                try buf.print(b.allocator, "--- {s}\n---@type integer\nwm.{s} = 0\n\n", .{ con.desc, con.name });
            }
            inline for (api.entries) |entry| {
                try doc_comment(b, &buf, entry.desc);
                inline for (entry.params) |p| {
                    try buf.print(b.allocator, "---@param {s} {s}\n", .{ p.name, p.typ });
                }
                if (!std.mem.eql(u8, entry.ret, "nil")) {
                    try buf.print(b.allocator, "---@return {s}\n", .{entry.ret});
                }
                try buf.print(b.allocator, "function wm.{s}(", .{entry.name});
                inline for (entry.params, 0..) |p, i| {
                    if (i > 0) try buf.appendSlice(b.allocator, ", ");
                    try buf.appendSlice(b.allocator, p.name);
                }
                try buf.appendSlice(b.allocator, ") end\n\n");
            }
            try root.writeFile(io, .{ .sub_path = "meta/wm.lua", .data = buf.items });
        }

        // Markdown
        {
            var buf: std.ArrayListUnmanaged(u8) = .empty;
            defer buf.deinit(b.allocator);
            try buf.appendSlice(b.allocator, "# duckwm Lua API\n\n");

            try buf.appendSlice(b.allocator, "## Contents\n\n");
            try buf.appendSlice(b.allocator, "- [Constants](#constants)\n");
            inline for (api.categories) |cat| {
                var anchor: [128]u8 = undefined;
                var ai: usize = 0;
                for (cat) |ch| {
                    anchor[ai] = if (ch == ' ' or ch == '&') '-' else std.ascii.toLower(ch);
                    ai += 1;
                }
                try buf.print(b.allocator, "- [{s}](#{s})\n", .{ cat, anchor[0..ai] });
            }
            try buf.appendSlice(b.allocator, "\n");

            try buf.appendSlice(b.allocator, "## Constants\n\n");
            inline for (api.constants) |con| {
                try buf.print(b.allocator, "- **`wm.{s}`** — {s}\n", .{ con.name, con.desc });
            }
            try buf.appendSlice(b.allocator, "\n");

            inline for (api.categories) |cat| {
                try buf.print(b.allocator, "## {s}\n\n", .{cat});
                inline for (api.entries) |entry| {
                    if (comptime !std.mem.eql(u8, entry.category, cat)) continue;
                    var sig: std.ArrayListUnmanaged(u8) = .empty;
                    defer sig.deinit(b.allocator);
                    inline for (entry.params, 0..) |p, i| {
                        if (i > 0) try sig.appendSlice(b.allocator, ", ");
                        try sig.print(b.allocator, "{s}: {s}", .{ p.name, p.typ });
                    }
                    try buf.print(b.allocator, "### `wm.{s}({s})`\n\n{s}\n\n", .{ entry.name, sig.items, entry.desc });
                    if (entry.params.len > 0) {
                        inline for (entry.params) |p| {
                            try buf.print(b.allocator, "- **{s}** `{s}`\n", .{ p.name, p.typ });
                        }
                        try buf.appendSlice(b.allocator, "\n");
                    }
                    if (!std.mem.eql(u8, entry.ret, "nil")) {
                        try buf.print(b.allocator, "**Returns:** `{s}`\n\n", .{entry.ret});
                    }
                }
            }
            try root.writeFile(io, .{ .sub_path = "API.md", .data = buf.items });
        }

        // Norg
        {
            var buf: std.ArrayListUnmanaged(u8) = .empty;
            defer buf.deinit(b.allocator);
            try buf.appendSlice(b.allocator,
                \\@document.meta
                \\title: duckwm Lua API
                \\categories: api reference
                \\@end
                \\
                \\* Contents
                \\
            );
            try buf.appendSlice(b.allocator, "  - {* Constants}\n");
            inline for (api.categories) |cat| {
                try buf.print(b.allocator, "  - {{* {s}}}\n", .{cat});
            }
            try buf.appendSlice(b.allocator, "\n");

            try buf.appendSlice(b.allocator, "* Constants\n\n");
            inline for (api.constants) |con| {
                try buf.print(b.allocator, "  - `wm.{s}` — {s}\n", .{ con.name, con.desc });
            }
            try buf.appendSlice(b.allocator, "\n");

            inline for (api.categories) |cat| {
                try buf.print(b.allocator, "* {s}\n\n", .{cat});
                inline for (api.entries) |entry| {
                    if (comptime !std.mem.eql(u8, entry.category, cat)) continue;
                    var sig: std.ArrayListUnmanaged(u8) = .empty;
                    defer sig.deinit(b.allocator);
                    inline for (entry.params, 0..) |p, i| {
                        if (i > 0) try sig.appendSlice(b.allocator, ", ");
                        try sig.print(b.allocator, "{s}: {s}", .{ p.name, p.typ });
                    }
                    try buf.print(b.allocator, "** `wm.{s}({s})`\n", .{ entry.name, sig.items });
                    var lines = std.mem.splitScalar(u8, entry.desc, '\n');
                    while (lines.next()) |line| {
                        const trimmed = std.mem.trim(u8, line, " \t");
                        if (trimmed.len == 0) {
                            try buf.appendSlice(b.allocator, "\n");
                        } else {
                            try buf.print(b.allocator, "   {s}\n", .{trimmed});
                        }
                    }
                    if (entry.params.len > 0) {
                        try buf.appendSlice(b.allocator, "\n");
                        inline for (entry.params) |p| {
                            try buf.print(b.allocator, "   - *{s}* `{s}`\n", .{ p.name, p.typ });
                        }
                    }
                    if (!std.mem.eql(u8, entry.ret, "nil")) {
                        try buf.print(b.allocator, "   - *Returns:* `{s}`\n", .{entry.ret});
                    }
                    try buf.appendSlice(b.allocator, "\n");
                }
            }
            try root.writeFile(io, .{ .sub_path = "API.norg", .data = buf.items });
        }
    }
};

const ProtoStep = struct {
    step: std.Build.Step,

    const out_path = "proto/duckwm.proto";

    fn create(b: *std.Build) *ProtoStep {
        const self = b.allocator.create(ProtoStep) catch @panic("OOM");
        self.* = .{ .step = .init(.{
            .id = .custom,
            .name = "generate " ++ out_path,
            .owner = b,
            .makeFn = make,
        }) };
        return self;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
        _ = options;
        const b = step.owner;
        const io = b.graph.io;

        // The build allocator is an arena: no need to free the text.
        const text = try protogen.generate(b.allocator);

        const path = b.pathFromRoot(out_path);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = text });
    }
};

const Platform = enum { x11, river };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const platform = b.option(Platform, "platform", "Display server backend (default: x11)") orelse .x11;

    // ---- C headers ----
    // Xlib, Xcursor, Xft: only the x11 backend sees these.
    const xlib_tc = b.addTranslateC(.{
        .root_source_file = b.path("src/x11/xlib.h"),
        .target = target,
        .optimize = optimize,
    });
    xlib_tc.linkSystemLibrary("xft", .{ .use_pkg_config = .force });
    xlib_tc.linkSystemLibrary("fontconfig", .{ .use_pkg_config = .force });
    xlib_tc.linkSystemLibrary("xrandr", .{ .use_pkg_config = .force });

    // Plain libc (fork/exec, getenv/setenv, /proc reading) for core and config.
    const libc_tc = b.addTranslateC(.{
        .root_source_file = b.path("src/libc.h"),
        .target = target,
        .optimize = optimize,
    });
    const libc_mod = libc_tc.createModule();

    // ---- Modules ----
    const ziglua = b.dependency("ziglua", .{
        .target = target,
        .optimize = optimize,
    });
    const zlua = ziglua.module("zlua");

    const types_mod = b.createModule(.{
        .root_source_file = b.path("src/types.zig"),
        .target = target,
    });

    const solver_mod = b.addModule("solver", .{
        .root_source_file = b.path("src/solver.zig"),
        .target = target,
    });

    const graph_mod = b.addModule("graph", .{
        .root_source_file = b.path("src/graph.zig"),
        .target = target,
    });
    graph_mod.addImport("solver", solver_mod);
    graph_mod.addImport("types", types_mod);

    // The X11 backend: the only module that links X and sees Xlib.
    const x11_mod = b.createModule(.{
        .root_source_file = b.path("src/x11.zig"),
        .target = target,
        .link_libc = true,
    });
    x11_mod.addImport("xlib", xlib_tc.createModule());
    x11_mod.addImport("types", types_mod);
    x11_mod.linkSystemLibrary("X11", .{});
    x11_mod.linkSystemLibrary("Xcursor", .{});
    x11_mod.linkSystemLibrary("Xrandr", .{});

    const platform_mod = switch (platform) {
        .x11 => x11_mod,
        .river => blk: {
            const scanner = Scanner.create(b, .{});
            scanner.addCustomProtocol(b.path("protocol/river-window-management-v1.xml"));
            scanner.addCustomProtocol(b.path("protocol/river-xkb-bindings-v1.xml"));
            scanner.addCustomProtocol(b.path("protocol/river-layer-shell-v1.xml"));
            scanner.addCustomProtocol(b.path("protocol/river-input-management-v1.xml"));
            scanner.addCustomProtocol(b.path("protocol/river-xkb-config-v1.xml"));
            scanner.generate("river_window_manager_v1", 4);
            scanner.generate("river_xkb_bindings_v1", 1);
            scanner.generate("river_layer_shell_v1", 1);
            scanner.generate("wl_compositor", 4);
            scanner.generate("wl_shm", 1);
            scanner.generate("river_xkb_config_v1", 1);
            scanner.generate("river_input_manager_v1", 1);
            scanner.generate("wl_seat", 5);

            const rc_tc = b.addTranslateC(.{
                .root_source_file = b.path("src/river/c.h"),
                .target = target,
                .optimize = optimize,
            });
            rc_tc.linkSystemLibrary("fcft", .{ .use_pkg_config = .force });
            rc_tc.linkSystemLibrary("pixman-1", .{ .use_pkg_config = .force });

            const wayland_mod = b.createModule(.{ .root_source_file = scanner.result });

            const xkbcommon = b.dependency("xkbcommon", .{}).module("xkbcommon");

            const river_mod = b.createModule(.{
                .root_source_file = b.path("src/river.zig"),
                .target = target,
                .link_libc = true,
            });
            river_mod.addImport("types", types_mod);
            river_mod.addImport("wayland", wayland_mod);
            river_mod.addImport("xkbcommon", xkbcommon);
            river_mod.linkSystemLibrary("xkbcommon", .{});
            river_mod.linkSystemLibrary("wayland-client", .{});
            river_mod.addImport("rc", rc_tc.createModule());
            river_mod.linkSystemLibrary("fcft", .{});
            river_mod.linkSystemLibrary("pixman-1", .{});
            break :blk river_mod;
        },
    };

    const protocol_mod = b.addModule("protocol", .{
        .root_source_file = b.path("src/protocol.zig"),
        .target = target,
    });

    const wm_mod = b.addModule("wm", .{
        .root_source_file = b.path("src/wm.zig"),
        .target = target,
    });
    wm_mod.addImport("graph", graph_mod);
    wm_mod.addImport("types", types_mod);
    wm_mod.addImport("platform", platform_mod);
    wm_mod.addImport("libc", libc_mod);
    wm_mod.addImport("ziglua", zlua);
    wm_mod.addImport("protocol", protocol_mod);

    const api_mod = b.addModule("api", .{
        .root_source_file = b.path("src/api_docs.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });

    const lua_mod = b.addModule("lua", .{
        .root_source_file = b.path("src/lua.zig"),
        .target = target,
    });
    lua_mod.addImport("ziglua", zlua);
    lua_mod.addImport("wm", wm_mod);
    lua_mod.addImport("graph", graph_mod);
    lua_mod.addImport("types", types_mod);
    lua_mod.addImport("api_docs", api_mod);
    lua_mod.addImport("libc", libc_mod);
    lua_mod.addImport("protocol", protocol_mod);

    const mod = b.addModule("duckwm", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });
    mod.addImport("graph", graph_mod);
    mod.addImport("wm", wm_mod);
    mod.addImport("config", lua_mod);

    // ---- duckwm ----
    const exe = b.addExecutable(.{
        .name = "duckwm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "duckwm", .module = mod },
                .{ .name = "graph", .module = graph_mod },
                .{ .name = "wm", .module = wm_mod },
                .{ .name = "types", .module = types_mod },
                .{ .name = "config", .module = lua_mod },
                .{ .name = "ziglua", .module = zlua },
            },
        }),
    });
    exe.use_llvm = true;
    exe.use_lld = true;
    b.installArtifact(exe);

    // ---- quack (IPC client) ----
    const quack = b.addExecutable(.{
        .name = "quack",
        .root_module = b.createModule(.{
            .root_source_file = b.path("quack/src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    quack.root_module.addImport("protocol", protocol_mod);
    b.installArtifact(quack);

    // ---- Steps ----
    const sysconfdir = b.option(
        []const u8,
        "sysconfdir",
        "Where install-config puts duckwm/config.lua, relative to the prefix (default: ../etc, so /etc for --prefix /usr)",
    ) orelse "../etc";
    const install_config = b.addInstallFile(
        b.path("config/default.lua"),
        b.fmt("{s}/duckwm/config.lua", .{sysconfdir}),
    );
    const install_step = b.step("install-config", "Install default config to etc/duckwm/");
    install_step.dependOn(&install_config.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run duckwm");
    run_step.dependOn(&run_cmd.step);

    const meta_gen = MetaStep.create(b);
    // Everything zig build install puts under the prefix besides the binaries
    // and the protocol: the X session, the LuaLS config, docs, and the
    // generated stubs and API reference (generated first).
    for ([_][2][]const u8{
        .{ "dist/duckwm.desktop", "share/xsessions/duckwm.desktop" },
        .{ "dist/luarc.json", "share/duckwm/luarc.json" },
        .{ "README.md", "share/doc/duckwm/README.md" },
    }) |f| b.getInstallStep().dependOn(&b.addInstallFile(b.path(f[0]), f[1]).step);

    for ([_][2][]const u8{
        .{ "meta/wm.lua", "share/duckwm/meta/wm.lua" },
        .{ "API.md", "share/doc/duckwm/API.md" },
        .{ "API.norg", "share/doc/duckwm/API.norg" },
    }) |f| {
        const s = b.addInstallFile(b.path(f[0]), f[1]);
        s.step.dependOn(&meta_gen.step);
        b.getInstallStep().dependOn(&s.step);
    }
    const meta_step = b.step("meta", "Regenerate LuaLS meta and API docs");
    meta_step.dependOn(&meta_gen.step);
    const proto_step = b.step("proto", "Regenerate proto/duckwm.proto from src/protocol.zig");
    proto_step.dependOn(&ProtoStep.create(b).step);
    b.getInstallStep().dependOn(&b.addInstallFile(b.path("proto/duckwm.proto"), "share/duckwm/duckwm.proto").step);

    // Type-checks every backend hook, including ones nothing calls yet.
    const x11_check = b.addTest(.{ .root_module = x11_mod });
    x11_check.use_llvm = true;
    x11_check.use_lld = true;
    const check_step = b.step("check", "Type-check every x11 backend hook");
    check_step.dependOn(&x11_check.step);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(mod_tests).step);
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);
    const protocol_tests = b.addTest(.{ .root_module = protocol_mod });
    test_step.dependOn(&b.addRunArtifact(protocol_tests).step);
}
