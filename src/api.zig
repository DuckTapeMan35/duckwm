pub const Param = struct {
    name: []const u8,
    typ:  []const u8,
};

pub const ApiEntry = struct {
    name:     []const u8,
    desc:     []const u8,
    params:   []const Param,
    ret:      []const u8,
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
    "Layout & Arrangers",
    "Constraints",
    "Geometry",
    "Appearance",
    "Rules",
    "Node Graph",
    "Debug",
};

pub const constants = [_]Constant{
    .{ .name = "MOD_SUPER",         .desc = "Mod4 (Super/Win key)" },
    .{ .name = "MOD_ALT",           .desc = "Mod1 (Alt key)" },
    .{ .name = "MOD_SHIFT",         .desc = "Shift modifier" },
    .{ .name = "MOD_CTRL",          .desc = "Control modifier" },
    .{ .name = "MOD_MOD2",          .desc = "Mod2 (usually NumLock)" },
    .{ .name = "MOD_MOD3",          .desc = "Mod3" },
    .{ .name = "MOD_MOD5",          .desc = "Mod5 (usually AltGr)" },
    .{ .name = "BUTTON_LEFT",        .desc = "Left mouse button (1)" },
    .{ .name = "BUTTON_MIDDLE",      .desc = "Middle mouse button (2)" },
    .{ .name = "BUTTON_RIGHT",       .desc = "Right mouse button (3)" },
    .{ .name = "BUTTON_SCROLL_UP",   .desc = "Scroll wheel up (4)" },
    .{ .name = "BUTTON_SCROLL_DOWN", .desc = "Scroll wheel down (5)" },
};

