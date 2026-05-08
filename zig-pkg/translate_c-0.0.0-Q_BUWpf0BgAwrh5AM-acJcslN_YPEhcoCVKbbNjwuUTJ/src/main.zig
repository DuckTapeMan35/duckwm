const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const process = std.process;
const Io = std.Io;

const aro = @import("aro");

const Translator = @import("Translator.zig");

const fast_exit = @import("builtin").mode != .Debug;

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main(init: process.Init.Minimal) u8 {
    const gpa = if (@import("builtin").link_libc)
        std.heap.c_allocator
    else
        debug_allocator.allocator();
    defer if (!@import("builtin").link_libc) {
        _ = debug_allocator.deinit();
    };

    var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    var threaded: Io.Threaded = .init(gpa, .{
        .argv0 = .init(init.args),
        .environ = init.environ,
    });
    defer threaded.deinit();
    const io = threaded.io();

    const args = init.args.toSlice(arena) catch {
        std.debug.print("ran out of memory allocating arguments\n", .{});
        if (fast_exit) process.exit(1);
        return 1;
    };

    var environ_map = std.process.Environ.createMap(init.environ, gpa) catch |err|
        std.process.fatal("failed to parse environment variables: {t}", .{err});
    defer environ_map.deinit();

    var stderr_buf: [1024]u8 = undefined;
    var stderr = Io.File.stderr().writer(io, &stderr_buf);
    var diagnostics: aro.Diagnostics = .{
        .output = .{ .to_writer = .{
            .mode = Io.Terminal.Mode.detect(io, stderr.file, false, false) catch .no_color,
            .writer = &stderr.interface,
        } },
    };

    var comp = aro.Compilation.init(.{
        .gpa = gpa,
        .arena = arena,
        .io = io,
        .diagnostics = &diagnostics,
        .environ_map = &environ_map,
    }) catch |err| switch (err) {
        error.OutOfMemory => {
            std.debug.print("ran out of memory initializing C compilation\n", .{});
            if (fast_exit) process.exit(1);
            return 1;
        },
    };
    defer comp.deinit();

    const exe_name = std.process.executableDirPathAlloc(io, gpa) catch {
        std.debug.print("unable to find translate-c executable path\n", .{});
        if (fast_exit) process.exit(1);
        return 1;
    };
    defer gpa.free(exe_name);

    var driver: aro.Driver = .{ .comp = &comp, .diagnostics = &diagnostics, .aro_name = exe_name };
    defer driver.deinit();

    var toolchain: aro.Toolchain = .{ .driver = &driver };
    defer toolchain.deinit();

    translate(&driver, &toolchain, args) catch |err| switch (err) {
        error.OutOfMemory => {
            std.debug.print("ran out of memory translating\n", .{});
            if (fast_exit) process.exit(1);
            return 1;
        },
        error.FatalError => {
            if (fast_exit) process.exit(1);
            return 1;
        },
        error.WriteFailed => {
            std.debug.print("unable to write to stdout\n", .{});
            if (fast_exit) process.exit(1);
            return 1;
        },
    };
    if (fast_exit) process.exit(@intFromBool(comp.diagnostics.errors != 0));
    return @intFromBool(comp.diagnostics.errors != 0);
}

pub const usage =
    \\Usage {s}: [options] file [CC options]
    \\
    \\Options:
    \\  --help                      Print this message
    \\  --version                   Print translate-c version
    \\  -fmodule-libs               Import libraries as modules
    \\  -fno-module-libs            (default) Install libraries next to output file
    \\  -fpub-static                (default) Translate static functions as pub
    \\  -fno-pub-static             Do not translate static functions as pub
    \\  -ffunc-bodies               (default) Translate function bodies
    \\  -fno-func-bodies            Do not translate function bodies
    \\  -fkeep-macro-literals       (default) Preserve macro names for literals
    \\  -fno-keep-macro-literals    Do not preserve macro names for literals
    \\  -fdefault-init              Default initialize struct fields
    \\  -fno-default-init           (default) Do not default initialize struct fields
    \\  -fstrict-flex-arrays=<n>    Control when to treat a trailing array as a flexible array member (default: 2)
    \\                                0: any trailing array
    \\                                1: size [0]/[1]/[]
    \\                                2: size [0]/[]
    \\                                3: [] only
    \\
    \\
;

