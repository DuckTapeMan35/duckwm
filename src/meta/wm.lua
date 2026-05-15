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

--- Register a keybinding.
---@param mod integer
---@param key string
---@param fn function
function wm.bind(mod, key, fn) end

--- Spawn a subprocess.
---@param argv string[]
function wm.spawn(argv) end

--- Move focus to the window on the left.
function wm.focus_left() end

--- Move focus to the window on the right.
function wm.focus_right() end

--- Move focus to the window above.
function wm.focus_up() end

--- Move focus to the window below.
function wm.focus_down() end

--- Focus a specific node by ID.
---@param id integer
function wm.focus(id) end

--- Swap focused window with the one to its left.
function wm.exchange_left() end

--- Swap focused window with the one to its right.
function wm.exchange_right() end

--- Swap focused window with the one above.
function wm.exchange_up() end

--- Swap focused window with the one below.
function wm.exchange_down() end

--- Set the default layout function for new workspaces.
---@param fn function
function wm.set_default_arranger(fn) end

--- Register a new layout function to a workspace.
---@param workspace_id integer
---@param fn function
function wm.register_arranger(workspace_id, fn) end

--- Return the ID of the currently focused node, or nil.
---@return integer|nil
function wm.get_focused() end

--- Send WM_DELETE_WINDOW to the focused client.
function wm.kill_client() end

--- Remove a node from the graph entirely.
---@param id integer
function wm.remove_node(id) end

--- Return 'window', 'empty', 'workspace', or nil.
---@param id integer
---@return 'window'|'empty'|'workspace'|nil
function wm.get_node_type(id) end

--- Return {x, y, width, height} for a node, or nil if not found.
---@param id integer
---@return { x: integer, y: integer, width: integer, height: integer }|nil
function wm.get_node_geometry(id) end

--- Return geometry table for a node.
---@param id integer
---@return { x: integer, y: integer, width: integer, height: integer }
function wm.get_node_info(id) end

--- Create an empty container node in the current graph.
---@return integer
function wm.create_container() end

--- Remove an empty container node from the graph.
---@param id integer
function wm.destroy_container(id) end

--- Create a full-screen empty container.
---@return integer
function wm.create_root_node() end

--- Create an unconstrained empty node.
---@return integer
function wm.create_empty_node() end

--- Remove all constraints from a node.
---@param id integer
function wm.clear_constraints(id) end

--- Place node in a grid cell of container. col/row are 0-based.
---@param id integer
---@param col integer
---@param row integer
---@param cols integer
---@param rows integer
---@param container integer
function wm.grid_cell(id, col, row, cols, rows, container) end

--- Place node in a grid cell of container, with absolute pixel sizes.
---@param id integer
---@param x integer
---@param y integer
---@param w integer
---@param h integer
---@param container integer
function wm.grid_cell_abs(id, x, y, w, h, container) end

--- Constrain: a.right == b.left.
---@param a integer
---@param b integer
function wm.left_of(a, b) end

--- Constrain: a.left == b.right.
---@param a integer
---@param b integer
function wm.right_of(a, b) end

--- Constrain: a.bottom == b.top.
---@param a integer
---@param b integer
function wm.above(a, b) end

--- Constrain: a.top == b.bottom.
---@param a integer
---@param b integer
function wm.below(a, b) end

--- Constrain: a.x == b.x.
---@param a integer
---@param b integer
function wm.align_left(a, b) end

--- Constrain: a.y == b.y.
---@param a integer
---@param b integer
function wm.align_top(a, b) end

--- Constrain: a.right == b.right.
---@param a integer
---@param b integer
function wm.align_right(a, b) end

--- Constrain: a.bottom == b.bottom.
---@param a integer
---@param b integer
function wm.align_bottom(a, b) end

--- Constrain: a.width == b.width.
---@param a integer
---@param b integer
function wm.equal_width(a, b) end

--- Constrain: a.height == b.height.
---@param a integer
---@param b integer
function wm.equal_height(a, b) end

--- Constrain: width/height == ratio.
---@param id integer
---@param ratio number
function wm.fixed_ratio(id, ratio) end

--- Constrain: width == w.
---@param id integer
---@param w integer
function wm.fixed_width(id, w) end

--- Constrain: height == h.
---@param id integer
---@param h integer
function wm.fixed_height(id, h) end

--- Constrain: x == x.
---@param id integer
---@param x integer
function wm.fixed_x(id, x) end

--- Constrain: y == y.
---@param id integer
---@param y integer
function wm.fixed_y(id, y) end

--- Make child fill parent via a 1x1 grid_cell constraint.
---@param child integer
---@param parent integer
function wm.reparent(child, parent) end

--- Return the container ID that node is grid_cell'd into, or nil.
---@param id integer
---@return integer|nil
function wm.get_container_of(id) end

--- Return list of all window/workspace node IDs in current graph.
---@return integer[]
function wm.get_all_windows() end

--- Return screen width in pixels.
---@return integer
function wm.screen_width() end

--- Return screen height in pixels.
---@return integer
function wm.screen_height() end

--- Clear a node's window content.
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

--- Set the modifier key used for mouse resize.
---@param mod integer
function wm.set_resize_modifier(mod) end

--- Move an edge of a specific node by delta pixels.
---@param id integer
---@param dir 'left'|'right'|'up'|'down'
---@param delta integer
function wm.resize_edge(id, dir, delta) end

--- Move a corner of a specific node.
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

--- Set the modifier key used for floating window drag.
---@param mod integer
function wm.set_float_modifier(mod) end

--- Toggle floating mode on the focused window.
function wm.toggle_floating() end

--- Set focused border color for a specific node (0xRRGGBB).
---@param id integer
---@param color integer
function wm.set_node_focused_border_color(id, color) end

--- Set unfocused border color for a specific node (0xRRGGBB).
---@param id integer
---@param color integer
function wm.set_node_unfocused_border_color(id, color) end

--- Set default focused border color (0xRRGGBB).
---@param color integer
function wm.set_default_focus_border_color(color) end

--- Set default unfocused border color (0xRRGGBB).
---@param color integer
function wm.set_default_unfocused_border_color(color) end

--- Set window border width in pixels.
---@param width integer
function wm.set_border_width(width) end

--- Create a new nested workspace node in the current graph.
---@return integer
function wm.create_nested_workspace() end

--- Enter the focused workspace node.
function wm.enter_nested() end

--- Leave the current nested workspace.
function wm.leave_nested() end

--- Enter a workspace node by ID.
---@param id integer
function wm.switch_workspace(id) end

--- Return the nth workspace node ID (1-based) in the current graph.
---@param index integer
---@return integer|nil
function wm.get_workspace(index) end

--- Return list of workspace node IDs at the current nesting level.
---@return integer[]
function wm.get_workspaces_at_level() end

--- Enter a workspace node by its ID.
---@param id integer
function wm.enter_workspace_by_id(id) end

--- Switch to workspace by 1-based index, creating it if needed.
---@param index integer
function wm.switch_to_workspace(index) end

--- Set on_remove=promote: when removed, sibling is promoted into its slot.
---@param id integer
function wm.set_on_remove_promote(id) end

--- Remove a node from the registry without freeing it.
---@param id integer
function wm.unregister_node(id) end

--- Return cursor position as (x, y) in screen coordinates.
---@return integer, integer
function wm.get_cursor_pos() end

--- Return cursor offset from focused window center as (dx, dy).
---@return integer, integer
function wm.get_cursor_relative_to_focused() end

