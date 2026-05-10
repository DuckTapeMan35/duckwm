---@meta

---@class wm
-- Constants
---@type integer
wm.MOD_SUPER
---@type integer
wm.MOD_ALT
---@type integer
wm.MOD_SHIFT
---@type integer
wm.MOD_CTRL

---Bind a key combination to a Lua function.
---@param mod integer
---@param key string
---@param func fun()
function wm.bind(mod, key, func) end

---Spawn a process.
---@param argv string[]
function wm.spawn(argv) end

---Move focus left.
function wm.focus_left() end
---Move focus right.
function wm.focus_right() end
---Move focus up.
function wm.focus_up() end
---Move focus down.
function wm.focus_down() end

---Focus a window by ID.
---@param id integer
function wm.focus(id) end

---Exchange with left neighbor.
function wm.exchange_left() end
---Exchange with right neighbor.
function wm.exchange_right() end
---Exchange with up neighbor.
function wm.exchange_up() end
---Exchange with down neighbor.
function wm.exchange_down() end

---Register map (window creation) callback.
---@param func fun(id: integer, focused: integer|nil)
function wm.on_map(func) end

---Register unmap (window destruction) callback.
---@param func fun(id: integer)
function wm.on_unmap(func) end

---Get focused window ID.
---@return integer|nil
function wm.get_focused() end

---Add layout focus edge.
---@param a integer
---@param b integer
---@param dir string # "left", "right", "up", "down"
---@param weight number
function wm.add_edge(a, b, dir, weight) end

---Remove a window node.
---@param id integer
function wm.remove_node(id) end

---Insert window to the right.
---@param anchor integer
---@param new integer
function wm.insert_right(anchor, new) end

---Insert window below.
---@param anchor integer
---@param new integer
function wm.insert_below(anchor, new) end

---Insert window to the left.
---@param anchor integer
---@param new integer
function wm.insert_left(anchor, new) end

---Insert window above.
---@param anchor integer
---@param new integer
function wm.insert_above(anchor, new) end

---Send WM_DELETE_WINDOW to focused client.
function wm.kill_client() end

-- Declare global wm
---@diagnostic disable-next-line: duplicate-set-field
_G.wm = wm
