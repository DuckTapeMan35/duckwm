const std = @import("std");
const Scanner = @import("wayland").Scanner;

const Platform = enum { x11, river };

const AllocatorKind = enum { debug, smp, c };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const platform = b.option(Platform, "platform", "Display server backend (default: x11)") orelse .x11;
    const allocator = b.option(
        AllocatorKind,
        "allocator",
        "Memory allocator: debug (leak and misuse checks; default in Debug builds), smp (fast; default in release builds) or c (libc malloc)",
    ) orelse if (optimize == .debug) AllocatorKind.debug else AllocatorKind.smp;
    const build_options = b.addOptions();
    build_options.addOption(AllocatorKind, "allocator", allocator);

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
    exe.root_module.addOptions("build_options", build_options);
    exe.use_llvm = true;
    exe.use_lld = true;
    b.installArtifact(exe);

    // ---- the client library: duckwm_client for Zig ----
    const client_mod = b.addModule("duckwm_client", .{
        .root_source_file = b.path("src/client.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    client_mod.addImport("protocol", protocol_mod);

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
    quack.root_module.addImport("duckwm_client", client_mod);
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
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Run duckwm");
    run_step.dependOn(&run_cmd.step);

    // The LuaLS stubs and the API reference, generated from src/api_docs.zig
    // by a small program built for this machine.
    const gen_meta = b.addExecutable(.{
        .name = "gen_meta",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/gen_meta.zig"),
            .target = b.graph.host,
        }),
    });
    const run_meta = b.addRunArtifact(gen_meta);
    const meta_lua = run_meta.addOutputFileArg("wm.lua");
    const api_md = run_meta.addOutputFileArg("API.md");
    const api_norg = run_meta.addOutputFileArg("API.norg");

    // Everything zig build install puts under the prefix besides the binaries
    // and the protocol: the X session, the LuaLS config, docs, and the
    // generated stubs and API reference.
    for ([_][2][]const u8{
        .{ "dist/duckwm.desktop", "share/xsessions/duckwm.desktop" },
        .{ "dist/luarc.json", "share/duckwm/luarc.json" },
        .{ "README.md", "share/doc/duckwm/README.md" },
    }) |f| b.getInstallStep().dependOn(&b.addInstallFile(b.path(f[0]), f[1]).step);
    b.getInstallStep().dependOn(&b.addInstallFile(meta_lua, "share/duckwm/meta/wm.lua").step);
    b.getInstallStep().dependOn(&b.addInstallFile(api_md, "share/doc/duckwm/API.md").step);
    b.getInstallStep().dependOn(&b.addInstallFile(api_norg, "share/doc/duckwm/API.norg").step);

    // zig build meta: the same files, copied back into the source tree.
    const update_meta = b.addUpdateSourceFiles();
    update_meta.addCopyFileToSource(meta_lua, "meta/wm.lua");
    update_meta.addCopyFileToSource(api_md, "API.md");
    update_meta.addCopyFileToSource(api_norg, "API.norg");
    const meta_step = b.step("meta", "Regenerate LuaLS meta and API docs");
    meta_step.dependOn(&update_meta.step);

    // zig build proto: proto/duckwm.proto from src/protocol.zig.
    const gen_proto = b.addExecutable(.{
        .name = "gen_proto",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/gen_proto.zig"),
            .target = b.graph.host,
        }),
    });
    const run_proto = b.addRunArtifact(gen_proto);
    const update_proto = b.addUpdateSourceFiles();
    update_proto.addCopyFileToSource(run_proto.addOutputFileArg("duckwm.proto"), "proto/duckwm.proto");
    const proto_step = b.step("proto", "Regenerate proto/duckwm.proto from src/protocol.zig");
    proto_step.dependOn(&update_proto.step);
    b.getInstallStep().dependOn(&b.addInstallFile(b.path("proto/duckwm.proto"), "share/duckwm/duckwm.proto").step);

    // Type-checks every backend hook, including ones nothing calls yet.
    const x11_check = b.addTest(.{ .root_module = x11_mod });
    x11_check.use_llvm = true;
    x11_check.use_lld = true;
    const check_step = b.step("check", "Type-check every x11 backend hook");
    check_step.dependOn(&x11_check.step);

    const test_step = b.step("test", "Run tests");
    const protocol_tests = b.addTest(.{ .root_module = protocol_mod });
    test_step.dependOn(&b.addRunArtifact(protocol_tests).step);
    // The whole WM on the fake backend (src/fake.zig), whatever -Dplatform says.
    const fake_mod = b.createModule(.{
        .root_source_file = b.path("src/fake.zig"),
        .target = target,
    });
    fake_mod.addImport("types", types_mod);
    const wm_fake_mod = b.createModule(.{
        .root_source_file = b.path("src/wm.zig"),
        .target = target,
    });
    wm_fake_mod.addImport("graph", graph_mod);
    wm_fake_mod.addImport("types", types_mod);
    wm_fake_mod.addImport("platform", fake_mod);
    wm_fake_mod.addImport("libc", libc_mod);
    wm_fake_mod.addImport("ziglua", zlua);
    wm_fake_mod.addImport("protocol", protocol_mod);
    const lua_fake_mod = b.createModule(.{
        .root_source_file = b.path("src/lua.zig"),
        .target = target,
    });
    lua_fake_mod.addImport("ziglua", zlua);
    lua_fake_mod.addImport("wm", wm_fake_mod);
    lua_fake_mod.addImport("graph", graph_mod);
    lua_fake_mod.addImport("types", types_mod);
    lua_fake_mod.addImport("api_docs", api_mod);
    lua_fake_mod.addImport("libc", libc_mod);
    lua_fake_mod.addImport("protocol", protocol_mod);
    const harness_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tests/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "wm", .module = wm_fake_mod },
            .{ .name = "platform", .module = fake_mod },
            .{ .name = "types", .module = types_mod },
            .{ .name = "config", .module = lua_fake_mod },
        },
    }) });
    harness_tests.root_module.addAnonymousImport("default_config", .{ .root_source_file = b.path("config/default.lua") });
    test_step.dependOn(&b.addRunArtifact(harness_tests).step);
    const client_tests = b.addTest(.{ .root_module = client_mod });
    test_step.dependOn(&b.addRunArtifact(client_tests).step);
}