fn translate(d: *aro.Driver, tc: *aro.Toolchain, args: []const [:0]const u8) !void {
    const gpa = d.comp.gpa;
    const io = d.comp.io;

    var module_libs = false;
    var pub_static = true;
    var func_bodies = true;
    var keep_macro_literals = true;
    var default_init = false;
    var strict_flex_arrays: Translator.StrictFlexArraysLevel = .@"2";

    var aro_args: std.ArrayList([:0]const u8) = try .initCapacity(gpa, args.len);
    defer aro_args.deinit(gpa);

    for (args) |arg| {
        if (mem.eql(u8, arg, "--help")) {
            var stdout_buf: [512]u8 = undefined;
            var stdout = Io.File.stdout().writer(io, &stdout_buf);
            try stdout.interface.print(usage, .{args[0]});
            try stdout.interface.flush();
            return;
        } else if (mem.eql(u8, arg, "--version")) {
            var stdout_buf: [512]u8 = undefined;
            var stdout = Io.File.stdout().writer(io, &stdout_buf);
            // TODO add version
            try stdout.interface.writeAll("0.0.0-dev\n");
            try stdout.interface.flush();
            return;
        } else if (mem.eql(u8, arg, "-fmodule-libs")) {
            module_libs = true;
        } else if (mem.eql(u8, arg, "-fno-module-libs")) {
            module_libs = false;
        } else if (mem.eql(u8, arg, "-fpub-static")) {
            pub_static = true;
        } else if (mem.eql(u8, arg, "-fno-pub-static")) {
            pub_static = false;
        } else if (mem.eql(u8, arg, "-ffunc-bodies")) {
            func_bodies = true;
        } else if (mem.eql(u8, arg, "-fno-func-bodies")) {
            func_bodies = false;
        } else if (mem.eql(u8, arg, "-fkeep-macro-literals")) {
            keep_macro_literals = true;
        } else if (mem.eql(u8, arg, "-fno-keep-macro-literals")) {
            keep_macro_literals = false;
        } else if (mem.eql(u8, arg, "-fdefault-init")) {
            default_init = true;
        } else if (mem.eql(u8, arg, "-fno-default-init")) {
            default_init = false;
        } else if (mem.startsWith(u8, arg, "-fstrict-flex-arrays=")) {
            const val_str = arg["-fstrict-flex-arrays=".len..];
            if (val_str.len != 1 or val_str[0] < '0' or val_str[0] > '3') {
                return d.fatal("-fstrict-flex-arrays= requires a value of '0', '1', '2', or '3'", .{});
            }
            strict_flex_arrays = @enumFromInt(val_str[0] - '0');
        } else {
            aro_args.appendAssumeCapacity(arg);
        }
    }
    const user_macros = macros: {
        var macro_buf: std.ArrayList(u8) = .empty;
        defer macro_buf.deinit(gpa);

        var discard_buf: [256]u8 = undefined;
        var discarding: Io.Writer.Discarding = .init(&discard_buf);
        assert(!try d.parseArgs(&discarding.writer, &macro_buf, aro_args.items));
        if (macro_buf.items.len > std.math.maxInt(u32)) {
            return d.fatal("user provided macro source exceeded max size", .{});
        }

        const content = try macro_buf.toOwnedSlice(gpa);
        errdefer gpa.free(content);

        break :macros try d.comp.addSourceFromOwnedBuffer("<command line>", content, .user);
    };

    if (d.inputs.items.len != 1) {
        return d.fatal("expected exactly one input file", .{});
    }
    const source = d.inputs.items[0];

    tc.discover() catch |er| switch (er) {
        error.OutOfMemory => return error.OutOfMemory,
        error.TooManyMultilibs => return d.fatal("found more than one multilib with the same priority", .{}),
    };
    try tc.defineSystemIncludes();
    try d.comp.initSearchPath(d.includes.items, d.verbose_search_path);

    const builtin_macros = d.comp.generateBuiltinMacros(d.system_defines) catch |err| switch (err) {
        error.FileTooBig => return d.fatal("builtin macro source exceeded max size", .{}),
        else => |e| return e,
    };

    var pp = try aro.Preprocessor.init(d.comp, .{
        .base_file = source.id,
    });
    defer pp.deinit();

    var name_buf: [std.fs.max_name_bytes]u8 = undefined;
    var opt_dep_file = try d.initDepFile(source, &name_buf);
    defer if (opt_dep_file) |*dep_file| dep_file.deinit(d.comp.gpa);

    if (opt_dep_file) |*dep_file| pp.dep_file = dep_file;

    try pp.preprocessSources(.{
        .main = source,
        .builtin = builtin_macros,
        .command_line = user_macros,
        .imacros = d.imacros.items,
        .implicit_includes = d.implicit_includes.items,
    });

    var c_tree = try pp.parse();
    defer c_tree.deinit();

    if (d.diagnostics.errors != 0) {
        if (fast_exit) process.exit(1);
        return error.FatalError;
    }

    var out_buf: [4096]u8 = undefined;
    if (opt_dep_file) |dep_file| {
        const dep_file_name = try d.getDepFileName(source, out_buf[0..std.fs.max_name_bytes]);

        const file = if (dep_file_name) |path|
            d.comp.cwd.createFile(io, path, .{}) catch |er|
                return d.fatal("unable to create dependency file '{s}': {s}", .{ path, aro.Driver.errorDescription(er) })
        else
            Io.File.stdout();
        defer if (dep_file_name != null) file.close(io);

        var file_writer = file.writer(io, &out_buf);
        dep_file.write(&file_writer.interface) catch
            return d.fatal("unable to write dependency file: {s}", .{aro.Driver.errorDescription(file_writer.err.?)});
    }

    const rendered_zig = try Translator.translate(.{
        .gpa = gpa,
        .comp = d.comp,
        .pp = &pp,
        .tree = &c_tree,
        .module_libs = module_libs,
        .pub_static = pub_static,
        .func_bodies = func_bodies,
        .keep_macro_literals = keep_macro_literals,
        .default_init = default_init,
        .strict_flex_arrays = strict_flex_arrays,
    });
    defer gpa.free(rendered_zig);

    var close_out_file = false;
    var out_file_path: []const u8 = "<stdout>";
    var out_file: Io.File = .stdout();
    defer if (close_out_file) out_file.close(io);

    if (d.output_name) |path| blk: {
        if (std.mem.eql(u8, path, "-")) break :blk;
        if (std.fs.path.dirname(path)) |dirname| {
            Io.Dir.cwd().createDirPath(io, dirname) catch |err|
                return d.fatal("failed to create path to '{s}': {s}", .{ path, aro.Driver.errorDescription(err) });
        }
        out_file = Io.Dir.cwd().createFile(io, path, .{}) catch |err| {
            return d.fatal("failed to create output file '{s}': {s}", .{ path, aro.Driver.errorDescription(err) });
        };
        close_out_file = true;
        out_file_path = path;
    }

    var out_writer = out_file.writer(io, &out_buf);
    out_writer.interface.writeAll(rendered_zig) catch {};
    out_writer.interface.flush() catch {};
    if (out_writer.err) |write_err|
        return d.fatal("failed to write result to '{s}': {s}", .{ out_file_path, aro.Driver.errorDescription(write_err) });

    if (!module_libs) {
        const dest_path = if (d.output_name) |path| std.fs.path.dirname(path) else null;
        installLibs(d, dest_path) catch |err|
            return d.fatal("failed to install library files: {s}", .{aro.Driver.errorDescription(err)});
    }

    if (fast_exit) process.exit(0);
}

