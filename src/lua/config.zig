const std = @import("std");
const ziglua = @import("ziglua");
const wm_mod = @import("wm");
const graph_mod = @import("graph");
const c = @import("libc");
const util = @import("util.zig");
const vm = @import("vm.zig");
const repl = @import("repl.zig");
const Lua = ziglua.Lua;
const WM = wm_mod.WM;

// ---- Paths and watching ----
fn resolve_user_path(wm: *WM) ?[]const u8 {
    if (c.getenv("XDG_CONFIG_HOME")) |xdg| {
        const base: []const u8 = std.mem.span(xdg);
        if (base.len > 0)
            return std.fmt.allocPrint(wm.allocator, "{s}/duckwm/config.lua", .{base}) catch null;
    }
    if (c.getenv("HOME")) |home_ptr| {
        const home: []const u8 = std.mem.span(home_ptr);
        if (home.len > 0)
            return std.fmt.allocPrint(wm.allocator, "{s}/.config/duckwm/config.lua", .{home}) catch null;
    }
    return null;
}

/// The user config path, null-terminated for Lua. Caller frees.
fn user_path_z(wm: *WM) ?[:0]u8 {
    const path = resolve_user_path(wm) orelse return null;
    defer wm.allocator.free(path);
    return wm.allocator.dupeSentinel(u8, path, 0) catch null;
}

fn watch_config(wm: *WM, path: []const u8) void {
    const dir = std.fs.path.dirname(path) orelse {
        std.debug.print("watch_config: could not get dirname of '{s}'\n", .{path});
        return;
    };
    std.debug.print("watch_config: watching dir '{s}'\n", .{dir});
    const dir_z = wm.allocator.dupeSentinel(u8, dir, 0) catch return;
    defer wm.allocator.free(dir_z);
    wm.watch_config_dir(dir_z);
}

// ---- State the config rebuilds on every run ----
/// Per-node border colors come from the config; clear them so a re-run starts fresh.
fn clear_all_node_colors(wm: *WM, g: *graph_mod.Graph) void {
    for (g.nodes.items) |node| {
        wm.journal.set(node, "border_color_focused", null);
        wm.journal.set(node, "border_color_unfocused", null);
        wm.journal.set(node, "border_color_top", null);
        wm.journal.set(node, "border_color_bottom", null);
        wm.journal.set(node, "border_color_left", null);
        wm.journal.set(node, "border_color_right", null);
        wm.journal.set(node, "indicator_side", null);
        if (node.content == .workspace) clear_all_node_colors(wm, node.content.workspace);
    }
}

/// Re-run the config in the current VM, after dropping everything a run adds
/// (bindings, rules, swallow pairs, RGB-frame classes, node colors), so the
/// re-run doesn't duplicate them.
pub fn reload_persistent(lua: *Lua) void {
    const wm = util.global_wm;
    const path_z = user_path_z(wm) orelse return;
    defer wm.allocator.free(path_z);

    clear_all_node_colors(wm, wm.current_graph);

    wm.clear_config_binds();

    for (wm.rules.items) |r| wm.release_callback(r.cb);
    wm.rules.clearRetainingCapacity();
    wm.clear_rgb_frame_classes();
    wm.clear_swallow_pairs();

    lua.doFile(path_z) catch lua.pop(1);
    wm.run_commands_file();
}

// ---- Lua functions ----
pub fn l_reload_persistent(lua: *Lua) i32 {
    reload_persistent(lua);
    return 0;
}

// ---- Loading ----
/// Map every tiled node of g (and its nested workspaces) through its arranger
/// again, as if each window had just appeared.
fn remap_all_graphs(wm: *WM, g: *graph_mod.Graph) void {
    if (g.arranger == null and wm.default_arranger == null) return;

    const saved_graph = wm.current_graph;
    wm.current_graph = g;
    defer wm.current_graph = saved_graph;

    var ids: std.ArrayListUnmanaged(u32) = .empty;
    defer ids.deinit(wm.allocator);
    for (g.nodes.items) |node| {
        if (node.floating) continue;
        switch (node.content) {
            .window, .workspace, .group => {
                if (node.content == .workspace and node.preview_window == null) continue;
                if (wm.get_id_for_node(node)) |id| ids.append(wm.allocator, id) catch {};
            },
            .empty => {},
        }
    }
    for (g.nodes.items) |node| {
        if (!node.floating) g.replace_constraints(node, &.{}) catch {};
    }

    var prev_id: ?u32 = null;
    for (ids.items) |id| {
        if (wm.get_node_by_id(id)) |node| {
            if (node.content == .workspace and node.content.workspace == saved_graph) {
                prev_id = id;
                continue;
            }
        }
        wm.call_arranger(g, .map, id, prev_id);
        prev_id = id;
    }
    wm.resolve(g) catch {};
    wm.rebuild_focus_edges() catch {};
    if (g == saved_graph) wm.flush(g) catch {};

    for (g.nodes.items) |node| {
        if (node.inner()) |sub| remap_all_graphs(wm, sub);
    }
}

