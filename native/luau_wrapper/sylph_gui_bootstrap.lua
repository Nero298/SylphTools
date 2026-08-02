-- sylph_gui_bootstrap.lua
--
-- Minimal mock of the Roblox Instance/GUI API, loaded into every Script
-- Runner session BEFORE the user's script runs. This is NOT a full Roblox
-- emulator — it only implements enough of the surface area (Instance.new,
-- common GUI class properties, UDim2/Color3/Vector2 constructors, event
-- :Connect, and game/workspace/Players plumbing) for scripts that build a
-- ScreenGui out of Frames/TextButtons/TextLabels/etc. to run without errors
-- and have their UI tree be inspectable from the Dart side.
--
-- Design: every Instance is a Luau table wrapped with a metatable. Reading
-- an unset property returns a sensible default; writing any property just
-- records it in the instance's own `__props` table. Snapshots are
-- pull-based: the host calls __sylph_dump() whenever it wants a fresh
-- JSON description of the current tree (after the script runs, and again
-- after every __sylph_fire call, since a callback may have mutated props).
-- `:Connect(fn)` stores the callback in `__conns[eventName]`, keyed by the
-- instance's own numeric id, so the host can invoke it later by id.

local INSTANCES_BY_ID = {}     -- id -> instance table, for __sylph_fire lookups
local NEXT_ID = 1

-- Properties that make sense as defaults for most GUI classes. Anything
-- not listed here just reads back as nil until explicitly set, which
-- matches real Roblox behavior closely enough for preview purposes.
local DEFAULT_PROPS = {
	Frame = { Size = "UDim2:0,100,0,100", BackgroundColor3 = "Color3:255,255,255", Visible = true, BackgroundTransparency = 0 },
	TextLabel = { Size = "UDim2:0,100,0,40", Text = "", TextColor3 = "Color3:0,0,0", TextSize = 14, BackgroundTransparency = 1, Visible = true },
	TextButton = { Size = "UDim2:0,100,0,40", Text = "Button", TextColor3 = "Color3:0,0,0", TextSize = 14, BackgroundColor3 = "Color3:225,225,225", Visible = true },
	ImageLabel = { Size = "UDim2:0,100,0,100", Image = "", BackgroundTransparency = 1, Visible = true },
	TextBox = { Size = "UDim2:0,150,0,36", Text = "", PlaceholderText = "", TextColor3 = "Color3:0,0,0", Visible = true },
	ScrollingFrame = { Size = "UDim2:0,200,0,200", BackgroundColor3 = "Color3:255,255,255", Visible = true },
	UIListLayout = { FillDirection = "Vertical", Padding = "UDim:0,4" },
	UIPadding = {},
	UICorner = { CornerRadius = "UDim:0,8" },
	ScreenGui = { Visible = true },
	Folder = {},
}

-- ── Tiny constructor helpers (UDim2, Color3, Vector2) ─────────────
-- These are just plain tables with a __type tag + a custom __tostring so
-- the serializer (below) can recognize and format them without needing a
-- real Roblox type system underneath.

local function newUDim2(xScale, xOffset, yScale, yOffset)
	return setmetatable(
		{ X = { Scale = xScale or 0, Offset = xOffset or 0 }, Y = { Scale = yScale or 0, Offset = yOffset or 0 }, __type = "UDim2" },
		{ __tostring = function(v) return string.format("UDim2:%g,%g,%g,%g", v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset) end }
	)
end

local function newUDim(scale, offset)
	return setmetatable(
		{ Scale = scale or 0, Offset = offset or 0, __type = "UDim" },
		{ __tostring = function(v) return string.format("UDim:%g,%g", v.Scale, v.Offset) end }
	)
end

local function newColor3(r, g, b)
	-- Roblox Color3 components are 0..1 floats; we store 0..255 internally
	-- for easy CSS-like consumption on the Dart side.
	return setmetatable(
		{ R = r or 0, G = g or 0, B = b or 0, __type = "Color3" },
		{ __tostring = function(v) return string.format("Color3:%g,%g,%g", v.R * 255, v.G * 255, v.B * 255) end }
	)
