---@meta
wm = {}

--- Mod4 (Super/Win key)
---@type integer
wm.MOD_SUPER = 0

--- Mod1 (Alt key)
---@type integer
wm.MOD_ALT = 0

--- Shift modifier
---@type integer
wm.MOD_SHIFT = 0

--- Control modifier
---@type integer
wm.MOD_CTRL = 0

--- Mod2 (usually NumLock)
---@type integer
wm.MOD_MOD2 = 0

--- Mod3
---@type integer
wm.MOD_MOD3 = 0

--- Mod5 (usually AltGr)
---@type integer
wm.MOD_MOD5 = 0

--- Left mouse button (1)
---@type integer
wm.BUTTON_LEFT = 0

--- Middle mouse button (2)
---@type integer
wm.BUTTON_MIDDLE = 0

--- Right mouse button (3)
---@type integer
wm.BUTTON_RIGHT = 0

--- Scroll wheel up (4)
---@type integer
wm.BUTTON_SCROLL_UP = 0

--- Scroll wheel down (5)
---@type integer
wm.BUTTON_SCROLL_DOWN = 0

--- X11 backend
---@type integer
wm.PLATFORM_X11 = 0

--- river (Wayland) backend
---@type integer
wm.PLATFORM_RIVER = 0

--- Backend this build of duckwm uses: wm.PLATFORM_X11 or wm.PLATFORM_RIVER
---@type integer
wm.PLATFORM = 0

--- Exit the window manager cleanly.
function wm.quit() end

--- Reload the Lua config file. The Lua VM is reset, all keybindings and rules are cleared, and the config is re-executed from scratch. Arrangers are re-mapped over existing windows.
function wm.reload_config() end

--- Re-run the config without killing the vm. This should be used only when it is known that the wm isn't in a bad internal state, for things like clearing keybinds set conditionally
function wm.reload_persistent() end

--- Set an environment variable in the WM process. All subsequently spawned windows inherit it.
---@param key string
---@param val string
function wm.setenv(key, val) end

--- Spawn a subprocess. The argv table must contain at least one string (the executable path). The process is detached from the WM.
---@param argv string[]
function wm.spawn(argv) end

--- Spawn a process at startup only; ignored on reloads. Use for autostart entries.
---@param argv string[]
function wm.exec_once(argv) end

--- Set the cursor theme and size, on X11 and river. Sets XCURSOR_THEME/XCURSOR_SIZE for spawned apps, and on X11 the RESOURCE_MANAGER property too.
---@param theme string
---@param size integer
function wm.set_cursor_theme(theme, size) end

--- Return the focused monitor's width in pixels.
---@return integer
function wm.screen_width() end

--- Return the focused monitor's height in pixels.
---@return integer
function wm.screen_height() end

--- The usable area of the current workspace's monitor as (x, y, width, height): the monitor minus the docks and bars on it (_NET_WM_STRUT_PARTIAL on X11, layer-shell exclusive zones on river).
---@return integer, integer, integer, integer
function wm.get_work_area() end

--- Run fn atomically. If fn raises an error or returns false, every change it made is undone; an error is re-raised after the rollback. Returns true if the changes were kept, false if fn returned false.
---@param fn fun(): boolean?
---@return boolean
function wm.transaction(fn) end

--- Run Lua source as the REPL does: an expression shows its value, statements run as they are. Returns a status ('ok', 'error' or 'incomplete') and the text printed or returned.
---@param src string
---@return 'ok'|'error'|'incomplete', string
function wm.eval(src) end

--- Register a keybinding. mod is a bitmask of modifier constants (e.g. MOD_SUPER | MOD_SHIFT). key is an X11 keysym name (e.g. 'Return', 'h', 'F11'). The function is called with no arguments when the key is pressed.
---@param mod integer
---@param key string
---@param fn function
function wm.bind(mod, key, fn) end

--- Remove a key's bind, whether it was made by bind or bind_commands.
---@param mods integer
---@param key string
function wm.unbind(mods, key) end

--- Every bound key combination, once each: mods is the modifier bitmask bind takes, key the keysym name ('Return', 'q'). Says nothing about what the binds do.
---@return { mods: integer, key: string }[]
function wm.get_keybinds() end

--- Ask the focused window to close (WM_DELETE_WINDOW on X11; on river, a close request). On X11, a client that doesn't support it is killed.
function wm.kill_client() end

--- Toggle floating mode on the focused window. Floating windows are excluded from tiling and can be freely moved and resized.
function wm.toggle_floating() end

--- Set floating state of a window directly. Pass false to re-integrate into tiling via the arranger.
---@param id integer
---@param val boolean
function wm.set_floating(id, val) end

--- Toggle fullscreen on the focused window. The window is moved to cover its whole monitor, docks and bars included.
function wm.toggle_fullscreen() end