fn installLibs(d: *aro.Driver, dest_path: ?[]const u8) !void {
    const gpa = d.comp.gpa;
    const io = d.comp.io;
    const cwd = Io.Dir.cwd();

    const self_exe_path = try std.process.executableDirPathAlloc(io, gpa);
    defer gpa.free(self_exe_path);

    var cur_dir: []const u8 = self_exe_path;
    while (std.fs.path.dirname(cur_dir)) |dirname| : (cur_dir = dirname) {
        var base_dir = cwd.openDir(io, dirname, .{}) catch continue;
        defer base_dir.close(io);

        var lib_dir = base_dir.openDir(io, "lib", .{}) catch continue;
        defer lib_dir.close(io);

        lib_dir.access(io, "c_builtins.zig", .{}) catch continue;

        {
            const install_path = try std.fs.path.join(gpa, &.{ dest_path orelse "", "c_builtins.zig" });
            defer gpa.free(install_path);
            try lib_dir.copyFile("c_builtins.zig", cwd, install_path, io, .{});
        }
        {
            const install_path = try std.fs.path.join(gpa, &.{ dest_path orelse "", "helpers.zig" });
            defer gpa.free(install_path);
            try lib_dir.copyFile("helpers.zig", cwd, install_path, io, .{});
        }
        return;
    }
    return error.FileNotFound;
}

comptime {
    if (@import("builtin").is_test) {
        _ = Translator;
        _ = @import("helpers.zig");
        _ = @import("PatternList.zig");
    }
}