end

local function newVector2(x, y)
	return setmetatable(
		{ X = x or 0, Y = y or 0, __type = "Vector2" },
		{ __tostring = function(v) return string.format("Vector2:%g,%g", v.X, v.Y) end }
	)
end

UDim2 = { new = newUDim2, fromScale = function(x, y) return newUDim2(x, 0, y, 0) end, fromOffset = function(x, y) return newUDim2(0, x, 0, y) end }
UDim = { new = newUDim }
Color3 = { new = newColor3, fromRGB = function(r, g, b) return newColor3(r / 255, g / 255, b / 255) end }
Vector2 = { new = newVector2 }
Enum = setmetatable({}, { __index = function(_, k) return setmetatable({}, { __index = function(_, k2) return k .. "." .. k2 end }) end })

-- ── The Instance metatable ─────────────────────────────────────────

local InstanceMeta = {}
InstanceMeta.__index = function(inst, key)
	local method = InstanceMeta[key]
	if method ~= nil then return method end

	local props = rawget(inst, "__props")
	if props[key] ~= nil then return props[key] end

	-- Children can be indexed by name, Roblox-style (e.g. frame.Title).
	for _, child in ipairs(rawget(inst, "__children")) do
		if rawget(child, "__props").Name == key then return child end
	end

	return nil
end

InstanceMeta.__newindex = function(inst, key, value)
	if key == "Parent" then
		local oldParent = rawget(inst, "__parent")
		if oldParent then
			local siblings = rawget(oldParent, "__children")
			for i, c in ipairs(siblings) do
				if c == inst then table.remove(siblings, i) break end
			end
		end
		rawset(inst, "__parent", value)
		if value ~= nil and rawget(value, "__children") ~= nil then
			table.insert(rawget(value, "__children"), inst)
		end
		return
	end

	rawget(inst, "__props")[key] = value
end

function InstanceMeta:FindFirstChild(name)
	for _, child in ipairs(rawget(self, "__children")) do
		if rawget(child, "__props").Name == name then return child end
	end
	return nil
end

function InstanceMeta:GetChildren()
	local out = {}
	for i, c in ipairs(rawget(self, "__children")) do out[i] = c end
	return out
end

function InstanceMeta:Destroy()
	self.Parent = nil
end

function InstanceMeta:IsA(className)
	return rawget(self, "__props").ClassName == className
end

-- Event objects (returned for keys like .MouseButton1Click / .Activated /
-- .Changed) — each is its own tiny table so :Connect(fn) can be stored
-- against the (instance id, event name) pair for later firing.
local EventMeta = {}
EventMeta.__index = EventMeta
function EventMeta:Connect(callback)
	local inst = rawget(self, "__inst")
	local name = rawget(self, "__name")
	local conns = rawget(inst, "__conns")
	conns[name] = conns[name] or {}
	table.insert(conns[name], callback)
	return { Disconnect = function() end }
end

local GUI_EVENT_NAMES = {
	MouseButton1Click = true, MouseButton1Down = true, MouseButton1Up = true,
	MouseEnter = true, MouseLeave = true, Activated = true,
	FocusLost = true, Changed = true,
}

-- Patch __index so GUI event names resolve to an Event object instead of
-- falling through to nil.
local baseIndex = InstanceMeta.__index
InstanceMeta.__index = function(inst, key)
	if GUI_EVENT_NAMES[key] then
		return setmetatable({ __inst = inst, __name = key }, EventMeta)
	end
	return baseIndex(inst, key)
end

-- ── Instance.new ───────────────────────────────────────────────────

Instance = {}
function Instance.new(className, parent)
	local id = NEXT_ID
	NEXT_ID = NEXT_ID + 1

	local defaults = DEFAULT_PROPS[className] or {}
	local props = { ClassName = className, Name = className }
	for k, v in pairs(defaults) do props[k] = v end

	local inst = setmetatable({
		__id = id,
		__props = props,
		__children = {},
		__conns = {},
		__parent = nil,
	}, InstanceMeta)

	INSTANCES_BY_ID[id] = inst

	if parent ~= nil then
		inst.Parent = parent
	end

	return inst
