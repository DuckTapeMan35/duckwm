const std = @import("std");
const api = @import("src/api.zig");

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

    fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
        @setEvalBranchQuota(100000);
        const self: *MetaStep = @fieldParentPtr("step", step);
        const b = self.b;
        const io = b.graph.io;
        const root = std.Io.Dir.cwd();

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
                try buf.print(b.allocator, "--- {s}\n", .{entry.desc});
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

            // Table of contents
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

            // Constants
            try buf.appendSlice(b.allocator, "## Constants\n\n");
            inline for (api.constants) |con| {
                try buf.print(b.allocator, "- **`wm.{s}`** — {s}\n", .{ con.name, con.desc });
            }
            try buf.appendSlice(b.allocator, "\n");

            // Functions by category
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

            // Constants
            try buf.appendSlice(b.allocator, "* Constants\n\n");
            inline for (api.constants) |con| {
                try buf.print(b.allocator, "  - `wm.{s}` — {s}\n", .{ con.name, con.desc });
            }
            try buf.appendSlice(b.allocator, "\n");

            // Functions by category
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

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    const mod = b.addModule("duckwm", .{
        // The root source file is the "entry point" of this module. Users of
        // this module will only be able to access public declarations contained
        // in this file, which means that if you have declarations that you
        // intend to expose to consumers that were defined in other files part
        // of this module, you will have to make sure to re-export them from
        // the root file.
        .root_source_file = b.path("src/root.zig"),
        // Later on we'll use this module as the root module of a test executable
        // which requires us to specify a target.
        .target = target,
    });

    const c_mod = b.addModule("c", .{
        .root_source_file = b.path("src/c.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ziglua = b.dependency("ziglua", .{
        .target = target,
        .optimize = optimize,
    });

    const graph_mod = b.addModule("graph", .{
        .root_source_file = b.path("src/graph.zig"),
        .target = target,
    });

    const wm_mod = b.addModule("wm", .{
        .root_source_file = b.path("src/wm.zig"),
        .target = target,
    });

    const config_mod = b.addModule("config", .{
        .root_source_file = b.path("src/config.zig"),
        .target = target,
    });

    const api_mod = b.addModule("api", .{
        .root_source_file = b.path("src/api.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });

    const solver_mod = b.addModule("solver", .{
        .root_source_file = b.path("src/solver.zig"),
        .target = target,
    });

    const meta_gen = MetaStep.create(b);
    const meta_step = b.step("meta", "Regenerate LuaLS meta and API docs");
    meta_step.dependOn(&meta_gen.step);

    mod.addImport("graph", graph_mod);
    mod.addImport("wm", wm_mod);
    mod.addImport("config", config_mod);
    wm_mod.addImport("graph", graph_mod);
    wm_mod.addImport("ziglua", ziglua.module("zlua"));
    wm_mod.addImport("c", c_mod);
    wm_mod.linkSystemLibrary("X11", .{});
    config_mod.addImport("ziglua", ziglua.module("zlua"));
    config_mod.addImport("wm", wm_mod);
    config_mod.addImport("graph", graph_mod);
    config_mod.addImport("c", c_mod);
    config_mod.addImport("api", api_mod);
    config_mod.linkSystemLibrary("X11", .{});
    config_mod.linkSystemLibrary("Xcursor", .{});
    graph_mod.addImport("c", c_mod);
    graph_mod.addImport("solver", solver_mod);
    c_mod.linkSystemLibrary("xft", .{ .use_pkg_config = .force });
    c_mod.linkSystemLibrary("fontconfig", .{ .use_pkg_config = .force });

    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    const exe = b.addExecutable(.{
        .name = "duckwm",
        .root_module = b.createModule(.{
            // b.createModule defines a new module just like b.addModule but,
            // unlike b.addModule, it does not expose the module to consumers of
            // this package, which is why in this case we don't have to give it a name.
            .root_source_file = b.path("src/main.zig"),
            // Target and optimization levels must be explicitly wired in when
            // defining an executable or library (in the root module), and you
            // can also hardcode a specific target for an executable or library
            // definition if desireable (e.g. firmware for embedded devices).
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            // List of modules available for import in source files part of the
            // root module.
            .imports = &.{
                // Here "duckwm" is the name you will use in your source code to
                // import this module (e.g. `@import("duckwm")`). The name is
                // repeated because you are allowed to rename your imports, which
                // can be extremely useful in case of collisions (which can happen
                // importing modules from different packages).
                .{ .name = "duckwm", .module = mod },
                .{ .name = "graph", .module = graph_mod},
                .{ .name = "wm", .module = wm_mod},
                .{ .name = "config", .module = config_mod},
            },
        }),
    });

    // link libX11
    exe.use_llvm = true;
    exe.use_lld = true;
    exe.root_module.linkSystemLibrary("X11", .{});
    exe.root_module.linkSystemLibrary("Xcursor", .{});
    exe.root_module.addImport("ziglua", ziglua.module("zlua"));

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    const quack = b.addExecutable(.{
        .name = "quack",
        .root_module = b.createModule(.{
            .root_source_file = b.path("quack/src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    b.installArtifact(quack);

    const install_config = b.addInstallFile(
        b.path("config/default.lua"),
        "../etc/duckwm/config.lua",  // relative to prefix, so /etc/duckwm/config.lua when prefix=/usr
    );
    const install_step = b.step("install-config", "Install default config to etc/duckwm/");
    install_step.dependOn(&install_config.step);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