pub const entries = [_]ApiEntry{

    // =========================================================
    // Core
    // =========================================================
    .{
        .category = "Core",
        .name     = "quit",
        .desc     = "Exit the window manager cleanly.",
        .params   = &.{},
        .ret      = "nil",
    },
    .{
        .category = "Core",
        .name     = "reload_config",
        .desc     = "Reload the Lua config file. The Lua VM is reset, all keybindings and rules are cleared, and the config is re-executed from scratch. Arrangers are re-mapped over existing windows.",
        .params   = &.{},
        .ret      = "nil",
    },
    .{
        .category = "Core",
        .name     = "reload_visuals",
        .desc     = "Re-run the config with only visual setters active. Faster than a full reload — use for live theming.",
        .params   = &.{},
        .ret      = "nil",
    },
    .{
        .category = "Core",
        .name     = "setenv",
        .desc     = "Set an environment variable in the WM process. All subsequently spawned windows inherit it.",
        .params   = &.{
            .{ .name = "key", .typ = "string" },
            .{ .name = "val", .typ = "string" },
        },
        .ret = "nil",
    },
    .{
        .category = "Core",
        .name     = "spawn",
        .desc     = "Spawn a subprocess. The argv table must contain at least one string (the executable path). The process is detached from the WM.",
        .params   = &.{ .{ .name = "argv", .typ = "string[]" } },
        .ret      = "nil",
    },
    .{
        .category = "Core",
        .name     = "exec_once",
        .desc     = "Spawn a subprocess at startup only. Calls after startup_done is set are ignored. Use for autostart entries.",
        .params   = &.{ .{ .name = "argv", .typ = "string[]" } },
        .ret      = "nil",
    },
    .{
        .category = "Core",
        .name     = "set_cursor_theme",
        .desc     = "Set the X11 cursor theme and size. Sets XCURSOR_THEME/XCURSOR_SIZE env vars and the RESOURCE_MANAGER root window property so both env-aware and X11 apps pick it up.",
        .params   = &.{
            .{ .name = "theme", .typ = "string" },
            .{ .name = "size",  .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Core",
        .name     = "screen_width",
        .desc     = "Return the total screen width in pixels.",
        .params   = &.{},
        .ret      = "integer",
    },
    .{
        .category = "Core",
        .name     = "screen_height",
        .desc     = "Return the total screen height in pixels.",
        .params   = &.{},
        .ret      = "integer",
    },
    .{
        .category = "Core",
        .name     = "get_work_area",
        .desc     = "Return the usable work area as (x, y, width, height), accounting for docks and bars that have set _NET_WM_STRUT_PARTIAL.",
        .params   = &.{},
        .ret      = "integer, integer, integer, integer",
    },

    // =========================================================
    // Keybindings
    // =========================================================
    .{
        .category = "Keybindings",
        .name     = "bind",
        .desc     = "Register a keybinding. mod is a bitmask of modifier constants (e.g. MOD_SUPER | MOD_SHIFT). key is an X11 keysym name (e.g. 'Return', 'h', 'F11'). The function is called with no arguments when the key is pressed.",
        .params   = &.{
            .{ .name = "mod", .typ = "integer" },
            .{ .name = "key", .typ = "string" },
            .{ .name = "fn",  .typ = "function" },
        },
        .ret = "nil",
    },

    // =========================================================
    // Window Management
    // =========================================================
    .{
        .category = "Window Management",
        .name     = "kill_client",
        .desc     = "Send WM_DELETE_WINDOW to the focused client. If the client does not support it, it is killed with XKillClient.",
        .params   = &.{},
        .ret      = "nil",
    },
    .{
        .category = "Window Management",
        .name     = "toggle_floating",
        .desc     = "Toggle floating mode on the focused window. Floating windows are excluded from tiling and can be freely moved and resized.",
        .params   = &.{},
        .ret      = "nil",
    },
    .{
        .category = "Window Management",
        .name     = "set_floating",
        .desc     = "Set floating state of a window directly. Pass false to re-integrate into tiling via the arranger.",
        .params   = &.{
            .{ .name = "id",  .typ = "integer" },
            .{ .name = "val", .typ = "boolean" },
        },
        .ret = "nil",
    },
    .{
        .category = "Window Management",
        .name     = "toggle_fullscreen",
        .desc     = "Toggle fullscreen on the focused window. The window is moved to cover the entire screen including the work area.",
        .params   = &.{},
        .ret      = "nil",
    },
    .{
        .category = "Window Management",
        .name     = "set_fullscreen",
        .desc     = "Set fullscreen state on a specific window node. Primarily for use in window rules.",
        .params   = &.{
            .{ .name = "id",  .typ = "integer" },
            .{ .name = "val", .typ = "boolean" },
        },
        .ret = "nil",
    },
    .{
        .category = "Window Management",
        .name     = "hide_window",
        .desc     = "Unmap a window's frame without destroying it. The node remains in the graph.",
        .params   = &.{ .{ .name = "id", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Window Management",
        .name     = "show_window",
        .desc     = "Map and raise a previously hidden window.",
        .params   = &.{ .{ .name = "id", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Window Management",
        .name     = "get_window_class",
        .desc     = "Return the WM_CLASS (res_class) of a window node, or nil if unavailable.",
        .params   = &.{ .{ .name = "id", .typ = "integer" } },
        .ret      = "string|nil",
    },
    .{
        .category = "Window Management",
        .name     = "get_window_name",
        .desc     = "Return the WM_NAME (title) of a window node, or nil if unavailable.",
        .params   = &.{ .{ .name = "id", .typ = "integer" } },
        .ret      = "string|nil",
    },
    .{
        .category = "Window Management",
        .name     = "get_window_pid",
        .desc     = "Return the PID of a window node via _NET_WM_PID, or nil if the property is not set.",
        .params   = &.{ .{ .name = "id", .typ = "integer" } },
        .ret      = "integer|nil",
    },
    .{
        .category = "Window Management",
        .name     = "get_urgent",
        .desc     = "Return whether a window has the urgency hint set.",
        .params   = &.{ .{ .name = "id", .typ = "integer" } },
        .ret      = "boolean",
    },
    .{
        .category = "Window Management",
        .name     = "set_urgent",
        .desc     = "Set or clear the urgency flag on a window node.",
        .params   = &.{
            .{ .name = "id",  .typ = "integer" },
            .{ .name = "val", .typ = "boolean" },
        },
        .ret = "nil",
    },

    // =========================================================
    // Focus
    // =========================================================
    .{
        .category = "Focus",
        .name     = "focus",
        .desc     = "Focus a specific node by ID.",
        .params   = &.{ .{ .name = "id", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Focus",
        .name     = "focus_left",
        .desc     = "Move focus to the nearest window to the left of the focused window, using focus edges.",
        .params   = &.{},
        .ret      = "nil",
    },
    .{
        .category = "Focus",
        .name     = "focus_right",
        .desc     = "Move focus to the nearest window to the right of the focused window, using focus edges.",
        .params   = &.{},
        .ret      = "nil",
    },
    .{
        .category = "Focus",
        .name     = "focus_up",
        .desc     = "Move focus to the nearest window above the focused window, using focus edges.",
        .params   = &.{},
        .ret      = "nil",
    },
    .{
        .category = "Focus",
        .name     = "focus_down",
        .desc     = "Move focus to the nearest window below the focused window, using focus edges.",
        .params   = &.{},
        .ret      = "nil",
    },
    .{
        .category = "Focus",
        .name     = "get_focused",
        .desc     = "Return the ID of the currently focused node, or nil if nothing is focused.",
        .params   = &.{},
        .ret      = "integer|nil",
    },
    .{
        .category = "Focus",
        .name     = "set_focus_follows_mouse",
        .desc     = "Enable or disable focus-follows-mouse. When enabled, moving the cursor into a window automatically focuses it.",
        .params   = &.{ .{ .name = "enabled", .typ = "boolean" } },
        .ret      = "nil",
    },
    .{
        .category = "Focus",
        .name     = "set_click_to_focus",
        .desc     = "Enable or disable click-to-focus mode. When enabled, clicking a window focuses it even if focus-follows-mouse is off.",
        .params   = &.{ .{ .name = "enabled", .typ = "boolean" } },
        .ret      = "nil",
    },
    .{
        .category = "Focus",
        .name     = "exchange_left",
        .desc     = "Swap the focused node's contents with the node to its left.",
        .params   = &.{},
        .ret      = "nil",
    },
    .{
        .category = "Focus",
        .name     = "exchange_right",
        .desc     = "Swap the focused node's contents with the node to its right.",
        .params   = &.{},
        .ret      = "nil",
    },
    .{
        .category = "Focus",
        .name     = "exchange_up",
        .desc     = "Swap the focused node's contents with the node above.",
        .params   = &.{},
        .ret      = "nil",
    },
    .{
        .category = "Focus",
        .name     = "exchange_down",
        .desc     = "Swap the focused node's contents with the node below.",
        .params   = &.{},
        .ret      = "nil",
    },

    // =========================================================
    // Workspaces
    // =========================================================
    .{
        .category = "Workspaces",
        .name     = "switch_to_workspace",
        .desc     = "Switch to a workspace by 1-based index at the current nesting level. Creates missing workspaces on demand.",
        .params   = &.{ .{ .name = "index", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Workspaces",
        .name     = "send_to_workspace",
        .desc     = "Send a window node to a workspace by 1-based index at the current nesting level. Creates missing workspaces on demand.",
        .params   = &.{
            .{ .name = "node_id", .typ = "integer" },
            .{ .name = "index",   .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Workspaces",
        .name     = "get_workspace",
        .desc     = "Return the node ID of the nth workspace (1-based) in the current graph, or nil.",
        .params   = &.{ .{ .name = "index", .typ = "integer" } },
        .ret      = "integer|nil",
    },
    .{
        .category = "Workspaces",
        .name     = "get_current_workspace",
        .desc     = "Return the 1-based number of the currently active workspace.",
        .params   = &.{},
        .ret      = "integer|nil",
    },
    .{
        .category = "Workspaces",
        .name     = "get_workspaces_at_level",
        .desc     = "Return a list of workspace numbers at the current nesting level that have content or are active.",
        .params   = &.{},
        .ret      = "integer[]",
    },
    .{
        .category = "Workspaces",
        .name     = "set_workspace_switch_mode",
        .desc     = "Set behaviour when switching to the already active workspace. 'none' does nothing; 'previous' switches to the previously active workspace.",
        .params   = &.{ .{ .name = "mode", .typ = "'none'|'previous'" } },
        .ret      = "nil",
    },
    .{
        .category = "Workspaces",
        .name     = "create_nested_workspace",
        .desc     = "Create a new nested workspace node in the current graph. Returns its node ID. The workspace is empty and uses the default arranger.",
        .params   = &.{},
        .ret      = "integer",
    },
    .{
        .category = "Workspaces",
        .name     = "enter_nested",
        .desc     = "Enter the focused workspace node, making it the active graph.",
        .params   = &.{},
        .ret      = "nil",
    },
    .{
        .category = "Workspaces",
        .name     = "leave_nested",
        .desc     = "Leave the current nested workspace and return to the parent graph. Blocked at the top level.",
        .params   = &.{},
        .ret      = "nil",
    },
    .{
        .category = "Workspaces",
        .name     = "enter_nested_by_id",
        .desc     = "Enter a workspace node by its node ID.",
        .params   = &.{ .{ .name = "id", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Workspaces",
        .name     = "enter_workspace_by_id",
        .desc     = "Enter a workspace node by its node ID (alias for enter_nested_by_id, used for top-level workspace switching).",
        .params   = &.{ .{ .name = "id", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Workspaces",
        .name     = "get_current_level",
        .desc     = "Return the nesting level of the current workspace. Level 1 is the top-level workspace layer; higher numbers mean deeper nesting.",
        .params   = &.{},
        .ret      = "integer",
    },
    .{
        .category = "Workspaces",
        .name     = "get_node_level",
        .desc     = "Return the nesting level of the graph that owns a node, or nil if the node is not found.",
        .params   = &.{ .{ .name = "id", .typ = "integer" } },
        .ret      = "integer|nil",
    },
    .{
        .category = "Workspaces",
        .name     = "get_workspace_positions",
        .desc     = "Return a list of positional indices (1-based) for all workspaces at the current level, sorted by creation order. Use this for bar display — index N corresponds to switch_to_workspace(N).",
        .params   = &.{},
        .ret      = "integer[]",
    },
    .{
        .category = "Workspaces",
        .name     = "get_current_workspace_position",
        .desc     = "Return the positional index (1-based) of the currently active workspace, matching switch_to_workspace. Returns nil if not found.",
        .params   = &.{},
        .ret      = "integer|nil",
    },

    // =========================================================
    // Layout & Arrangers
    // =========================================================
    .{
        .category = "Layout & Arrangers",
        .name     = "set_arranger",
        .desc     =
            \\Switch the arranger for the current workspace. factory is a function that returns an arranger function. The arranger function receives (event, id, prev_id) where event is one of:
            \\  'map'     — a window was added to the layout
            \\  'unmap'   — a window was removed from the layout
            \\  'resize'  — a window was resized by the user
            \\  'pre_map' — fires before 'map', before constraints are applied (use for setup)
            \\The arranger should set constraints on nodes using the constraint API.
        ,
        .params   = &.{
            .{ .name = "factory", .typ = "function" },
            .{ .name = "name",    .typ = "string?" },
        },
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name     = "set_default_arranger",
        .desc     = "Set the default arranger factory used for new workspaces.",
        .params   = &.{
            .{ .name = "fn",   .typ = "function" },
            .{ .name = "name", .typ = "string?" },
        },
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name     = "register_arranger",
        .desc     = "Set the arranger for a specific workspace node by ID.",
        .params   = &.{
            .{ .name = "workspace_id", .typ = "integer" },
            .{ .name = "factory",      .typ = "function" },
            .{ .name = "name",         .typ = "string?" },
        },
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name     = "get_arranger_name",
        .desc     = "Return the display name of the current workspace's arranger, or nil if none is set.",
        .params   = &.{},
        .ret      = "string|nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name     = "get_arranger_index",
        .desc     = "Return the arranger index stored on the current workspace. Used to track which arranger in a cycle is active.",
        .params   = &.{},
        .ret      = "integer",
    },
    .{
        .category = "Layout & Arrangers",
        .name     = "set_arranger_index",
        .desc     = "Set the arranger index on the current workspace.",
        .params   = &.{ .{ .name = "index", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name     = "get_all_windows",
        .desc     = "Return a list of all window and workspace node IDs in the current graph.",
        .params   = &.{},
        .ret      = "integer[]",
    },
    .{
        .category = "Layout & Arrangers",
        .name     = "set_gaps",
        .desc     = "Set global gap sizes in pixels. inner_h/inner_v are gaps between windows; outer_h/outer_v are gaps between windows and screen edges.",
        .params   = &.{
            .{ .name = "inner_h", .typ = "integer" },
            .{ .name = "inner_v", .typ = "integer" },
            .{ .name = "outer_h", .typ = "integer" },
            .{ .name = "outer_v", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name     = "set_gaps_workspace",
        .desc     = "Set gap sizes for a specific workspace node.",
        .params   = &.{
            .{ .name = "id",      .typ = "integer" },
            .{ .name = "inner_h", .typ = "integer" },
            .{ .name = "inner_v", .typ = "integer" },
            .{ .name = "outer_h", .typ = "integer" },
            .{ .name = "outer_v", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name     = "set_pan",
        .desc     = "Set the pan offset for the current workspace in pixels. Used with virtual canvases larger than the screen.",
        .params   = &.{
            .{ .name = "x", .typ = "integer" },
            .{ .name = "y", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name     = "get_pan",
        .desc     = "Return the current pan offset as (x, y).",
        .params   = &.{},
        .ret      = "integer, integer",
    },
    .{
        .category = "Layout & Arrangers",
        .name     = "pan_by",
        .desc     = "Pan the current workspace by a relative offset in pixels.",
        .params   = &.{
            .{ .name = "dx", .typ = "integer" },
            .{ .name = "dy", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name     = "set_virtual_size",
        .desc     = "Set the virtual canvas size for the current workspace. Windows can be placed beyond the physical screen bounds and panned into view.",
        .params   = &.{
            .{ .name = "width",  .typ = "integer" },
            .{ .name = "height", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name     = "set_lock_horizontal_resize",
        .desc     = "Prevent tiled windows from being resized horizontally in the current workspace.",
        .params   = &.{ .{ .name = "locked", .typ = "boolean" } },
        .ret      = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name     = "set_lock_vertical_resize",
        .desc     = "Prevent tiled windows from being resized vertically in the current workspace.",
        .params   = &.{ .{ .name = "locked", .typ = "boolean" } },
        .ret      = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name     = "set_pan_disabled",
        .desc     = "Disable or enable mouse panning for the current workspace.",
        .params   = &.{ .{ .name = "disabled", .typ = "boolean" } },
        .ret      = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name     = "set_pan_modifier",
        .desc     = "Set the modifier key used for mouse panning.",
        .params   = &.{ .{ .name = "mod", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name     = "set_pan_button",
        .desc     = "Set the mouse button used for panning (default: BUTTON_MIDDLE).",
        .params   = &.{ .{ .name = "button", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name     = "set_resize_modifier",
        .desc     = "Set the modifier key used for mouse resize of tiled windows.",
        .params   = &.{ .{ .name = "mod", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name     = "set_float_modifier",
        .desc     = "Set the modifier key used for dragging floating windows.",
        .params   = &.{ .{ .name = "mod", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name     = "set_float_move_button",
        .desc     = "Set the mouse button used to move floating windows (default: BUTTON_LEFT).",
        .params   = &.{ .{ .name = "button", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name     = "set_float_resize_button",
        .desc     = "Set the mouse button used to resize floating windows (default: BUTTON_RIGHT).",
        .params   = &.{ .{ .name = "button", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Layout & Arrangers",
        .name     = "get_layout",
        .desc     =
            \\Return the current graph as a rich Lua table with:
            \\  nodes    — array of all node tables
            \\  by_id    — map id -> node table (same objects as nodes, O(1) lookup)
            \\  windows  — array of window/workspace node ids
            \\  focused  — id of currently focused node, or nil
            \\  root     — id of root container node, or nil
            \\Each node table has: id, type, x, y, width, height, constraints, parent, parent_idx.
            \\parent is the id of the split container that owns this node, or nil if root.
            \\parent_idx is 1 or 2 indicating which child slot in the parent split.
        ,
        .params = &.{},
        .ret    = "{ nodes: node[], by_id: table, windows: integer[], focused: integer|nil, root: integer|nil }",
    },
    .{
    .category = "Layout & Arrangers",
        .name     = "set_layout",
        .desc     =
            \\Apply a layout table to the current graph. Accepts the same format returned by get_layout.
            \\Clears all constraints on nodes present in the table, then applies the constraints
            \\described in each node's constraints array. Nodes are matched by id.
            \\Typically called after mutating the table returned by get_layout.
        ,
        .params = &.{ .{ .name = "layout", .typ = "{ nodes: node[] }" } },
        .ret    = "nil",
    },

    // =========================================================
    // Constraints
    // =========================================================
    .{
        .category = "Constraints",
        .name     = "left_of",
        .desc     =
            \\Constrain a so that a.right == b.left (a is immediately left of b).
            \\The constraint solver is iterative and runs up to 50 passes. Constraints are applied
            \\in declaration order each pass until the layout converges. Circular constraints may
            \\not converge — avoid them.
        ,
        .params   = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Constraints",
        .name     = "right_of",
        .desc     = "Constrain a so that a.left == b.right (a is immediately right of b).",
        .params   = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Constraints",
        .name     = "above",
        .desc     = "Constrain a so that a.bottom == b.top (a is immediately above b).",
        .params   = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Constraints",
        .name     = "below",
        .desc     = "Constrain a so that a.top == b.bottom (a is immediately below b).",
        .params   = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Constraints",
        .name     = "align_left",
        .desc     = "Constrain: a.x == b.x (left edges aligned).",
        .params   = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Constraints",
        .name     = "align_top",
        .desc     = "Constrain: a.y == b.y (top edges aligned).",
        .params   = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Constraints",
        .name     = "align_right",
        .desc     = "Constrain: a.right == b.right (right edges aligned).",
        .params   = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Constraints",
        .name     = "align_bottom",
        .desc     = "Constrain: a.bottom == b.bottom (bottom edges aligned).",
        .params   = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Constraints",
        .name     = "equal_width",
        .desc     = "Constrain: a.width == b.width. Symmetric — applied via averaging each pass.",
        .params   = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Constraints",
        .name     = "equal_height",
        .desc     = "Constrain: a.height == b.height. Symmetric — applied via averaging each pass.",
        .params   = &.{ .{ .name = "a", .typ = "integer" }, .{ .name = "b", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Constraints",
        .name     = "fixed_ratio",
        .desc     = "Constrain: width / height == ratio. Applied each solver pass.",
        .params   = &.{ .{ .name = "id", .typ = "integer" }, .{ .name = "ratio", .typ = "number" } },
        .ret      = "nil",
    },
    .{
        .category = "Constraints",
        .name     = "fixed_width",
        .desc     = "Constrain: width == w. Coordinates are relative to the work area origin.",
        .params   = &.{ .{ .name = "id", .typ = "integer" }, .{ .name = "w", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Constraints",
        .name     = "fixed_height",
        .desc     = "Constrain: height == h.",
        .params   = &.{ .{ .name = "id", .typ = "integer" }, .{ .name = "h", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Constraints",
        .name     = "fixed_x",
        .desc     =
            \\Constrain: x == x. Coordinates are relative to the work area origin (0,0 = top-left of usable area after bars).
            \\The solver converts these to absolute screen coordinates internally.
        ,
        .params   = &.{ .{ .name = "id", .typ = "integer" }, .{ .name = "x", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Constraints",
        .name     = "fixed_y",
        .desc     = "Constrain: y == y. See fixed_x for coordinate system notes.",
        .params   = &.{ .{ .name = "id", .typ = "integer" }, .{ .name = "y", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Constraints",
        .name     = "grid_cell",
        .desc     =
            \\Place a node in a cell of a grid defined by a container node.
            \\col and row are 0-based. The container's geometry is divided into cols x rows equal cells.
            \\The last cell in each axis absorbs rounding pixels.
        ,
        .params   = &.{
            .{ .name = "id",        .typ = "integer" },
            .{ .name = "col",       .typ = "integer" },
            .{ .name = "row",       .typ = "integer" },
            .{ .name = "cols",      .typ = "integer" },
            .{ .name = "rows",      .typ = "integer" },
            .{ .name = "container", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Constraints",
        .name     = "grid_cell_abs",
        .desc     = "Place a node at absolute pixel offsets within a container.",
        .params   = &.{
            .{ .name = "id",        .typ = "integer" },
            .{ .name = "x",         .typ = "integer" },
            .{ .name = "y",         .typ = "integer" },
            .{ .name = "w",         .typ = "integer" },
            .{ .name = "h",         .typ = "integer" },
            .{ .name = "container", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Constraints",
        .name     = "split",
        .desc     =
            \\Split a container atomically into N children along an axis.
            \\ratios is a table of N numbers that need not sum to 1 — they are normalized internally.
            \\The last child absorbs rounding pixels. This is the preferred way to divide space
            \\proportionally; it is more efficient than chaining left_of/right_of constraints.
        ,
        .params   = &.{
            .{ .name = "container", .typ = "integer" },
            .{ .name = "axis",      .typ = "'h'|'v'" },
            .{ .name = "ratios",    .typ = "number[]" },
            .{ .name = "children",  .typ = "integer[]" },
        },
        .ret = "nil",
    },
    .{
        .category = "Constraints",
        .name     = "clear_constraints",
        .desc     = "Remove all constraints from a node. Call this before adding new constraints when relaying out.",
        .params   = &.{ .{ .name = "id", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Constraints",
        .name     = "remove_constraint",
        .desc     = "Remove all constraints of a given type from a node.",
        .params   = &.{
            .{ .name = "id",   .typ = "integer" },
            .{ .name = "type", .typ = "'fixed_x'|'fixed_y'|'fixed_width'|'fixed_height'|'right_of'|'left_of'|'above'|'below'|'grid_cell'|'split'|'align_left'|'align_right'|'align_top'|'align_bottom'|'equal_width'|'equal_height'" },
        },
        .ret = "nil",
    },

    // =========================================================
    // Geometry
    // =========================================================
    .{
        .category = "Geometry",
        .name     = "get_node_geometry",
        .desc     = "Return the geometry of a node as a table with x, y, width, height fields (absolute screen coordinates), or nil if not found.",
        .params   = &.{ .{ .name = "id", .typ = "integer" } },
        .ret      = "{ x: integer, y: integer, width: integer, height: integer }|nil",
    },
    .{
        .category = "Geometry",
        .name     = "get_node_info",
        .desc     = "Return full info for a node: x, y, width, height, type, floating.",
        .params   = &.{ .{ .name = "id", .typ = "integer" } },
        .ret      = "{ x: integer, y: integer, width: integer, height: integer, type: string, floating: boolean }|nil",
    },
    .{
        .category = "Geometry",
        .name     = "get_node_type",
        .desc     = "Return the type of a node: 'window', 'empty', or 'workspace', or nil if not found.",
        .params   = &.{ .{ .name = "id", .typ = "integer" } },
        .ret      = "'window'|'empty'|'workspace'|nil",
    },
    .{
        .category = "Geometry",
        .name     = "get_cursor_pos",
        .desc     = "Return the cursor position as (x, y) in absolute screen coordinates.",
        .params   = &.{},
        .ret      = "integer, integer",
    },
    .{
        .category = "Geometry",
        .name     = "get_cursor_relative_to_focused",
        .desc     = "Return the cursor offset from the center of the focused window as (dx, dy). Useful in arrangers for split direction hinting.",
        .params   = &.{},
        .ret      = "integer, integer",
    },
    .{
        .category = "Geometry",
        .name     = "warp_cursor",
        .desc     = "Warp the cursor to absolute screen coordinates.",
        .params   = &.{
            .{ .name = "x", .typ = "integer" },
            .{ .name = "y", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Geometry",
        .name     = "warp_cursor_to_node",
        .desc     = "Warp the cursor to the center of a node.",
        .params   = &.{ .{ .name = "id", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Geometry",
        .name     = "get_mouse_node",
        .desc     = "Return the ID of the smallest node under the cursor, or nil.",
        .params   = &.{},
        .ret      = "integer|nil",
    },
    .{
        .category = "Geometry",
        .name     = "resize_edge",
        .desc     = "Move an edge of a specific node by delta pixels, adjusting constraints accordingly.",
        .params   = &.{
            .{ .name = "id",    .typ = "integer" },
            .{ .name = "dir",   .typ = "'left'|'right'|'up'|'down'" },
            .{ .name = "delta", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Geometry",
        .name     = "resize_corner",
        .desc     = "Move a corner of a specific node by (delta_x, delta_y) pixels.",
        .params   = &.{
            .{ .name = "id",      .typ = "integer" },
            .{ .name = "delta_x", .typ = "integer" },
            .{ .name = "delta_y", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Geometry",
        .name     = "resize_focused_edge",
        .desc     = "Move an edge of the focused node by delta pixels.",
        .params   = &.{
            .{ .name = "dir",   .typ = "'left'|'right'|'up'|'down'" },
            .{ .name = "delta", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Geometry",
        .name     = "resize_focused_corner",
        .desc     = "Move a corner of the focused node.",
        .params   = &.{
            .{ .name = "delta_x", .typ = "integer" },
            .{ .name = "delta_y", .typ = "integer" },
        },
        .ret = "nil",
    },

    // =========================================================
    // Appearance
    // =========================================================
    .{
        .category = "Appearance",
        .name     = "set_border_width",
        .desc     = "Set the window border width in pixels.",
        .params   = &.{ .{ .name = "width", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Appearance",
        .name     = "set_default_focused_border_color",
        .desc     = "Set the default border color for focused windows (0xRRGGBB).",
        .params   = &.{ .{ .name = "color", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Appearance",
        .name     = "set_default_unfocused_border_color",
        .desc     = "Set the default border color for unfocused windows (0xRRGGBB).",
        .params   = &.{ .{ .name = "color", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Appearance",
        .name     = "set_default_urgent_border_color",
        .desc     = "Set the border color used for windows with the urgency hint (0xRRGGBB).",
        .params   = &.{ .{ .name = "color", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Appearance",
        .name     = "set_node_focused_border_color",
        .desc     = "Override the focused border color for a specific node (0xRRGGBB).",
        .params   = &.{ .{ .name = "id", .typ = "integer" }, .{ .name = "color", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Appearance",
        .name     = "set_node_unfocused_border_color",
        .desc     = "Override the unfocused border color for a specific node (0xRRGGBB).",
        .params   = &.{ .{ .name = "id", .typ = "integer" }, .{ .name = "color", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Appearance",
        .name     = "set_preview_colors",
        .desc     = "Set the colors used when drawing workspace preview thumbnails. Colors are 0xRRGGBB.",
        .params   = &.{
            .{ .name = "bg",     .typ = "integer" },
            .{ .name = "win_bg", .typ = "integer" },
            .{ .name = "border", .typ = "integer" },
            .{ .name = "text",   .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
    .category = "Appearance",
        .name     = "set_preview_colors_workspace",
        .desc     = "Override the preview colors for a specific workspace node. Falls back to global preview colors for any value not set.",
        .params   = &.{
            .{ .name = "id",     .typ = "integer" },
            .{ .name = "bg",     .typ = "integer" },
            .{ .name = "win_bg", .typ = "integer" },
            .{ .name = "border", .typ = "integer" },
            .{ .name = "text",   .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Appearance",
        .name     = "set_node_border_side_color",
        .desc     = "Set the color of a single border side for a node. side is 'top', 'bottom', 'left', or 'right'. Overrides the base border color for that side only. Pass 0xRRGGBB.",
        .params   = &.{
            .{ .name = "id",    .typ = "integer" },
            .{ .name = "side",  .typ = "'top'|'bottom'|'left'|'right'" },
            .{ .name = "color", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Appearance",
        .name     = "clear_node_border_side_colors",
        .desc     = "Clear all per-side border color overrides for a node, reverting to the base focused/unfocused color on all sides.",
        .params   = &.{
            .{ .name = "id", .typ = "integer" },
        },
        .ret = "nil",
    },
    .{
        .category = "Appearance",
        .name     = "set_border_side_colors_focused_only",
        .desc     = "When true, per-side border color overrides are only shown on the focused window. Unfocused windows show their base unfocused color on all sides. Default: false.",
        .params   = &.{ .{ .name = "enabled", .typ = "boolean" } },
        .ret      = "nil",
    },

    // =========================================================
    // Rules
    // =========================================================
    .{
        .category = "Rules",
        .name     = "add_rule",
        .desc     =
            \\Register a global window rule. Rules fire for every window regardless of arranger.
            \\The function receives (event, id) where event is one of:
            \\  'pre_map' — fires before the arranger places the window (use for float/fullscreen rules)
            \\  'map'     — fires after the arranger places the window
            \\  'prop'    — fires when WM_CLASS or window title changes (for apps that set class late)
            \\Returns a handle that can be passed to remove_rule.
        ,
        .params   = &.{ .{ .name = "fn", .typ = "function(event: string, id: integer)" } },
        .ret      = "integer",
    },
    .{
        .category = "Rules",
        .name     = "remove_rule",
        .desc     = "Remove a previously registered rule by its handle.",
        .params   = &.{ .{ .name = "handle", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Rules",
        .name     = "set_reparent_strategy",
        .desc     = "Set the reparenting strategy for a node when it is removed. 'promote' promotes its sibling into its container slot, 'remove' removes the node entirely, 'empty' leaves an empty slot. Pass nil to clear.",
        .params   = &.{
            .{ .name = "id",       .typ = "integer" },
            .{ .name = "strategy", .typ = "'promote'|'remove'|'empty'|nil" },
        },
        .ret = "nil",
    },

    // =========================================================
    // Node Graph
    // =========================================================
    .{
        .category = "Node Graph",
        .name     = "create_container",
        .desc     = "Create an empty container node in the current graph. Containers have no X window — they exist purely to define geometry for constraint targets.",
        .params   = &.{},
        .ret      = "integer",
    },
    .{
        .category = "Node Graph",
        .name     = "destroy_container",
        .desc     = "Remove an empty container node from the graph.",
        .params   = &.{ .{ .name = "id", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Node Graph",
        .name     = "create_root_node",
        .desc     = "Create a full-screen empty container (width=screen_width, height=screen_height).",
        .params   = &.{},
        .ret      = "integer",
    },
    .{
        .category = "Node Graph",
        .name     = "create_empty_node",
        .desc     = "Create an unconstrained empty node with zero initial geometry.",
        .params   = &.{},
        .ret      = "integer",
    },
    .{
        .category = "Node Graph",
        .name     = "remove_node",
        .desc     = "Remove a node from the graph entirely, freeing it.",
        .params   = &.{ .{ .name = "id", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Node Graph",
        .name     = "unregister_node",
        .desc     = "Remove a node from the ID registry without freeing it. Use with care.",
        .params   = &.{ .{ .name = "id", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Node Graph",
        .name     = "set_node_empty",
        .desc     = "Clear a node's window content, making it an empty node.",
        .params   = &.{ .{ .name = "id", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Node Graph",
        .name     = "set_node_window",
        .desc     = "Assign an X window to a node.",
        .params   = &.{ .{ .name = "id", .typ = "integer" }, .{ .name = "win", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Node Graph",
        .name     = "move_window_to_node",
        .desc     = "Move the window from src node to dst node.",
        .params   = &.{ .{ .name = "src", .typ = "integer" }, .{ .name = "dst", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Node Graph",
        .name     = "reparent",
        .desc     = "Make child fill parent entirely via a 1x1 grid_cell constraint.",
        .params   = &.{ .{ .name = "child", .typ = "integer" }, .{ .name = "parent", .typ = "integer" } },
        .ret      = "nil",
    },
    .{
        .category = "Node Graph",
        .name     = "get_container_of",
        .desc     = "Return the container ID that a node is grid_cell'd into, or nil.",
        .params   = &.{ .{ .name = "id", .typ = "integer" } },
        .ret      = "integer|nil",
    },
    .{
        .category = "Node Graph",
        .name     = "get_split_ratios",
        .desc     = "Return the current split ratios of a container node as a table, or nil if the node has no split constraint.",
        .params   = &.{ .{ .name = "id", .typ = "integer" } },
        .ret      = "number[]|nil",
    },

    // =========================================================
    // Debug
    // =========================================================
    .{
        .category = "Debug",
        .name     = "print_graph",
        .desc     = "Return a string representation of the current graph showing nodes, geometry, and constraint relationships as labeled arrows. Recurses into nested workspaces. Use with quack: quack print_graph | jq -r '.result'",
        .params   = &.{},
        .ret      = "string",
    },
};
