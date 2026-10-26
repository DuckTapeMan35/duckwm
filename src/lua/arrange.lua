-- wm.arrange: writing arrangers in Lua, without the boilerplate. Built into
-- duckwm (src/lua/arrange.lua), the same as duckwm_rs, duckwm_py and
-- libduckwm's arrange, tree and geometry modules.
--
--   local A = wm.arrange
--   local tile = A.arranger("tile", function(s)
--       local order = A.track(s, A.state(s, {}))  -- window order, kept as the state
--       local layout = A.row(order[1], A.col(table.unpack(order, 2))):ratios({ 0.55, 0.45 })
--       return A.reply(s, layout, order)
--   end)
--   A.set_default(tile)  -- or the ready-made A.tile, A.fair, A.grid
--
-- An arranger gets a snapshot s of its workspace (s.event, s.id, s.prev_id,
-- s.work_area, s.windows, s.layout, s.state...) and returns the whole layout
-- and the state to keep; duckwm stores the state per workspace. Window
-- constraints are relative to the work area. Containers are named by keys:
-- duckwm creates the ones a layout mentions and drops the others.

---@class wm.arrange
local A = {}

-- ------------------------------------------------------------
-- Rectangles
-- ------------------------------------------------------------

---@class wm.Rect
---@field x integer
---@field y integer
---@field width integer
---@field height integer
local Rect = {}
Rect.__index = Rect

---A rectangle: position, then size.
---@return wm.Rect
function A.rect(x, y, width, height)
	return setmetatable({ x = x, y = y, width = width, height = height }, Rect)
end

-- How much of total: a float is a fraction, an integer is pixels.
local function length(total, amount)
	local n = math.type(amount) == "float" and math.floor(total * amount + 0.5) or amount
	return math.max(0, math.min(total, n))
end

---Take a piece off one side ("left", "right", "top", "bottom"): the piece,
---and what's left. amount: a float is a fraction (0.25), an integer pixels (30).
---@return wm.Rect piece, wm.Rect rest
function Rect:cut(side, amount)
	local x, y, w, h = self.x, self.y, self.width, self.height
	if side == "left" then
		local p = length(w, amount)
		return A.rect(x, y, p, h), A.rect(x + p, y, w - p, h)
	elseif side == "right" then
		local p = length(w, amount)
		return A.rect(x + w - p, y, p, h), A.rect(x, y, w - p, h)
	elseif side == "top" then
		local p = length(h, amount)
		return A.rect(x, y, w, p), A.rect(x, y + p, w, h - p)
	elseif side == "bottom" then
		local p = length(h, amount)
		return A.rect(x, y + h - p, w, p), A.rect(x, y, w, h - p)
	end
	error("cut: side is left, right, top or bottom, not " .. tostring(side), 2)
end

---Side by side ("h") or stacked ("v"), by a list of ratios or into n equal
---parts. The pieces cover the rectangle exactly.
---@return wm.Rect[]
function Rect:split(axis, ratios)
	if type(ratios) == "number" then
		local n = ratios
		ratios = {}
		for i = 1, n do
			ratios[i] = 1
		end
	end
	local total = 0
	for _, r in ipairs(ratios) do
		total = total + r
	end
	local len = axis == "h" and self.width or self.height
	local out, acc, prev = {}, 0, 0
	for i, r in ipairs(ratios) do
		acc = acc + r
		local e = math.floor(len * acc / total + 0.5)
		if axis == "h" then
			out[i] = A.rect(self.x + prev, self.y, e - prev, self.height)
		else
			out[i] = A.rect(self.x, self.y + prev, self.width, e - prev)
		end
		prev = e
	end
	return out
end

