local load, xpcall, select, tostring, type, pairs, ipairs = load, xpcall, select, tostring, type, pairs, ipairs
local concat, sort, pack = table.concat, table.sort, table.pack
local clock, sethook, traceback = os.clock, debug.sethook, debug.traceback

local limit = 2 -- seconds of CPU before a snippet is stopped

local function show(v, depth, seen)
	local t = type(v)
	if t == "string" then
		return string.format("%q", v)
	end
	if t ~= "table" then
		return tostring(v)
	end
	if seen[v] then
		return "<cycle>"
	end
	if depth >= 4 then
		return "{...}"
	end
	seen[v] = true
	local parts, n = {}, #v
	for i = 1, n do
		parts[#parts + 1] = show(v[i], depth + 1, seen)
	end
	local keys = {}
	for k in pairs(v) do
		if not (math.type(k) == "integer" and k >= 1 and k <= n) then
			keys[#keys + 1] = k
		end
	end
	sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	for _, k in ipairs(keys) do
		local name = type(k) == "string" and k:match("^[%a_][%w_]*$") and k or "[" .. show(k, depth + 1, seen) .. "]"
		parts[#parts + 1] = name .. " = " .. show(v[k], depth + 1, seen)
	end
	seen[v] = nil
	return #parts == 0 and "{}" or "{ " .. concat(parts, ", ") .. " }"
end

return function(src)
	-- An expression shows its value; otherwise it runs as statements.
	local f = load("return " .. src, "=repl", "t")
	if not f then
		local err
		f, err = load(src, "=repl", "t")
		if not f then
			if err:find("<eof>$") then
				return "incomplete", ""
			end
			return "error", err .. "\n"
		end
	end

	-- print() goes to the REPL while the snippet runs.
	local out, saved = {}, _G.print
	_G.print = function(...)
		local s = {}
		for i = 1, select("#", ...) do
			s[i] = tostring((select(i, ...)))
		end
		out[#out + 1] = concat(s, "\t") .. "\n"
	end
	local deadline = clock() + limit
	sethook(function()
		if clock() > deadline then
			error("stopped: ran for more than " .. limit .. "s", 2)
		end
	end, "", 100000)
	local res = pack(xpcall(f, function(e)
		-- The traceback stops at the snippet: the frames below it are the REPL's.
		return (traceback(tostring(e), 2):gsub("\n[^\n]*'xpcall'.*$", ""))
	end))
	sethook()
	_G.print = saved

	if not res[1] then
		out[#out + 1] = tostring(res[2]) .. "\n"
		return "error", concat(out)
	end
	local vals = {}
	for i = 2, res.n do
		vals[#vals + 1] = show(res[i], 0, {})
	end
	if #vals > 0 then
		out[#out + 1] = concat(vals, "\t") .. "\n"
	end
	return "ok", concat(out)
end
