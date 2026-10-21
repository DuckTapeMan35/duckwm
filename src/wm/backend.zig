pub const Backend = @import("platform").Backend;
pub const platform_id = @import("platform").id;

pub const WindowHandle = @import("types").WindowHandle;

comptime {
    const required = .{
        "init",
        "deinit",
        "screen_size",
        "close_window",
        "publish_work_area",
        "publish_workspaces",
        "publish_window_list",
        "publish_window_workspace",
        "show_error",
        "hide_error",
        "window_info",
        "window_traits",
        "window_hints",
        "pointer_position",
        "warp_pointer",
        "set_cursor_theme",
        "keysym_from_name",
        "grab_key",
        "ungrab_all_keys",
        "set_pointer_grabs",
        "start",
        "event_fd",
        "set_input_focus",
        "publish_window_fullscreen",
        "publish_frame_extents",
        "set_click_to_focus",
        "draw_borders",
        "apply_windows",
        "apply_outlines",
        "hide_window",
        "raise_window",
        "release_window",
        "draw_preview",
        "flush_output",
        "next_event",
        "release_pointer",
        "capture_pointer",
        "sync",
        "reserved_insets",
        "frame_window",
        "unframe",
        "create_preview_window",
        "destroy_preview_window",
        "end_session",
        "set_keymap",
        "set_layout_index",
        "set_animation",
        "poll_timeout",
        "show_prompt",
        "show_message",
        "hide_prompt",
        "outputs",
    };
    for (required) |name| {
        if (!@hasDecl(Backend, name))
            @compileError("backend is missing required hook: " ++ name);
    }
}
