# duckwm Lua API

## Constants

- **`wm.MOD_SUPER`** — Mod4 (Super/Win key)
- **`wm.MOD_ALT`** — Mod1 (Alt key)
- **`wm.MOD_SHIFT`** — Shift modifier
- **`wm.MOD_CTRL`** — Control modifier

## Functions

### `wm.bind(mod: integer, key: string, fn: function)`

Register a keybinding.

### `wm.spawn(argv: string[])`

Spawn a subprocess.

### `wm.focus_left()`

Move focus to the window on the left.

### `wm.focus_right()`

Move focus to the window on the right.

### `wm.focus_up()`

Move focus to the window above.

### `wm.focus_down()`

Move focus to the window below.

### `wm.focus(id: integer)`

Focus a specific node by ID.

### `wm.exchange_left()`

Swap focused window with the one to its left.

### `wm.exchange_right()`

Swap focused window with the one to its right.

### `wm.exchange_up()`

Swap focused window with the one above.

### `wm.exchange_down()`

Swap focused window with the one below.

### `wm.on_map(fn: fun(id: integer, focused: integer|nil))`

Register callback fired when a window maps. focused is nil for the first window.

### `wm.on_unmap(fn: fun(id: integer))`

Register callback fired when a window unmaps.

### `wm.get_focused()`

Return the ID of the currently focused node, or nil.

**Returns:** `integer|nil`

### `wm.kill_client()`

Send WM_DELETE_WINDOW to the focused client.

### `wm.remove_node(id: integer)`

Remove a node from the graph entirely.

### `wm.get_node_type(id: integer)`

Return 'window', 'empty', 'workspace', or nil.

**Returns:** `'window'|'empty'|'workspace'|nil`

### `wm.get_node_geometry(id: integer)`

Return {x, y, width, height} for a node, or nil if not found.

**Returns:** `{ x: integer, y: integer, width: integer, height: integer }|nil`

### `wm.get_node_info(id: integer)`

Return geometry table for a node.

**Returns:** `{ x: integer, y: integer, width: integer, height: integer }`

### `wm.create_container()`

Create an empty container node in the current graph.

**Returns:** `integer`

### `wm.destroy_container(id: integer)`

Remove an empty container node from the graph.

### `wm.create_root_node()`

Create a full-screen empty container.

**Returns:** `integer`

### `wm.create_empty_node()`

Create an unconstrained empty node.

**Returns:** `integer`

### `wm.clear_constraints(id: integer)`

Remove all constraints from a node.

### `wm.grid_cell(id: integer, col: integer, row: integer, cols: integer, rows: integer, container: integer)`

Place node in a grid cell of container. col/row are 0-based.

### `wm.grid_cell_abs(id: integer, x: integer, y: integer, w: integer, h: integer, container: integer)`

Place node in a grid cell of container, with absolute pixel sizes.

### `wm.left_of(a: integer, b: integer)`

Constrain: a.right == b.left.

### `wm.right_of(a: integer, b: integer)`

Constrain: a.left == b.right.

### `wm.above(a: integer, b: integer)`

Constrain: a.bottom == b.top.

### `wm.below(a: integer, b: integer)`

Constrain: a.top == b.bottom.

### `wm.align_left(a: integer, b: integer)`

Constrain: a.x == b.x.

### `wm.align_top(a: integer, b: integer)`

Constrain: a.y == b.y.

### `wm.align_right(a: integer, b: integer)`

Constrain: a.right == b.right.

### `wm.align_bottom(a: integer, b: integer)`

Constrain: a.bottom == b.bottom.

### `wm.equal_width(a: integer, b: integer)`

Constrain: a.width == b.width.

### `wm.equal_height(a: integer, b: integer)`

Constrain: a.height == b.height.

### `wm.fixed_ratio(id: integer, ratio: number)`

Constrain: width/height == ratio.

### `wm.fixed_width(id: integer, w: integer)`

Constrain: width == w.

### `wm.fixed_height(id: integer, h: integer)`

Constrain: height == h.

### `wm.fixed_x(id: integer, x: integer)`

Constrain: x == x.

### `wm.fixed_y(id: integer, y: integer)`

Constrain: y == y.

### `wm.reparent(child: integer, parent: integer)`

Make child fill parent via a 1x1 grid_cell constraint.

### `wm.get_container_of(id: integer)`

Return the container ID that node is grid_cell'd into, or nil.

**Returns:** `integer|nil`

### `wm.get_all_windows()`

Return list of all window/workspace node IDs in current graph.

**Returns:** `integer[]`

### `wm.screen_width()`

Return screen width in pixels.

**Returns:** `integer`

### `wm.screen_height()`

Return screen height in pixels.

**Returns:** `integer`

### `wm.set_node_empty(id: integer)`

Clear a node's window content.

### `wm.set_node_window(id: integer, win: integer)`

Assign an X window to a node.

### `wm.move_window_to_node(src: integer, dst: integer)`

Move the window from src node to dst node.

### `wm.set_resize_modifier(mod: integer)`

Set the modifier key used for mouse resize.

### `wm.resize_edge(id: integer, dir: 'left'|'right'|'up'|'down', delta: integer)`

Move an edge of a specific node by delta pixels.

### `wm.resize_corner(id: integer, delta_x: integer, delta_y: integer)`

Move a corner of a specific node.

### `wm.resize_focused_edge(dir: 'left'|'right'|'up'|'down', delta: integer)`

Move an edge of the focused node by delta pixels.

### `wm.resize_focused_corner(delta_x: integer, delta_y: integer)`

Move a corner of the focused node.

### `wm.set_float_modifier(mod: integer)`

Set the modifier key used for floating window drag.

### `wm.toggle_floating()`

Toggle floating mode on the focused window.

### `wm.set_node_focused_border_color(id: integer, color: integer)`

Set focused border color for a specific node (0xRRGGBB).

### `wm.set_node_unfocused_border_color(id: integer, color: integer)`

Set unfocused border color for a specific node (0xRRGGBB).

### `wm.set_default_focus_border_color(color: integer)`

Set default focused border color (0xRRGGBB).

### `wm.set_default_unfocused_border_color(color: integer)`

Set default unfocused border color (0xRRGGBB).

### `wm.set_border_width(width: integer)`

Set window border width in pixels.

### `wm.create_nested_workspace()`

Create a new nested workspace node in the current graph.

**Returns:** `integer`

### `wm.enter_nested()`

Enter the focused workspace node.

### `wm.leave_nested()`

Leave the current nested workspace.

### `wm.switch_workspace(id: integer)`

Enter a workspace node by ID.

### `wm.get_workspace(index: integer)`

Return the nth workspace node ID (1-based) in the current graph.

**Returns:** `integer|nil`

### `wm.get_workspaces_at_level()`

Return list of workspace node IDs at the current nesting level.

**Returns:** `integer[]`

### `wm.enter_workspace_by_id(id: integer)`

Enter a workspace node by its ID.

### `wm.switch_to_workspace(index: integer)`

Switch to workspace by 1-based index, creating it if needed.

### `wm.set_on_remove_promote(id: integer)`

Set on_remove=promote: when removed, sibling is promoted into its slot.

### `wm.unregister_node(id: integer)`

Remove a node from the registry without freeing it.

### `wm.get_cursor_pos()`

Return cursor position as (x, y) in screen coordinates.

**Returns:** `integer, integer`

### `wm.get_cursor_relative_to_focused()`

Return cursor offset from focused window center as (dx, dy).

**Returns:** `integer, integer`