---rows x cols cells, row by row.
---@return wm.Rect[]
function Rect:grid(rows, cols)
	local out = {}
	for _, line in ipairs(self:split("v", rows)) do
		for _, cell in ipairs(line:split("h", cols)) do
			out[#out + 1] = cell
		end
	end
	return out
end

-- ------------------------------------------------------------
-- What an arranger sees
-- ------------------------------------------------------------

---The tiled windows, in the order they appeared; not one being unmapped.
---@return integer[]
function A.windows(s)
	local out = {}
	for _, w in ipairs(s.windows or {}) do
		if not (s.event == "unmap" and w.id == s.id) then
			out[#out + 1] = w.id
		end
	end
	return out
end

---A window's rectangle, as duckwm has it now.
---@return wm.Rect?
function A.geometry(s, id)
	for _, w in ipairs(s.windows or {}) do
		if w.id == id then
			local g = w.geometry
			return A.rect(g.x, g.y, g.width, g.height)
		end
	end
end

---The work area, relative to itself: what window constraints are measured in.
---@return wm.Rect
function A.area(s)
	return A.rect(0, 0, s.work_area.width, s.work_area.height)
end

---The state as stored, or default if it's missing or not a table.
function A.state(s, default)
	return type(s.state) == "table" and s.state or default
end

---Keyed container k's split ratios as duckwm has them: resizes end up here.
---@return number[]?
function A.ratios_of(s, k)
	for _, n in ipairs((s.layout or {}).nodes or {}) do
		if type(n.id) == "table" and n.id.key == k then
			for _, c in ipairs(n.constraints or {}) do
				if c.type == "split" then
					return c.ratios
				end
			end
		end
	end
end

---Last time's window order, minus closed windows, plus new ones: a new
---window goes after the one that was focused, any others at the end.
---(duckwm calls an arranger with pre_map before map, the new window already
---in that snapshot: it's placed then, and map finds it in place.)
---@param old integer[] last time's order, e.g. kept as the state
---@return integer[]
function A.track(s, old)
	local present, out, seen = {}, {}, {}
	for _, w in ipairs(A.windows(s)) do
		present[w] = true
	end
	for _, w in ipairs(old or {}) do
		if present[w] and not seen[w] then
			out[#out + 1], seen[w] = w, true
		end
	end
	for _, w in ipairs(A.windows(s)) do
		if not seen[w] then
			local pos = #out + 1
			if (s.event == "map" or s.event == "pre_map") and w == s.id then
				for i, x in ipairs(out) do
					if x == s.prev_id then
						pos = i + 1
					end
				end
			end
			table.insert(out, pos, w)
			seen[w] = true
		end
	end
	return out
end

-- ------------------------------------------------------------
-- Nodes and constraints
-- ------------------------------------------------------------

---A container, by key.
function A.key(k)
	return { key = k }
end

---Position and size, relative to the work area.
function A.fixed(x, y, w, h)
	return {
		{ type = "fixed_x", value = x },
		{ type = "fixed_y", value = y },
		{ type = "fixed_width", value = math.max(0, w) },
		{ type = "fixed_height", value = math.max(0, h) },
	}
end

---A node (a window id, or A.key(k)) placed at a rectangle of the work area:
---A.at(id, rect) or A.at(id, x, y, w, h).
function A.at(id, x, y, w, h)
	if type(x) == "table" then
		x, y, w, h = x.x, x.y, x.width, x.height
	end
	return { id = id, constraints = A.fixed(x, y, w, h) }
end

function A.grid_cell(container, col, row, cols, rows)
	return { type = "grid_cell", col = col, row = row, cols = cols, rows = rows, container = container }
end

---An exact rectangle inside container, in its own coordinates.
function A.cell_abs(container, x, y, w, h)
	return { type = "grid_cell_abs", x = x, y = y, w = math.max(0, w), h = math.max(0, h), container = container }
end

---The whole of container.
function A.fill(container)
	return A.grid_cell(container, 0, 0, 1, 1)
end

---Divide container among children, side by side ("h") or stacked ("v");
---equal shares without ratios.
function A.split(container, axis, children, ratios)
	if not ratios then
		ratios = {}
		for i = 1, #children do
			ratios[i] = 1 / #children
		end
	end
	return { type = "split", container = container, axis = axis, ratios = ratios, children = children }
end

-- ------------------------------------------------------------
-- Trees of rows and columns
-- ------------------------------------------------------------

---@class wm.Branch
---@field axis "h"|"v"
---@field kids (integer|wm.Branch)[]
local Branch = {}
Branch.__index = Branch

local function branch(axis, ...)
	local kids = {}
	for i = 1, select("#", ...) do -- nil children are skipped
		local c = select(i, ...)
		if c ~= nil then
			kids[#kids + 1] = c
		end
	end
	return setmetatable({ axis = axis, kids = kids }, Branch)
end

---Children side by side: window ids or other rows and columns; nil ones are
---skipped. A row of nothing is nothing, and a row of one is just that one.
---@return wm.Branch
function A.row(...)
	return branch("h", ...)
end

---Children stacked top to bottom.
---@return wm.Branch
function A.col(...)
	return branch("v", ...)
end

---Shares of the row or column; ignored unless there's one per child.
---@return wm.Branch
function Branch:ratios(r)
	self.ratio_list = r
	return self
end

---A key of its own, instead of the depth-first one: for layouts that
---restructure, so a container keeps its key (and its resized ratios).
---@return wm.Branch
function Branch:key(k)
	self.k_given = k
	return self
end

-- The tree with empty branches dropped and lone children in their parent's place.
local function simplify(t)
	if getmetatable(t) ~= Branch then
		return t
	end
	local kids = {}
	for _, c in ipairs(t.kids) do
		local s = simplify(c)
		if s ~= nil then
			kids[#kids + 1] = s
		end
	end
	if #kids == 0 then
		return nil
	end
	if #kids == 1 and t.k_given == nil then
		return kids[1]
	end
	local ratios = t.ratio_list
	if ratios and #ratios ~= #kids then
		ratios = nil
	end
	return { axis = t.axis, kids = kids, ratios = ratios, key = t.k_given }
end

---A tree as nodes: keyed containers holding splits; the root fills the work
---area. Keys are depth-first from 0 unless given; a container's ratios as
---duckwm has them win over the tree's while it has the same number of
---children, so resizes stick until the shape changes.
function A.compile(s, tree)
	local t = simplify(tree)
	local area = A.area(s)
	if t == nil then
		return {}
	end
	if type(t) ~= "table" then
		return { A.at(t, area) }
	end
	local branches, taken = {}, {}
	local function walk(b)
		branches[#branches + 1] = b
		if b.key then
			taken[b.key] = true
		end
		for _, c in ipairs(b.kids) do
			if type(c) == "table" then
				walk(c)
			end
		end
	end
	walk(t)
	local auto = 0
	for _, b in ipairs(branches) do
		if b.key then
			b.k = b.key
		else
			while taken[auto] do
				auto = auto + 1
			end
			b.k, auto = auto, auto + 1
		end
	end
	local nodes = {}
	for _, b in ipairs(branches) do
		local stored = A.ratios_of(s, b.k) or {}
		local usable = #stored == #b.kids
		for _, r in ipairs(stored) do
			usable = usable and r > 0
		end
		local kids = {}
		for i, c in ipairs(b.kids) do
			kids[i] = type(c) == "table" and A.key(c.k) or c
		end
		local cons = b == t and A.fixed(0, 0, area.width, area.height) or {}
		cons[#cons + 1] = A.split(A.key(b.k), b.axis, kids, usable and stored or b.ratios)
		nodes[#nodes + 1] = { id = A.key(b.k), constraints = cons }
		for _, c in ipairs(b.kids) do
			if type(c) ~= "table" then
				nodes[#nodes + 1] = { id = c, constraints = {} }
			end
		end
	end
	return nodes
end

---What an arranger returns: the whole layout (a tree of A.row/A.col, a
---window id, or a list of nodes) and the state to keep (nil leaves it
---alone). A newly mapped window gets focus.
function A.reply(s, layout, state)
	local nodes
	if layout == nil or type(layout) == "number" or getmetatable(layout) == Branch then
		nodes = A.compile(s, layout)
	else
		nodes = layout
	end
	if s.event == "map" then
		pcall(wm.focus, s.id)
	end
	return { nodes = nodes }, state
end

-- ------------------------------------------------------------
-- Arrangers
-- ------------------------------------------------------------

---@class wm.Arranger
---@field name string
---@field fn fun(s: table): table, any

---A layout function and its name (what get_arranger_name shows). If it
---fails, the error is reported and the workspace laid out as a grid this
---time, its state reset so the next call starts over.
---@param fn fun(s: table): table, any
---@return wm.Arranger
function A.arranger(name, fn)
	return { name = name, fn = fn }
end

local reported = {}

---Called when an arranger fails, before the grid stands in. Replace it to
---report errors your own way; by default it writes to stderr, and shows the
---first failure of each arranger in the input bar.
---@param name string the arranger's
---@param err any what it raised
function A.on_error(name, err)
	io.stderr:write("duckwm: layout " .. name .. ": " .. tostring(err) .. "\n")
	if not reported[name] then -- once, not on every event
		reported[name] = true
		pcall(wm.message, "layout " .. name .. " failed: " .. tostring(err), 4000)
	end
end

-- What duckwm calls: a factory, returning the function it calls per event.
local function factory(a)
	return function()
		return function(_, _, _, s)
			local ok, layout, state = pcall(a.fn, s)
			if ok then
				return layout, state
			end
			pcall(A.on_error, a.name, layout)
			local nodes = A.grid.fn(s)
			return nodes, false
		end
	end
end

---This workspace gets arranger a.
function A.set(a)
	wm.set_arranger(factory(a), a.name)
end

---New workspaces, and those whose arranger went away, get a; this one too.
function A.set_default(a)
	wm.set_default_arranger(factory(a), a.name)
	A.set(a)
end

---Node id (a workspace or group) gets arranger a.
function A.register(id, a)
	wm.register_arranger(id, factory(a), a.name)
end

---Bind a key to switching this workspace to arranger a.
function A.bind(mods, key, a)
	wm.bind(mods, key, function()
		A.set(a)
	end)
end

-- ------------------------------------------------------------
-- Ready-made arrangers
-- ------------------------------------------------------------

---As square as fits, filled row by row. No state, nothing to go wrong:
---also what a failing arranger falls back to.
A.grid = A.arranger("grid", function(s)
	local ws = A.windows(s)
	if #ws == 0 then
		return A.reply(s, {})
	end
	local cols = math.ceil(math.sqrt(#ws))
	local rows = math.ceil(#ws / cols)
	local cells = A.area(s):grid(rows, cols)
	local nodes = {}
	for i, w in ipairs(ws) do
		nodes[i] = A.at(w, cells[i])
	end
	return A.reply(s, nodes)
end)

---Columns of near-equal windows: two side by side, then as square as possible.
A.fair = A.arranger("fair", function(s)
	local ws = A.windows(s)
	local rows = #ws == 2 and 1 or math.max(1, math.ceil(math.sqrt(#ws)))
	local columns = {}
	for i = 1, #ws, rows do
		columns[#columns + 1] = A.col(table.unpack(ws, i, math.min(#ws, i + rows - 1)))
	end
	return A.reply(s, A.row(table.unpack(columns)))
end)

---Master and stack: the first window on the left, the rest stacked on the right.
A.tile = A.arranger("tile", function(s)
	local order = A.track(s, A.state(s, {}))
	local master = order[1]
	local layout = A.row(master, A.col(table.unpack(order, 2))):ratios({ 0.55, 0.45 })
	return A.reply(s, layout, order)
end)

wm.arrange = A
return A