/// Live reload: check the file compiles before throwing away the running VM,
/// then re-run it in a fresh one, falling back to the system config on error.
pub fn reload(wm: *WM) void {
    const path_z = user_path_z(wm) orelse {
        std.debug.print("duckwm: no user config path found for reload\n", .{});
        return;
    };
    defer wm.allocator.free(path_z);

    // Syntax check only: compile without executing. Retried briefly, since an
    // editor may still be writing the file when inotify fires.
    const old_lua = wm.lua orelse return;
    std.debug.print("reload: attempting to load '{s}'\n", .{path_z});
    var load_err: ?anyerror = null;
    for (0..5) |_| {
        old_lua.loadFile(path_z, .text) catch |err| {
            load_err = err;
            _ = c.usleep(10_000);
            continue;
        };
        load_err = null;
        break;
    }
    if (load_err) |err| {
        const msg = old_lua.toString(-1) catch @errorName(err);
        const owned = wm.allocator.dupe(u8, msg) catch null;
        old_lua.pop(1);
        if (owned) |m| {
            wm.show_error(m);
            wm.allocator.free(m);
        }
        return;
    }
    old_lua.pop(1);

    // Compiles: full reset and run.
    var lua = vm.reset_vm(wm) catch {
        std.debug.print("reload: failed to init Lua VM\n", .{});
        return;
    };
    lua.doFile(path_z) catch |err| {
        const raw = lua.toString(-1) catch null;
        const owned: ?[]u8 = if (raw) |m| wm.allocator.dupe(u8, m) catch null else null;
        lua.pop(1);
        wm.show_error(owned orelse @errorName(err));
        if (owned) |m| wm.allocator.free(m);

        lua = vm.reset_vm(wm) catch return;
        lua.doFile("/etc/duckwm/config.lua") catch |err2| {
            std.debug.print("default config also failed: {}\n", .{err2});
            lua.pop(1);
        };
        return;
    };
    for (wm.outputs.items) |o| remap_all_graphs(wm, &o.root);
    wm.hide_error();
    wm.run_commands_file();
    std.debug.print("config reloaded successfully\n", .{});
}

/// Run a config given as source text instead of a file (tests: the fake
/// backend's harness). No fallback and no watching; an error is returned.
pub fn load_source(wm: *WM, source: [:0]const u8) !void {
    util.global_wm = wm;
    const lua = try Lua.init(wm.allocator);
    wm.lua = lua;
    vm.setup_lua(wm, lua);
    wm.eval_fn = repl.eval;
    lua.doString(source) catch |err| {
        std.debug.print("load_source: {s}\n", .{lua.toString(-1) catch @errorName(err)});
        lua.pop(1);
        return err;
    };
    for (wm.outputs.items) |o| remap_all_graphs(wm, &o.root);
}

/// Startup: run the user config, falling back to the system one. A failing
/// user config is reported once the WM is up (post_load_error).
pub fn load(wm: *WM) !void {
    std.debug.print("load: starting\n", .{});
    util.global_wm = wm;

    var lua = try Lua.init(wm.allocator);
    wm.lua = lua;
    vm.setup_lua(wm, lua);
    wm.eval_fn = repl.eval;

    const user_path = resolve_user_path(wm);
    defer if (user_path) |p| wm.allocator.free(p);

    var pending_error: ?[]u8 = null;
    defer if (pending_error) |msg| wm.allocator.free(msg);

    const paths_to_try = [_]?[]const u8{ user_path, "/etc/duckwm/config.lua" };
    for (paths_to_try) |maybe_path| {
        const path = maybe_path orelse continue;
        std.debug.print("load: trying path '{s}'\n", .{path});
        const path_z = wm.allocator.dupeSentinel(u8, path, 0) catch continue;
        defer wm.allocator.free(path_z);

        lua.doFile(path_z) catch |err| {
            std.debug.print("load: doFile failed: {}\n", .{err});
            const raw = lua.toString(-1) catch null;
            const owned: ?[]u8 = if (raw) |m| wm.allocator.dupe(u8, m) catch null else null;
            defer if (owned) |m| wm.allocator.free(m);

            const is_missing = if (owned) |m|
                std.mem.indexOf(u8, m, "No such file") != null or std.mem.indexOf(u8, m, "cannot open") != null
            else
                err == error.FileNotFound;

            lua.pop(1);
            lua = vm.reset_vm(wm) catch continue;
            if (is_missing) continue;

            if (pending_error == null)
                pending_error = wm.allocator.dupe(u8, owned orelse @errorName(err)) catch null;
            continue;
        };
        std.debug.print("load: loaded '{s}'\n", .{path});

        if (pending_error) |msg| {
            wm.post_load_error = msg;
            pending_error = null;
        }
        // Watch for live reload only when the user config is the one that loaded.
        if (user_path) |up| {
            if (std.mem.eql(u8, path, up)) watch_config(wm, path);
        }

        wm.reload_fn = reload;
        for (wm.outputs.items) |o| remap_all_graphs(wm, &o.root);
        return;
    }

    wm.post_load_error = pending_error orelse
        wm.allocator.dupe(u8, "no config found at $XDG_CONFIG_HOME/duckwm/config.lua or /etc/duckwm/config.lua") catch null;
    pending_error = null;
}