--- Set fullscreen state on a specific window node. Primarily for use in window rules.
---@param id integer
---@param val boolean
function wm.set_fullscreen(id, val) end

--- Unmap a window's frame without destroying it. The node remains in the graph.
---@param id integer
function wm.hide_window(id) end

--- Map and raise a previously hidden window.
---@param id integer
function wm.show_window(id) end

--- Get the WM_CLASS of a window: its class (second string, e.g. "XTerm") and instance (first string, e.g. "xterm"). Either may be nil.
---@param id integer
---@return string|nil, string|nil
function wm.get_window_class(id) end

--- Return the WM_NAME (title) of a window node, or nil if unavailable.
---@param id integer
---@return string|nil
function wm.get_window_name(id) end

--- Return the PID of a window node via _NET_WM_PID, or nil if the property is not set.
---@param id integer
---@return integer|nil
function wm.get_window_pid(id) end

--- Return whether a window has the urgency hint set.
---@param id integer
---@return boolean
function wm.get_urgent(id) end

--- Set or clear the urgency flag on a window node.
---@param id integer
---@param val boolean
function wm.set_urgent(id, val) end

--- Register a terminal/application WM_CLASS pair for swallowing. When a window whose class matches `child` maps and one of its ancestor processes owns a window whose class matches `terminal` in the current workspace, the terminal is replaced in the layout by the new window and restored when it closes.
---@param terminal string
---@param child string
function wm.register_swallow(terminal, child) end

--- Remove a previously registered terminal/application swallow pair.
---@param terminal string
---@param child string
function wm.unregister_swallow(terminal, child) end

--- Toggle a scratchpad window: stash it in the off-screen parking lot if it's showing, or summon it onto the current workspace (floating) if it's stashed.
---@param id integer
function wm.scratchpad_toggle(id) end

--- Summon a stashed scratchpad window onto the current workspace as a floating window and focus it.
---@param id integer
function wm.scratchpad_show(id) end

--- Stash a window into the off-screen parking lot; the tiled survivors re-flow as if it were closed.
---@param id integer
function wm.scratchpad_hide(id) end

--- The node IDs stashed in the scratchpad, oldest first. They survive a config reload, so a config can find its scratchpad windows again with this.
---@return integer[]
function wm.get_scratchpad() end

--- Focus a specific node by ID.
---@param id integer
function wm.focus(id) end

--- Move focus to the nearest window to the left of the focused window, using focus edges.
function wm.focus_left() end

--- Move focus to the nearest window to the right of the focused window, using focus edges.
function wm.focus_right() end

--- Move focus to the nearest window above the focused window, using focus edges.
function wm.focus_up() end

--- Move focus to the nearest window below the focused window, using focus edges.
function wm.focus_down() end

--- Return the ID of the currently focused node, or nil if nothing is focused.
---@return integer|nil
function wm.get_focused() end

--- Enable or disable focus-follows-mouse. When enabled, moving the cursor into a window automatically focuses it.
---@param enabled boolean
function wm.set_focus_follows_mouse(enabled) end

--- Enable or disable click-to-focus mode. When enabled, clicking a window focuses it even if focus-follows-mouse is off.
---@param enabled boolean
function wm.set_click_to_focus(enabled) end

--- Swap the focused node's contents with the node to its left.
function wm.exchange_left() end

--- Swap the focused node's contents with the node to its right.
function wm.exchange_right() end

--- Swap the focused node's contents with the node above.
function wm.exchange_up() end

--- Swap the focused node's contents with the node below.
function wm.exchange_down() end

--- Switch to a workspace by 1-based index at the current nesting level, on the focused monitor. Creates missing workspaces on demand.
---@param index integer
function wm.switch_to_workspace(index) end

--- Send a window node to a workspace by 1-based index at the current nesting level, on the focused monitor. Creates missing workspaces on demand.
---@param node_id integer
---@param index integer
function wm.send_to_workspace(node_id, index) end

--- Return the node ID of the nth workspace (1-based) in the current graph, or nil.
---@param index integer
---@return integer|nil
function wm.get_workspace(index) end

--- Return the 1-based number of the currently active workspace.
---@return integer|nil
function wm.get_current_workspace() end

--- Return a list of workspace numbers at the current nesting level that have content or are active.
---@return integer[]
function wm.get_workspaces_at_level() end

--- Set behaviour when switching to the already active workspace. 'none' does nothing; 'previous' switches to the previously active workspace.
---@param mode 'none'|'previous'
function wm.set_workspace_switch_mode(mode) end

--- Create a new nested workspace node in the current graph. Returns its node ID. The workspace is empty and uses the default arranger.
---@return integer
function wm.create_nested_workspace() end

