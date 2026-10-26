pub const Param = struct {
    name: []const u8,
    typ: []const u8,
};

pub const ApiEntry = struct {
    name: []const u8,
    desc: []const u8,
    params: []const Param,
    ret: []const u8,
    category: []const u8 = "Misc",
};

pub const Constant = struct {
    name: []const u8,
    desc: []const u8,
};

pub const categories = [_][]const u8{
    "Core",
    "Keybindings",
    "Window Management",
    "Focus",
    "Workspaces",
    "Groups",
    "Layout & Arrangers",
    "Constraints",
    "Geometry",
    "Appearance",
    "Rules",
    "Node Graph",
    "Debug",
    "Input",
};

pub const constants = [_]Constant{
    .{ .name = "MOD_SUPER", .desc = "Mod4 (Super/Win key)" },
    .{ .name = "MOD_ALT", .desc = "Mod1 (Alt key)" },
    .{ .name = "MOD_SHIFT", .desc = "Shift modifier" },
    .{ .name = "MOD_CTRL", .desc = "Control modifier" },
    .{ .name = "MOD_MOD2", .desc = "Mod2 (usually NumLock)" },
    .{ .name = "MOD_MOD3", .desc = "Mod3" },
    .{ .name = "MOD_MOD5", .desc = "Mod5 (usually AltGr)" },
    .{ .name = "BUTTON_LEFT", .desc = "Left mouse button (1)" },
    .{ .name = "BUTTON_MIDDLE", .desc = "Middle mouse button (2)" },
    .{ .name = "BUTTON_RIGHT", .desc = "Right mouse button (3)" },
    .{ .name = "BUTTON_SCROLL_UP", .desc = "Scroll wheel up (4)" },
    .{ .name = "BUTTON_SCROLL_DOWN", .desc = "Scroll wheel down (5)" },
    .{ .name = "PLATFORM_X11", .desc = "X11 backend" },
    .{ .name = "PLATFORM_RIVER", .desc = "river (Wayland) backend" },
    .{ .name = "PLATFORM", .desc = "Backend this build of duckwm uses: wm.PLATFORM_X11 or wm.PLATFORM_RIVER" },
};

