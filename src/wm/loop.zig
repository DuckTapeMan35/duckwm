const std = @import("std");
const core = @import("core.zig");
const settings = @import("settings.zig");
const registry = @import("registry.zig");
const ipc = @import("ipc.zig");
const WM = core.WM;

pub fn run(wm: *WM) !void {
    wm.current_graph = &wm.graph;
    wm.graph.on_node_free = registry.on_node_freed;
    wm.graph.on_node_free_ctx = wm;
    wm.backend.start() catch |err| {
        std.debug.print("duckwm: backend failed to start: {}\n", .{err});
        return;
    };
    wm.graph.journal = &wm.journal;
    try wm.create_initial_workspace();
    wm.scratch_graph = try wm.create_workspace_graph(1);
    wm.visible_graph = wm.current_graph;

    if (wm.post_load_error) |msg| {
        wm.show_error(msg);
        wm.allocator.free(msg);
        wm.post_load_error = null;
    }

    wm.startup_done = true;
    wm.commit();
    wm.run_commands_file();
    wm.commit();

    try wm.init_ipc();
    const event_fd = wm.backend.event_fd();

    var fds: std.ArrayListUnmanaged(std.posix.pollfd) = .empty;
    defer fds.deinit(wm.allocator);

    while (true) {
        fds.clearRetainingCapacity();
        try fds.append(wm.allocator, .{ .fd = event_fd, .events = std.posix.POLL.IN, .revents = 0 });
        const watching = wm.inotify_fd >= 0;
        if (watching) try fds.append(wm.allocator, .{ .fd = wm.inotify_fd, .events = std.posix.POLL.IN, .revents = 0 });
        const ipc_first = fds.items.len;
        try ipc.add_poll_fds(wm, &fds);

        // The timeout wakes the loop for the next animation frame, if any.
        _ = std.posix.poll(fds.items, wm.backend.poll_timeout()) catch continue;

        ipc.handle(wm, fds.items[ipc_first..]);
        if (watching and fds.items[1].revents & std.posix.POLL.IN != 0) settings.handle_config_events(wm);

        while (wm.backend.next_event()) |ev| wm.handle_event(ev);

        if (wm.pending_reload) {
            wm.pending_reload = false;
            if (wm.reload_fn) |f| f(wm);
        }

        // Everything this iteration changed reaches the screen here, once.
        wm.commit();
        wm.backend.flush_output();
    }
}