--- Enter the focused workspace node, making it the active graph.
function wm.enter_nested() end

--- Leave the current nested workspace and return to the parent graph. Blocked at the top level.
function wm.leave_nested() end

--- Enter a workspace node by its node ID.
---@param id integer
function wm.enter_nested_by_id(id) end

--- Enter a workspace node by its node ID (alias for enter_nested_by_id, used for top-level workspace switching).
---@param id integer
function wm.enter_workspace_by_id(id) end

--- Return the nesting level of the current workspace. Level 1 is the top-level workspace layer; higher numbers mean deeper nesting.
---@return integer
function wm.get_current_level() end

--- Return the nesting level of the graph that owns a node, or nil if the node is not found.
---@param id integer
---@return integer|nil
function wm.get_node_level(id) end

--- Return a list of positional indices (1-based) for all workspaces at the current level, sorted by creation order. Use this for bar display — index N corresponds to switch_to_workspace(N).
---@return integer[]
function wm.get_workspace_positions() end

--- Return the positional index (1-based) of the currently active workspace, matching switch_to_workspace. Returns nil if not found.
---@return integer|nil
function wm.get_current_workspace_position() end

--- Return a table of all workspaces at the current level, each with a position (1-based index), state ('focused', 'active', or 'inactive') and its node id (for set_name). All workspaces are included regardless of whether they have content.
---@return { position: integer, state: 'focused'|'active'|'inactive', id: integer }[]
function wm.get_workspace_states() end

--- Cleans up subgraphs with windows that don't have a visible preview window
function wm.cleanup_left_behind() end

--- When enabled, killing a workspace that leaves windows behind in hidden (no-preview) sibling workspaces sweeps them immediately and silently, instead of showing the cleanup notification prompt.
---@param enabled boolean
function wm.set_autoclean(enabled) end

--- The monitors, the primary first: id, name (its connector, e.g. 'DP-1', nil if unknown), x, y, width, height, focused. Each has its own workspaces; switch_to_workspace acts on the focused one.
---@return { id: integer, name: string|nil, x: integer, y: integer, width: integer, height: integer, focused: boolean }[]
function wm.get_outputs() end

--- Focus the nearest monitor in a direction: what was focused there last, or its top-left window. The pointer moves there too.
---@param dir 'left'|'right'|'up'|'down'
function wm.focus_output(dir) end

--- Move a window to the workspace showing on the nearest monitor in a direction. Focus doesn't follow.
---@param id integer
---@param dir 'left'|'right'|'up'|'down'
function wm.send_to_output(id, dir) end

--- What every monitor shows, in one call (for bars): its id, name, x, y, whether it's focused, the positions of its workspaces with content (as get_workspace_positions), the current one's position, its level, layout name and window count, and its focused window (id, title, class) or nil.
---@return { id: integer, name: string|nil, x: integer, y: integer, focused: boolean, workspaces: integer[], current: integer|nil, level: integer, layout: string|nil, windows: integer, window: { id: integer, title: string|nil, class: string|nil }|nil }[]
function wm.get_output_states() end

--- Wrap nodes in a new group, which takes the place of the first of them. A group is laid out
--- like a window by the arranger of the graph holding it, and lays out its own nodes inside its
--- rectangle with an arranger of its own (the default one, until register_arranger gives it
--- another). Groups pan and zoom with their workspace. With no ids, the focused window is wrapped.
--- New windows open in the focused window's group; a group whose last node leaves goes away.
--- The ids must all be in the same workspace or group.
---@param ids integer[]?
---@return integer
function wm.create_group(ids) end

--- Move everything in a group to the graph holding it, where the group was; the group goes.
---@param id integer
function wm.ungroup(id) end

--- Move a node into a group, where its arranger places it. With no group, move it out of the group it's in, one level up. Focus stays on it.
---@param id integer
---@param group integer?
function wm.move_to_group(id, group) end

--- The group a node is in, or nil if it's directly in a workspace.
---@param id integer
---@return integer?
function wm.get_group(id) end

--- The nodes directly in a group, in the order they joined.
---@param id integer
---@return integer[]
function wm.get_group_members(id) end

--- The outline drawn along the inside of every group that doesn't set its own. Width 0 (the default) draws none; the group's nodes are laid out inside the outline.
---@param width integer
---@param color integer
function wm.set_group_outline(width, color) end

--- One group's outline. nil for width or color goes back to set_group_outline's.
---@param id integer
---@param width integer?
---@param color integer?
function wm.set_group_outline_of(id, width, color) end

--- Focus the group holding the focused node; commands that act on the focused window then act on the group. Directional focus moves on from it as from a window. Returns the group, or nil.
---@return integer?
function wm.focus_parent() end

--- From a focused group, focus the node in it on the way to what had focus last. Returns it, or nil.
---@return integer?
function wm.focus_child() end