pub const entries = [_]ApiEntry{

    // =========================================================
    // Core
    // =========================================================
    .{
        .category = "Core",
        .name = "quit",
        .desc = "Exit the window manager cleanly.",
        .params = &.{},
        .ret = "nil",
    },
    .{
        .category = "Core",
        .name = "reload_config",
        .desc = "Reload the Lua config file. The Lua VM is reset, all keybindings and rules are cleared, and the config is re-executed from scratch. Arrangers are re-mapped over existing windows.",
        .params = &.{},
        .ret = "nil",
    },
    .{
        .category = "Core",
        .name = "reload_persistent",
        .desc = "Re-run the config without killing the vm. This should be used only when it is known that the wm isn't in a bad internal state, for things like clearing keybinds set conditionally",
        .params = &.{},
        .ret = "nil",
    },
    .{
        .category = "Core",
        .name = "setenv",
        .desc = "Set an environment variable in the WM process. All subsequently spawned windows inherit it.",
        .params = &.{
            .{ .name = "key", .typ = "string" },
            .{ .name = "val", .typ = "string" },
        },
        .ret = "nil",
    },
    .{
        .category = "Core",
        .name = "spawn",
        .desc = "Spawn a subprocess. The argv table must contain at least one string (the executable path). The process is detached from the WM.",
        .params = &.{.{ .name = "argv", .typ = "string[]" }},
        .ret = "nil",
    },
    .{
        .category = "Core",
        .name = "exec_once",
        .desc = "Spawn a process at startup only; ignored on reloads. Use for autostart entries.",
        .params = &.{.{ .name = "argv", .typ = "string[]" }},
        .ret = "nil",
    },
    .{
        .category = "Core",
        .name = "set_cursor_theme",
        .desc = "Set the cursor theme and size, on X11 and river. Sets XCURSOR_THEME/XCURSOR_SIZE for spawned apps, and on X11 the RESOURCE_MANAGER property too.",
        .params = &.{
            .{ .name = "theme", .typ = "string" },
            .{ .name = "size", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Core",
        .name = "screen_width",
        .desc = "Return the focused monitor's width in pixels.",
        .params = &.{},
        .ret = "integer",
    },
    .{
        .category = "Core",
        .name = "screen_height",
        .desc = "Return the focused monitor's height in pixels.",
        .params = &.{},
        .ret = "integer",
    },
    .{
        .category = "Core",
        .name = "get_work_area",
        .desc = "The usable area of the current workspace's monitor as (x, y, width, height): the monitor minus the docks and bars on it (_NET_WM_STRUT_PARTIAL on X11, layer-shell exclusive zones on river).",
        .params = &.{},
        .ret = "integer, integer, integer, integer",
    },
    .{
        .category = "Core",
        .name = "transaction",
        .desc = "Run fn atomically. If fn raises an error or returns false, every change it made is undone; an error is re-raised after the rollback. Returns true if the changes were kept, false if fn returned false.",
        .params = &.{
            .{ .name = "fn", .typ = "fun(): boolean?" },
        },
        .ret = "boolean",
    },
    .{
        .category = "Core",
        .name = "eval",
        .desc = "Run Lua source as the REPL does: an expression shows its value, statements run as they are. Returns a status ('ok', 'error' or 'incomplete') and the text printed or returned.",
        .params = &.{.{ .name = "src", .typ = "string" }},
        .ret = "'ok'|'error'|'incomplete', string",
    },

    // =========================================================
    // Keybindings
    // =========================================================
    .{
        .category = "Keybindings",
        .name = "bind",
        .desc = "Register a keybinding. mod is a bitmask of modifier constants (e.g. MOD_SUPER | MOD_SHIFT). key is an X11 keysym name (e.g. 'Return', 'h', 'F11'). The function is called with no arguments when the key is pressed.",
        .params = &.{
            .{ .name = "mod", .typ = "integer" },
            .{ .name = "key", .typ = "string" },
            .{ .name = "fn", .typ = "function" },
        },
        .ret = "nil",
    },
    .{
        .category = "Keybindings",
        .name = "unbind",
        .desc = "Remove a key's bind, whether it was made by bind or bind_commands.",
        .params = &.{
            .{ .name = "mods", .typ = "integer" },
            .{ .name = "key", .typ = "string" },
        },
        .ret = "nil",
    },
    .{
        .category = "Keybindings",
        .name = "get_keybinds",
        .desc = "Every bound key combination, once each: mods is the modifier bitmask bind takes, key the keysym name ('Return', 'q'). Says nothing about what the binds do.",
        .params = &.{},
        .ret = "{ mods: integer, key: string }[]",
    },

    // =========================================================
    // Window Management
    // =========================================================
    .{
        .category = "Window Management",
        .name = "kill_client",
        .desc = "Ask the focused window to close (WM_DELETE_WINDOW on X11; on river, a close request). On X11, a client that doesn't support it is killed.",
        .params = &.{},
        .ret = "nil",
    },
    .{
        .category = "Window Management",
        .name = "toggle_floating",
        .desc = "Toggle floating mode on the focused window. Floating windows are excluded from tiling and can be freely moved and resized.",
        .params = &.{},
        .ret = "nil",
    },
    .{
        .category = "Window Management",
        .name = "set_floating",
        .desc = "Set floating state of a window directly. Pass false to re-integrate into tiling via the arranger.",
        .params = &.{
            .{ .name = "id", .typ = "integer" },
            .{ .name = "val", .typ = "boolean" },
        },
        .ret = "nil",
    },
    .{
        .category = "Window Management",
        .name = "toggle_fullscreen",
        .desc = "Toggle fullscreen on the focused window. The window is moved to cover its whole monitor, docks and bars included.",
        .params = &.{},
        .ret = "nil",
    },
    .{
        .category = "Window Management",
        .name = "set_fullscreen",
        .desc = "Set fullscreen state on a specific window node. Primarily for use in window rules.",
        .params = &.{
            .{ .name = "id", .typ = "integer" },
            .{ .name = "val", .typ = "boolean" },
        },
        .ret = "nil",
    },
    .{
        .category = "Window Management",
        .name = "hide_window",
        .desc = "Unmap a window's frame without destroying it. The node remains in the graph.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Window Management",
        .name = "show_window",
        .desc = "Map and raise a previously hidden window.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Window Management",
        .name = "get_window_class",
        .desc = "Get the WM_CLASS of a window: its class (second string, e.g. \"XTerm\") and instance (first string, e.g. \"xterm\"). Either may be nil.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "string|nil, string|nil",
    },
    .{
        .category = "Window Management",
        .name = "get_window_name",
        .desc = "Return the WM_NAME (title) of a window node, or nil if unavailable.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "string|nil",
    },
    .{
        .category = "Window Management",
        .name = "get_window_pid",
        .desc = "Return the PID of a window node via _NET_WM_PID, or nil if the property is not set.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "integer|nil",
    },
    .{
        .category = "Window Management",
        .name = "get_urgent",
        .desc = "Return whether a window has the urgency hint set.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "boolean",
    },
    .{
        .category = "Window Management",
        .name = "set_urgent",
        .desc = "Set or clear the urgency flag on a window node.",
        .params = &.{
            .{ .name = "id", .typ = "integer" },
            .{ .name = "val", .typ = "boolean" },
        },
        .ret = "nil",
    },
    .{
        .category = "Window Management",
        .name = "register_swallow",
        .desc = "Register a terminal/application WM_CLASS pair for swallowing. When a window whose class matches `child` maps and one of its ancestor processes owns a window whose class matches `terminal` in the current workspace, the terminal is replaced in the layout by the new window and restored when it closes.",
        .params = &.{
            .{ .name = "terminal", .typ = "string" },
            .{ .name = "child", .typ = "string" },
        },
        .ret = "nil",
    },
    .{
        .category = "Window Management",
        .name = "unregister_swallow",
        .desc = "Remove a previously registered terminal/application swallow pair.",
        .params = &.{
            .{ .name = "terminal", .typ = "string" },
            .{ .name = "child", .typ = "string" },
        },
        .ret = "nil",
    },
    .{
        .category = "Window Management",
        .name = "scratchpad_toggle",
        .desc = "Toggle a scratchpad window: stash it in the off-screen parking lot if it's showing, or summon it onto the current workspace (floating) if it's stashed.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Window Management",
        .name = "scratchpad_show",
        .desc = "Summon a stashed scratchpad window onto the current workspace as a floating window and focus it.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Window Management",
        .name = "scratchpad_hide",
        .desc = "Stash a window into the off-screen parking lot; the tiled survivors re-flow as if it were closed.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Window Management",
        .name = "get_scratchpad",
        .desc = "The node IDs stashed in the scratchpad, oldest first. They survive a config reload, so a config can find its scratchpad windows again with this.",
        .params = &.{},
        .ret = "integer[]",
    },

    // =========================================================
    // Focus
    // =========================================================
    .{
        .category = "Focus",
        .name = "focus",
        .desc = "Focus a specific node by ID.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Focus",
        .name = "focus_left",
        .desc = "Move focus to the nearest window to the left of the focused window, using focus edges.",
        .params = &.{},
        .ret = "nil",
    },
    .{
        .category = "Focus",
        .name = "focus_right",
        .desc = "Move focus to the nearest window to the right of the focused window, using focus edges.",
        .params = &.{},
        .ret = "nil",
    },
    .{
        .category = "Focus",
        .name = "focus_up",
        .desc = "Move focus to the nearest window above the focused window, using focus edges.",
        .params = &.{},
        .ret = "nil",
    },
    .{
        .category = "Focus",
        .name = "focus_down",
        .desc = "Move focus to the nearest window below the focused window, using focus edges.",
        .params = &.{},
        .ret = "nil",
    },
    .{
        .category = "Focus",
        .name = "get_focused",
        .desc = "Return the ID of the currently focused node, or nil if nothing is focused.",
        .params = &.{},
        .ret = "integer|nil",
    },
    .{
        .category = "Focus",
        .name = "set_focus_follows_mouse",
        .desc = "Enable or disable focus-follows-mouse. When enabled, moving the cursor into a window automatically focuses it.",
        .params = &.{.{ .name = "enabled", .typ = "boolean" }},
        .ret = "nil",
    },
    .{
        .category = "Focus",
        .name = "set_click_to_focus",
        .desc = "Enable or disable click-to-focus mode. When enabled, clicking a window focuses it even if focus-follows-mouse is off.",
        .params = &.{.{ .name = "enabled", .typ = "boolean" }},
        .ret = "nil",
    },
    .{
        .category = "Focus",
        .name = "exchange_left",
        .desc = "Swap the focused node's contents with the node to its left.",
        .params = &.{},
        .ret = "nil",
    },
    .{
        .category = "Focus",
        .name = "exchange_right",
        .desc = "Swap the focused node's contents with the node to its right.",
        .params = &.{},
        .ret = "nil",
    },
    .{
        .category = "Focus",
        .name = "exchange_up",
        .desc = "Swap the focused node's contents with the node above.",
        .params = &.{},
        .ret = "nil",
    },
    .{
        .category = "Focus",
        .name = "exchange_down",
        .desc = "Swap the focused node's contents with the node below.",
        .params = &.{},
        .ret = "nil",
    },

    // =========================================================
    // Workspaces
    // =========================================================
    .{
        .category = "Workspaces",
        .name = "switch_to_workspace",
        .desc = "Switch to a workspace by 1-based index at the current nesting level, on the focused monitor. Creates missing workspaces on demand.",
        .params = &.{.{ .name = "index", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Workspaces",
        .name = "send_to_workspace",
        .desc = "Send a window node to a workspace by 1-based index at the current nesting level, on the focused monitor. Creates missing workspaces on demand.",
        .params = &.{
            .{ .name = "node_id", .typ = "integer" },
            .{ .name = "index", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Workspaces",
        .name = "get_workspace",
        .desc = "Return the node ID of the nth workspace (1-based) in the current graph, or nil.",
        .params = &.{.{ .name = "index", .typ = "integer" }},
        .ret = "integer|nil",
    },
    .{
        .category = "Workspaces",
        .name = "get_current_workspace",
        .desc = "Return the 1-based number of the currently active workspace.",
        .params = &.{},
        .ret = "integer|nil",
    },
    .{
        .category = "Workspaces",
        .name = "get_workspaces_at_level",
        .desc = "Return a list of workspace numbers at the current nesting level that have content or are active.",
        .params = &.{},
        .ret = "integer[]",
    },
    .{
        .category = "Workspaces",
        .name = "set_workspace_switch_mode",
        .desc = "Set behaviour when switching to the already active workspace. 'none' does nothing; 'previous' switches to the previously active workspace.",
        .params = &.{.{ .name = "mode", .typ = "'none'|'previous'" }},
        .ret = "nil",
    },
    .{
        .category = "Workspaces",
        .name = "create_nested_workspace",
        .desc = "Create a new nested workspace node in the current graph. Returns its node ID. The workspace is empty and uses the default arranger.",
        .params = &.{},
        .ret = "integer",
    },
    .{
        .category = "Workspaces",
        .name = "enter_nested",
        .desc = "Enter the focused workspace node, making it the active graph.",
        .params = &.{},
        .ret = "nil",
    },
    .{
        .category = "Workspaces",
        .name = "leave_nested",
        .desc = "Leave the current nested workspace and return to the parent graph. Blocked at the top level.",
        .params = &.{},
        .ret = "nil",
    },
    .{
        .category = "Workspaces",
        .name = "enter_nested_by_id",
        .desc = "Enter a workspace node by its node ID.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Workspaces",
        .name = "enter_workspace_by_id",
        .desc = "Enter a workspace node by its node ID (alias for enter_nested_by_id, used for top-level workspace switching).",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Workspaces",
        .name = "get_current_level",
        .desc = "Return the nesting level of the current workspace. Level 1 is the top-level workspace layer; higher numbers mean deeper nesting.",
        .params = &.{},
        .ret = "integer",
    },
    .{
        .category = "Workspaces",
        .name = "get_node_level",
        .desc = "Return the nesting level of the graph that owns a node, or nil if the node is not found.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "integer|nil",
    },
    .{
        .category = "Workspaces",
        .name = "get_workspace_positions",
        .desc = "Return a list of positional indices (1-based) for all workspaces at the current level, sorted by creation order. Use this for bar display — index N corresponds to switch_to_workspace(N).",
        .params = &.{},
        .ret = "integer[]",
    },
    .{
        .category = "Workspaces",
        .name = "get_current_workspace_position",
        .desc = "Return the positional index (1-based) of the currently active workspace, matching switch_to_workspace. Returns nil if not found.",
        .params = &.{},
        .ret = "integer|nil",
    },
    .{
        .category = "Workspaces",
        .name = "get_workspace_states",
        .desc = "Return a table of all workspaces at the current level, each with a position (1-based index) and state ('focused', 'active', or 'inactive'). All workspaces are included regardless of whether they have content.",
        .params = &.{},
        .ret = "{ position: integer, state: 'focused'|'active'|'inactive' }[]",
    },
    .{
        .category = "Workspaces",
        .name = "cleanup_left_behind",
        .desc = "Cleans up subgraphs with windows that don't have a visible preview window",
        .params = &.{},
        .ret = "nil",
    },
    .{
        .category = "Workspaces",
        .name = "set_autoclean",
        .desc = "When enabled, killing a workspace that leaves windows behind in hidden (no-preview) sibling workspaces sweeps them immediately and silently, instead of showing the cleanup notification prompt.",
        .params = &.{
            .{ .name = "enabled", .typ = "boolean" },
        },
        .ret = "nil",
    },
    .{
        .category = "Workspaces",
        .name = "get_outputs",
        .desc = "The monitors, the primary first: id, x, y, width, height, focused. Each has its own workspaces; switch_to_workspace acts on the focused one.",
        .params = &.{},
        .ret = "{ id: integer, x: integer, y: integer, width: integer, height: integer, focused: boolean }[]",
    },
    .{
        .category = "Workspaces",
        .name = "focus_output",
        .desc = "Focus the nearest monitor in a direction: what was focused there last, or its top-left window. The pointer moves there too.",
        .params = &.{.{ .name = "dir", .typ = "'left'|'right'|'up'|'down'" }},
        .ret = "nil",
    },
    .{
        .category = "Workspaces",
        .name = "send_to_output",
        .desc = "Move a window to the workspace showing on the nearest monitor in a direction. Focus doesn't follow.",
        .params = &.{
            .{ .name = "id", .typ = "integer" },
            .{ .name = "dir", .typ = "'left'|'right'|'up'|'down'" },
        },
        .ret = "nil",
    },
    .{
        .category = "Workspaces",
        .name = "get_output_states",
        .desc = "What every monitor shows, in one call (for bars): its id, x, y, whether it's focused, the positions of its workspaces with content (as get_workspace_positions), the current one's position, its level, layout name and window count, and its focused window (id, title, class) or nil.",
        .params = &.{},
        .ret = "{ id: integer, x: integer, y: integer, focused: boolean, workspaces: integer[], current: integer|nil, level: integer, layout: string|nil, windows: integer, window: { id: integer, title: string|nil, class: string|nil }|nil }[]",
    },

    // =========================================================
    // Groups
    // =========================================================
    .{
        .category = "Groups",
        .name = "create_group",
        .desc =
        \\Wrap nodes in a new group, which takes the place of the first of them. A group is laid out
        \\like a window by the arranger of the graph holding it, and lays out its own nodes inside its
        \\rectangle with an arranger of its own (the default one, until register_arranger gives it
        \\another). Groups pan and zoom with their workspace. With no ids, the focused window is wrapped.
        \\New windows open in the focused window's group; a group whose last node leaves goes away.
        \\The ids must all be in the same workspace or group.
        ,
        .params = &.{.{ .name = "ids", .typ = "integer[]?" }},
        .ret = "integer",
    },
    .{
        .category = "Groups",
        .name = "ungroup",
        .desc = "Move everything in a group to the graph holding it, where the group was; the group goes.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Groups",
        .name = "move_to_group",
        .desc = "Move a node into a group, where its arranger places it. With no group, move it out of the group it's in, one level up. Focus stays on it.",
        .params = &.{
            .{ .name = "id", .typ = "integer" },
            .{ .name = "group", .typ = "integer?" },
        },
        .ret = "nil",
    },
    .{
        .category = "Groups",
        .name = "get_group",
        .desc = "The group a node is in, or nil if it's directly in a workspace.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "integer?",
    },
    .{
        .category = "Groups",
        .name = "get_group_members",
        .desc = "The nodes directly in a group, in the order they joined.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "integer[]",
    },
    .{
        .category = "Groups",
        .name = "set_group_outline",
        .desc = "The outline drawn along the inside of every group that doesn't set its own. Width 0 (the default) draws none; the group's nodes are laid out inside the outline.",
        .params = &.{
            .{ .name = "width", .typ = "integer" },
            .{ .name = "color", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Groups",
        .name = "set_group_outline_of",
        .desc = "One group's outline. nil for width or color goes back to set_group_outline's.",
        .params = &.{
            .{ .name = "id", .typ = "integer" },
            .{ .name = "width", .typ = "integer?" },
            .{ .name = "color", .typ = "integer?" },
        },
        .ret = "nil",
    },
    .{
        .category = "Groups",
        .name = "focus_parent",
        .desc = "Focus the group holding the focused node; commands that act on the focused window then act on the group. Directional focus moves on from it as from a window. Returns the group, or nil.",
        .params = &.{},
        .ret = "integer?",
    },
    .{
        .category = "Groups",
        .name = "focus_child",
        .desc = "From a focused group, focus the node in it on the way to what had focus last. Returns it, or nil.",
        .params = &.{},
        .ret = "integer?",
    },

    // =========================================================
    // Layout & Arrangers
    // =========================================================
    .{
        .category = "Layout & Arrangers",
        .name = "set_arranger",
        .desc =
        \\Set the current workspace's arranger. factory is called once per workspace and returns the
        \\arranger: a function(event, id, prev_id, snapshot) that returns the whole layout
        \\({ nodes = ... }, or nil to keep the current one) and the state to keep (nil keeps the old one).
        \\event is one of:
        \\  'map'     — a window joined the layout
        \\  'unmap'   — a window is leaving it (the snapshot still lists it)
        \\  'resize'  — the user resized a window
        \\  'focus'   — a window gained focus
        \\  'pre_map' — before 'map', before the window is placed
        \\  'area'    — the work area changed size (a bar, the monitor)
        \\The snapshot has event, id, prev_id, work_area, windows, focused, cursor_dx, cursor_dy,
        \\layout (as duckwm has it, with the user's resizes) and state. Keys bound while the
        \\factory runs belong to that workspace. The guide walks through writing one.
        ,
        .params = &.{
            .{ .name = "factory", .typ = "function" },
            .{ .name = "name", .typ = "string?" },
        },
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "set_default_arranger",
        .desc = "Set the default arranger factory used for new workspaces. The factory is called with no arguments and must return an arranger function. See set_arranger for the full list of events the arranger receives.",
        .params = &.{
            .{ .name = "factory", .typ = "function" },
            .{ .name = "name", .typ = "string?" },
        },
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "register_arranger",
        .desc = "Set the arranger for a workspace or group node by ID. See set_arranger for the full list of events the arranger receives.",
        .params = &.{
            .{ .name = "id", .typ = "integer" },
            .{ .name = "factory", .typ = "function" },
            .{ .name = "name", .typ = "string?" },
        },
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "get_arranger_name",
        .desc = "Return the display name of the current workspace's arranger, or nil if none is set.",
        .params = &.{},
        .ret = "string|nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "get_arranger_index",
        .desc = "Return the arranger index stored on the current workspace. Used to track which arranger in a cycle is active.",
        .params = &.{},
        .ret = "integer",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "set_arranger_index",
        .desc = "Set the arranger index on the current workspace.",
        .params = &.{.{ .name = "index", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "get_all_windows",
        .desc = "Return a list of all window and workspace node IDs in the current graph.",
        .params = &.{},
        .ret = "integer[]",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "set_gaps",
        .desc = "Set global gap sizes in pixels. inner_h/inner_v are gaps between windows; outer_h/outer_v are gaps between windows and screen edges.",
        .params = &.{
            .{ .name = "inner_h", .typ = "integer" },
            .{ .name = "inner_v", .typ = "integer" },
            .{ .name = "outer_h", .typ = "integer" },
            .{ .name = "outer_v", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "set_gaps_workspace",
        .desc = "Set gap sizes for a specific workspace node.",
        .params = &.{
            .{ .name = "id", .typ = "integer" },
            .{ .name = "inner_h", .typ = "integer" },
            .{ .name = "inner_v", .typ = "integer" },
            .{ .name = "outer_h", .typ = "integer" },
            .{ .name = "outer_v", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "set_pan",
        .desc = "Set the pan offset for the current workspace in pixels. Used with virtual canvases larger than the screen.",
        .params = &.{
            .{ .name = "x", .typ = "integer" },
            .{ .name = "y", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "get_pan",
        .desc = "Return the current pan offset as (x, y).",
        .params = &.{},
        .ret = "integer, integer",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "pan_by",
        .desc = "Pan the current workspace by a relative offset in pixels.",
        .params = &.{
            .{ .name = "dx", .typ = "integer" },
            .{ .name = "dy", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "set_virtual_size",
        .desc = "Set the virtual canvas size for the current workspace. Windows can be placed beyond the physical screen bounds and panned into view.",
        .params = &.{
            .{ .name = "width", .typ = "integer" },
            .{ .name = "height", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "set_lock_horizontal_resize",
        .desc = "Prevent tiled windows from being resized horizontally in the current workspace.",
        .params = &.{.{ .name = "locked", .typ = "boolean" }},
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "set_lock_vertical_resize",
        .desc = "Prevent tiled windows from being resized vertically in the current workspace.",
        .params = &.{.{ .name = "locked", .typ = "boolean" }},
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "set_pan_disabled",
        .desc = "Disable or enable mouse panning for the current workspace.",
        .params = &.{.{ .name = "disabled", .typ = "boolean" }},
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "set_pan_modifier",
        .desc = "Set the modifier key used for mouse panning.",
        .params = &.{.{ .name = "mod", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "set_pan_button",
        .desc = "Set the mouse button used for panning (default: BUTTON_MIDDLE).",
        .params = &.{.{ .name = "button", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "set_resize_modifier",
        .desc = "Set the modifier key used for mouse resize of tiled windows.",
        .params = &.{.{ .name = "mod", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "set_float_modifier",
        .desc = "Set the modifier key used for dragging floating windows.",
        .params = &.{.{ .name = "mod", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "set_float_move_button",
        .desc = "Set the mouse button used to move floating windows (default: BUTTON_LEFT).",
        .params = &.{.{ .name = "button", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "set_float_resize_button",
        .desc = "Set the mouse button used to resize floating windows (default: BUTTON_RIGHT).",
        .params = &.{.{ .name = "button", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "get_layout",
        .desc =
        \\Return the current workspace's graph as a Lua table with:
        \\  nodes    — array of all node tables
        \\  windows  — array of window/workspace node ids
        \\  focused  — id of currently focused node, or nil
        \\  root     — id of the first container that's no split's child, or nil
        \\Each node table has: id, type, x, y, width, height, constraints, parent, parent_idx.
        \\parent is the id of the container whose split holds this node, or nil.
        \\parent_idx is its 1-based position among that split's children.
        ,
        .params = &.{},
        .ret = "{ nodes: table[], windows: integer[], focused: integer|nil, root: integer|nil }",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "set_layout",
        .desc =
        \\Apply a layout table to the current graph. Accepts the same format returned by get_layout.
        \\Clears all constraints on nodes present in the table, then applies the constraints
        \\described in each node's constraints array. Nodes are matched by id.
        \\Typically called after mutating the table returned by get_layout.
        ,
        .params = &.{.{ .name = "layout", .typ = "{ nodes: table[] }" }},
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "set_zoom",
        .desc = "Draw the current workspace zoomed out: 1 is normal, 0.5 shows twice as much of the canvas each way, 0 fits the whole canvas on screen. Windows are really resized (river and X11 can't scale them), and get their size back at 1. While zoomed, mouse move and resize are off; panning and click-to-focus work.",
        .params = &.{.{ .name = "zoom", .typ = "number" }},
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name = "get_zoom",
        .desc = "The current workspace's zoom; for 0 (fit), the factor that works out to.",
        .params = &.{},
        .ret = "number",
    },

    // =========================================================
    // Constraints
    // =========================================================
    .{
        .category = "Constraints",
        .name = "left_of",
        .desc =
        \\Constrain a so that a.right == b.left (a is immediately left of b).
        \\Positional constraints like this one are strong rather than required: when they
        \\conflict with others, the solver relaxes them instead of failing.
        ,
        .params = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Constraints",
        .name = "right_of",
        .desc = "Constrain a so that a.left == b.right (a is immediately right of b).",
        .params = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Constraints",
        .name = "above",
        .desc = "Constrain a so that a.bottom == b.top (a is immediately above b).",
        .params = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Constraints",
        .name = "below",
        .desc = "Constrain a so that a.top == b.bottom (a is immediately below b).",
        .params = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Constraints",
        .name = "align_left",
        .desc = "Constrain: a.x == b.x (left edges aligned).",
        .params = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Constraints",
        .name = "align_top",
        .desc = "Constrain: a.y == b.y (top edges aligned).",
        .params = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Constraints",
        .name = "align_right",
        .desc = "Constrain: a.right == b.right (right edges aligned).",
        .params = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Constraints",
        .name = "align_bottom",
        .desc = "Constrain: a.bottom == b.bottom (bottom edges aligned).",
        .params = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Constraints",
        .name = "equal_width",
        .desc = "Constrain: a.width == b.width. Strong, like the positional constraints.",
        .params = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Constraints",
        .name = "equal_height",
        .desc = "Constrain: a.height == b.height. Strong, like the positional constraints.",
        .params = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Constraints",
        .name = "fixed_ratio",
        .desc = "Constrain: width / height == ratio. Strong.",
        .params = &.{ .{ .name = "id", .typ = "integer" }, .{ .name = "ratio", .typ = "number" } },
        .ret = "nil",
    },
    .{
        .category = "Constraints",
        .name = "fixed_width",
        .desc = "Constrain: width == w. Coordinates are relative to the work area origin.",
        .params = &.{ .{ .name = "id", .typ = "integer" }, .{ .name = "w", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Constraints",
        .name = "fixed_height",
        .desc = "Constrain: height == h.",
        .params = &.{ .{ .name = "id", .typ = "integer" }, .{ .name = "h", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Constraints",
        .name = "fixed_x",
        .desc =
        \\Constrain: x == x. Coordinates are relative to the work area origin (0,0 = top-left of usable area after bars).
        \\The solver converts these to absolute screen coordinates internally.
        ,
        .params = &.{ .{ .name = "id", .typ = "integer" }, .{ .name = "x", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Constraints",
        .name = "fixed_y",
        .desc = "Constrain: y == y. See fixed_x for coordinate system notes.",
        .params = &.{ .{ .name = "id", .typ = "integer" }, .{ .name = "y", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Constraints",
        .name = "grid_cell",
        .desc =
        \\Place a node in a cell of a grid defined by a container node.
        \\col and row are 0-based. The container's geometry is divided into cols x rows equal cells.
        ,
        .params = &.{
            .{ .name = "id", .typ = "integer" },
            .{ .name = "col", .typ = "integer" },
            .{ .name = "row", .typ = "integer" },
            .{ .name = "cols", .typ = "integer" },
            .{ .name = "rows", .typ = "integer" },
            .{ .name = "container", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Constraints",
        .name = "grid_cell_abs",
        .desc = "Place a node at absolute pixel offsets within a container.",
        .params = &.{
            .{ .name = "id", .typ = "integer" },
            .{ .name = "x", .typ = "integer" },
            .{ .name = "y", .typ = "integer" },
            .{ .name = "w", .typ = "integer" },
            .{ .name = "h", .typ = "integer" },
            .{ .name = "container", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Constraints",
        .name = "split",
        .desc =
        \\Split a container atomically into N children along an axis.
        \\ratios is a table of N numbers that need not sum to 1 — they are normalized internally.
        \\This is the preferred way to divide space proportionally: it's one required constraint
        \\per child, where chaining left_of/right_of gives strong ones that can be relaxed.
        ,
        .params = &.{
            .{ .name = "container", .typ = "integer" },
            .{ .name = "axis", .typ = "'h'|'v'" },
            .{ .name = "ratios", .typ = "number[]" },
            .{ .name = "children", .typ = "integer[]" },
        },
        .ret = "nil",
    },
    .{
        .category = "Constraints",
        .name = "clear_constraints",
        .desc = "Remove all constraints from a node. Call this before adding new constraints when relaying out.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Constraints",
        .name = "remove_constraint",
        .desc = "Remove all constraints of a given type from a node.",
        .params = &.{
            .{ .name = "id", .typ = "integer" },
            .{ .name = "type", .typ = "'fixed_x'|'fixed_y'|'fixed_width'|'fixed_height'|'right_of'|'left_of'|'above'|'below'|'grid_cell'|'split'|'align_left'|'align_right'|'align_top'|'align_bottom'|'equal_width'|'equal_height'" },
        },
        .ret = "nil",
    },

    // =========================================================
    // Geometry
    // =========================================================
    .{
        .category = "Geometry",
        .name = "get_node_geometry",
        .desc = "Return the geometry of a node as a table with x, y, width, height fields (absolute screen coordinates), or nil if not found.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "{ x: integer, y: integer, width: integer, height: integer }|nil",
    },
    .{
        .category = "Geometry",
        .name = "get_node_info",
        .desc = "Return full info for a node: x, y, width, height, type, floating.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "{ x: integer, y: integer, width: integer, height: integer, type: string, floating: boolean }|nil",
    },
    .{
        .category = "Geometry",
        .name = "get_node_type",
        .desc = "Return the type of a node: 'window', 'empty', 'group' or 'workspace', or nil if not found.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "'window'|'empty'|'workspace'|'workspace'|nil",
    },
    .{
        .category = "Geometry",
        .name = "get_cursor_pos",
        .desc = "Return the cursor position as (x, y) in absolute screen coordinates.",
        .params = &.{},
        .ret = "integer, integer",
    },
    .{
        .category = "Geometry",
        .name = "get_cursor_relative_to_focused",
        .desc = "Return the cursor offset from the center of the focused window as (dx, dy). Useful in arrangers for split direction hinting.",
        .params = &.{},
        .ret = "integer, integer",
    },
    .{
        .category = "Geometry",
        .name = "warp_cursor",
        .desc = "Warp the cursor to absolute screen coordinates.",
        .params = &.{
            .{ .name = "x", .typ = "integer" },
            .{ .name = "y", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Geometry",
        .name = "warp_cursor_to_node",
        .desc = "Warp the cursor to the center of a node.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Geometry",
        .name = "get_mouse_node",
        .desc = "Return the ID of the smallest node under the cursor, or nil.",
        .params = &.{},
        .ret = "integer|nil",
    },
    .{
        .category = "Geometry",
        .name = "resize_edge",
        .desc = "Move an edge of a specific node by delta pixels, adjusting constraints accordingly.",
        .params = &.{
            .{ .name = "id", .typ = "integer" },
            .{ .name = "dir", .typ = "'left'|'right'|'up'|'down'" },
            .{ .name = "delta", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Geometry",
        .name = "resize_corner",
        .desc = "Move a corner of a specific node by (delta_x, delta_y) pixels.",
        .params = &.{
            .{ .name = "id", .typ = "integer" },
            .{ .name = "delta_x", .typ = "integer" },
            .{ .name = "delta_y", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Geometry",
        .name = "resize_focused_edge",
        .desc = "Move an edge of the focused node by delta pixels.",
        .params = &.{
            .{ .name = "dir", .typ = "'left'|'right'|'up'|'down'" },
            .{ .name = "delta", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Geometry",
        .name = "resize_focused_corner",
        .desc = "Move a corner of the focused node.",
        .params = &.{
            .{ .name = "delta_x", .typ = "integer" },
            .{ .name = "delta_y", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Geometry",
        .name = "float_left_of",
        .desc = "Move floating window a so its right edge touches b's left edge, aligning their top edges. Resolves and flushes immediately.",
        .params = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Geometry",
        .name = "float_right_of",
        .desc = "Move floating window a so its left edge touches b's right edge, aligning their top edges. Resolves and flushes immediately.",
        .params = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Geometry",
        .name = "float_above",
        .desc = "Move floating window a so its bottom edge touches b's top edge, aligning their left edges. Resolves and flushes immediately.",
        .params = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Geometry",
        .name = "float_below",
        .desc = "Move floating window a so its top edge touches b's bottom edge, aligning their left edges. Resolves and flushes immediately.",
        .params = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Geometry",
        .name = "float_equal_width",
        .desc = "Constrain floating window a to have the same width as b. Additive — combine with positional constraints. Resolves and flushes immediately.",
        .params = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Geometry",
        .name = "float_equal_height",
        .desc = "Constrain floating window a to have the same height as b. Additive — combine with positional constraints. Resolves and flushes immediately.",
        .params = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Geometry",
        .name = "float_align_left",
        .desc = "Constrain floating window a so its left edge aligns with b's left edge. Resolves and flushes immediately.",
        .params = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Geometry",
        .name = "float_align_top",
        .desc = "Constrain floating window a so its top edge aligns with b's top edge. Resolves and flushes immediately.",
        .params = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Geometry",
        .name = "float_align_right",
        .desc = "Constrain floating window a so its right edge aligns with b's right edge. Resolves and flushes immediately.",
        .params = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Geometry",
        .name = "float_align_bottom",
        .desc = "Constrain floating window a so its bottom edge aligns with b's bottom edge. Resolves and flushes immediately.",
        .params = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Geometry",
        .name = "float_clear_constraints",
        .desc = "Remove all constraints from a floating window, freeing it to move independently. Resolves and flushes immediately.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "nil",
    },

    // =========================================================
    // Appearance
    // =========================================================
    .{
        .category = "Appearance",
        .name = "set_border_width",
        .desc = "Set the window border width in pixels.",
        .params = &.{.{ .name = "width", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Appearance",
        .name = "set_default_focused_border_color",
        .desc = "Set the default border color for focused windows (0xRRGGBB).",
        .params = &.{.{ .name = "color", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Appearance",
        .name = "set_default_unfocused_border_color",
        .desc = "Set the default border color for unfocused windows (0xRRGGBB).",
        .params = &.{.{ .name = "color", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Appearance",
        .name = "set_argb_frames",
        .desc = "Allow 32-bit (translucent) windows to get ARGB frames. When false, every newly mapped window gets a normal-depth frame and loses translucency. Default: true.",
        .params = &.{.{ .name = "enabled", .typ = "boolean" }},
        .ret = "nil",
    },
    .{
        .category = "Appearance",
        .name = "force_rgb_frames",
        .desc = "Always give windows matching this WM_CLASS class or instance a normal-depth frame, even if they are 32-bit. Works around clients that misbehave inside ARGB frames. Applies to windows mapped after the call.",
        .params = &.{.{ .name = "class", .typ = "string" }},
        .ret = "nil",
    },
    .{
        .category = "Appearance",
        .name = "set_default_urgent_border_color",
        .desc = "Set the border color used for windows with the urgency hint (0xRRGGBB).",
        .params = &.{.{ .name = "color", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Appearance",
        .name = "set_node_focused_border_color",
        .desc = "Override the focused border color for a specific node (0xRRGGBB).",
        .params = &.{ .{ .name = "id", .typ = "integer" }, .{ .name = "color", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Appearance",
        .name = "set_node_unfocused_border_color",
        .desc = "Override the unfocused border color for a specific node (0xRRGGBB).",
        .params = &.{ .{ .name = "id", .typ = "integer" }, .{ .name = "color", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Appearance",
        .name = "set_preview_colors",
        .desc = "Set the colors used when drawing workspace preview thumbnails. Colors are 0xRRGGBB.",
        .params = &.{
            .{ .name = "bg", .typ = "integer" },
            .{ .name = "win_bg", .typ = "integer" },
            .{ .name = "border", .typ = "integer" },
            .{ .name = "text", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Appearance",
        .name = "set_preview_colors_workspace",
        .desc = "Override the preview colors for a specific workspace node. Falls back to global preview colors for any value not set.",
        .params = &.{
            .{ .name = "id", .typ = "integer" },
            .{ .name = "bg", .typ = "integer" },
            .{ .name = "win_bg", .typ = "integer" },
            .{ .name = "border", .typ = "integer" },
            .{ .name = "text", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Appearance",
        .name = "set_preview_font",
        .desc = "Set the Xft font name used for labels in workspace preview thumbnails (e.g. \"monospace:pixelsize=10\"). Falls back to a built-in font if the name can't be opened.",
        .params = &.{
            .{ .name = "font", .typ = "string" },
        },
        .ret = "nil",
    },
    .{
        .category = "Appearance",
        .name = "set_preview_font_workspace",
        .desc = "Override the preview label font for a specific workspace node (e.g. \"monospace:pixelsize=10\"). Pass an empty string to clear the override and fall back to the global preview font.",
        .params = &.{
            .{ .name = "id", .typ = "integer" },
            .{ .name = "font", .typ = "string" },
        },
        .ret = "nil",
    },
    .{
        .category = "Appearance",
        .name = "set_preview_max_icon_size",
        .desc = "Cap the maximum pixel size of window icons drawn in preview thumbnails. Icons otherwise scale with the thumbnail size. Pass 0 to remove the cap.",
        .params = &.{
            .{ .name = "size", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Appearance",
        .name = "set_node_border_side_color",
        .desc = "Set the color of a single border side for a node. side is 'top', 'bottom', 'left', or 'right'. Overrides the base border color for that side only. Pass 0xRRGGBB.",
        .params = &.{
            .{ .name = "id", .typ = "integer" },
            .{ .name = "side", .typ = "'top'|'bottom'|'left'|'right'" },
            .{ .name = "color", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Appearance",
        .name = "clear_node_border_side_colors",
        .desc = "Clear all per-side border color overrides for a node, reverting to the base focused/unfocused color on all sides.",
        .params = &.{
            .{ .name = "id", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Appearance",
        .name = "set_border_side_colors_focused_only",
        .desc = "When true, per-side border color overrides are only shown on the focused window. Unfocused windows show their base unfocused color on all sides. Default: true.",
        .params = &.{.{ .name = "enabled", .typ = "boolean" }},
        .ret = "nil",
    },
    .{
        .category = "Appearance",
        .name = "clear_node_focused_border_color",
        .desc = "Clear the per-node focused border color override, reverting to the default.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Appearance",
        .name = "clear_node_unfocused_border_color",
        .desc = "Clear the per-node unfocused border color override, reverting to the default.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Appearance",
        .name = "set_animation",
        .desc = "Set animation duration and curve (currently river only)",
        .params = &.{
            .{ .name = "duration_ms", .typ = "integer" },
            .{ .name = "curve", .typ = "string|number[]|fun(t: number): number" },
        },
        .ret = "nil",
    },
    .{
        .name = "set_indicator_color",
        .category = "Appearance",
        .desc = "Set the indicator color shared by every node. Indicators already shown are recolored immediately.",
        .params = &.{
            .{ .name = "color", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .name = "set_node_indicator",
        .category = "Appearance",
        .desc = "Draw one side of a node's border in the indicator color, replacing its previous indicator side. Takes precedence over that side's own color, and shows only when side colors do (see set_border_side_colors_focused_only).",
        .params = &.{
            .{ .name = "id", .typ = "integer" },
            .{ .name = "side", .typ = "'top'|'bottom'|'left'|'right'" },
        },
        .ret = "nil",
    },
    .{
        .name = "clear_node_indicator",
        .category = "Appearance",
        .desc = "Remove a node's indicator.",
        .params = &.{
            .{ .name = "id", .typ = "integer" },
        },
        .ret = "nil",
    },

    // =========================================================
    // Rules
    // =========================================================
    .{
        .category = "Rules",
        .name = "add_rule",
        .desc =
        \\Register a global window rule. Rules fire for every window regardless of arranger.
        \\The function receives (event, id) where event is one of:
        \\  'pre_map' — fires before the arranger places the window (use for float/fullscreen rules)
        \\  'map'     — fires after the arranger places the window
        \\  'unmap'   — fires when the window is removed from the layout (e.g. closed or floating)
        \\  'prop'    — fires when WM_CLASS or window title changes (for apps that set class late)
        \\Returns a handle that can be passed to remove_rule.
        ,
        .params = &.{.{ .name = "fn", .typ = "fun(event: string, id: integer)" }},
        .ret = "integer",
    },
    .{
        .category = "Rules",
        .name = "remove_rule",
        .desc = "Remove a previously registered rule by its handle.",
        .params = &.{.{ .name = "handle", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Rules",
        .name = "set_reparent_strategy",
        .desc = "Set the reparenting strategy for a node when it is removed. 'promote' promotes its sibling into its container slot, 'remove' removes the node entirely, 'empty' leaves an empty slot. Pass nil to clear.",
        .params = &.{
            .{ .name = "id", .typ = "integer" },
            .{ .name = "strategy", .typ = "'promote'|'remove'|'empty'|nil" },
        },
        .ret = "nil",
    },
    .{
        .category = "Appearance",
        .name = "get_node_border_side_colors",
        .desc = "Return a table with the per-side border color overrides for a node. Only sides that have been explicitly set are present. Keys are 'top', 'bottom', 'left', 'right'. Returns nil if the node is not found.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "{ top: integer?, bottom: integer?, left: integer?, right: integer? }|nil",
    },

    // =========================================================
    // Node Graph
    // =========================================================
    .{
        .category = "Node Graph",
        .name = "create_container",
        .desc = "Create an empty container node in the current graph. Containers have no X window — they exist purely to define geometry for constraint targets.",
        .params = &.{},
        .ret = "integer",
    },
    .{
        .category = "Node Graph",
        .name = "destroy_container",
        .desc = "Remove an empty container node from the graph.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Node Graph",
        .name = "create_root_node",
        .desc = "Create a full-screen empty container (width=screen_width, height=screen_height).",
        .params = &.{},
        .ret = "integer",
    },
    .{
        .category = "Node Graph",
        .name = "create_empty_node",
        .desc = "Create an unconstrained empty node with zero initial geometry.",
        .params = &.{},
        .ret = "integer",
    },
    .{
        .category = "Node Graph",
        .name = "remove_node",
        .desc = "Remove a node from the graph entirely, freeing it.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Node Graph",
        .name = "unregister_node",
        .desc = "Remove a node from the ID registry without freeing it. Use with care.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Node Graph",
        .name = "set_node_empty",
        .desc = "Clear a node's window content, making it an empty node.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Node Graph",
        .name = "set_node_window",
        .desc = "Assign an X window to a node.",
        .params = &.{ .{ .name = "id", .typ = "integer" }, .{ .name = "win", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Node Graph",
        .name = "move_window_to_node",
        .desc = "Move the window from src node to dst node.",
        .params = &.{ .{ .name = "src", .typ = "integer" }, .{ .name = "dst", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Node Graph",
        .name = "reparent",
        .desc = "Make child fill parent entirely via a 1x1 grid_cell constraint.",
        .params = &.{ .{ .name = "child", .typ = "integer" }, .{ .name = "parent", .typ = "integer" } },
        .ret = "nil",
    },
    .{
        .category = "Node Graph",
        .name = "get_container_of",
        .desc = "Return the container ID that a node is grid_cell'd into, or nil.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "integer|nil",
    },
    .{
        .category = "Node Graph",
        .name = "get_split_ratios",
        .desc = "Return the current split ratios of a container node as a table, or nil if the node has no split constraint.",
        .params = &.{.{ .name = "id", .typ = "integer" }},
        .ret = "number[]|nil",
    },

    // =========================================================
    // Input
    // =========================================================
    .{
        .category = "Input",
        .name = "set_keyboard_layout",
        .desc = "Set the XKB keymap for all keyboards. Comma-separated layouts give a multi-layout keymap (\"us,pt\"); options like \"grp:alt_shift_toggle\" add a switching key. variant, options and model may be omitted.",
        .params = &.{
            .{ .name = "layout", .typ = "string" },
            .{ .name = "variant", .typ = "string?" },
            .{ .name = "options", .typ = "string?" },
            .{ .name = "model", .typ = "string?" },
        },
        .ret = "nil",
    },
    .{
        .category = "Input",
        .name = "set_keyboard_layout_index",
        .desc = "Switch to the layout at this 0-based index within the current keymap (\"us,pt\": 0 = us, 1 = pt).",
        .params = &.{.{ .name = "index", .typ = "integer" }},
        .ret = "nil",
    },
    .{
        .category = "Input",
        .name = "read_line",
        .desc = "Open the input bar at the top of the screen and read a line, StumpWM style. fn gets the text on Enter; Escape closes the bar without calling it (with vi keys, Escape from normal mode). While it's open every key goes to the bar, so binds don't fire.",
        .params = &.{
            .{ .name = "prompt", .typ = "string" },
            .{ .name = "fn", .typ = "fun(text: string)" },
            .{ .name = "initial", .typ = "string?" },
        },
        .ret = "nil",
    },
    .{
        .category = "Input",
        .name = "set_prompt_keys",
        .desc = "Editing keys for the input bar: 'emacs' (readline's; Escape cancels) or 'vi' (insert and normal modes, counts, motions, d/c/y, undo, j/k for history). Default: 'emacs'.",
        .params = &.{.{ .name = "keys", .typ = "'emacs'|'vi'" }},
        .ret = "nil",
    },
    .{
        .category = "Input",
        .name = "message",
        .desc = "Show text in the input bar for timeout_ms milliseconds (0: 3 seconds). Ignored while a line is being typed.",
        .params = &.{
            .{ .name = "text", .typ = "string" },
            .{ .name = "timeout_ms", .typ = "integer" },
        },
        .ret = "nil",
    },

    // =========================================================
    // Debug
    // =========================================================
    .{
        .category = "Debug",
        .name = "print_graph",
        .desc = "Return a string representation of the current graph showing nodes, geometry, and constraint relationships as labeled arrows. Recurses into nested workspaces. Use with quack: quack print_graph | jq -r '.result'",
        .params = &.{},
        .ret = "string",
    },
    .{
        .category = "Debug",
        .name = "print_graph_pretty",
        .desc = "The current workspace drawn to scale as boxes: windows, floating windows, groups (with what's in them) and workspace previews, each labelled with its id, and the focused one marked *. The whole canvas is drawn, off-screen parts of a scrolling layout included.",
        .params = &.{
            .{ .name = "cols", .typ = "integer?" },
            .{ .name = "rows", .typ = "integer?" },
        },
        .ret = "string",
    },
};