end

-- ── game / workspace / Players plumbing ─────────────────────────────
-- Just enough for the common `game.Players.LocalPlayer.PlayerGui` and
-- `game:GetService("...")` idioms to resolve to *something* sane instead
-- of erroring on nil-index.

local playerGui = Instance.new("Folder")
playerGui.Name = "PlayerGui"

-- PlayerGui is stored as a plain prop value (not JSON-serialized directly
-- since propToJson only knows about primitives/UDim2/Color3 — but that's
-- fine, __sylph_dump walks the tree from `playerGui` directly and never
-- serializes localPlayer's own prop table).
local localPlayer = setmetatable(
	{ __props = { Name = "LocalPlayer", ClassName = "Player", PlayerGui = playerGui }, __children = {}, __conns = {}, __parent = nil },
	InstanceMeta
)

local Players = { LocalPlayer = localPlayer }
local services = {
	Players = Players,
	Lighting = Instance.new("Folder"),
	ReplicatedStorage = Instance.new("Folder"),
	RunService = { RenderStepped = { Connect = function() return { Disconnect = function() end } end }, Heartbeat = { Connect = function() return { Disconnect = function() end } end } },
	UserInputService = { InputBegan = { Connect = function() return { Disconnect = function() end } end } },
	TweenService = { Create = function(inst, info, props) return { Play = function() for k, v in pairs(props) do inst[k] = v end end } end },
}

game = {
	Players = Players,
	Workspace = Instance.new("Folder"),
	GetService = function(_, name) return services[name] end,
}
workspace = game.Workspace

-- ── Serialization: dump the tree rooted at PlayerGui + ROOT ─────────

local function escapeJson(s)
	s = tostring(s)
	s = s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n')
	return s
end

local function propToJson(v)
	if v == nil then return "null" end
	if type(v) == "boolean" then return tostring(v) end
	if type(v) == "number" then return tostring(v) end
	if type(v) == "table" and v.__type then return '"' .. escapeJson(tostring(v)) .. '"' end
	if type(v) == "table" or type(v) == "function" then return "null" end -- Instance refs, closures, etc. aren't renderable props
	return '"' .. escapeJson(tostring(v)) .. '"'
end

local function dumpInstance(inst)
	local props = rawget(inst, "__props")
	local parts = { '{"id":' .. rawget(inst, "__id") .. ',"className":"' .. escapeJson(props.ClassName or "?") .. '","props":{' }
	local first = true
	for k, v in pairs(props) do
		if k ~= "ClassName" then
			if not first then table.insert(parts, ",") end
			first = false
			table.insert(parts, '"' .. escapeJson(k) .. '":' .. propToJson(v))
		end
	end
	table.insert(parts, '},"children":[')
	local children = rawget(inst, "__children")
	for i, child in ipairs(children) do
		if i > 1 then table.insert(parts, ",") end
		table.insert(parts, dumpInstance(child))
	end
	table.insert(parts, ']}')
	return table.concat(parts)
end

function __sylph_dump()
	local parts = { "[" }
	for i, inst in ipairs(rawget(playerGui, "__children")) do
		if i > 1 then table.insert(parts, ",") end
		table.insert(parts, dumpInstance(inst))
	end
	table.insert(parts, "]")
	return table.concat(parts)
end

-- ── Firing events back from the host (Dart) ─────────────────────────
-- Called by the bridge when the user taps a button in the preview.
-- Returns "OK" or "ERROR\n<message>" as a plain string.

function __sylph_fire(instanceId, eventName)
	local inst = INSTANCES_BY_ID[instanceId]
	if not inst then return "ERROR\nUnknown instance id" end
	local conns = rawget(inst, "__conns")
	local handlers = conns[eventName]
	if not handlers then return "OK" end
	for _, fn in ipairs(handlers) do
		local ok, err = pcall(fn)
		if not ok then return "ERROR\n" .. tostring(err) end
	end
	return "OK"
end