--- Set the current workspace's arranger. factory is called once per workspace and returns the
--- arranger: a function(event, id, prev_id, snapshot) that returns the whole layout
--- ({ nodes = ... }, or nil to keep the current one) and the state to keep (nil keeps the old one).
--- event is one of:
---   'map'     — a window joined the layout
---   'unmap'   — a window is leaving it (the snapshot still lists it)
---   'resize'  — the user resized a window
---   'focus'   — a window gained focus
---   'pre_map' — before 'map', before the window is placed
---   'area'    — the work area changed size (a bar, the monitor)
--- The snapshot has event, id, prev_id, work_area, windows, focused, cursor_dx, cursor_dy,
--- layout (as duckwm has it, with the user's resizes) and state. Keys bound while the
--- factory runs belong to that workspace. The guide walks through writing one.
---@param factory function
---@param name string?
function wm.set_arranger(factory, name) end

--- Set the default arranger factory used for new workspaces. The factory is called with no arguments and must return an arranger function. See set_arranger for the full list of events the arranger receives.
---@param factory function
---@param name string?
function wm.set_default_arranger(factory, name) end

--- Set the arranger for a workspace or group node by ID. See set_arranger for the full list of events the arranger receives.
---@param id integer
---@param factory function
---@param name string?
function wm.register_arranger(id, factory, name) end

--- Return the display name of the current workspace's arranger, or nil if none is set.
---@return string|nil
function wm.get_arranger_name() end

--- Return the arranger index stored on the current workspace. Used to track which arranger in a cycle is active.
---@return integer
function wm.get_arranger_index() end

--- Set the arranger index on the current workspace.
---@param index integer
function wm.set_arranger_index(index) end

--- Return a list of all window and workspace node IDs in the current graph.
---@return integer[]
function wm.get_all_windows() end

--- Set global gap sizes in pixels. inner_h/inner_v are gaps between windows; outer_h/outer_v are gaps between windows and screen edges. Inside within, only for the workspaces in its path.
---@param inner_h integer
---@param inner_v integer
---@param outer_h integer
---@param outer_v integer
function wm.set_gaps(inner_h, inner_v, outer_h, outer_v) end

--- Set gap sizes for a specific workspace node.
---@param id integer
---@param inner_h integer
---@param inner_v integer
---@param outer_h integer
---@param outer_v integer
function wm.set_gaps_workspace(id, inner_h, inner_v, outer_h, outer_v) end

--- Set the pan offset for the current workspace in pixels. Used with virtual canvases larger than the screen.
---@param x integer
---@param y integer
function wm.set_pan(x, y) end

--- Return the current pan offset as (x, y).
---@return integer, integer
function wm.get_pan() end

--- Pan the current workspace by a relative offset in pixels.
---@param dx integer
---@param dy integer
function wm.pan_by(dx, dy) end

--- Set the virtual canvas size for the current workspace. Windows can be placed beyond the physical screen bounds and panned into view.
---@param width integer
---@param height integer
function wm.set_virtual_size(width, height) end

--- Prevent tiled windows from being resized horizontally in the current workspace.
---@param locked boolean
function wm.set_lock_horizontal_resize(locked) end

--- Prevent tiled windows from being resized vertically in the current workspace.
---@param locked boolean
function wm.set_lock_vertical_resize(locked) end

--- Disable or enable mouse panning for the current workspace.
---@param disabled boolean
function wm.set_pan_disabled(disabled) end

--- Set the modifier key used for mouse panning.
---@param mod integer
function wm.set_pan_modifier(mod) end

--- Set the mouse button used for panning (default: BUTTON_MIDDLE).
---@param button integer
function wm.set_pan_button(button) end

--- Set the modifier key used for mouse resize of tiled windows.
---@param mod integer
function wm.set_resize_modifier(mod) end

--- Set the modifier key used for dragging floating windows.
---@param mod integer
function wm.set_float_modifier(mod) end

--- Set the mouse button used to move floating windows (default: BUTTON_LEFT).
---@param button integer
function wm.set_float_move_button(button) end

--- Set the mouse button used to resize floating windows (default: BUTTON_RIGHT).
---@param button integer
function wm.set_float_resize_button(button) end

--- Return the current workspace's graph as a Lua table with:
---   nodes    — array of all node tables
---   windows  — array of window/workspace node ids
---   focused  — id of currently focused node, or nil
---   root     — id of the first container that's no split's child, or nil
--- Each node table has: id, type, x, y, width, height, constraints, parent, parent_idx.
--- parent is the id of the container whose split holds this node, or nil.
--- parent_idx is its 1-based position among that split's children.
---@return { nodes: table[], windows: integer[], focused: integer|nil, root: integer|nil }
function wm.get_layout() end

--- Apply a layout table to the current graph. Accepts the same format returned by get_layout.
--- Clears all constraints on nodes present in the table, then applies the constraints
--- described in each node's constraints array. Nodes are matched by id.
--- Typically called after mutating the table returned by get_layout.
---@param layout { nodes: table[] }
function wm.set_layout(layout) end

--- Draw the current workspace zoomed out: 1 is normal, 0.5 shows twice as much of the canvas each way, 0 fits the whole canvas on screen. Windows are really resized (river and X11 can't scale them), and get their size back at 1. While zoomed, mouse move and resize are off; panning and click-to-focus work.
---@param zoom number
function wm.set_zoom(zoom) end

--- The current workspace's zoom; for 0 (fit), the factor that works out to.
---@return number
function wm.get_zoom() end

--- Constrain a so that a.right == b.left (a is immediately left of b).
--- Positional constraints like this one are strong rather than required: when they
--- conflict with others, the solver relaxes them instead of failing.
---@param a integer
---@param b integer
function wm.left_of(a, b) end

--- Constrain a so that a.left == b.right (a is immediately right of b).
---@param a integer
---@param b integer
function wm.right_of(a, b) end

--- Constrain a so that a.bottom == b.top (a is immediately above b).
---@param a integer
---@param b integer
function wm.above(a, b) end

--- Constrain a so that a.top == b.bottom (a is immediately below b).
---@param a integer
---@param b integer
function wm.below(a, b) end

--- Constrain: a.x == b.x (left edges aligned).
---@param a integer
---@param b integer
function wm.align_left(a, b) end

--- Constrain: a.y == b.y (top edges aligned).
---@param a integer
---@param b integer
function wm.align_top(a, b) end

--- Constrain: a.right == b.right (right edges aligned).
---@param a integer
---@param b integer
function wm.align_right(a, b) end

--- Constrain: a.bottom == b.bottom (bottom edges aligned).
---@param a integer
---@param b integer
function wm.align_bottom(a, b) end

--- Constrain: a.width == b.width. Strong, like the positional constraints.
---@param a integer
---@param b integer
function wm.equal_width(a, b) end

--- Constrain: a.height == b.height. Strong, like the positional constraints.
---@param a integer
---@param b integer
function wm.equal_height(a, b) end

--- Constrain: width / height == ratio. Strong.
---@param id integer
---@param ratio number
function wm.fixed_ratio(id, ratio) end

--- Constrain: width == w. Coordinates are relative to the work area origin.
---@param id integer
---@param w integer
function wm.fixed_width(id, w) end

--- Constrain: height == h.
---@param id integer
---@param h integer
function wm.fixed_height(id, h) end

--- Constrain: x == x. Coordinates are relative to the work area origin (0,0 = top-left of usable area after bars).
--- The solver converts these to absolute screen coordinates internally.
---@param id integer
---@param x integer
function wm.fixed_x(id, x) end

--- Constrain: y == y. See fixed_x for coordinate system notes.
---@param id integer
---@param y integer
function wm.fixed_y(id, y) end

--- Place a node in a cell of a grid defined by a container node.
--- col and row are 0-based. The container's geometry is divided into cols x rows equal cells.
---@param id integer
---@param col integer
---@param row integer
---@param cols integer
---@param rows integer
---@param container integer
function wm.grid_cell(id, col, row, cols, rows, container) end

--- Place a node at absolute pixel offsets within a container.
---@param id integer
---@param x integer
---@param y integer
---@param w integer
---@param h integer
---@param container integer
function wm.grid_cell_abs(id, x, y, w, h, container) end

--- Split a container atomically into N children along an axis.
--- ratios is a table of N numbers that need not sum to 1 — they are normalized internally.
--- This is the preferred way to divide space proportionally: it's one required constraint
--- per child, where chaining left_of/right_of gives strong ones that can be relaxed.
---@param container integer
---@param axis 'h'|'v'
---@param ratios number[]
---@param children integer[]
function wm.split(container, axis, ratios, children) end

--- Remove all constraints from a node. Call this before adding new constraints when relaying out.
---@param id integer
function wm.clear_constraints(id) end

--- Remove all constraints of a given type from a node.
---@param id integer
---@param type 'fixed_x'|'fixed_y'|'fixed_width'|'fixed_height'|'right_of'|'left_of'|'above'|'below'|'grid_cell'|'split'|'align_left'|'align_right'|'align_top'|'align_bottom'|'equal_width'|'equal_height'
function wm.remove_constraint(id, type) end

--- Return the geometry of a node as a table with x, y, width, height fields (absolute screen coordinates), or nil if not found.
---@param id integer
---@return { x: integer, y: integer, width: integer, height: integer }|nil
function wm.get_node_geometry(id) end

--- Return full info for a node: x, y, width, height, type, floating.
---@param id integer
---@return { x: integer, y: integer, width: integer, height: integer, type: string, floating: boolean }|nil
function wm.get_node_info(id) end

--- Return the type of a node: 'window', 'empty', 'group' or 'workspace', or nil if not found.
---@param id integer
---@return 'window'|'empty'|'workspace'|'workspace'|nil
function wm.get_node_type(id) end

--- Return the cursor position as (x, y) in absolute screen coordinates.
---@return integer, integer
function wm.get_cursor_pos() end

--- Return the cursor offset from the center of the focused window as (dx, dy). Useful in arrangers for split direction hinting.
---@return integer, integer
function wm.get_cursor_relative_to_focused() end

--- Warp the cursor to absolute screen coordinates.
---@param x integer
---@param y integer
function wm.warp_cursor(x, y) end

--- Warp the cursor to the center of a node.
---@param id integer
function wm.warp_cursor_to_node(id) end

--- Return the ID of the smallest node under the cursor, or nil.
---@return integer|nil
function wm.get_mouse_node() end

--- Move an edge of a specific node by delta pixels, adjusting constraints accordingly.
---@param id integer
---@param dir 'left'|'right'|'up'|'down'
---@param delta integer
function wm.resize_edge(id, dir, delta) end

--- Move a corner of a specific node by (delta_x, delta_y) pixels.
---@param id integer
---@param delta_x integer
---@param delta_y integer
function wm.resize_corner(id, delta_x, delta_y) end

--- Move an edge of the focused node by delta pixels.
---@param dir 'left'|'right'|'up'|'down'
---@param delta integer
function wm.resize_focused_edge(dir, delta) end

--- Move a corner of the focused node.
---@param delta_x integer
---@param delta_y integer
function wm.resize_focused_corner(delta_x, delta_y) end

--- Move floating window a so its right edge touches b's left edge, aligning their top edges. Resolves and flushes immediately.
---@param a integer
---@param b integer
function wm.float_left_of(a, b) end

--- Move floating window a so its left edge touches b's right edge, aligning their top edges. Resolves and flushes immediately.
---@param a integer
---@param b integer
function wm.float_right_of(a, b) end

--- Move floating window a so its bottom edge touches b's top edge, aligning their left edges. Resolves and flushes immediately.
---@param a integer
---@param b integer
function wm.float_above(a, b) end

--- Move floating window a so its top edge touches b's bottom edge, aligning their left edges. Resolves and flushes immediately.
---@param a integer
---@param b integer
function wm.float_below(a, b) end

--- Constrain floating window a to have the same width as b. Additive — combine with positional constraints. Resolves and flushes immediately.
---@param a integer
---@param b integer
function wm.float_equal_width(a, b) end

--- Constrain floating window a to have the same height as b. Additive — combine with positional constraints. Resolves and flushes immediately.
---@param a integer
---@param b integer
function wm.float_equal_height(a, b) end

--- Constrain floating window a so its left edge aligns with b's left edge. Resolves and flushes immediately.
---@param a integer
---@param b integer
function wm.float_align_left(a, b) end

--- Constrain floating window a so its top edge aligns with b's top edge. Resolves and flushes immediately.
---@param a integer
---@param b integer
function wm.float_align_top(a, b) end

--- Constrain floating window a so its right edge aligns with b's right edge. Resolves and flushes immediately.
---@param a integer
---@param b integer
function wm.float_align_right(a, b) end

--- Constrain floating window a so its bottom edge aligns with b's bottom edge. Resolves and flushes immediately.
---@param a integer
---@param b integer
function wm.float_align_bottom(a, b) end

--- Remove all constraints from a floating window, freeing it to move independently. Resolves and flushes immediately.
---@param id integer
function wm.float_clear_constraints(id) end

--- Set the window border width in pixels.
---@param width integer
function wm.set_border_width(width) end

--- Set the default border color for focused windows (0xRRGGBB).
---@param color integer
function wm.set_default_focused_border_color(color) end

--- Set the default border color for unfocused windows (0xRRGGBB).
---@param color integer
function wm.set_default_unfocused_border_color(color) end

--- Allow 32-bit (translucent) windows to get ARGB frames. When false, every newly mapped window gets a normal-depth frame and loses translucency. Default: true.
---@param enabled boolean
function wm.set_argb_frames(enabled) end

--- Always give windows matching this WM_CLASS class or instance a normal-depth frame, even if they are 32-bit. Works around clients that misbehave inside ARGB frames. Applies to windows mapped after the call.
---@param class string
function wm.force_rgb_frames(class) end

--- Set the border color used for windows with the urgency hint (0xRRGGBB).
---@param color integer
function wm.set_default_urgent_border_color(color) end

--- Override the focused border color for a specific node (0xRRGGBB).
---@param id integer
---@param color integer
function wm.set_node_focused_border_color(id, color) end

--- Override the unfocused border color for a specific node (0xRRGGBB).
---@param id integer
---@param color integer
function wm.set_node_unfocused_border_color(id, color) end

--- Set the colors used when drawing workspace preview thumbnails. Colors are 0xRRGGBB. Inside within, only for the workspaces in its path.
---@param bg integer
---@param win_bg integer
---@param border integer
---@param text integer
function wm.set_preview_colors(bg, win_bg, border, text) end

--- Override the preview colors for a specific workspace node. Falls back to global preview colors for any value not set.
---@param id integer
---@param bg integer
---@param win_bg integer
---@param border integer
---@param text integer
function wm.set_preview_colors_workspace(id, bg, win_bg, border, text) end

--- Set the Xft font name used for labels in workspace preview thumbnails (e.g. "monospace:pixelsize=10"). Falls back to a built-in font if the name can't be opened. Inside within, only for the workspaces in its path.
---@param font string
function wm.set_preview_font(font) end

--- Override the preview label font for a specific workspace node (e.g. "monospace:pixelsize=10"). Pass an empty string to clear the override and fall back to the global preview font.
---@param id integer
---@param font string
function wm.set_preview_font_workspace(id, font) end

--- Cap the maximum pixel size of window icons drawn in preview thumbnails. Icons otherwise scale with the thumbnail size. Pass 0 to remove the cap.
---@param size integer
function wm.set_preview_max_icon_size(size) end

--- Set the color of a single border side for a node. side is 'top', 'bottom', 'left', or 'right'. Overrides the base border color for that side only. Pass 0xRRGGBB.
---@param id integer
---@param side 'top'|'bottom'|'left'|'right'
---@param color integer
function wm.set_node_border_side_color(id, side, color) end

--- Clear all per-side border color overrides for a node, reverting to the base focused/unfocused color on all sides.
---@param id integer
function wm.clear_node_border_side_colors(id) end

--- When true, per-side border color overrides are only shown on the focused window. Unfocused windows show their base unfocused color on all sides. Default: true.
---@param enabled boolean
function wm.set_border_side_colors_focused_only(enabled) end

--- Clear the per-node focused border color override, reverting to the default.
---@param id integer
function wm.clear_node_focused_border_color(id) end

--- Clear the per-node unfocused border color override, reverting to the default.
---@param id integer
function wm.clear_node_unfocused_border_color(id) end

--- Set animation duration and curve (currently river only)
---@param duration_ms integer
---@param curve string|number[]|fun(t: number): number
function wm.set_animation(duration_ms, curve) end

--- Set the indicator color shared by every node. Indicators already shown are recolored immediately.
---@param color integer
function wm.set_indicator_color(color) end

--- Draw one side of a node's border in the indicator color, replacing its previous indicator side. Takes precedence over that side's own color, and shows only when side colors do (see set_border_side_colors_focused_only).
---@param id integer
---@param side 'top'|'bottom'|'left'|'right'
function wm.set_node_indicator(id, side) end

--- Remove a node's indicator.
---@param id integer
function wm.clear_node_indicator(id) end

--- Register a global window rule. Rules fire for every window regardless of arranger;
--- one added inside within only for windows in its path.
--- The function receives (event, id) where event is one of:
---   'pre_map' — fires before the arranger places the window (use for float/fullscreen rules)
---   'map'     — fires after the arranger places the window
---   'unmap'   — fires when the window is removed from the layout (e.g. closed or floating)
---   'prop'    — fires when WM_CLASS or window title changes (for apps that set class late)
--- Returns a handle that can be passed to remove_rule.
---@param fn fun(event: string, id: integer)
---@return integer
function wm.add_rule(fn) end

--- Remove a previously registered rule by its handle.
---@param handle integer
function wm.remove_rule(handle) end

--- Set the reparenting strategy for a node when it is removed. 'promote' promotes its sibling into its container slot, 'remove' removes the node entirely, 'empty' leaves an empty slot. Pass nil to clear.
---@param id integer
---@param strategy 'promote'|'remove'|'empty'|nil
function wm.set_reparent_strategy(id, strategy) end

--- Return a table with the per-side border color overrides for a node. Only sides that have been explicitly set are present. Keys are 'top', 'bottom', 'left', 'right'. Returns nil if the node is not found.
---@param id integer
---@return { top: integer?, bottom: integer?, left: integer?, right: integer? }|nil
function wm.get_node_border_side_colors(id) end

--- Give a node a name, for paths like 'DP-1/web/chat' (see find). No '/' in it, and nothing else in the same named place can have it already. nil clears it. Kept until the node is gone, across config reloads.
---@param id integer
---@param name string|nil
function wm.set_name(id, name) end

--- Return a node's name, or nil if it has none.
---@param id integer
---@return string|nil
function wm.get_name(id) end

--- Run fn, and have what it sets up apply only in path (see find): on the node whose path ends in it, or anything inside. Keybinds apply while focus is there, and win over binds made outside, the nearest match to the focus first. Rules (add_rule) only run for windows there. set_gaps, set_preview_colors and set_preview_font only apply to the workspaces there, including ones that get there later (made, named or moved), the nearest path winning; set without within, they reset every workspace and these are laid over again. The path needn't exist yet, and what was set up stays when its node is closed and made again. Nested, paths add up: within('DP-1', ...) around within('web', ...) is 'DP-1/web'.
---@param path string
---@param fn fun()
function wm.within(path, fn) end

--- The node at a path: 'DP-1/web/chat' is the node named 'chat', in the nearest named thing 'web', on output 'DP-1'. Unnamed nodes in between don't count, and the start can be left off ('web/chat', 'chat') while only one node matches; more than one is an error. nil if none matches, or if the path names an output.
---@param path string
---@return integer|nil
function wm.find(path) end

--- A node's whole path: the names of the named things it's in, outermost (its output) first, then its own if it has one. nil if none of them is named.
---@param id integer
---@return string|nil
function wm.get_path(id) end

--- Create an empty container node in the current graph. Containers have no X window — they exist purely to define geometry for constraint targets.
---@return integer
function wm.create_container() end

--- Remove an empty container node from the graph.
---@param id integer
function wm.destroy_container(id) end

--- Create a full-screen empty container (width=screen_width, height=screen_height).
---@return integer
function wm.create_root_node() end

--- Create an unconstrained empty node with zero initial geometry.
---@return integer
function wm.create_empty_node() end

--- Remove a node from the graph entirely, freeing it.
---@param id integer
function wm.remove_node(id) end

--- Remove a node from the ID registry without freeing it. Use with care.
---@param id integer
function wm.unregister_node(id) end

--- Clear a node's window content, making it an empty node.
---@param id integer
function wm.set_node_empty(id) end

--- Assign an X window to a node.
---@param id integer
---@param win integer
function wm.set_node_window(id, win) end

--- Move the window from src node to dst node.
---@param src integer
---@param dst integer
function wm.move_window_to_node(src, dst) end

--- Make child fill parent entirely via a 1x1 grid_cell constraint.
---@param child integer
---@param parent integer
function wm.reparent(child, parent) end

--- Return the container ID that a node is grid_cell'd into, or nil.
---@param id integer
---@return integer|nil
function wm.get_container_of(id) end

--- Return the current split ratios of a container node as a table, or nil if the node has no split constraint.
---@param id integer
---@return number[]|nil
function wm.get_split_ratios(id) end

--- Set the XKB keymap for all keyboards. Comma-separated layouts give a multi-layout keymap ("us,pt"); options like "grp:alt_shift_toggle" add a switching key. variant, options and model may be omitted.
---@param layout string
---@param variant string?
---@param options string?
---@param model string?
function wm.set_keyboard_layout(layout, variant, options, model) end

--- Switch to the layout at this 0-based index within the current keymap ("us,pt": 0 = us, 1 = pt).
---@param index integer
function wm.set_keyboard_layout_index(index) end

--- Open the input bar at the top of the screen and read a line, StumpWM style. fn gets the text on Enter; Escape closes the bar without calling it (with vi keys, Escape from normal mode). While it's open every key goes to the bar, so binds don't fire.
---@param prompt string
---@param fn fun(text: string)
---@param initial string?
function wm.read_line(prompt, fn, initial) end

--- Editing keys for the input bar: 'emacs' (readline's; Escape cancels) or 'vi' (insert and normal modes, counts, motions, d/c/y, undo, j/k for history). Default: 'emacs'.
---@param keys 'emacs'|'vi'
function wm.set_prompt_keys(keys) end

--- Show text in the input bar for timeout_ms milliseconds (0: 3 seconds). Ignored while a line is being typed.
---@param text string
---@param timeout_ms integer
function wm.message(text, timeout_ms) end

--- Return a string representation of the current graph showing nodes, geometry, and constraint relationships as labeled arrows. Recurses into nested workspaces. Use with quack: quack print_graph | jq -r '.result'
---@return string
function wm.print_graph() end

--- The current workspace drawn to scale as boxes: windows, floating windows, groups (with what's in them) and workspace previews, each labelled with its id, and the focused one marked *. The whole canvas is drawn, off-screen parts of a scrolling layout included.
---@param cols integer?
---@param rows integer?
---@return string
function wm.print_graph_pretty(cols, rows) end

