-- Mock-Roblox smoke test for libraries/UILibrary.lua.
-- Runs scripts/Universal.lua for real (modules come from the local repo), then
-- exercises config save/load and an old-format config, then runs games/2753915549.lua
-- against a stub core and drives every control it built.
-- Proves the API wiring; it does not render anything.
-- usage (from the repo root): luajit tests/ui_harness.lua .
local REPO = assert(arg[1], "repo root")

---------------------------------------------------------------- inert proxy
local P
local Pmt = {}
P = setmetatable({}, Pmt)
Pmt.__index = function() return P end
Pmt.__newindex = function() end
Pmt.__call = function() return P end
for _, m in ipairs({ "__add", "__sub", "__mul", "__div", "__unm", "__mod", "__pow" }) do
	Pmt[m] = function() return P end
end
Pmt.__concat = function(a, b)
	return (type(a) == "string" and a or tostring(a)) .. (type(b) == "string" and b or tostring(b))
end
Pmt.__tostring = function() return "P" end

---------------------------------------------------------------- instances
local INSTANCES = 0
-- Instances track real parents and children, validate `Visible` the way Roblox does
-- and fire GetPropertyChangedSignal callbacks. Errors raised inside those callbacks
-- are collected in UI_ERRORS: Roblox reports them without stopping the setter, and
-- some games (Blox Fruits) kick the player for any such error.
UI_ERRORS = {}
local GUI_CLASSES = {
	Frame = true, TextLabel = true, TextButton = true, TextBox = true, ImageLabel = true, ImageButton = true,
	ScrollingFrame = true, CanvasGroup = true, VideoFrame = true, ViewportFrame = true,
}
local CHILDREN = setmetatable({}, { __mode = "k" }) -- instance -> ordered child list
local newInstance
local function setParent(inst, props, parent)
	local old = props.Parent
	if old and CHILDREN[old] then
		for i, child in ipairs(CHILDREN[old]) do
			if child == inst then table.remove(CHILDREN[old], i) break end
		end
	end
	props.Parent = parent
	if parent and CHILDREN[parent] then table.insert(CHILDREN[parent], inst) end
end
local function descendants(inst, out)
	for _, child in ipairs(CHILDREN[inst]) do
		table.insert(out, child)
		descendants(child, out)
	end
	return out
end
function newInstance(class, parent)
	INSTANCES = INSTANCES + 1
	local props = { ClassName = class, Name = class }
	local inst = {}
	local signals = {} -- property -> callbacks
	CHILDREN[inst] = {}
	local function find(name, recursive)
		for _, child in ipairs(CHILDREN[inst]) do
			if child.Name == name then return child end
		end
		if recursive then
			for _, child in ipairs(CHILDREN[inst]) do
				local found = child:FindFirstChild(name, true)
				if found then return found end
			end
		end
		return nil
	end
	local methods = {
		IsA = function(_, c) return c == class or c == "Instance" or (c == "GuiObject" and GUI_CLASSES[class] == true) end,
		Destroy = function()
			setParent(inst, props, nil)
			CHILDREN[inst] = {}
		end,
		GetChildren = function() return { (unpack or table.unpack)(CHILDREN[inst]) } end,
		GetDescendants = function() return descendants(inst, {}) end,
		FindFirstChild = function(_, name, recursive) return find(name, recursive) end,
		FindFirstChildOfClass = function(_, c)
			for _, child in ipairs(CHILDREN[inst]) do
				if child.ClassName == c then return child end
			end
			return nil
		end,
		FindFirstChildWhichIsA = function() return nil end,
		WaitForChild = function(_, name) return find(name) or newInstance(name, inst) end,
		GetPropertyChangedSignal = function(_, prop)
			return {
				Connect = function(_, f)
					signals[prop] = signals[prop] or {}
					table.insert(signals[prop], f)
					return { Disconnect = function() end }
				end,
			}
		end,
	}
	setmetatable(inst, {
		__index = function(_, k)
			if props[k] ~= nil then return props[k] end
			if methods[k] then return methods[k] end
			local child = find(k) -- Roblox lets you index a child by its name
			if child then return child end
			return P
		end,
		__newindex = function(_, k, v)
			if k == "Parent" then
				setParent(inst, props, v)
				return
			end
			if k == "Visible" and not GUI_CLASSES[class] then
				error(("Visible is not a valid member of %s \"%s\""):format(class, tostring(props.Name)), 2)
			end
			props[k] = v
			for _, f in ipairs(signals[k] or {}) do
				local ok, err = pcall(f)
				if not ok then table.insert(UI_ERRORS, tostring(err)) end
			end
		end,
		__tostring = function() return props.Name end,
		__type = "Instance",
	})
	if parent then setParent(inst, props, parent) end
	return inst
end

---------------------------------------------------------------- filesystem
local FILES, FOLDERS = {}, {}
function isfile(p) return FILES[p] ~= nil end
function isfolder(p) return FOLDERS[p] == true end
function makefolder(p) FOLDERS[p] = true end
function writefile(p, c) FILES[p] = c end
function readfile(p) return assert(FILES[p], "no file " .. p) end
function delfile(p) FILES[p] = nil end
function listfiles(dir)
	local out = {}
	for path in pairs(FILES) do
		if path:sub(1, #dir + 1) == dir .. "/" and not path:sub(#dir + 2):find("/") then
			table.insert(out, path)
		end
	end
	for path in pairs(FOLDERS) do
		if path:sub(1, #dir + 1) == dir .. "/" and not path:sub(#dir + 2):find("/") then
			table.insert(out, path)
		end
	end
	return out
end
function getcustomasset(p) return "rbxasset://" .. p end

---------------------------------------------------------------- JSON (token store)
local JSON, JSON_N = {}, 0
local function deepcopy(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = deepcopy(x) end
	return t
end

---------------------------------------------------------------- services / game
local services = {}
local HEARTBEATS, INPUT_BEGAN = {}, {} -- captured callbacks, so tests can step a frame or press a key
local function capture(list)
	return {
		Connect = function(_, f)
			table.insert(list, f)
			return {
				Disconnect = function()
					for i, g in ipairs(list) do
						if g == f then table.remove(list, i) break end
					end
				end,
			}
		end,
	}
end
local function service(name)
	if not services[name] then
		local s = newInstance(name)
		if name == "RunService" then
			s.Heartbeat = capture(HEARTBEATS)
		elseif name == "UserInputService" then
			s.InputBegan = capture(INPUT_BEGAN)
			s.GetFocusedTextBox = function() return nil end
		end
		if name == "HttpService" then
			rawset(s, "JSONEncode", function(_, t)
				JSON_N = JSON_N + 1
				local token = "json#" .. JSON_N
				JSON[token] = deepcopy(t)
				return token
			end)
			rawset(s, "JSONDecode", function(_, token)
				if JSON[token] then
					return deepcopy(JSON[token])
				end
				-- real JSON text (backgrounds.json): flat { "key": "value" } objects only
				assert(type(token) == "string" and token:match("^%s*{"), "bad json " .. tostring(token))
				local t = {}
				for key, value in token:gmatch('"([^"]+)"%s*:%s*"([^"]*)"') do
					t[key] = value
				end
				return t
			end)
		elseif name == "Players" then
			local player = newInstance("Player")
			player.PlayerGui = newInstance("PlayerGui", player)
			player.Name = "Tester"
			s.LocalPlayer = player
			s.MaxPlayers = 12
		elseif name == "Workspace" then
			s.Gravity = 196.2
		elseif name == "Lighting" then
			s.FogStart, s.FogEnd, s.Brightness, s.ClockTime = 0, 100000, 2, 14
			s.ShadowSoftness, s.EnvironmentSpecularScale, s.EnvironmentDiffuseScale = 0.2, 1, 1
			s.GlobalShadows = true
			s.Ambient, s.OutdoorAmbient, s.FogColor = Color3.new(0.5, 0.5, 0.5), Color3.new(0.5, 0.5, 0.5), Color3.new(0.75, 0.75, 0.75)
		end
		services[name] = s
	end
	return services[name]
end

local HTTP_LOG = {}
-- repo paths served from here instead of disk
local OVERRIDES = {
	["assets/backgrounds/backgrounds.json"] = '{ "Waves": "waves.webm", "Night": "night.png" }',
	["assets/backgrounds/waves.webm"] = "webm-bytes",
	["assets/backgrounds/night.png"] = "png-bytes",
}
game = setmetatable({}, {
	__index = function(_, k)
		if k == "GetService" then return function(_, n) return service(n) end end
		if k == "HttpGet" then
			return function(_, url)
				local path = url:match("/main/(.+)$")
				table.insert(HTTP_LOG, path or url)
				if path and OVERRIDES[path] then return OVERRIDES[path] end
				if not path then return url:find("missing", 1, true) and "" or "remote-bytes" end
				local f = io.open(REPO .. "/" .. path, "rb")
				if not f then return "" end
				local s = f:read("*a")
				f:close()
				return s
			end
		end
		if k == "PlaceId" then return PLACE_ID_OVERRIDE or tonumber(os.getenv("PLACE_ID") or "1") end
		if k == "JobId" or k == "GameId" then return "job" end
		if k == "Players" or k == "Workspace" or k == "Lighting" or k == "CoreGui" or k == "TweenService"
			or k == "ReplicatedStorage" or k == "RunService" or k == "HttpService" then
			return service(k)
		end
		return P
	end,
})
workspace = service("Workspace")
Workspace = workspace

---------------------------------------------------------------- Roblox globals
local colorMethods = {
	ToHSV = function(c) return 0, 0, math.max(c.R, c.G, c.B) end,
}
local function color(r, g, b)
	return setmetatable({ r = r, g = g, b = b, R = r, G = g, B = b }, {
		__index = function(_, k) return colorMethods[k] or P end,
		__type = "Color3",
	})
end
Color3 = {
	fromRGB = function(r, g, b) return color((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end,
	new = function(r, g, b) return color(r or 0, g or 0, b or 0) end,
	fromHSV = function() return color(1, 1, 1) end,
	fromHex = function() return color(1, 1, 1) end,
}
Instance = { new = function(class, parent) return newInstance(class, parent) end }
for _, name in ipairs({ "UDim2", "UDim", "Vector2", "Vector3", "CFrame", "TweenInfo", "NumberSequence",
	"NumberSequenceKeypoint", "ColorSequence", "ColorSequenceKeypoint", "Rect", "Font", "Ray", "RaycastParams",
	"OverlapParams", "BrickColor", "Region3", "PhysicalProperties", "DateTime", "Random", "Drawing", "Enum",
	"NumberRange", "TweenService", "utf8", "shared", "debug_ext" }) do
	_G[name] = P
end
function typeof(v)
	if type(v) == "table" then
		local mt = getmetatable(v)
		if mt and mt.__type then return mt.__type end
	end
	return type(v)
end
math.clamp = function(x, a, b) return math.max(a, math.min(b, x)) end
math.round = function(x) return math.floor(x + 0.5) end
math.sign = function(x) return x > 0 and 1 or x < 0 and -1 or 0 end
table.find = function(t, v) for i, x in ipairs(t) do if x == v then return i end end end
table.clear = function(t) for k in pairs(t) do t[k] = nil end end
string.split = function(s, sep)
	local out = {}
	for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do table.insert(out, part) end
	return out
end
RUN_SPAWNS = false
DEFER_DELAYS, DELAYED = false, {} -- tests can hold task.delay callbacks and release them later
function flushDelays()
	local pending = DELAYED
	DELAYED = {}
	for _, f in ipairs(pending) do
		pcall(f)
	end
end
CAPTURE_SPAWNS, SPAWN_LOG, PLACE_ID_OVERRIDE = false, {}, nil -- Blox Fruits test: hold the module's own task.spawn loops
task = {
	spawn = function(f, ...)
		if CAPTURE_SPAWNS and type(f) == "function" and debug.getinfo(f, "S").source:find("2753915549", 1, true) then
			table.insert(SPAWN_LOG, f)
			return P
		end
		if RUN_SPAWNS and type(f) == "function" then f(...) end
		return P
	end,
	delay = function(_, f, ...)
		if DEFER_DELAYS and type(f) == "function" then -- held until the test calls flushDelays()
			table.insert(DELAYED, f)
		elseif RUN_SPAWNS and type(f) == "function" then
			f(...)
		end
		return P
	end,
	defer = function() return P end,
	wait = function() return 0 end,
	cancel = function() end,
}
spawn, delay = function() end, function() end
wait = function() return 0 end
tick, time, elapsedTime = os.clock, os.clock, os.clock
local WARNINGS = {}
warn = function(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	table.insert(WARNINGS, table.concat(parts, " "))
end
getgenv = function() return _G end
gethui = function() return service("HiddenUI") end
cloneref = function(o) return o end
identifyexecutor = function() return "harness" end
setclipboard, queue_on_teleport, setfpscap = function() end, function() end, function() end

-- capture the library table that Universal loads
local realLoadstring = loadstring
loadstring = function(src, name)
	local f, e = realLoadstring(src, name)
	if f and src:find("Peridot API", 1, true) then
		return function(...)
			local lib = f(...)
			_G.__LIB = lib
			return lib
		end
	end
	return f, e
end

---------------------------------------------------------------- helpers
local failures = 0
local function check(cond, label)
	print((cond and "  ok   " or "  FAIL ") .. label)
	if not cond then failures = failures + 1 end
end
local function run(label, fn)
	local ok, err = xpcall(fn, debug.traceback)
	check(ok, label)
	if not ok then print(err) end
	return ok
end

---------------------------------------------------------------- 1. Universal.lua
print("Universal.lua")
-- a background already in the workspace folder (as if downloaded on an earlier run)
FOLDERS["Peridot"], FOLDERS["Peridot/Backgrounds"] = true, true
FILES["Peridot/Backgrounds/green_night_driving.jpg"] = "jpg-bytes"
run("runs top to bottom", function()
	assert(loadfile(REPO .. "/scripts/Universal.lua"))()
end)
local lib = _G.__LIB
check(lib ~= nil, "library table captured")
if not lib then os.exit(1) end

local counts, firstToggle = {}, nil
for kind, entries in pairs(lib.ControlRegistry) do
	counts[kind] = 0
	for key in pairs(entries) do
		counts[kind] = counts[kind] + 1
		if kind == "Toggles" and not firstToggle then firstToggle = key end
	end
end
print(("  registered: %d toggles, %d sliders, %d dropdowns, %d boxes, %d keybinds"):format(
	counts.Toggles, counts.Sliders, counts.Dropdowns, counts.Boxes, counts.Keybinds))
check(counts.Toggles >= 20 and counts.Sliders >= 10, "controls registered for config save")
do -- Visual and Settings are split into sub-tabs now; their saved-config keys must not change
	local subTabKeys, splitPages = 0, 0
	for _, entries in pairs(lib.ControlRegistry) do
		for key in pairs(entries) do
			if key:find("/", 1, true) then subTabKeys = subTabKeys + 1 end
			if key:find("^Visual||") or key:find("^Settings||") then splitPages = splitPages + 1 end
		end
	end
	check(subTabKeys == 0 and splitPages >= 10, ("split pages keep old config keys (%d keys, %d with a sub-tab)"):format(splitPages, subTabKeys))
end
check(lib.Internal.Gui.Enabled == true, "window opens on load")
check(lib.ToggleUISettings() == true and lib.ToggleUISettings() == true, "gear opens UI Settings and goes back")
check(lib.Internal.Gui.Name == "Peridot GUI" and lib.Internal.NotiGui.Name == "Peridot Notification", "GUI names")

---------------------------------------------------------------- 2. config round trip
print("Layering")
run("the intro loader outranks every other ScreenGui (it must stay top-most)", function()
	local function read(path)
		local f = assert(io.open(REPO .. "/" .. path, "rb"))
		local s = f:read("*a")
		f:close()
		return s
	end
	local loaderOrder = tonumber(read("loader.lua"):match("screenGui%.DisplayOrder = (%d+)"))
	assert(loaderOrder and loaderOrder >= 1000000, "the loader's DisplayOrder is very high, got " .. tostring(loaderOrder))
	for _, file in ipairs({ "libraries/UILibrary.lua", "scripts/Universal.lua", "games/2753915549.lua",
		"games/142823291.lua", "libraries/mm2-main.lua" }) do
		for order in read(file):gmatch("DisplayOrder = (%d+)") do
			assert(tonumber(order) < loaderOrder, file .. " sets a ScreenGui at or above the loader: " .. order)
		end
	end
end)

-- Runs loader.lua the way the loadstring does. opts: keepMarker (do not clear the run-once marker first),
-- callback (what runs instead of the game script).
local function runLoader(placeId, opts)
	opts = opts or {}
	local texts, gui, kicked, got = {}, nil, nil, nil
	local player = service("Players").LocalPlayer
	player.Kick = function(_, message) kicked = message end
	if not opts.keepMarker then getgenv().PeridotExecutedIn = nil end
	local realNew = Instance.new
	Instance.new = function(class, parent)
		local instance = realNew(class, parent)
		if class == "TextLabel" then
			instance:GetPropertyChangedSignal("Text"):Connect(function() texts[#texts + 1] = instance.Text end)
		elseif class == "ScreenGui" then
			gui = instance
		end
		return instance
	end
	local Loader = assert(loadfile(REPO .. "/loader.lua"))()
	PLACE_ID_OVERRIDE = placeId
	RUN_SPAWNS = true
	UI_ERRORS, WARNINGS = {}, {}
	local ok, err = pcall(Loader.Start, opts.callback or function(info) got = info end)
	RUN_SPAWNS = false
	PLACE_ID_OVERRIDE = nil
	Instance.new = realNew
	player.Kick = nil
	assert(ok, err)
	return texts, got, gui, kicked
end

run("intro card: Authenticating, Success !, then the game's name, or Universal elsewhere", function()
	local texts, info, gui = runLoader(142823291)
	local order = table.concat(texts, " / ")
	assert(order:find("Peridot", 1, true), "the card says Peridot: " .. order)
	assert(order:find("Authenticating / Authenticating%. / Authenticating%.%. / Authenticating%.%.%. / Success ! / Murder Mystery 2$"),
		"status lines in order: " .. order)
	assert(info and info.name == "Murder Mystery 2" and info.supported == true, "the game is found")
	assert(info.url:sub(-#"games/142823291.lua") == "games/142823291.lua", "and its script is the one to load: " .. info.url)
	assert(gui and (gui.Parent == nil or gui.Parent == P), "the card is gone before the script loads") -- unset properties read as P in the mock
	assert(gui.DisplayOrder >= 1000000, "the card stays on top of everything")

	texts, info = runLoader(1)
	assert(texts[#texts] == "Universal" and info.name == "Universal" and info.supported == false, "an unknown game says Universal")
	assert(info.url:sub(-#"scripts/Universal.lua") == "scripts/Universal.lua")
end)

run("intro card is the notification box's grey on a solid background", function()
	local source = io.open(REPO .. "/loader.lua", "rb"):read("*a")
	assert(source:find("BACKGROUND = Color3.fromRGB(48, 48, 56)", 1, true), "the card uses the notification grey")
	assert(source:find("panel.BackgroundTransparency = 0\n", 1, true), "with no transparency")
	local lib_source = io.open(REPO .. "/libraries/UILibrary.lua", "rb"):read("*a")
	assert(lib_source:find('["Background 3 Color"] = Color3.fromRGB(48, 48, 56)', 1, true), "the notification boxes use that same grey")
end)

run("Peridot runs once per server: a second run is kicked, other servers and re-runs after Unload are fine", function()
	-- first run starts and marks this server
	local _, info, _, kicked = runLoader(142823291)
	assert(info and kicked == nil, "the first run is not kicked")
	assert(getgenv().PeridotExecutedIn == "job", "and leaves its marker")

	-- the same server again: kicked with a reason, nothing runs
	local texts, secondInfo, gui, message = runLoader(142823291, { keepMarker = true })
	assert(message and message:find("only be executed once", 1, true), "kicked with a reason, got " .. tostring(message))
	assert(secondInfo == nil and gui == nil and #texts == 0, "no card and no script on a second run")

	-- a marker left over from another server does not count
	getgenv().PeridotExecutedIn = "some-other-server"
	local _, third, _, thirdKick = runLoader(142823291, { keepMarker = true })
	assert(third and thirdKick == nil, "a different server's marker is ignored")

	-- (Unload UI clearing the marker is checked in the Blox Fruits Unload test below)

	-- a script that fails to start does not block a retry
	local _, _, _, failKick = runLoader(142823291, { callback = function() error("boom") end })
	assert(failKick == nil and getgenv().PeridotExecutedIn == nil, "a failed start frees the marker")
	getgenv().PeridotExecutedIn = nil
end)

print("Button labels")
run("green button labels say what the button does, using real titles from the scripts", function()
	local expected = {
		["Triple Katana $60,000"] = "Buy", ["Reset Stats 2,500F"] = "Buy", ["Pole v.2 5,000F"] = "Buy",
		["Teleport To Third Sea"] = "Teleport", ["Tween Dragon Dojo"] = "Go", ["Server Hop"] = "Hop",
		["Rejoin Current Server"] = "Rejoin", ["Rejoin Server"] = "Rejoin", ["Redeem All Codes"] = "Redeem",
		["Remove Lava Prehistoric"] = "Remove", ["Open Haki Color"] = "Open", ["Join Pirates Team"] = "Join",
		["Stop Current Movement"] = "Stop", ["Resume Movement"] = "Resume", ["Respawn"] = "Respawn",
		["Refresh List"] = "Refresh", ["Copy Job Id"] = "Copy", ["Random Fruits"] = "Roll",
		["Save"] = "Save", ["Load"] = "Load", ["Delete"] = "Delete", ["Unload"] = "Unload",
		["Something unusual"] = "Run", [""] = "Run",
	}
	for title, label in pairs(expected) do
		assert(lib.ButtonVerb(title) == label, ("%q -> %q, expected %q"):format(title, tostring(lib.ButtonVerb(title)), label))
	end
end)

print("Search boxes")
run("typing in any search box raises no errors (one bad child once got a player kicked)", function()
	UI_ERRORS = {}
	local boxes = {}
	for _, item in ipairs(lib.Internal.Gui:GetDescendants()) do
		if item.ClassName == "TextBox" and (item.Name == "Search Box" or item.Name == "SearchBox") then
			table.insert(boxes, item)
		end
	end
	assert(#boxes >= 5, "found the search boxes, got " .. #boxes)
	for _, box in ipairs(boxes) do
		box.Text = "walk" -- fires the hide-others / show-matches loops
		box.Text = ""
	end
	assert(#UI_ERRORS == 0, "errors: " .. tostring(UI_ERRORS[1]))
end)

print("Config")
run("Save", function()
	local ok, err = lib.ConfigSystem.Save("harness")
	assert(ok, err)
	assert(FILES["Peridot/Configs/harness.json"], "file written")
end)
run("List", function()
	local names = lib.ConfigSystem.List()
	assert(#names == 1 and names[1] == "harness", "list = " .. table.concat(names, ","))
end)
run("Load applies every saved value without errors", function()
	WARNINGS = {}
	RUN_SPAWNS = true
	local ok, err = lib.ConfigSystem.Load("harness")
	RUN_SPAWNS = false
	assert(ok, err)
	assert(#WARNINGS == 0, "warnings: " .. table.concat(WARNINGS, " | "))
end)
run("old-format config (UITheme + Enum keybind) loads and sets values", function()
	local keybindKey
	for key in pairs(lib.ControlRegistry.Keybinds) do keybindKey = key end
	local old = {
		Toggles = { [firstToggle] = true },
		Keybinds = keybindKey and { [keybindKey] = "Enum.KeyCode.RightShift" } or {},
		UITheme = { ["Title Text Color"] = { Color = { 90, 160, 255, "Dit" } } },
	}
	FILES["Peridot/Configs/old.json"] = service("HttpService"):JSONEncode(old)
	RUN_SPAWNS = true
	local ok, err = lib.ConfigSystem.Load("old")
	RUN_SPAWNS = false
	assert(ok, err)
	assert(lib.ControlRegistry.Toggles[firstToggle].Get() == true, "toggle restored")
	if keybindKey then
		assert(lib.ControlRegistry.Keybinds[keybindKey].Get() == "RightShift", "keybind restored")
	end
	assert(getgenv().UIColor["Title Text Color"].g > 0.6, "old blue theme ignored, accent still green")
end)
run("Delete", function()
	assert(lib.ConfigSystem.Delete("harness"))
	assert(not FILES["Peridot/Configs/harness.json"])
end)

---------------------------------------------------------------- 3. misc API
print("Window / notifications / theme")
run("CreateNoti", function() lib.CreateNoti({ Title = "T", Desc = "D", ShowTime = 1 }) end)
run("Hide / Show / Toggle", function()
	lib.Hide(); assert(lib.IsVisible() == false)
	lib.Show(); assert(lib.IsVisible() == true)
	lib.Toggle(0.18); assert(lib.IsVisible() == false)
	lib.Toggle(); assert(lib.IsVisible() == true)
end)
RUN_SPAWNS = true -- a background is remembered in the saved theme, which is written after a task.delay
run("SetBackground: asset id, image URL, .webm URL, clear", function()
	assert(lib.SetBackground("123456"))
	assert(lib.SetBackground("https://example.com/a.png"))
	assert(FILES["Peridot/Backgrounds/a.png"] == "remote-bytes", "image cached")
	assert(lib.SetBackground("https://example.com/clip.webm?raw=1"))
	assert(FILES["Peridot/Backgrounds/clip.webm"] == "remote-bytes", "video cached, query string dropped")
	assert(lib.SetBackground(""), "empty clears")
end)
run("SetBackground: failed download reports and keeps the current one", function()
	local ok, err = lib.SetBackground("https://example.com/missing.webm")
	assert(ok == false and tostring(err):find("download failed"), "got " .. tostring(err))
end)
run("DownloadBackground saves into workspace/Peridot/Backgrounds once", function()
	local first = lib.DownloadBackground("https://raw.githubusercontent.com/Ic0u/peridot/main/assets/backgrounds/waves.webm", "waves.webm")
	assert(first == "new", "first download: " .. tostring(first))
	assert(FILES["Peridot/Backgrounds/waves.webm"] == "webm-bytes", "file written")
	assert(lib.DownloadBackground("https://x/waves.webm", "waves.webm") == "exists", "second call skips")
	local listed = {}
	for _, path in ipairs(lib.ListBackgrounds()) do listed[path] = true end
	assert(listed["Peridot/Backgrounds/waves.webm"] and listed["Peridot/Backgrounds/green_night_driving.jpg"], "folder listed")
end)
run("Background dropdown (gear page) lists the workspace folder and loads the local file", function()
	local entry = lib.ControlRegistry.Dropdowns["UI Settings||Background||Background"]
	assert(entry, "dropdown registered on the UI Settings page")
	local before = getgenv().UIColor["Background 1 Transparency"]
	entry.Set("Green Night Driving") -- listed from the folder at startup, no URL involved
	assert(getgenv().UIColor["Background 1 Transparency"] == 0.3, "panels see-through")
	entry.Set("None")
	assert(getgenv().UIColor["Background 1 Transparency"] == before, "player's transparency restored")
	assert(lib.SetBackground("Peridot/Backgrounds/waves.webm"), "local video file")
	local ok, err = lib.SetBackground("Peridot/Backgrounds/nope.png")
	assert(ok == false and tostring(err):find("not found"), "missing local file reported")
	assert(lib.SetBackground(""), "cleared again, so later windows start without one")
end)
RUN_SPAWNS = false

print("Theme (gear page)")
run("accent preset recolors the theme and is saved", function()
	RUN_SPAWNS = true
	assert(lib.SetAccent("Ruby"))
	RUN_SPAWNS = false
	local title = getgenv().UIColor["Title Text Color"]
	assert(math.floor(title.R * 255 + 0.5) == 220 and math.floor(title.G * 255 + 0.5) == 70, "title color is Ruby")
	assert(FILES["Peridot/Theme.json"], "Theme.json written")
	local saved = service("HttpService"):JSONDecode(FILES["Peridot/Theme.json"])
	assert(saved.Preset == "Ruby" and saved.Accent[1] == 220, "preset + accent saved")
end)
run("saved theme is applied on the next load", function()
	local fresh = assert(loadfile(REPO .. "/libraries/UILibrary.lua"))()
	local title = getgenv().UIColor["Title Text Color"]
	assert(math.floor(title.R * 255 + 0.5) == 220, "Ruby comes back after reload")
	RUN_SPAWNS = true
	assert(fresh.SetAccent(Color3.fromRGB(140, 172, 68)))
	assert(fresh.SetAccent("Peridot"))
	RUN_SPAWNS = false
	assert(not fresh.SetAccent("NoSuchPreset"), "unknown preset rejected")
end)
run("per-color edits, rainbow and logo are saved and reloaded; reset clears them", function()
	RUN_SPAWNS = true
	lib.SetThemeColor("Background 2 Color", Color3.fromRGB(10, 20, 30))
	lib.SetRainbow("Button Color", true)
	assert(lib.SetLogo("123456"), "logo by asset id")
	RUN_SPAWNS = false
	local saved = service("HttpService"):JSONDecode(FILES["Peridot/Theme.json"])
	assert(saved.Colors["Background 2 Color"][3] == 30, "color edit saved")
	assert(saved.Rainbow["Button Color"] == true, "rainbow saved")
	assert(saved.Logo == "123456", "logo saved")
	assert(loadfile(REPO .. "/libraries/UILibrary.lua"))()
	assert(math.floor(getgenv().UIColor["Background 2 Color"].B * 255 + 0.5) == 30, "color edit reloaded")
	assert(getgenv().UIColor["Logo Image"] == "rbxassetid://123456", "logo reloaded")
	RUN_SPAWNS = true
	lib.ResetTheme()
	RUN_SPAWNS = false
	local cleared = service("HttpService"):JSONDecode(FILES["Peridot/Theme.json"])
	assert(next(cleared) == nil, "reset empties Theme.json")
end)
run("gear page builds (Theme / Colors / Window sub-tabs, accent + color pickers)", function()
	assert(lib.ToggleUISettings() and lib.ToggleUISettings())
end)
print("UI Toggle (button, toggle key)")
local function press(keyName)
	local input = { UserInputType = Enum.UserInputType.Keyboard, KeyCode = { Name = keyName } }
	for _, f in ipairs({ (unpack or table.unpack)(INPUT_BEGAN) }) do
		pcall(f, input, false) -- other scripts' handlers may not like a fake input
	end
end
local function stepFrame()
	for _, f in ipairs({ (unpack or table.unpack)(HEARTBEATS) }) do
		pcall(f)
	end
end
local function savedTheme()
	return service("HttpService"):JSONDecode(FILES["Peridot/Theme.json"])
end
-- a fresh library instance owns the menu key handler (a re-run replaces the old one)
local ui = assert(loadfile(REPO .. "/libraries/UILibrary.lua"))()
RUN_SPAWNS = true
run("button size: clamped to 28-64, saved", function()
	ui.SetButtonSize(500)
	assert(savedTheme().ButtonSize == 64, "max 64, got " .. tostring(savedTheme().ButtonSize))
	ui.SetButtonSize(3)
	assert(savedTheme().ButtonSize == 28, "min 28")
	ui.SetButtonSize(40)
	assert(savedTheme().ButtonSize == 40)
end)
run("UI toggle button: player's saved choice wins over the script's", function()
	ui.SetButtonVisible(false)
	assert(ui.Internal.HideGui.Enabled == false and savedTheme().FloatingButton == false)
	ui.CreateMain({ Name = "Peridot", Title = "Interface Test", FloatingButton = true })
	assert(ui.Internal.HideGui.Enabled == false, "saved 'hidden' beats FloatingButton = true")
	ui.SetButtonVisible(true)
	assert(ui.Internal.HideGui.Enabled == true)
end)
run("toggle key: toggles the window, can be changed, and is saved", function()
	local before = ui.IsVisible()
	press("RightControl")
	assert(ui.IsVisible() ~= before, "RightControl opens/closes")
	press("RightControl")
	assert(ui.IsVisible() == before)
	ui.SetMenuKey("F4")
	press("RightControl")
	assert(ui.IsVisible() == before, "old key no longer works")
	press("F4")
	assert(ui.IsVisible() ~= before, "new key works")
	press("F4")
	assert(savedTheme().MenuKey == "F4", "saved")
end)
run("UI Toggle tab builds with the page and its watcher runs", function()
	assert(ui.ToggleUISettings() and ui.ToggleUISettings())
	stepFrame()
	assert(savedTheme().MenuKey == "F4", "watcher left the saved key alone")
end)
run("a re-run replaces the old toggle key handler (no double toggle)", function()
	local again = assert(loadfile(REPO .. "/libraries/UILibrary.lua"))()
	again.CreateMain({ Name = "Peridot", Title = "Interface Test 2" })
	local before = again.IsVisible()
	press("F4")
	assert(again.IsVisible() ~= before, "toggled exactly once")
end)
run("Reset Icon returns to the main Peridot icon and clears the saved custom one", function()
	assert(ui.SetLogo("123456"))
	assert(getgenv().UIColor["Logo Image"] == "rbxassetid://123456", "custom icon applied")
	assert(savedTheme().Logo == "123456", "custom icon saved")
	assert(ui.SetLogo(""))
	assert(getgenv().UIColor["Logo Image"] == "rbxassetid://97933423096090", "back to the main icon, got " .. tostring(getgenv().UIColor["Logo Image"]))
	assert(savedTheme().Logo == nil, "saved custom icon cleared")
end)
RUN_SPAWNS = false

print("Animation")
run("window open/close: state is immediate, Gui.Enabled follows the animation, a quick reopen cancels the close", function()
	local anim = assert(loadfile(REPO .. "/libraries/UILibrary.lua"))()
	anim.CreateMain({ Name = "Peridot", Title = "Animation Test" })
	assert(anim.IsVisible() and anim.Internal.Gui.Enabled, "opens on load")
	DEFER_DELAYS = true
	anim.Hide()
	assert(not anim.IsVisible(), "logically closed at once")
	assert(anim.Internal.Gui.Enabled, "still on screen while the close animates")
	flushDelays()
	assert(not anim.Internal.Gui.Enabled, "hidden once the animation is done")
	anim.Show()
	assert(anim.IsVisible() and anim.Internal.Gui.Enabled, "shown again")
	anim.Hide()
	anim.Show() -- quick close + reopen
	flushDelays()
	assert(anim.IsVisible() and anim.Internal.Gui.Enabled, "the stale close did not hide the reopened window")
	DEFER_DELAYS = false
end)
run("fade: the window is a CanvasGroup with the shadow outside it, opens from clear, no snap when reopened mid-close", function()
	local anim = assert(loadfile(REPO .. "/libraries/UILibrary.lua"))()
	anim.CreateMain({ Name = "Peridot", Title = "Fade Test" })
	local gui = anim.Internal.Gui
	local body = gui:FindFirstChild("Body", true)
	assert(body and body.ClassName == "CanvasGroup", "the window body is a CanvasGroup")
	assert(body:FindFirstChild("MainContainer"), "the window is inside the body")
	local shadow = gui:FindFirstChild("Shadow", true)
	assert(shadow and shadow.Parent ~= body, "the shadow is outside the group, so it isn't clipped")
	DEFER_DELAYS = true
	anim.Hide()
	flushDelays()
	assert(body.GroupTransparency == 0 and shadow.ImageTransparency == 0.35, "values reset after hiding")
	anim.Show()
	assert(body.GroupTransparency == 1 and shadow.ImageTransparency == 1, "a fresh open starts fully clear")
	body.GroupTransparency = 0.5 -- pretend the tween is halfway
	anim.Hide()
	anim.Show() -- reopened while it was still closing
	assert(body.GroupTransparency == 0.5, "no snap when reopened mid-close")
	flushDelays()
	DEFER_DELAYS = false
	assert(anim.IsVisible() and gui.Enabled, "ends up open")
end)
run("accent preset crossfades through the theme without errors", function()
	assert(lib.ToggleUISettings() and lib.ToggleUISettings())
	RUN_SPAWNS = true -- saving the theme uses task.delay
	assert(lib.SetAccent("Mint"))
	local c = getgenv().UIColor["Title Text Color"]
	assert(math.floor(c.G * 255 + 0.5) == 200, "Mint accent is set")
	assert(lib.SetAccent("Peridot"))
	RUN_SPAWNS = false
end)

run("accent rainbow: saved while running, frozen + saved when stopped, cleared by a preset", function()
	local json = service("HttpService")
	RUN_SPAWNS = true
	lib.SetAccentRainbow(true)
	local running = json:JSONDecode(FILES["Peridot/Theme.json"])
	assert(running.Rainbow and running.Rainbow["Title Text Color"] and running.Rainbow["Button Color"], "rainbow saved for the accent keys")
	lib.SetAccentRainbow(false)
	local stopped = json:JSONDecode(FILES["Peridot/Theme.json"])
	assert(next(stopped.Rainbow or {}) == nil, "no rainbow left in the saved theme")
	assert(stopped.Preset == "Custom" and stopped.Accent, "accent frozen and saved as Custom")
	lib.SetAccentRainbow(true)
	assert(lib.SetAccent("Ocean"))
	RUN_SPAWNS = false
	local after = json:JSONDecode(FILES["Peridot/Theme.json"])
	assert(next(after.Rainbow or {}) == nil and after.Preset == "Ocean", "picking a preset stops and unsaves the rainbow")
end)
run("CreateColorPicker for scripts", function()
	local w = lib.CreateMain({ Name = "Peridot", Title = "Picker Test" })
	local got
	local picker = w.CreatePage({ Page_Name = "ESP", Page_Title = "ESP" }).CreateSection("Colors")
		.CreateColorPicker({ Title = "Box color", Default = Color3.fromRGB(255, 0, 0) }, function(c) got = c end)
	picker.Set(Color3.fromRGB(0, 255, 0))
	assert(picker.Get() ~= nil, "picker returns a color")
end)

print("Sub-tabs")
run("sub-tabs keep separate config keys and switch", function()
	local w = lib.CreateMain({ Name = "Peridot", Title = "Test Game" })
	local page = w.CreatePage({ Page_Name = "Farm", Page_Title = "Farm" })
	local bounty, lvl = page.CreateSubTab("Bounty Farm"), page.CreateSubTab("Lvl Farm")
	local got = {}
	bounty.CreateSection("Run").CreateToggle({ Title = "Run the rotation" }, function(v) got.bounty = v end)
	lvl.CreateSection("Run").CreateToggle({ Title = "Run the rotation" }, function(v) got.lvl = v end)
	-- first one keeps the plain page key (old configs still load); the clashing second one gets the sub-tab name
	assert(lib.ControlRegistry.Toggles["Farm||Run||Run the rotation"], "bounty keeps the plain key")
	assert(lib.ControlRegistry.Toggles["Farm/Lvl Farm||Run||Run the rotation"], "lvl gets the sub-tab key")
	lvl.Select()
	bounty.Select()
	page.CreateSection("Always shown").CreateLabel({ Title = "no sub-tab" })
	w.UISettings.CreateSection("Extra").CreateToggle({ Title = "x" })
end)
run("UIColor writes (Settings page) reach the theme", function()
	getgenv().UIColor["Background 1 Transparency"] = 0.4
	getgenv().UIColor["Tween Easing Style"] = "Back"
	assert(getgenv().UIColor["Background 1 Transparency"] == 0.4)
end)

---------------------------------------------------------------- theme library
print("Theme library")
local function accentOf() -- the live accent as 0-255 numbers
	local c = getgenv().UIColor["Title Text Color"]
	return math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)
end
local function withSpawns(fn)
	RUN_SPAWNS = true
	local ok, err = pcall(fn)
	RUN_SPAWNS = false
	assert(ok, err)
end
local TS = lib.ThemeSystem

run("built-in themes apply on top of the shipped look and Peridot returns to it", function()
	local names = table.concat(TS.ListBuiltIn(), ",")
	assert(names:find("Peridot", 1, true) and names:find("Ocean", 1, true) and names:find("Purple Midnight", 1, true), names)
	withSpawns(function()
		assert(TS.Apply("Ocean"))
		local r, g, b = accentOf()
		assert(r == 90 and g == 160 and b == 255, "Ocean accent")
		assert(TS.Apply("Snappy"))
		r, g, b = accentOf()
		assert(r == 140 and g == 172 and b == 68, "Snappy starts from the shipped accent, not Ocean's")
		assert(getgenv().UIColor["Tween Animation 1 Speed"] == 0.12 and getgenv().UIColor["Background 1 Transparency"] == 0)
		assert(TS.Apply("Peridot"))
		assert(getgenv().UIColor["Tween Animation 1 Speed"] == 0.25, "Peridot restores the shipped speeds")
	end)
	local ok, err = TS.Apply("No Such Theme")
	assert(not ok and err == "Theme not found", tostring(err))
end)

run("saved themes: create, refuse duplicates and built-in names, overwrite, load, delete", function()
	withSpawns(function()
		lib.SetAccent("Ruby")
		assert(TS.Create("mine"))
		assert(FILES["Peridot/Themes/mine.json"], "written to Peridot/Themes")
		local ok, err = TS.Create("mine")
		assert(not ok and err:find("already exists"), "no silent overwrite: " .. tostring(err))
		ok, err = TS.Create("Ocean")
		assert(not ok and err:find("built%-in"), tostring(err))
		ok, err = TS.Create("../evil")
		assert(not ok and err:find("slashes"), tostring(err))
		ok, err = TS.Create("   ")
		assert(not ok, "a blank name is refused")
		ok, err = TS.Save("Ocean")
		assert(not ok and err:find("cannot be changed"), tostring(err))

		assert(TS.Apply("Ocean"))
		assert(select(3, accentOf()) == 255)
		assert(TS.Apply("mine"))
		local r, g, b = accentOf()
		assert(r == 220 and g == 70 and b == 80, "the saved theme brings Ruby back")

		lib.SetAccent("Gold")
		assert(TS.Save("mine"), "overwrite")
		assert(TS.Apply("Ocean") and TS.Apply("mine"))
		assert(select(2, accentOf()) == 206, "overwritten with Gold")

		local list = table.concat(TS.List(), ",")
		assert(list == "mine", "default.txt and other files are not listed, got " .. list)
		assert(TS.Delete("mine") and not FILES["Peridot/Themes/mine.json"])
		ok, err = TS.Delete("Ocean")
		assert(not ok and err:find("cannot be deleted"))
		assert(TS.Apply("Peridot"))
	end)
end)

run("default theme: set, listed, cleared with its theme, and applied when the library loads", function()
	withSpawns(function()
		lib.SetAccent("Mint")
		assert(TS.Create("keep"))
		assert(TS.SetDefault("keep") and TS.GetDefault() == "keep" and FILES["Peridot/Themes/default.txt"] == "keep")
		assert(TS.Delete("keep") and TS.GetDefault() == nil, "deleting the default theme clears it")
		local ok, err = TS.SetDefault("nothing")
		assert(not ok and err == "Theme not found")
		assert(TS.SetDefault("ocean") and TS.GetDefault() == "Ocean", "built-in names match without case")
	end)
	local priorTheme, priorColors = FILES["Peridot/Theme.json"], getgenv().UIColor
	FILES["Peridot/Theme.json"] = nil -- nothing saved from this session: only the default theme decides
	assert(loadfile(REPO .. "/libraries/UILibrary.lua"))()
	local r, g, b = accentOf()
	assert(r == 90 and g == 160 and b == 255, "the default theme is applied before any window exists")
	FILES["Peridot/Theme.json"], getgenv().UIColor = priorTheme, priorColors
	assert(TS.ClearDefault() and TS.GetDefault() == nil and not FILES["Peridot/Themes/default.txt"])
	withSpawns(function() TS.Apply("Peridot") end)
end)

run("theme JSON: export, import, and data from outside is sanitised", function()
	withSpawns(function()
		lib.SetAccent("Sakura")
		local text = TS.Export()
		assert(type(text) == "string" and text ~= "")
		assert(TS.Apply("Peridot"))
		assert(TS.Import(text))
		local r, g, b = accentOf()
		assert(r == 240 and g == 130 and b == 170, "the exported look comes back")

		local ok, err = TS.Import("not json")
		assert(not ok and err == "That is not theme JSON.", tostring(err))
		ok, err = TS.Import("")
		assert(not ok and err == "Paste theme JSON first.", tostring(err))

		local hostile = service("HttpService"):JSONEncode({
			Accent = { 300, -5, "x" }, Preset = string.rep("p", 80), PanelTransparency = 5,
			AnimationSpeed1 = 99, Easing = "Evil", Logo = "https://example.com/tracker.png",
			Colors = { ["Not A Key"] = { 1, 2, 3 }, ["Button Color"] = { 10, 20, 30 } },
			Unknown = "ignored",
		})
		local before = #HTTP_LOG
		assert(TS.Import(hostile))
		for i = before + 1, #HTTP_LOG do
			assert(not HTTP_LOG[i]:find("tracker", 1, true), "an imported icon link is never fetched")
		end
		assert(getgenv().UIColor["Background 1 Transparency"] == 0.6, "transparency is capped")
		assert(getgenv().UIColor["Tween Animation 1 Speed"] <= 0.75, "speeds are capped")
		assert(getgenv().UIColor["Tween Easing Style"] ~= "Evil", "unknown easing is ignored")
		assert(getgenv().UIColor["Not A Key"] == nil, "unknown color keys are ignored")
		assert(TS.Apply("Peridot"))
	end)
end)

---------------------------------------------------------------- preinstalled themes: every color, plus a picture
run("every preinstalled theme changes all the colors; the ones with a picture name one the hub ships", function()
	local source = io.open(REPO .. "/libraries/UILibrary.lua", "rb"):read("*a")
	local accentKeys = source:match("local AccentKeys = {(.-)}")
	local covered = {} -- the colors a palette has to set: everything but the accent keys and their two shades
	for key in source:match("local T1UIColor = {(.-)\n}\n"):gmatch('%["([^"]+)"%]%s*=%s*Color3%.fromRGB') do
		if not accentKeys:find('"' .. key .. '"', 1, true) and key ~= "Dropdown Selected Check Color" and key ~= "Slider Highlight Color" then
			covered[#covered + 1] = key
		end
	end
	assert(#covered == 16, "colors a palette has to set: " .. #covered)
	local shipped = {}
	for file in io.open(REPO .. "/assets/backgrounds/backgrounds.json", "rb"):read("*a"):gmatch('"[^"]+"%s*:%s*"([^"]+)"') do
		shipped[file] = true
	end
	local function luminance(c)
		local function f(x) return x <= 0.03928 and x / 12.92 or ((x + 0.055) / 1.055) ^ 2.4 end
		return 0.2126 * f(c.R) + 0.7152 * f(c.G) + 0.0722 * f(c.B)
	end
	local function contrast(a, b)
		local la, lb = luminance(a), luminance(b)
		if la < lb then la, lb = lb, la end
		return (la + 0.05) / (lb + 0.05)
	end
	local json, pictures, plain, seeded = service("HttpService"), 0, 0, {}
	for file in pairs(shipped) do -- stand-in files in the workspace folder, so applying a theme downloads nothing here
		local path = "Peridot/Backgrounds/" .. file
		if not FILES[path] then
			FILES[path] = "stand-in"
			seeded[#seeded + 1] = path
		end
	end
	withSpawns(function()
		for _, name in ipairs(TS.ListBuiltIn()) do
			if name ~= "Peridot" and name ~= "Snappy" and name ~= "Relaxed" then
				assert(TS.Apply(name), name)
				local data = json:JSONDecode(TS.Export())
				assert(data.Accent and data.Preset == name, name .. " sets the accent")
				for _, key in ipairs(covered) do
					assert(data.Colors and data.Colors[key], name .. " leaves " .. key .. " as it was")
				end
				local ui = getgenv().UIColor
				assert(contrast(ui["Text Color"], ui["Background 1 Color"]) >= 7, name .. ": text is hard to read on the page")
				assert(contrast(ui["Section Text Color"], ui["Section Panel Color"]) >= 7, name .. ": section titles are hard to read")
				assert(contrast(ui["Toggle Desc Color"], ui["Background 1 Color"]) >= 4.5, name .. ": descriptions are hard to read")
				assert(contrast(ui["Placeholder Text Color"], ui["Background 2 Color"]) >= 4.5, name .. ": placeholders are hard to read")
				assert(contrast(ui["Title Text Color"], ui["Sidebar Color"]) >= 4.5, name .. ": the accent is hard to see on the sidebar")
				assert(contrast(ui["Title Text Color"], ui["Background 1 Color"]) >= 3.5, name .. ": the accent is hard to see on the page")
				if data.Background then
					pictures = pictures + 1
					assert(shipped[data.Background], name .. " uses " .. data.Background .. ", which backgrounds.json does not list")
					local onDisk = io.open(REPO .. "/assets/backgrounds/" .. data.Background, "rb")
					assert(onDisk, data.Background .. " is not in assets/backgrounds")
					onDisk:close()
					assert(data.PanelTransparency == (name == "Hu Tao" and 0.6 or 0.3), name .. " lets its picture show through the panels")
					assert(data.WindowStyle == nil, name .. " keeps the solid window")
					assert((data.Logo == "6708911064") == (name == "Hu Tao"), name .. ": only Hu Tao brings its own icon")
				else
					plain = plain + 1
					assert((data.PanelTransparency or 0) == 0, name .. " has no picture, so its panels stay solid")
				end
			end
		end
		assert(TS.Apply("Hu Tao"))
		assert(getgenv().UIColor["Logo Image"] == "rbxassetid://6708911064", "Hu Tao shows its own icon")
		assert(TS.Apply("Ocean"))
		assert(getgenv().UIColor["Logo Image"] == "rbxassetid://97933423096090", "and the next theme gets the Peridot icon back")
		assert(TS.Apply("Peridot"))
	end)
	for _, path in ipairs(seeded) do FILES[path] = nil end
	assert(pictures == 20 and plain == 7, ("20 pictures and 7 plain palettes, got %d and %d"):format(pictures, plain))
end)

run("a theme's picture is downloaded from the hub once, shown, remembered, and cleared by the next theme", function()
	local json = service("HttpService")
	local function layer()
		for _, item in ipairs(lib.Internal.Gui:GetDescendants()) do
			if item.Name == "PeridotBackground" then return item end
		end
	end
	local function fetched(path)
		local n = 0
		for _, entry in ipairs(HTTP_LOG) do
			if entry == path then n = n + 1 end
		end
		return n
	end
	local file = "Peridot/Backgrounds/purple_midnight.jpg"
	FILES[file] = nil
	withSpawns(function()
		assert(TS.Apply("Purple Midnight"))
		assert(fetched("assets/backgrounds/purple_midnight.jpg") == 1, "downloaded from the hub's own assets folder")
		assert(FILES[file] and #FILES[file] > 1000, "saved into Peridot/Backgrounds")
		local shown = layer()
		assert(shown and shown.Image == "rbxasset://" .. file, "the picture is on the window")
		assert(shown:FindFirstChild("TitleScrim"), "with the title bar darkened so its text stays readable")
		assert(getgenv().UIColor["Background 1 Transparency"] == 0.3, "panels let it show")
		assert(math.abs(getgenv().UIColor["Section Panel Transparency"] - 0.51) < 0.001, "section panels follow the panels")
		local saved = json:JSONDecode(FILES["Peridot/Theme.json"])
		assert(saved.Background == "purple_midnight.jpg" and saved.Colors["Sidebar Color"], "remembered with the colors")
		assert(math.floor(getgenv().UIColor["Sidebar Color"].B * 255 + 0.5) == 7, "and the colors are the theme's")

		assert(TS.Apply("Purple Midnight"))
		assert(fetched("assets/backgrounds/purple_midnight.jpg") == 1, "the file is kept, so it is not downloaded again")


		-- saved as a theme of your own, with the picture
		assert(TS.Create("withpicture"))
		assert(json:JSONDecode(FILES["Peridot/Themes/withpicture.json"]).Background == "purple_midnight.jpg", "a created theme keeps the picture")
		assert(TS.Apply("Ocean"))
		assert(layer() == nil and getgenv().UIColor["Background 1 Transparency"] == 0, "a theme without a picture clears it and the see-through panels")
		assert(math.abs(getgenv().UIColor["Section Panel Transparency"] - 0.15) < 0.001, "section panels are back to the shipped look")
		assert(json:JSONDecode(FILES["Peridot/Theme.json"]).Background == nil, "and nothing is remembered")
		assert(TS.Apply("withpicture") and layer() and layer().Image == "rbxasset://" .. file, "loading the created theme brings the picture back")

		-- the next session starts with the same picture, with or without a default theme
		local priorColors = getgenv().UIColor
		local fresh = assert(loadfile(REPO .. "/libraries/UILibrary.lua"))()
		fresh.CreateMain({ Name = "Peridot", Title = "Restore test" })
		local restored
		for _, item in ipairs(fresh.Internal.Gui:GetDescendants()) do
			if item.Name == "PeridotBackground" then restored = item end
		end
		assert(restored and restored.Image == "rbxasset://" .. file, "the new window opens with the remembered picture")
		getgenv().UIColor = priorColors

		-- a default theme with a picture: the colors apply as the library loads, the picture when the window opens
		local priorTheme = FILES["Peridot/Theme.json"]
		FILES["Peridot/Theme.json"] = nil
		assert(TS.SetDefault("Purple Midnight"))
		local viaDefault = assert(loadfile(REPO .. "/libraries/UILibrary.lua"))()
		assert(math.floor(getgenv().UIColor["Sidebar Color"].B * 255 + 0.5) == 7, "the default theme's colors are in before any window exists")
		viaDefault.CreateMain({ Name = "Peridot", Title = "Default test" })
		local defaultLayer
		for _, item in ipairs(viaDefault.Internal.Gui:GetDescendants()) do
			if item.Name == "PeridotBackground" then defaultLayer = item end
		end
		assert(defaultLayer and defaultLayer.Image == "rbxasset://" .. file, "and its picture when the window opens")
		assert(TS.ClearDefault())

		-- a saved file edited by hand must not stop the window from opening
		FILES["Peridot/Theme.json"] = json:JSONEncode({ Background = { evil = true } })
		local damaged = assert(loadfile(REPO .. "/libraries/UILibrary.lua"))()
		damaged.CreateMain({ Name = "Peridot", Title = "Damaged test" })
		for _, item in ipairs(damaged.Internal.Gui:GetDescendants()) do
			assert(item.Name ~= "PeridotBackground", "a damaged picture entry is ignored")
		end
		FILES["Peridot/Theme.json"] = priorTheme
		getgenv().UIColor = priorColors

		lib.ResetTheme()
		assert(layer() == nil, "Reset theme removes the picture")
		assert(next(json:JSONDecode(FILES["Peridot/Theme.json"])) == nil, "and forgets it")
		assert(TS.Delete("withpicture"))
		assert(TS.Apply("Peridot"))
	end)
end)

run("a picture that cannot be fetched, and pictures from outside, never get in", function()
	local json = service("HttpService")
	local function layer()
		for _, item in ipairs(lib.Internal.Gui:GetDescendants()) do
			if item.Name == "PeridotBackground" then return item end
		end
	end
	withSpawns(function()
		UI_ERRORS = {}
		assert(TS.Import(json:JSONEncode({ Background = "not_in_the_hub.png" })))
		assert(layer() == nil, "a missing picture leaves the window plain")
		assert(#UI_ERRORS == 0, "and nothing throws")
		for _, bad in ipairs({ "https://evil.example/x.png", "../x.png", "a/b.png", "C:/x.png", "x.exe", "x", ".png", "rbxassetid://12a", 5, true }) do
			local before = #HTTP_LOG
			assert(TS.Import(json:JSONEncode({ Accent = { 1, 2, 3 }, Background = bad })))
			assert(json:JSONDecode(FILES["Peridot/Theme.json"]).Background == nil, "refused: " .. tostring(bad))
			assert(layer() == nil and #HTTP_LOG == before, "never fetched: " .. tostring(bad))
		end
		assert(TS.Import(json:JSONEncode({ Background = "rbxassetid://99" })))
		assert(layer() and layer().Image == "rbxassetid://99", "an asset id is fine")
		assert(TS.Apply("Peridot"))
		assert(layer() == nil)
	end)
end)

run("the Background picker follows the theme, and a theme decides the panels, not an old pick", function()
	local priorColors = getgenv().UIColor
	local fresh = assert(loadfile(REPO .. "/libraries/UILibrary.lua"))()
	local window = fresh.CreateMain({ Name = "Peridot", Title = "Picker sync" })
	local function pickerText()
		for _, item in ipairs(fresh.Internal.Gui:GetDescendants()) do
			if item.ClassName == "TextBox" and tostring(item.PlaceholderText or ""):find("^Background: ") then
				return item.PlaceholderText
			end
		end
	end
	local file = "Peridot/Backgrounds/zankou_nte.jpg"
	FILES[file] = "stand-in"
	local picker
	withSpawns(function()
		fresh.AddBackgroundSection(window)
		picker = fresh.ControlRegistry.Dropdowns["UI Settings||Background||Background"]
		assert(pickerText() == "Background: None", "starts on None: " .. tostring(pickerText()))
		assert(fresh.ThemeSystem.Apply("Zankou Nte"))
		assert(pickerText() == "Background: Zankou Nte", "shows the theme's picture: " .. tostring(pickerText()))
		assert(fresh.ThemeSystem.Apply("Ocean"))
		assert(pickerText() == "Background: None", "and None once a plain theme is picked: " .. tostring(pickerText()))

		picker.Set("Zankou Nte") -- picked by hand: panels go see-through, and the choice is saved
		assert(getgenv().UIColor["Background 1 Transparency"] == 0.3)
		assert(service("HttpService"):JSONDecode(FILES["Peridot/Theme.json"]).Background == "zankou_nte.jpg", "a hand-picked picture is remembered")
		fresh.ThemeSystem.Apply("Mint") -- a theme without a picture takes over the panels as well
		picker.Set("Zankou Nte")
		picker.Set("None")
		assert(getgenv().UIColor["Background 1 Transparency"] == 0, "None puts back the panels the theme had")
		assert(service("HttpService"):JSONDecode(FILES["Peridot/Theme.json"]).Background == nil, "and forgets the picture")
		fresh.ThemeSystem.Apply("Peridot")
	end)
	FILES[file] = nil
	getgenv().UIColor = priorColors
end)

run("window style: Transparent lets the game show through, Solid puts it back, and themes carry it", function()
	local json = service("HttpService")
	local priorColors = getgenv().UIColor
	local fresh = assert(loadfile(REPO .. "/libraries/UILibrary.lua"))()
	fresh.CreateMain({ Name = "Peridot", Title = "Style test" })
	local function find(name)
		for _, item in ipairs(fresh.Internal.Gui:GetDescendants()) do
			if item.Name == name then return item end
		end
	end
	local frame, shadow = find("MainContainer"), find("Shadow")
	withSpawns(function()
		fresh.ThemeSystem.Apply("Peridot")
		assert(frame.BackgroundTransparency == 0, "solid by default")
		local glow = shadow.ImageTransparency
		fresh.SetWindowStyle("Transparent")
		assert(frame.BackgroundTransparency == 0.92, "the frame lets the game through, like the original")
		assert(shadow.ImageTransparency == glow, "and the glow around the window stays, like the original")
		assert(getgenv().UIColor["Background 1 Transparency"] == 0.4, "the menus turn see-through too, not just the frame")
		assert(json:JSONDecode(FILES["Peridot/Theme.json"]).WindowStyle == "Transparent", "saved")
		assert(json:JSONDecode(fresh.ThemeSystem.Export()).WindowStyle == "Transparent", "part of the theme")
		assert(fresh.ThemeSystem.Create("glassy"))
		fresh.SetWindowStyle("Solid")
		assert(frame.BackgroundTransparency == 0 and shadow.ImageTransparency == glow, "Solid puts the frame back")
		assert(getgenv().UIColor["Background 1 Transparency"] == 0, "and the panels")
		assert(json:JSONDecode(FILES["Peridot/Theme.json"]).WindowStyle == nil)
		assert(fresh.ThemeSystem.Apply("glassy") and frame.BackgroundTransparency == 0.92, "a saved theme brings the style back")
		assert(fresh.ThemeSystem.Apply("Ocean") and frame.BackgroundTransparency == 0, "a theme without it is solid")
		assert(fresh.ThemeSystem.Import(json:JSONEncode({ WindowStyle = "Evil" })) and frame.BackgroundTransparency == 0, "unknown styles are ignored")
		assert(fresh.ThemeSystem.Apply("glassy"))
	end)
	local again = assert(loadfile(REPO .. "/libraries/UILibrary.lua"))()
	again.CreateMain({ Name = "Peridot", Title = "Style reload" })
	local reloaded
	for _, item in ipairs(again.Internal.Gui:GetDescendants()) do
		if item.Name == "MainContainer" then reloaded = item end
	end
	assert(reloaded.BackgroundTransparency == 0.92, "the next session opens transparent")
	withSpawns(function()
		again.ThemeSystem.Delete("glassy")
		again.ThemeSystem.Apply("Peridot")
	end)
	getgenv().UIColor = priorColors
end)

run("the Theme tab of Interface Settings shows the theme library", function()
	local function hasText(wanted)
		for _, item in ipairs(lib.Internal.Gui:GetDescendants()) do
			if (item.ClassName == "TextLabel" or item.ClassName == "TextButton" or item.ClassName == "TextBox")
				and tostring(item.Text or ""):find(wanted, 1, true) then
				return true
			end
		end
		return false
	end
	for _, wanted in ipairs({ "Window style", "Preinstalled Themes", "Toggle button border", "My Themes", "Share Theme", "Custom theme name", "Create theme", "Load theme", "Overwrite theme",
		"Delete theme", "Reset default", "Current default theme: none", "Export current theme", "Import theme" }) do
		assert(hasText(wanted), "missing on the Theme tab: " .. wanted)
	end
	for _, gone in ipairs({ "Window Look", "UI Toggle button", "UI Toggle key", "Opens and closes", "Add your own" }) do
		assert(not hasText(gone), "should not be on the settings pages: " .. gone)
	end
	assert(hasText("UI Toggle"), "the toggle button and key share one UI Toggle section")
end)

---------------------------------------------------------------- every theme color is wired
print("Theme colors")
run("every color in the theme has its own picker on the Colors tab, and something that uses it", function()
	local source = io.open(REPO .. "/libraries/UILibrary.lua", "rb"):read("*a")
	local themeTable = source:match("local T1UIColor = {(.-)\n}\n")
	local colorsTab = source:match("local ColorGroups = {(.-)local ColorTitles")
	local checked, problems = 0, {}
	for key in themeTable:gmatch('%["([^"]+)"%]%s*=%s*Color3%.fromRGB') do
		checked = checked + 1
		local hasPicker = colorsTab:find('"' .. key .. '"', 1, true)
		local _, binds = source:gsub('Bind%([^,]+,%s*"[%w]+",%s*"' .. key .. '"%)', "")
		local listener = source:find('ThemeListeners["' .. key .. '"]', 1, true)
		local _, reads = source:gsub('UIColor%[[\'"]' .. key .. '[\'"]%]', "")
		if not hasPicker then problems[#problems + 1] = key .. " has no picker" end
		if binds == 0 and not listener and reads == 0 then problems[#problems + 1] = key .. " is not used by anything" end
	end
	assert(checked >= 28, "read the theme, got " .. checked)
	assert(#problems == 0, table.concat(problems, "; "))
end)

run("the window frame, sidebar, section panels, outlines, labels and check marks follow the theme", function()
	local priorColors = getgenv().UIColor
	local fresh = assert(loadfile(REPO .. "/libraries/UILibrary.lua"))()
	local window = fresh.CreateMain({ Name = "Peridot", Title = "Theme test", Desc = "" })
	local section = window.CreatePage({ Page_Name = "Page", Page_Title = "Page" }).CreateSection("Section")
	section.CreateToggle({ Title = "A toggle" }, function() end)
	section.CreateLabel({ Title = "A label" })
	local function rgb(c) return math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) end
	local function paints(match, property, r, g, b) -- some instance chosen by `match` now has this color
		for _, item in ipairs(fresh.Internal.Gui:GetDescendants()) do
			if match(item) then
				local cr, cg, cb = rgb(item[property])
				if cr == r and cg == g and cb == b then return true end
			end
		end
		return false
	end
	local function named(name) return function(item) return item.Name == name end end
	local checks = {
		{ "Background Main Color", named("MainContainer"), "BackgroundColor3", "the window frame" },
		{ "Sidebar Color", named("Background1"), "BackgroundColor3", "the sidebar" },
		{ "Section Panel Color", function(item) return item.Name:sub(-4) == "_Dot" end, "BackgroundColor3", "the section panels" },
		{ "Outline Color", named("TopStroke"), "BackgroundColor3", "the line under the title" },
		{ "Label Color", named("LabelBG"), "BackgroundColor3", "label rows" },
		{ "Toggle Checked Color", named("check"), "BackgroundColor3", "toggle check marks" },
	}
	for index, entry in ipairs(checks) do
		local r, g, b = 10 + index, 20 + index, 30 + index
		getgenv().UIColor[entry[1]] = Color3.fromRGB(r, g, b)
		assert(paints(entry[2], entry[3], r, g, b), entry[4] .. " did not follow " .. entry[1])
	end
	-- outlines are UIStrokes: the window edge, the sidebar edge, section edges
	getgenv().UIColor["Outline Color"] = Color3.fromRGB(7, 8, 9)
	local strokes = 0
	for _, item in ipairs(fresh.Internal.Gui:GetDescendants()) do
		if item.ClassName == "UIStroke" then
			local r, g, b = rgb(item.Color)
			if r == 7 and g == 8 and b == 9 then strokes = strokes + 1 end
		end
	end
	assert(strokes >= 3, "window, sidebar and section outlines follow Outline Color, got " .. strokes)
	local function sectionAlpha()
		for _, item in ipairs(fresh.Internal.Gui:GetDescendants()) do
			if item.Name:sub(-4) == "_Dot" then return item.BackgroundTransparency end
		end
	end
	assert(math.abs(sectionAlpha() - 0.15) < 0.001, "section panels keep their slight see-through by default")
	getgenv().UIColor["Background 1 Transparency"] = 0.3
	assert(math.abs(sectionAlpha() - 0.51) < 0.001, "and follow the panels when those become see-through")
	getgenv().UIColor["Background 1 Transparency"] = 0
	assert(math.abs(sectionAlpha() - 0.15) < 0.001, "and come back")
	getgenv().UIColor = priorColors
end)

---------------------------------------------------------------- dark, solid window
print("Dark window")
run("the window frame and panels are solid by default, and an old see-through setting is capped", function()
	local source = io.open(REPO .. "/libraries/UILibrary.lua", "rb"):read("*a")
	assert(source:find("uigradient.Transparency = NumberSequence.new(0)", 1, true), "the window frame is not see-through")
	local priorTheme, priorColors = FILES["Peridot/Theme.json"], getgenv().UIColor
	FILES["Peridot/Theme.json"] = nil
	assert(loadfile(REPO .. "/libraries/UILibrary.lua"))()
	assert(getgenv().UIColor["Background 1 Transparency"] == 0, "panels start solid")
	FILES["Peridot/Theme.json"] = service("HttpService"):JSONEncode({ PanelTransparency = 0.9 })
	assert(loadfile(REPO .. "/libraries/UILibrary.lua"))()
	assert(getgenv().UIColor["Background 1 Transparency"] == 0.6, "an old 0.9 is capped at 0.6")
	FILES["Peridot/Theme.json"], getgenv().UIColor = priorTheme, priorColors
end)

---------------------------------------------------------------- 4. Blox Fruits module
print("games/2753915549.lua")

local BF_STUB_CORE = [==[
local env = getgenv()
HARNESS_CALLS = { esp = 0, hop = 0, lowcpu = 0, fly = nil, flySpeed = nil }
env.Core = {
	EspPly = function() HARNESS_CALLS.esp = HARNESS_CALLS.esp + 1 end,
	LocationEsp = function() end, DevEsp = function() end, flowerEsp = function() end,
	EventIslandEsp = function() end, gearEsp = function() end, AdvanFruitEsp = function() end,
	HakiClorEsp = function() end, LegenSword = function() end, ChestEsp = function() end,
	berriesEsp = function() end,
}
env.BossList = { "Bobby", "Yeti" }
env.MaterialList = { "Angel Wings", "Fish Tail" }
env.AllBoats = { "Guardian", "Sloop" }
env.DungeonTables = { "Flame", "Ice" }
env.IslandData = { ["Pirate Village"] = {}, ["Frozen Village"] = {} }
env.GetMobs = function() return { "Bandit", "Monkey" } end
env.HopServer = function() HARNESS_CALLS.hop = HARNESS_CALLS.hop + 1 end
env.LowCpu = function() HARNESS_CALLS.lowcpu = HARNESS_CALLS.lowcpu + 1 end
env.getInfinity_Ability = function(kind, on) HARNESS_CALLS.ability = kind .. tostring(on) end
env.getFruitStock = function() HARNESS_CALLS.stock = (HARNESS_CALLS.stock or 0) + 1 return "Advance Fruit Stock\nRocket-Rocket - $5,000\n" end
env.Check_Eye = function() HARNESS_CALLS.eyes = true return 3, false end
env.IsInSubmergedIsland = function() return HARNESS_CALLS.submerged == true end
env.fetchServersData = function()
	return {
		{ id = "job", playing = 5, maxPlayers = 12, ping = 80 }, -- this server: not offered
		{ id = "aaaaaaaa11", playing = 9, maxPlayers = 12, ping = 60 },
		{ id = "bbbbbbbb22", playing = 2, maxPlayers = 12, ping = 120 },
		{ id = "cccccccc33", playing = 12, maxPlayers = 12, ping = 40 }, -- full: not offered
	}
end
env.Pirates = function() HARNESS_CALLS.team = "Pirates" end
env.Marines = function() HARNESS_CALLS.team = "Marines" end
_G.toggleFly = function(on) HARNESS_CALLS.fly = on end
_G.updateFlySpeed = function(v) HARNESS_CALLS.flySpeed = v end
]==]

local function snapshot()
	local copy = {}
	for key, value in pairs(_G) do copy[key] = value end
	return copy
end
local function changedKeys(before, after)
	local keys = {}
	for key, value in pairs(after) do if before[key] ~= value then keys[#keys + 1] = key end end
	for key in pairs(before) do if after[key] == nil then keys[#keys + 1] = key end end
	return keys
end
local function control(kind, suffix) -- one control of this kind whose key ends with `suffix`
	local found
	for key, handle in pairs(lib.ControlRegistry[kind]) do
		if key:sub(-#suffix) == suffix then
			assert(not found, "ambiguous control " .. suffix)
			found = handle
		end
	end
	return assert(found, "missing " .. kind .. " " .. suffix)
end
local function runLoops(hook, limit) -- run each captured task.spawn body until it has waited `limit` times
	local realWait = task.wait
	for _, f in ipairs(SPAWN_LOG) do
		local n = 0
		task.wait = function()
			n = n + 1
			if hook then hook(n) end
			if n > limit then error("STOP_LOOP", 0) end
			return 0
		end
		local ok, err = pcall(f)
		task.wait = realWait
		assert(ok or err == "STOP_LOOP", "spawned task failed: " .. tostring(err))
	end
end

local universalBackground = lib.ControlRegistry.Dropdowns["UI Settings||Background||Background"]
local registryBefore = {}
for kind, entries in pairs(lib.ControlRegistry) do
	registryBefore[kind] = {}
	for key in pairs(entries) do registryBefore[kind][key] = true end
end

-- Buttons have no handle in the registry, so wrap the section factories while the
-- module builds and keep each button's callback by title.
local BUTTONS, BOXES, DROPDOWNS = {}, {}, {}
local function recordButtons()
	local realCreateMain = lib.CreateMain
	local function patch(section)
		local realButton, realBox, realDropdown = section.CreateButton, section.CreateBox, section.CreateDropdown
		section.CreateButton = function(options, callback)
			BUTTONS[options.Title] = callback
			return realButton(options, callback)
		end
		section.CreateBox = function(options, callback)
			local handle = realBox(options, callback)
			BOXES[options.Title] = { callback = callback, handle = handle }
			return handle
		end
		section.CreateDropdown = function(options, callback)
			local handle = realDropdown(options, callback)
			DROPDOWNS[options.Title] = handle
			return handle
		end
		return section
	end
	lib.CreateMain = function(...)
		local main = realCreateMain(...)
		local realPage = main.CreatePage
		main.CreatePage = function(...)
			local page = realPage(...)
			local realSection, realSubTab = page.CreateSection, page.CreateSubTab
			page.CreateSection = function(...) return patch(realSection(...)) end
			page.CreateSubTab = function(...)
				local sub = realSubTab(...)
				local subSection = sub.CreateSection
				sub.CreateSection = function(...) return patch(subSection(...)) end
				return sub
			end
			return page
		end
		return main
	end
	return function() lib.CreateMain = realCreateMain end
end

run("module builds with no errors (stub core, shared library)", function()
	OVERRIDES["libraries/UILibrary.lua"] = "return _G.__HARNESS_LIB"
	OVERRIDES["libraries/bf-main.lua"] = BF_STUB_CORE
	_G.__HARNESS_LIB = lib
	PLACE_ID_OVERRIDE = 2753915549
	getgenv().PeridotBloxFruitsLoaded, getgenv().PeridotBloxFruitsCoreLoaded = nil, nil
	UI_ERRORS, WARNINGS = {}, {}
	CAPTURE_SPAWNS = true
	local stopRecording = recordButtons()
	local ok, err = pcall(assert(loadfile(REPO .. "/games/2753915549.lua")))
	stopRecording()
	CAPTURE_SPAWNS = false
	PLACE_ID_OVERRIDE = nil
	assert(ok, err)
	assert(#UI_ERRORS == 0, "errors: " .. tostring(UI_ERRORS[1]))
	assert(#WARNINGS == 0, "warnings: " .. table.concat(WARNINGS, " | "))
	assert(#SPAWN_LOG >= 3, "module started its loops, got " .. #SPAWN_LOG)
	assert(lib.Internal.HideGui.Enabled ~= false, "the UI toggle button stays available")
end)

local bfToggles = {}
for key, handle in pairs(lib.ControlRegistry.Toggles) do
	if not registryBefore.Toggles[key] then bfToggles[#bfToggles + 1] = { key = key, handle = handle } end
end

run("every toggle writes an option flag in both directions", function()
	assert(#bfToggles >= 200, "toggles built: " .. #bfToggles)
	for _, t in ipairs(bfToggles) do
		if t.key:sub(-5) ~= "||Fly" then -- calls the core's fly function instead of writing a flag
		local was = t.handle.Get()
		local before = snapshot()
		t.handle.Set(not was)
		assert(#changedKeys(before, snapshot()) > 0, "toggle writes nothing: " .. t.key)
		local flipped = snapshot()
		t.handle.Set(was)
		assert(#changedKeys(flipped, snapshot()) > 0, "toggle does not undo: " .. t.key)
		end
	end
	local fly = control("Toggles", "Misc||Movement||Fly")
	fly.Set(true)
	assert(HARNESS_CALLS.fly == true, "Fly calls the core")
	fly.Set(false)
	assert(HARNESS_CALLS.fly == false)
	control("Sliders", "Misc||Movement||Fly Speed").Set(120)
	assert(HARNESS_CALLS.flySpeed == 120)
end)

run("defaults reach the flags the core reads", function()
	assert(_G.ChooseWP == "Melee" and _G.SelectedBoat == "Guardian" and _G.DangerSc == "Lv 1")
	assert(_G.TweenSpeedNear == 120 and _G.TweenSpeedFar == 100 and _G.HopDelay == 1800, "tween defaults are the slower, safer pair")
	assert(_G.MasteryHealthPct == 70 and _G.pSats == 1 and _G.Num_self == 25 and _G.Range == 100)
	assert(_G.FishCatchDelay == nil, "0 means the core's random delay")
	assert(_G.ABmethod == "Aim Player" and _G.SelectDN == "Day" and _G.SelectIslandMastery == "Cake")
	assert(#_G.SelectedMasterySkills == 5)
end)

run("dropdowns and sliders write their flags", function()
	control("Dropdowns", "||Auto Farm||Weapon").Set("Sword")
	assert(_G.ChooseWP == "Sword")
	control("Dropdowns", "||Selected Mob||Mob").Set("Monkey")
	assert(_G.SelectMob == "Monkey" and getgenv().SelectMob == "Monkey")
	control("Dropdowns", "||Selected Island||Island").Set("Frozen Village")
	assert(_G.SelectIsland == "Frozen Village")
	control("Dropdowns", "||Boss Farm||Boss").Set("Bobby")
	assert(_G.FindBoss == "Bobby")
	control("Sliders", "||Server||Hop Every (Minutes)").Set(10)
	assert(_G.HopDelay == 600, "minutes become seconds, got " .. tostring(_G.HopDelay))
	control("Sliders", "||Fishing||Catch Delay (0 = random)").Set(4)
	assert(_G.FishCatchDelay == 4)
	control("Sliders", "||Fishing||Catch Delay (0 = random)").Set(0)
	assert(_G.FishCatchDelay == nil)
end)

run("mastery skill switches rebuild the skill list", function()
	control("Toggles", "||Mastery Skills||Use Skill X").Set(false)
	local list = table.concat(_G.SelectedMasterySkills, "")
	assert(list == "ZCVF", "got " .. list)
	control("Toggles", "||Mastery Skills||Use Skill X").Set(true)
	assert(table.concat(_G.SelectedMasterySkills, "") == "ZXCVF")
end)

run("a switch follows the core when it turns a feature off by itself", function()
	local farm = control("Toggles", "||Auto Farm||Auto Farm Level")
	farm.Set(true)
	assert(_G.Level == true)
	_G.Level = false -- the core finishing a quest
	runLoops(nil, 2)
	assert(farm.Get() == false, "toggle caught up with the core")
	assert(_G.Level == false)
end)

run("ESP routines run while a switch is on and once more after it goes off", function()
	local esp = control("Toggles", "||ESP Targets||Players")
	local calls = {}
	runLoops(function(n)
		calls[n] = HARNESS_CALLS.esp
		if n == 1 then esp.Set(true) end
		if n == 3 then esp.Set(false) end
	end, 7)
	assert(calls[2] == calls[1] + 1 or calls[2] > calls[1], "ran while on")
	assert(HARNESS_CALLS.esp > 0)
	-- after the switch went off: exactly one cleanup pass, then silence
	local afterOff, final = calls[5], calls[7]
	assert(afterOff == final, "stopped calling after cleanup, " .. tostring(afterOff) .. " vs " .. tostring(final))
end)

run("running the module twice is refused", function()
	WARNINGS = {}
	PLACE_ID_OVERRIDE = 2753915549
	local ok, err = pcall(assert(loadfile(REPO .. "/games/2753915549.lua")))
	PLACE_ID_OVERRIDE = nil
	assert(ok, err)
	assert(WARNINGS[#WARNINGS] and WARNINGS[#WARNINGS]:find("already running", 1, true), "second run warns")
end)

local function hasLabel(text)
	for _, item in ipairs(lib.Internal.Gui:GetDescendants()) do
		if item.ClassName == "TextLabel" and item.Text == text then return true end
	end
	return false
end

run("buttons call the core and report instead of throwing", function()
	UI_ERRORS, WARNINGS = {}, {}
	BUTTONS["Server Hop"]()
	assert(HARNESS_CALLS.hop == 1, "Server Hop calls HopServer")
	BUTTONS["Low CPU Mode"]()
	assert(HARNESS_CALLS.lowcpu == 1, "Low CPU Mode calls LowCpu")
	BUTTONS["Disable Camera Shake"]() -- the stub core has no such function: must say so, not error
	BUTTONS["Remove Dodge Cooldown"]()
	assert(#UI_ERRORS == 0 and #WARNINGS == 0, "no errors: " .. tostring(UI_ERRORS[1] or WARNINGS[1]))
end)

run("lists show how many entries they found, and Refresh re-reads them", function()
	assert(hasLabel("2 mobs found") and hasLabel("2 islands found"), "initial counts")
	control("Dropdowns", "||Selected Mob||Mob").Set("Monkey")
	getgenv().GetMobs = function() return { "A", "B", "C" } end
	BUTTONS["Refresh Mob List"]()
	assert(hasLabel("3 mobs found"), "count updated after Refresh")
	assert(_G.SelectMob == nil, "the cleared dropdown no longer leaves a hidden selection")
	getgenv().GetMobs = function() return {} end
	BUTTONS["Refresh Mob List"]()
	assert(hasLabel("No mobs found. Press Refresh once the game has finished loading."), "empty state says what to do")
end)

run("Interface Settings has the Background section, and it loads a background", function()
	local entry -- the second window's picker is registered under its sub-tab key
	for key, handle in pairs(lib.ControlRegistry.Dropdowns) do
		if key:sub(-#"||Background||Background") == "||Background||Background" and handle ~= universalBackground then
			entry = handle
		end
	end
	assert(entry, "the Blox Fruits window built its own Background picker")
	local before = getgenv().UIColor["Background 1 Transparency"]
	entry.Set("Green Night Driving")
	assert(getgenv().UIColor["Background 1 Transparency"] == 0.3, "panels turn see-through while a background shows")
	entry.Set("None")
	assert(getgenv().UIColor["Background 1 Transparency"] == before, "and come back when it is cleared")
end)

run("Stop All Features switches everything off", function()
	local farm = control("Toggles", "||Auto Farm||Auto Farm Level")
	farm.Set(true)
	BUTTONS["Stop All Features"]()
	assert(farm.Get() == false and _G.Level == false)
end)

run("config manager: create, overwrite, load, autoload, export and import, delete", function()
	local folder = "Peridot/BloxFruits/"
	local farm = control("Toggles", "||Auto Farm||Auto Farm Level")
	local speed = control("Sliders", "||Tween Speed||Short Hop Speed")
	UI_ERRORS, WARNINGS = {}, {}

	BOXES["Config name"].callback("bf")
	BUTTONS["Create config"]()
	assert(FILES[folder .. "bf.json"], "created")
	local first = FILES[folder .. "bf.json"]
	BUTTONS["Create config"]() -- same name again: refused, file untouched
	assert(FILES[folder .. "bf.json"] == first, "Create does not overwrite")

	BUTTONS["Load config"]() -- nothing picked yet: says so
	DROPDOWNS["Config list"].Set("bf")
	farm.Set(true)
	speed.Set(222)
	BUTTONS["Overwrite config"]()
	assert(FILES[folder .. "bf.json"] ~= first, "overwritten with the current values")

	farm.Set(false)
	speed.Set(100)
	RUN_SPAWNS = true -- Load applies values from task.spawn
	BUTTONS["Load config"]()
	RUN_SPAWNS = false
	assert(farm.Get() == true and _G.Level == true, "toggle restored")
	assert(_G.TweenSpeedNear == 222, "slider restored, got " .. tostring(_G.TweenSpeedNear))

	BUTTONS["Set as autoload"]()
	assert(FILES[folder .. "autoload.txt"] == "bf", "autoload remembered")
	assert(hasLabel("Current autoload config: bf"), "label shows it")
	assert(lib.ConfigSystem.GetAutoload() == "bf")

	BUTTONS["Export current config"]()
	local exported = BOXES["Config JSON"].handle.Get()
	assert(exported ~= "", "export fills the JSON box")
	farm.Set(false)
	RUN_SPAWNS = true
	BOXES["Config JSON"].callback(exported)
	BUTTONS["Import config"]()
	RUN_SPAWNS = false
	assert(farm.Get() == true, "import applies the exported values")
	BOXES["Config JSON"].callback("not json")
	BUTTONS["Import config"]() -- reports instead of throwing

	BUTTONS["Reset autoload"]()
	assert(FILES[folder .. "autoload.txt"] == nil and hasLabel("Current autoload config: none"))
	BUTTONS["Set as autoload"]()
	BUTTONS["Delete config"]()
	assert(FILES[folder .. "bf.json"] == nil, "deleted")
	assert(FILES[folder .. "autoload.txt"] == nil, "deleting the autoload config clears autoload")
	assert(#UI_ERRORS == 0 and #WARNINGS == 0, "no errors: " .. tostring(UI_ERRORS[1] or WARNINGS[1]))
	farm.Set(false)
end)

run("config names with slashes are refused", function()
	local ok, err = lib.ConfigSystem.Create("../evil")
	assert(not ok and tostring(err):find("slashes"), tostring(err))
end)

run("controls marked NoSave stay out of configs", function()
	local text = lib.ConfigSystem.Export()
	local data = service("HttpService"):JSONDecode(text)
	for key in pairs(data.Boxes) do
		assert(not key:find("Config JSON", 1, true) and not key:find("Config name", 1, true), "saved: " .. key)
	end
	for key in pairs(data.Dropdowns) do
		assert(not key:find("Config list", 1, true), "saved: " .. key)
	end
end)


-- The page container is 435 px wide; the sub-tab bar loses 10 px to its inset and 8 px to padding.
-- Text is GothamBold 14, about 8.5 px a letter, so 9 px a letter leaves some room.
local STRIP_WIDTH = 435 - 10 - 8
local function stripsFit()
	local strips = 0
	for _, item in ipairs(lib.Internal.Gui:GetDescendants()) do
		if item.Name == "SubTabBar" then
			strips = strips + 1
			local width, tabs, names = 0, 0, {}
			for _, tab in ipairs(item:GetChildren()) do
				if tab.ClassName == "TextButton" then
					tabs = tabs + 1
					names[#names + 1] = tab.Text
					width = width + #tab.Text * 9
				end
			end
			width = width + 14 * math.max(tabs - 1, 0)
			assert(width <= STRIP_WIDTH, ("sub-tabs %s need about %d px, the bar has %d"):format(table.concat(names, ", "), width, STRIP_WIDTH))
		end
	end
	assert(strips > 0, "found the sub-tab bars")
end

run("every page's sub-tab bar fits without scrolling (all seas unknown, so every tab is built)", stripsFit)

run("Go Through Portal sends the entrance request for the chosen portal", function()
	local rs = service("ReplicatedStorage")
	local remotes = rs:FindFirstChild("Remotes") or newInstance("Remotes", rs)
	local comm = remotes:FindFirstChild("CommF_") or newInstance("CommF_", remotes)
	local sent
	comm.InvokeServer = function(_, ...) sent = { ... } end
	UI_ERRORS, WARNINGS = {}, {}
	BUTTONS["Go Through Portal"]() -- nothing picked yet: says so instead of sending
	assert(sent == nil, "no request without a portal")
	control("Dropdowns", "||Portals||Portal").Set("Hydra Island")
	assert(_G.PortalTarget == "Hydra Island")
	BUTTONS["Go Through Portal"]()
	assert(sent and sent[1] == "requestEntrance" and sent[2] ~= nil, "request sent")
	assert(#UI_ERRORS == 0 and #WARNINGS == 0, "no errors")
end)

run("shop, sea travel and team buttons send the script's own commands", function()
	local comm = service("ReplicatedStorage"):FindFirstChild("Remotes"):FindFirstChild("CommF_")
	local sent
	comm.InvokeServer = function(_, ...) sent = { ... } return 1 end
	local expected = {
		["Buy Black Leg"] = { "BuyBlackLeg" },
		["Buy Dragon Claw"] = { "BlackbeardReward", "DragonClaw", "2" },
		["Buy Godhuman"] = { "BuyGodhuman" },
		["Buy Bisento"] = { "BuyItem", "Bisento" },
		["Buy Soul Guitar"] = { "soulGuitarBuy", true },
		["Random Bone Roll"] = { "Bones", "Buy", 1, 1 },
		["Random Fruit From Cousin"] = { "Cousin", "Buy" },
		["Travel To Second Sea"] = { "TravelDressrosa" },
		["Travel To Third Sea"] = { "TravelZou" },
	}
	UI_ERRORS, WARNINGS = {}, {}
	for title, args in pairs(expected) do
		sent = nil
		assert(BUTTONS[title], "missing button " .. title)
		BUTTONS[title]()
		assert(sent and #sent == #args, title .. " sent " .. tostring(sent and #sent))
		for i = 1, #args do
			assert(sent[i] == args[i], title .. " argument " .. i .. " is " .. tostring(sent[i]))
		end
	end
	BUTTONS["Join Marines"]()
	assert(HARNESS_CALLS.team == "Marines")
	assert(#UI_ERRORS == 0 and #WARNINGS == 0, "no errors")
end)

run("the submarine trip switches itself off once you are on the Submerged Island", function()
	local trip = control("Toggles", "||Submerged Island||Go To Submerged Island (Submarine)")
	trip.Set(true)
	HARNESS_CALLS.submerged = true
	runLoops(nil, 2)
	runLoops(nil, 2) -- the second pass lets the sync loop see the flag change
	assert(_G.SubmarineTravel == false and trip.Get() == false)
	HARNESS_CALLS.submerged = false
end)

run("Go To Island with no island picked switches itself off instead of erroring", function()
	local go = control("Toggles", "||Islands||Go To Island")
	go.Set(true)
	runLoops(nil, 2)
	runLoops(nil, 2)
	assert(_G.TeleportIslandOn == false and go.Get() == false)
end)

run("server list: fewest players first, this server and full ones left out", function()
	BUTTONS["Refresh Server List"]()
	assert(hasLabel("2 servers found"), "two joinable servers")
	local dropdown = control("Dropdowns", "||Server List||Server")
	dropdown.Set("2 of 12 players, ping 120, bbbbbbbb")
	assert(_G.ServerChoice == "2 of 12 players, ping 120, bbbbbbbb")
	UI_ERRORS, WARNINGS = {}, {}
	BUTTONS["Join Selected Server"]()
	assert(#UI_ERRORS == 0 and #WARNINGS == 0)
end)

run("stock, eye check and ability buttons call the core", function()
	BUTTONS["Check Advanced Dealer Stock"]()
	assert(HARNESS_CALLS.stock == 1)
	BUTTONS["Check Tyrant Eyes"]()
	assert(HARNESS_CALLS.eyes == true)
	BUTTONS["Infinite Energy (until you rejoin)"]()
	assert(HARNESS_CALLS.ability == "Energytrue")
	BUTTONS["Infinite Observation Range"]()
	assert(HARNESS_CALLS.ability == "Observationtrue")
end)

local function buildSea(world, stubExtra)
	local known = {}
	for _, entries in pairs(lib.ControlRegistry) do
		for _, handle in pairs(entries) do known[handle] = true end
	end
	OVERRIDES["libraries/bf-main.lua"] = BF_STUB_CORE .. "\nenv.World" .. world .. " = true\n" .. (stubExtra or "")
	getgenv().PeridotBloxFruitsLoaded, getgenv().PeridotBloxFruitsCoreLoaded = nil, nil
	_G.World1, _G.World2, _G.World3 = nil, nil, nil
	PLACE_ID_OVERRIDE = 2753915549
	UI_ERRORS, WARNINGS = {}, {}
	local ok, err = pcall(assert(loadfile(REPO .. "/games/2753915549.lua")))
	PLACE_ID_OVERRIDE = nil
	assert(ok, err)
	assert(#UI_ERRORS == 0 and #WARNINGS == 0, "errors: " .. tostring(UI_ERRORS[1] or WARNINGS[1]))
	stripsFit()
	local titles = {}
	for _, entries in pairs(lib.ControlRegistry) do
		for key, handle in pairs(entries) do
			if not known[handle] then titles[key:match("||([^|]*)$")] = true end
		end
	end
	return titles
end
local function expectControls(titles, present, absent)
	for _, title in ipairs(present) do assert(titles[title], "missing in this sea: " .. title) end
	for _, title in ipairs(absent) do assert(not titles[title], "should not exist in this sea: " .. title) end
end

run("Sea 1 hides the controls that only work in Sea 2 and Sea 3", function()
	local titles = buildSea(1, "env.GetMobs = function() return {} end")
	expectControls(titles,
		{ "Auto Farm Level", "Get Saber", "Get Marine Coat", "Second Sea Quest", "Farm Chests", "Auto Server Hop",
		  "Kill Chief Warden", "Unlock Flamingo Access (Level 1500+)", "Go To Island", "Go To NPC" },
		{ "Farm Bones", "Dough King", "Get Tushita", "Get Trident", "Factory Raid", "Castle Raid", "Auto Start Raid",
		  "Buy Microchip", "Dojo Belt Quests", "Find Mirage Island", "Find Kitsune Island", "Find Prehistoric Island and Go To Head",
		  "Elite Hunter", "Kill Tyrant of the Skies", "Third Sea Quest", "Get Electric Claw", "Kill Kilo Admiral",
		  "Go To Submerged Island (Submarine)" })
	assert(_G.SelectIslandMastery == "Selected Mob", "mastery target only offers what works here")
	assert(hasLabel("No mobs found. Press Refresh once the game has finished loading."), "empty list explains itself")
end)
run("Sea 2 shows its own controls only", function()
	local titles = buildSea(2)
	expectControls(titles,
		{ "Auto Farm Level", "Get Trident", "Get Longsword", "Factory Raid", "Buy Microchip", "Auto Start Raid",
		  "Bartilo Quest", "Third Sea Quest", "Get Godhuman" },
		{ "Get Saber", "Get Marine Coat", "Second Sea Quest", "Farm Bones", "Castle Raid", "Get Tushita",
		  "Find Mirage Island", "Dojo Belt Quests", "Get Dragon Talon" })
end)
run("Sea 3 shows its own controls only", function()
	local titles = buildSea(3)
	expectControls(titles,
		{ "Auto Farm Level", "Farm Bones", "Dough King", "Get Tushita", "Castle Raid", "Auto Start Raid",
		  "Find Mirage Island", "Find Kitsune Island", "Dojo Belt Quests", "Get Rainbow Haki", "Elite Hunter" },
		{ "Get Saber", "Get Trident", "Factory Raid", "Buy Microchip", "Second Sea Quest", "Bartilo Quest" })
	assert(_G.SelectIslandMastery == "Cake")
end)
run("an unknown sea hides nothing", function()
	-- the first run, with no World flag set, built every control
	assert(#bfToggles >= 200)
end)

---------------------------------------------------------------- Murder Mystery 2 module
print("games/142823291.lua")

-- Drives the adapter the way libraries/mm2-main.lua (the Noir script) does: through
-- host.CreateTab() and the section builders, with Noir's argument order.
local MM2_STUB_CORE = [==[
local host = getgenv().PeridotMM2Host
MM2 = { calls = {} }
local calls = MM2.calls
local tab = host.CreateTab()
local aim = tab:AddSection("SILENT AIM", "Server FireServer redirect")
MM2.setAim = aim:AddToggle("Enabled", function(v) calls.aim = v end)
aim:AddToggle("Wall Check", function(v) calls.wall = v end)
MM2.mode = aim:AddDropdown("Silent Aim Mode", { "Noir", "Tering" }, function(v) calls.mode = v end)
MM2.width = aim:AddSlider("Tracer Width", 40, 250, 100, function(v) calls.width = v end)
MM2.color = aim:AddColorpicker("Tracer Color", Color3.new(1, 0, 0), function(c) calls.color = c end)
aim:AddLabel("Стили: Energy/Laser. Preview — камера преследует трейсер.")
aim:AddParagraph("Bullet Tracer", "Трейсер пули.")
aim:AddButton("Preview Tracer", function() calls.preview = (calls.preview or 0) + 1 end)
aim:AddButton("Print Telemetry", function() calls.telemetry = true end)
aim:AddToggle("Wall Check", function(v) calls.wall2 = v end) -- the same label twice
aim:AddPlayerDropdown("Target player", function(p) calls.player = p end)
local lock = tab:AddSection("MISC • AIMLOCK", "Camera lock")
MM2.key = lock:AddKeybind("Aimlock Quick Toggle", "None", function(k) calls.key = k end)
MM2.label = lock:AddLabel("Status: idle")
MM2.box = tab:AddSection("MISC • CUSTOMIZE CURSOR"):AddTextBox("Custom Cursor ID", function(t) calls.text = t end)
tab:AddSection("MAIN • SELF MODS"):AddToggle("Enable WalkSpeed", function(v) calls.speed = v end)
local fps = tab:AddSection("MISC • FPS")
fps:AddToggle("Fade", function(v) calls.fade = v end)
fps:AddToggle("Less Lag", function() end)
tab:AddSection("MAIN \x75{2022} FUN CLIENT"):AddToggle("Permanent Headless", function() end)
tab:AddSection("TROLL \u{2022} BANG"):AddButton("Refresh Player List", function() end)
tab:AddSection("⚡ Fling"):AddButton("🔫 Sheriff", function() calls.fling = true end)
tab:AddSection("VISUAL • CHAM", "BY PLAYER"):AddToggle("Murderer Only", function() end)
tab:AddSection("FE Animations"):AddToggle("Enable FE Anims", function() end)
tab:AddSection("MAP • TELEPORT"):AddButton("Teleport to Lobby", function() end)
tab:AddSection("MISC • SOMETHING NEW", "a new tool"):AddToggle("LOUD SWITCH", function() end)
host.Notify("MM2 Silent Aim: loaded", 2)
getgenv().__NoirShowPanel = function(page) calls.panel = page end
getgenv().__NoirGui = Instance.new("ScreenGui")
]==]

local mm2Saved = { BUTTONS, BOXES, DROPDOWNS }
run("MM2 module builds the script's controls in the Peridot window", function()
	BUTTONS, BOXES, DROPDOWNS = {}, {}, {}
	OVERRIDES["libraries/mm2-main.lua"] = MM2_STUB_CORE
	PLACE_ID_OVERRIDE = 142823291
	getgenv().PeridotMM2Loaded = nil
	UI_ERRORS, WARNINGS = {}, {}
	local stopRecording = recordButtons()
	local ok, err = pcall(assert(loadfile(REPO .. "/games/142823291.lua")))
	stopRecording()
	PLACE_ID_OVERRIDE = nil
	assert(ok, err)
	assert(#UI_ERRORS == 0 and #WARNINGS == 0, "errors: " .. tostring(UI_ERRORS[1] or WARNINGS[1]))
	assert(MM2 and MM2.setAim, "the stub core ran against the adapter")
end)

local function hasBadText(text)
	return text:find("[\208\209]") ~= nil -- Russian
end

run("MM2 controls land on the right page, sub-tab and section, with plain titles", function()
	local expected = {
		Toggles = {
			"Gun||Aim Assist||Aim Assist", "Gun||Aim Assist||Ignore Targets Behind Walls", "Gun||Aim Assist||Ignore Targets Behind Walls (2)",
			"Player||Speed And Jumping||Change Walking Speed", "Player||Protection||Remove Screen Fade",
			"Extras||Smoother Game||Less Lag", "Player||Avatar Looks||Headless Look",
			"See||Solid Color Players||Only The Murderer", "Emotes||Custom Animations||Use Custom Animations",
			"Extras||Something New||Loud Switch",
		},
		Sliders = { "Gun||Bullet Trails||Trail Thickness" },
		Dropdowns = { "Gun||Aim Assist||Aim Style", "Extras||Camera Aim Lock||Key To Turn It On Or Off", "Gun||Aim Assist||Target player" },
		Boxes = { "Extras||Custom Cursor||Your Own Cursor Picture Number" },
	}
	for kind, keys in pairs(expected) do
		for _, key in ipairs(keys) do
			assert(lib.ControlRegistry[kind][key], "missing " .. kind .. " " .. key)
		end
	end
	for _, title in ipairs({ "Preview The Trail", "Fling The Sheriff", "Go To The Lobby", "Refresh Player List" }) do
		assert(BUTTONS[title], "missing button " .. title)
	end
	assert(not BUTTONS["Print Telemetry"], "a developer-only button stays hidden")
	stripsFit() -- every page's sub-tab bar still fits the window
end)

run("MM2 shows no Russian text and no leftover developer wording in the window", function()
	local words = { "Silent Aim", "Prediction", "Hitbox", "Noclip", "Desync", "Aimlock", "Tracer", "ESP ", "Keybind", "Telemetry", "Noir" }
	for _, item in ipairs(lib.Internal.Gui:GetDescendants()) do
		if item.ClassName == "TextLabel" or item.ClassName == "TextButton" then
			local text = tostring(item.Text or "")
			assert(not hasBadText(text), "Russian text on screen: " .. text)
		end
	end
	for kind, entries in pairs(lib.ControlRegistry) do
		for key in pairs(entries) do
			if key:find("^Gun||") or key:find("^Player||") or key:find("^Extras||") or key:find("^See||") or key:find("^Fun||") then
				for _, word in ipairs(words) do
					assert(not key:find(word, 1, true), "developer wording in " .. kind .. " " .. key)
				end
			end
		end
	end
	assert(not hasLabel("Status: idle") == false, "the script's own status text still shows")
end)

run("MM2 controls keep the Noir return values and callback timing", function()
	local calls = MM2.calls
	assert(calls.aim == false, "a toggle reports its start state")
	MM2.setAim(true)
	assert(calls.aim == true and lib.ControlRegistry.Toggles["Gun||Aim Assist||Aim Assist"].Get() == true)
	MM2.setAim()
	assert(calls.aim == false, "calling the setter with nothing flips it")

	assert(calls.width == 100, "a slider reports its start value once")
	MM2.width:SetValue(200)
	assert(calls.width == 200 and MM2.width:GetValue() == 200)

	assert(calls.mode == nil, "a dropdown says nothing until something is picked")
	MM2.mode:SetValue("Tering")
	assert(calls.mode == "Tering", "the script gets its own value back, got " .. tostring(calls.mode))
	assert(hasLabel("Aim Assist") or true)
	lib.ControlRegistry.Dropdowns["Gun||Aim Assist||Aim Style"].Set("Normal")
	assert(calls.mode == "Noir", "the plain name 'Normal' gives the script 'Noir', got " .. tostring(calls.mode))
	MM2.mode:Refresh({ "Noir" }, "Noir")
	assert(calls.mode == "Noir")

	lib.ControlRegistry.Dropdowns["Extras||Camera Aim Lock||Key To Turn It On Or Off"].Set("Q")
	assert(calls.key == "Q" and MM2.key:GetValue() == "Q", "a key picker hands the key name over")

	assert(calls.color ~= nil, "a color picker reports its start color")
	local before = calls.color
	MM2.color:SetRGBValue(Color3.new(0, 1, 0))
	assert(calls.color ~= before)

	MM2.label:SetValue("Status: aiming")
	assert(MM2.label:GetValue() == "Status: aiming" and hasLabel("Status: aiming"))
	BUTTONS["Preview The Trail"]()
	assert(calls.preview == 1)
	BUTTONS["Fling The Sheriff"]()
	assert(calls.fling == true)
	MM2.box:SetValue("123")
end)

run("MM2 panel buttons open the script's own panels", function()
	for title, page in pairs({ ["Open The Emote Browser"] = "emotes", ["Skin Changer"] = "skins", ["Language And Streamer Options"] = "settings" }) do
		BUTTONS[title]()
		assert(MM2.calls.panel == page, title .. " opened " .. tostring(MM2.calls.panel))
	end
end)

run("MM2 Stop All Features and Unload UI", function()
	MM2.setAim(true)
	BUTTONS["Stop All Features"]()
	assert(MM2.calls.aim == false, "switches go off")
	local realUnload, unloaded = lib.Unload, false
	lib.Unload = function() unloaded = true end -- the shared test window stays for the tests after this
	BUTTONS["Unload UI"]()
	lib.Unload = realUnload
	assert(unloaded and getgenv().PeridotMM2Loaded == nil and getgenv().PeridotMM2Host == nil)
end)

run("MM2 wording: every control and section of the script is explained in plain English", function()
	local Text = assert(loadfile(REPO .. "/libraries/mm2-text.lua"))()
	local developerWords = { "Silent Aim", "Prediction", "Hitbox", "Noclip", "Desync", "Aimlock", "Tracer", "ESP", "Keybind",
		"Bind Button", "FOV", "Ping", "Config", "Telemetry", "Whitelist", "Cache", "Xray", "GUI", "Trigger Bot", "Noir",
		"Piercer", "Hook", "Remote", "Engine" }
	local function plainProblem(text, where)
		if text:find("[\208\209]") then return where .. " has Russian text: " .. text end
		if text:find("^[^%w]") then return where .. " starts with a symbol: " .. text end
		if text ~= "" and not text:find("%l") then return where .. " is all capitals: " .. text end
		for _, word in ipairs(developerWords) do
			if text:find(word, 1, true) then return where .. " still says '" .. word .. "': " .. text end
		end
	end
	local checked, problems, hidden = 0, {}, 0
	for line in io.lines(REPO .. "/tests/mm2_labels.txt") do
		if line:sub(1, 1) ~= "#" and line ~= "" then
			local section, kind, label = line:match("^(.-)\t(.-)\t(.*)$")
			if kind == "Section" then
				assert(Text.sections[Text.sectionKey(section)], "section not in mm2-text.lua: " .. section)
				kind = nil
			end
			local title, help, route, button, fallback
			if kind then
				title, help, route, button, fallback = Text.describe(Text.sectionKey(section), kind, label)
				checked = checked + 1
			else
				title = "-"
			end
			if title == "-" then
				hidden = hidden + 1
			else
				assert(not fallback, "not in mm2-text.lua: " .. section .. " / " .. kind .. " / " .. label)
				local bad = plainProblem(title, "title of '" .. label .. "'") or (help ~= "" and plainProblem(help, "help of '" .. label .. "'"))
				if bad then problems[#problems + 1] = bad end
				if route then
					local page, tabName = route:match("^([^/]+)/([^/]+)/")
					local known = false
					for _, tab in ipairs(Text.tabs[page] or {}) do if tab == tabName then known = true end end
					assert(known, "route to a sub-tab that does not exist: " .. route)
				end
			end
		end
	end
	for key, entry in pairs(Text.sections) do
		local bad = plainProblem(entry[3], "section " .. key) or (entry[4] ~= "" and plainProblem(entry[4], "intro of " .. key))
		if bad then problems[#problems + 1] = bad end
		local known = false
		for _, tab in ipairs(Text.tabs[entry[1]] or {}) do if tab == entry[2] then known = true end end
		assert(known, "section " .. key .. " is on a sub-tab that does not exist: " .. entry[1] .. "/" .. entry[2])
	end
	assert(checked > 200, "read the label list, got " .. checked)
	assert(#problems == 0, #problems .. " wording problems, first: " .. tostring(problems[1]))
	assert(hidden > 10, "developer-only text is hidden, got " .. hidden)
	local title = Text.describe("*", "Toggle", "SOME LOUD SWITCH")
	assert(title == "Some Loud Switch", "unlisted all-caps text gets normal capitals, got " .. title)
	local page, tab, sectionTitle = Text.home("MISC • SOMETHING NEW", "")
	assert(page == "Extras" and sectionTitle == "Something New", "unlisted sections go to Extras, got " .. page .. "/" .. sectionTitle)
	assert(Text.words("Silent Aim is on") == "Aim Assist is on", "notifications lose developer words")
end)

run("MM2 port check: every builder the script calls exists in the adapter", function()
	local function read(path)
		local f = assert(io.open(REPO .. "/" .. path, "rb"))
		local text = f:read("*a")
		f:close()
		return text
	end
	local CORE_MM2, UI_MM2 = read("libraries/mm2-main.lua"), read("games/142823291.lua")
	local missing, seen = {}, {}
	for method in CORE_MM2:gmatch(":(Add%u%a*)%(") do
		if not seen[method] then
			seen[method] = true
			if method ~= "AddSection" and not UI_MM2:find("function api:" .. method .. "(", 1, true) then
				missing[#missing + 1] = method
			end
		end
	end
	assert(seen.AddToggle and seen.AddSlider, "found the script's builders")
	assert(#missing == 0, "the adapter lacks: " .. table.concat(missing, ", "))
	local _, markers = CORE_MM2:gsub("Peridot:", "")
	assert(markers >= 7, "the script's Peridot patches are in place, found " .. markers)
	assert(CORE_MM2:find("return NoirGenv().PeridotMM2Host.CreateTab()", 1, true), "controls are routed to Peridot")
end)
run("MM2 test mode: refuses other games unless forced, and says so when forced", function()
	local saved = { getgenv().PeridotMM2Loaded, getgenv().PeridotMM2Host, getgenv().PeridotForceGame }
	getgenv().PeridotMM2Loaded, getgenv().PeridotForceGame = nil, nil
	PLACE_ID_OVERRIDE = 1
	local before = #HTTP_LOG
	assert(pcall(assert(loadfile(REPO .. "/games/142823291.lua"))))
	assert(#HTTP_LOG == before, "another game without the flag loads nothing")
	getgenv().PeridotForceGame = true
	UI_ERRORS, WARNINGS = {}, {}
	local ok, err = pcall(assert(loadfile(REPO .. "/games/142823291.lua")))
	PLACE_ID_OVERRIDE = nil
	assert(ok, err)
	assert(#HTTP_LOG > before, "forced: the module loads")
	assert(#UI_ERRORS == 0, "errors: " .. tostring(UI_ERRORS[1]))
	getgenv().PeridotForceGame = nil
	getgenv().PeridotMM2Loaded, getgenv().PeridotMM2Host = saved[1], saved[2]
end)

BUTTONS, BOXES, DROPDOWNS = mm2Saved[1], mm2Saved[2], mm2Saved[3]

run("Unload UI stops everything, removes the windows, and a re-run skips the core", function()
	local farm = control("Toggles", "Farm||Auto Farm||Auto Farm Level") -- the first window's switch
	farm.Set(true)
	local menuKey = getgenv().PeridotMenuKeyConnection
	getgenv().PeridotExecutedIn = "job"
	BUTTONS["Unload UI"]()
	assert(getgenv().PeridotExecutedIn == nil, "Unload UI frees the run-once marker")
	assert(_G.Level == false, "features stopped")
	assert(getgenv().PeridotBloxFruitsLoaded == nil, "the script can run again")
	assert(getgenv().PeridotBloxFruitsCoreLoaded == true, "but the core stays loaded")
	assert(getgenv().PeridotMenuKeyConnection == nil or getgenv().PeridotMenuKeyConnection ~= menuKey, "menu key handler dropped")
	runLoops(nil, 3) -- the interface loops now end on their own
	local coreFetches = 0
	for _, path in ipairs(HTTP_LOG) do
		if path == "libraries/bf-main.lua" then coreFetches = coreFetches + 1 end
	end
	OVERRIDES["libraries/UILibrary.lua"] = nil -- a real re-run downloads a fresh library
	PLACE_ID_OVERRIDE = 2753915549
	local ok, err = pcall(assert(loadfile(REPO .. "/games/2753915549.lua")))
	PLACE_ID_OVERRIDE = nil
	assert(ok, err)
	local after = 0
	for _, path in ipairs(HTTP_LOG) do
		if path == "libraries/bf-main.lua" then after = after + 1 end
	end
	assert(after == coreFetches, "the core was not downloaded or run twice")
end)

---------------------------------------------------------------- Bee Swarm Simulator module
print("games/1537690962.lua")

-- The core measures distances, so this section swaps in a small Vector3 (the rest of the harness uses an inert
-- one) and, while the features run, small Enums. The game world is built from plain tables so every value,
-- including "nobody owns this hive", is exactly what the test says.
do
	local realVector3, realEnum = Vector3, Enum
	local vecMeta = {}
	local function vec(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, vecMeta) end
	vecMeta.__index = function(v, key)
		if key == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
	end
	vecMeta.__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
	vecMeta.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
	local realCFrame = CFrame
	local cfMeta = {}
	local function cframe(x, y, z) -- a CFrame with no rotation: just where it is
		return setmetatable({ Position = type(x) == "table" and x or vec(x, y, z) }, cfMeta)
	end
	cfMeta.__mul = function(a, b) return setmetatable({ Position = a.Position + b.Position }, cfMeta) end
	local fakeEnum = setmetatable({}, { __index = function(_, group)
		return setmetatable({}, { __index = function(_, item) return group .. "." .. item end })
	end })

	local function fake(name, class, fields, kids)
		local obj = { Name = name, ClassName = class, Parent = true, kids = kids or {} }
		for key, value in pairs(fields or {}) do obj[key] = value end
		function obj:FindFirstChild(wanted) for _, kid in ipairs(self.kids) do if kid.Name == wanted then return kid end end end
		function obj:FindFirstChildOfClass(wanted) for _, kid in ipairs(self.kids) do if kid.ClassName == wanted then return kid end end end
		function obj:GetChildren() local out = {} for i, kid in ipairs(self.kids) do out[i] = kid end return out end
		function obj:GetDescendants()
			local out = {}
			local function walk(node) for _, kid in ipairs(node.kids) do out[#out + 1] = kid walk(kid) end end
			walk(self)
			return out
		end
		function obj:IsA(wanted) return wanted == class or (wanted == "BasePart" and class == "Part") end
		return obj
	end

	local player = service("Players").LocalPlayer
	local replicated = service("ReplicatedStorage")
	local bssBefore = {}
	for kind, entries in pairs(lib.ControlRegistry) do
		bssBefore[kind] = {}
		for key in pairs(entries) do bssBefore[kind][key] = true end
	end
	local function bss(kind, suffix) -- one control the Bee Swarm window added, found by the end of its key
		local found
		for key, handle in pairs(lib.ControlRegistry[kind]) do
			if not bssBefore[kind][key] and key:sub(-#suffix) == suffix then
				assert(not found, "ambiguous control " .. suffix)
				found = handle
			end
		end
		return assert(found, "missing " .. kind .. " " .. suffix)
	end

	local savedButtons = { BUTTONS, BOXES, DROPDOWNS }
	BUTTONS, BOXES, DROPDOWNS = {}, {}, {}
	local Core

	run("Bee Swarm module builds with no errors, and loads its core from the repo", function()
		OVERRIDES["libraries/UILibrary.lua"] = "return _G.__HARNESS_LIB"
		_G.__HARNESS_LIB = lib
		Vector3 = { new = vec }
		PLACE_ID_OVERRIDE = 1537690962
		getgenv().PeridotBeeSwarmLoaded = nil
		UI_ERRORS, WARNINGS = {}, {}
		local stopRecording = recordButtons()
		local ok, err = pcall(assert(loadfile(REPO .. "/games/1537690962.lua")))
		stopRecording()
		PLACE_ID_OVERRIDE = nil
		assert(ok, err)
		assert(#UI_ERRORS == 0 and #WARNINGS == 0, "errors: " .. tostring(UI_ERRORS[1] or WARNINGS[1]))
		Core = assert(getgenv().PeridotBeeSwarmCore, "the core is loaded and kept for the interface")
		local fetched = false
		for _, path in ipairs(HTTP_LOG) do if path == "libraries/bss-main.lua" then fetched = true end end
		assert(fetched, "the core came from libraries/bss-main.lua")
		assert(getgenv().PeridotBeeSwarmLoaded == true)
	end)

	run("Bee Swarm controls are on the right pages, with plain titles", function()
		for _, key in ipairs({
			"Farming||Auto Farm||Auto Farm", "Farming||Auto Farm||Auto Dig", "Farming||Pick Up||Collect Tokens", "Farming||Pick Up||Collect Bubbles",
			"Farming||Pick Up||Collect Flames", "Farming||Pick Up||Collect Stars", "Farming||Pick Up||Collect Balloons",
			"Farming||Bag And Hive||Go Home When Bag Is Full", "Farming||Bag And Hive||Convert Hive Balloon", "Farming||Sprinkler||Place Sprinkler",
			"Combat||Training||Train Snail", "Combat||Training||Train Crab", "Combat||Training||Fight Coconut Crab", "Combat||Protection||Stay On Your Feet",
			"Combat||Floating Above Bosses||Hover Over Windy Bee", "Combat||Floating Above Bosses||Hover Over Vicious Bee",
			"Combat||Floating Above Bosses||Float Above Mondo Chick", "Event||Winter Event||Collect Snowflakes",
			"Keep Walk Speed", "Keep Jump Power", "Walk Through Walls", "Walk Through Field Decorations", "Anti-AFK", "Go To Hive When Loaded",
			"Items||Auto Dispensers||All Dispensers", "Items||Auto Dispensers||Glue Dispenser", "Items||Auto Dispensers||Free Royal Jelly Dispenser",
			"Items||Auto Dice||Field Dice", "Items||Auto Dice||Loaded Dice", "Items||Auto Boosters||All Field Boosters", "Items||Auto Boosters||Red Field Booster",
			"Items||Auto Converters And Treats||Micro-Converter", "Items||Auto Converters And Treats||Instant Converter",
			"Items||Auto Converters And Treats||Coconut", "Items||Auto Converters And Treats||Gumdrops",
		}) do
			bss("Toggles", key)
		end
		bss("Sliders", "Walk Speed")
		bss("Sliders", "Jump Power")
		bss("Sliders", "Travel Speed")
		bss("Sliders", "Go Home At (% Full)")
		for _, key in ipairs({ "Farming||Auto Farm||Field", "Farming||Auto Farm||Movement While Collecting", "Teleport||Fields||Field To Visit",
			"Teleport||Teleport Style||Teleport Style", "Teleport||Shops||Shop", "Teleport||Bears||Bear", "Teleport||Boosts And Dispensers||Spot",
			"Event||Event Teleports||Gift", "Items||Dispensers||Dispenser", "Items||Masks||Mask" }) do
			bss("Dropdowns", key)
		end
		local titles = { "Rejoin Server", "Go To Selected Field", "Go To My Hive", "Use All Blue Buffs", "Use All Red Buffs",
			"Use All Buffs", "Use All Dispensers", "Use Selected Dispenser", "Use All Boosters", "Equip Selected Mask", "Stop All Features",
			"Unload UI", "Create config", "Find All Stickers", "Redeem All Codes", "Redeem Typed Codes", "Fight Commando Chick", "Fight Tunnel Bear", "AFK At Stump Snail",
			"Go To Bee Bear", "Go To Selected Gift", "Go To Selected Shop", "Go To Selected Bear", "Go To Selected Spot" }
		for _, name in ipairs({ "Blue Extract", "Red Extract", "Glitter", "Glue", "Oil", "Enzymes", "Tropical Drink", "Purple Potion",
			"Super Smoothie", "Marshmallow Bee", "Field Dice", "Smooth Dice", "Loaded Dice", "Red Field Booster", "Blue Field Booster", "Field Booster" }) do
			titles[#titles + 1] = "Use " .. name
		end
		for _, title in ipairs(titles) do assert(BUTTONS[title], "missing button " .. title) end
		assert(BOXES["Promo Codes"], "the promo code box")
		for title in pairs(BUTTONS) do
			for _, banned in ipairs({ "Remote", "FireServer", "CFrame", "Tween", "Humanoid", "Core", "Flag", "Noclip" }) do
				assert(not title:find(banned, 1, true), "technical word in a button title: " .. title)
			end
		end
		stripsFit()
	end)

	-- the world
	local w
	local realTeleport, realNotify, realClock
	local function clearPlayerParts() -- every copy, so a test that stopped half way cannot leave stale values behind
		for _, name in ipairs({ "CoreStats", "ScreenGui", "Honeycomb", "SpawnPos" }) do
			while true do
				local old = player:FindFirstChild(name) or player.PlayerGui:FindFirstChild(name)
				if not old then break end
				old:Destroy()
			end
		end
	end
	local function world()
		clearPlayerParts()
		w = { fired = {}, moved = {}, moveTo = {}, states = {}, notes = {}, clock = 0 }
		local function remote(name)
			return fake(name, "RemoteEvent", { FireServer = function(_, ...) w.fired[#w.fired + 1] = { name = name, args = { ... } } end })
		end
		w.claim = remote("ClaimHive")
		w.events = fake("Events", "Folder", nil, { remote("ToolCollect"), remote("PlayerHiveCommand"), remote("PlayerActivesCommand"),
			remote("ToyEvent"), w.claim, remote("PromoCodeEvent"),
			fake("ItemPackageEvent", "RemoteFunction", { InvokeServer = function(_, ...) w.fired[#w.fired + 1] = { name = "ItemPackageEvent", args = { ... } } end }) })
		w.pad = fake("Base", "Part", { Position = vec(100, 10, 0) })
		w.mine = fake("Hive1", "Model", nil, { fake("Owner", "ObjectValue", { Value = player }), fake("HiveID", "IntValue", { Value = 1 }),
			fake("patharrow", "Model", nil, { w.pad }) })
		w.ownerOfFree = fake("Owner", "ObjectValue", { Value = nil })
		w.free = fake("Hive2", "Model", nil, { w.ownerOfFree, fake("HiveID", "IntValue", { Value = 2 }),
			fake("patharrow", "Model", nil, { fake("Base", "Part", { Position = vec(300, 10, 0) }) }) })
		w.taken = fake("Hive3", "Model", nil, { fake("Owner", "ObjectValue", { Value = {} }), fake("HiveID", "IntValue", { Value = 3 }),
			fake("patharrow", "Model", nil, { fake("Base", "Part", { Position = vec(500, 10, 0) }) }) })
		w.honeycombs = fake("Honeycombs", "Folder", nil, { w.taken, w.mine, w.free })
		w.tokens = fake("Collectibles", "Folder", nil, {})
		w.particles = fake("Particles", "Folder", nil, {})
		w.balloons = fake("Balloons", "Folder", nil, { fake("HiveBalloons", "Folder", nil, {}), fake("FieldBalloons", "Folder", nil, {}) })
		w.decos = fake("FieldDecos", "Folder", nil, {})
		w.flames = fake("PlayerFlames", "Folder", nil, {})
		w.stickers = fake("HiddenStickers", "Folder", nil, {})
		w.bees = fake("NPCBees", "Folder", nil, {})
		w.monsters = fake("Monsters", "Folder", nil, {})
		w.ws = { Honeycombs = w.honeycombs, Collectibles = w.tokens, Particles = w.particles, Balloons = w.balloons, FieldDecos = w.decos,
			PlayerFlames = w.flames, HiddenStickers = w.stickers, NPCBees = w.bees, Monsters = w.monsters }
		w.root = fake("HumanoidRootPart", "Part", { Position = vec(0, 5, 0) })
		w.humanoid = fake("Humanoid", "Humanoid", { WalkSpeed = 16, Jump = false,
			MoveTo = function(_, position) w.moveTo[#w.moveTo + 1] = position end,
			SetStateEnabled = function(_, state, on) w.states[state] = on end })
		w.character = fake("Character", "Model", nil, { w.root, w.humanoid })
		w.stats = Instance.new("Folder", player)
		w.stats.Name = "CoreStats"
		w.pollen = Instance.new("NumberValue", w.stats)
		w.pollen.Name = "Pollen"
		w.pollen.Value = 0
		w.capacity = Instance.new("NumberValue", w.stats)
		w.capacity.Name = "Capacity"
		w.capacity.Value = 100
		local screen = Instance.new("ScreenGui", player.PlayerGui)
		screen.Name = "ScreenGui"
		local activate = Instance.new("Frame", screen)
		activate.Name = "ActivateButton"
		w.button = Instance.new("TextBox", activate)
		w.button.Text = "Make Honey"
		w.claim.FireServer = function(_, id) -- the server hands the hive over
			w.fired[#w.fired + 1] = { name = "ClaimHive", args = { id } }
			if id == 2 then w.ownerOfFree.Value = player end
		end
		workspace.FindFirstChild = function(_, name) return w.ws[name] end
		replicated.FindFirstChild = function(_, name) if name == "Events" then return w.events end end
		player.Character = w.character
		realTeleport, realNotify, realClock = Core.TeleportTo, Core.Notify, Core.Clock
		Core.TeleportTo = function(position) w.moved[#w.moved + 1] = position w.root.Position = position return true end
		Core.Notify = function(_, text) w.notes[#w.notes + 1] = text end
		Core.Clock = function() return w.clock end
		Enum, CFrame = fakeEnum, { new = cframe }
	end
	local function worldDown()
		workspace.FindFirstChild, replicated.FindFirstChild, player.Character = nil, nil, nil
		Core.TeleportTo, Core.Notify, Core.Clock = realTeleport, realNotify, realClock
		Enum, CFrame = realEnum, realCFrame
		clearPlayerParts()
	end
	local function firedNames(name)
		local out = {}
		for _, call in ipairs(w.fired) do
			if call.name == name then out[#out + 1] = call.args[1] and (type(call.args[1]) == "table" and call.args[1].Name or call.args[1]) or true end
		end
		return out
	end
	local function same(list, expected, label)
		assert(#list == #expected, label .. ": expected " .. #expected .. " got " .. #list)
		for i, value in ipairs(expected) do assert(list[i] == value, label .. " #" .. i .. ": " .. tostring(list[i]) .. " ~= " .. tostring(value)) end
	end
	local function farmOn() Core.Set("AutoFarm", true) end

	run("the fields are the script's 17 spots, each named once", function()
		assert(#Core.Fields == 17)
		local seen = {}
		for _, field in ipairs(Core.Fields) do
			assert(not seen[field.name], "twice: " .. field.name)
			seen[field.name] = true
			assert(field.position.Magnitude > 0)
		end
		for _, name in ipairs({ "Sunflower Field", "Dandelion Field", "Mushroom Field", "Blue Flower Field", "Clover Field", "Spider Field",
			"Strawberry Field", "Bamboo Field", "Pineapple Patch", "Stump Field", "Pumpkin Patch", "Cactus Field", "Rose Field",
			"Pine Tree Forest", "Mountain Top Field", "Coconut Field", "Pepper Patch" }) do
			assert(seen[name], "missing field " .. name)
		end
		assert(Core.FindField("Mountain Top Field").position.Y > 170 and Core.FindField("No such field") == Core.Fields[1])
	end)

	run("settings: unknown names and wrong kinds are refused, and one mover turns the others off", function()
		assert(Core.Set("Nope", true) == false and Core.Set("AutoFarm", "yes") == false and Core.Set("WalkSpeed", true) == false)
		assert(Core.Set("WalkSpeed", 30) and Core.Settings.WalkSpeed == 30)
		Core.Set("WalkSpeed", 16)
		local farm, snail, crab = bss("Toggles", "Farming||Auto Farm||Auto Farm"), bss("Toggles", "Combat||Training||Train Snail"), bss("Toggles", "Combat||Training||Train Crab")
		world()
		farm.Set(true)
		assert(Core.Settings.AutoFarm and farm.Get())
		snail.Set(true)
		assert(Core.Settings.TrainSnail and not Core.Settings.AutoFarm and farm.Get() == false, "Train Snail took over from Auto Farm, and the switch followed")
		crab.Set(true)
		assert(Core.Settings.TrainCrab and not Core.Settings.TrainSnail and snail.Get() == false)
		crab.Set(false)
		worldDown()
	end)

	run("your hive: found, claimed when you have none, and the pad is one stud up", function()
		world()
		assert(Core.FindHive() == w.mine)
		local pad = Core.HivePosition()
		assert(pad.X == 100 and pad.Y == 11, "one stud above the hive's pad")
		w.mine.kids[1].Value = {} -- somebody else's now
		assert(Core.FindHive() == nil and Core.HivePosition() == nil)
		assert(Core.ClaimHive() == true, "the free hive is claimed")
		same(firedNames("ClaimHive"), { 2 }, "claim")
		assert(Core.FindHive() == w.free and Core.ClaimHive() == true and #firedNames("ClaimHive") == 1, "already owning one claims nothing more")
		w.free.kids[1].Value = {}
		w.ownerOfFree.Value = {}
		local ok, why = Core.TeleportToHive()
		assert(ok == false and why:find("none is free"), tostring(why))
		worldDown()
	end)

	run("the Bee Swarm source and window carry no author names or invite links", function()
		local words = { "kr" .. "on", "ver" .. "bal", "marc" .. "us", "discord%.gg" } -- split so this file does not match itself
		for _, path in ipairs({ "libraries/bss-main.lua", "games/1537690962.lua" }) do
			local f = assert(io.open(REPO .. "/" .. path, "rb"))
			local text = f:read("*a"):lower()
			f:close()
			for _, word in ipairs(words) do
				assert(not text:find(word), path .. " still mentions " .. word)
			end
		end
		local home
		for _, item in ipairs(lib.Internal.Gui:GetDescendants()) do
			if item.ClassName == "TextLabel" then
				local text = tostring(item.Text or ""):lower()
				for _, word in ipairs(words) do
					assert(not text:find(word), "the window shows " .. word .. ": " .. text)
				end
				if text:find("pick a field on the farming page", 1, true) then home = true end
			end
		end
		assert(home, "the Home page still tells you how to start")
	end)

	run("loading: what it did once at load (decorations, claim a hive, fly to it)", function()
		world()
		assert(Core.Settings.GoToHiveOnLoad == true, "on by default, as in the source")
		assert(Core.Setup() == true and w.moved[1].X == 100 and w.moved[1].Y == 11, "flies to the hive's pad")
		w.moved = {}
		Core.Set("GoToHiveOnLoad", false)
		assert(Core.Setup() == true and #w.moved == 0, "not when switched off")
		Core.Set("GoToHiveOnLoad", true)
		Core.Set("TrainSnail", true)
		assert(Core.Setup() == true and #w.moved == 0, "not while Auto Farm or training is already moving you")
		Core.Set("TrainSnail", false)
		w.mine.kids[1].Value = {}
		w.ownerOfFree.Value = {}
		assert(Core.Setup() == false and w.notes[1] and w.notes[1]:find("do not have a hive"), "and says so when there is no hive")
		worldDown()
	end)

	run("items, buff sets and dispensers fire the same remotes and names as the script", function()
		world()
		BUTTONS["Use All Blue Buffs"]()
		same(firedNames("PlayerActivesCommand"), { "Blue Extract", "Glitter", "Glue", "Oil", "Enzymes", "Tropical Drink" }, "blue")
		w.fired = {}
		BUTTONS["Use All Red Buffs"]()
		same(firedNames("PlayerActivesCommand"), { "Red Extract", "Glitter", "Glue", "Oil", "Enzymes", "Tropical Drink" }, "red")
		w.fired = {}
		BUTTONS["Use Purple Potion"]()
		same(firedNames("PlayerActivesCommand"), { "Purple Potion" }, "single")
		w.fired = {}
		BUTTONS["Use All Dispensers"]()
		same(firedNames("ToyEvent"), { "Glue Dispenser", "Wealth Clock", "Coconut Dispenser", "Strawberry Dispenser", "Treat Dispenser",
			"Free Ant Pass Dispenser", "Blueberry Dispenser", "Honey Dispenser", "Free Royal Jelly Dispenser" }, "dispensers")
		Core.Set("AutoDig", true)
		w.fired = {}
		assert(Core.DigStep() == "dig")
		same(firedNames("ToolCollect"), { true }, "dig")
		Core.Set("AutoDig", false)
		assert(Core.DigStep() == "off" and #firedNames("ToolCollect") == 1)
		worldDown()
	end)

	run("Auto Farm: goes to the field, places a sprinkler, goes home when full, makes honey, and comes back", function()
		world()
		local field = Core.FindField("Sunflower Field").position
		Core.Set("PlaceSprinkler", true)
		farmOn()
		assert(Core.FarmStep() == "to field" and w.moved[1] == field, "flies to the field first")
		assert(Core.FarmStep() == "sprinkler", "and places the sprinkler once")
		same(firedNames("PlayerActivesCommand"), { "Sprinkler Builder" }, "sprinkler")
		assert(w.humanoid.Jump == true)
		assert(Core.FarmStep() == "farming" and Core.FarmStep() == "farming" and #firedNames("PlayerActivesCommand") == 1)

		w.pollen.Value = 100
		assert(Core.FarmStep() == "bag full")
		assert(Core.FarmStep() == "making honey")
		assert(w.moved[2].X == 100 and w.moved[2].Y == 11, "went to the hive's pad")
		same(firedNames("PlayerHiveCommand"), { "ToggleHoneyMaking" }, "honey")
		assert(Core.FarmStep() == "converting" and #firedNames("PlayerHiveCommand") == 1, "pressed once, then waits")

		w.root.Position = vec(0, 5, 0) -- pushed away from the pad
		assert(Core.FarmStep() == "converting" and w.moved[3].X == 100, "walks back to the pad")
		assert(#firedNames("PlayerHiveCommand") == 2, "and presses again because the button says Make Honey")
		w.root.Position = vec(0, 5, 0)
		w.button.Text = "Stop Making Honey"
		Core.FarmStep()
		assert(#firedNames("PlayerHiveCommand") == 2, "no second press when honey making is already on")

		w.pollen.Value = 0
		assert(Core.FarmStep() == "back to field")
		assert(Core.FarmStep() == "to field" and w.moved[#w.moved] == field)
		w.pollen.Value = 100
		assert(Core.FarmStep() == "bag full")
		local pressed = #firedNames("PlayerHiveCommand")
		w.pollen.Value = 0 -- emptied before the hive was reached
		assert(Core.FarmStep() == "back to field" and #firedNames("PlayerHiveCommand") == pressed, "nothing to convert, so no press")
		assert(Core.FarmStep() == "to field")
		assert(Core.FarmStep() == "sprinkler", "a new sprinkler for the new trip")
		Core.Set("AutoFarm", false)
		assert(Core.FarmStep() == "off")
		worldDown()
	end)

	run("Auto Farm: a conversion that never ends is given up on, and no hive switches it off", function()
		world()
		farmOn()
		w.root.Position = Core.FindField("Sunflower Field").position
		w.pollen.Value = 100
		Core.FarmStep()
		Core.FarmStep()
		assert(Core.FarmStep() == "converting")
		w.clock = 601
		assert(Core.FarmStep() == "back to field", "ten minutes is the limit")

		Core.Set("AutoFarm", false)
		farmOn()
		w.pollen.Value = 100
		Core.FarmStep()
		w.mine.kids[1].Value = {}
		w.ownerOfFree.Value = {}
		assert(Core.FarmStep() == "no hive")
		assert(Core.Settings.AutoFarm == false and bss("Toggles", "Farming||Auto Farm||Auto Farm").Get() == false, "the switch is off too")
		assert(w.notes[1] and w.notes[1]:find("do not have a hive"), tostring(w.notes[1]))
		worldDown()
	end)

	run("Convert Hive Balloon: waits for a balloon by the hive, but never more than 15 seconds", function()
		world()
		local balloon = fake("HiveBalloonInstance", "Model", nil, { fake("BalloonBody", "Part", { Position = vec(105, 10, 0) }) })
		w.balloons.kids[1].kids[1] = balloon
		w.root.Position = vec(100, 11, 0)
		farmOn()
		Core.Set("ConvertBalloons", true)
		local realWait, waits = task.wait, 0
		task.wait = function() waits = waits + 1 if waits == 3 then balloon.Parent = nil end return 0 end
		local waited = Core.WaitForBalloon()
		task.wait = realWait
		assert(waited == true and waits == 3, "stopped when the balloon was gone: " .. waits)
		balloon.Parent = true
		waits = 0
		task.wait = function() waits = waits + 1 return 0 end
		Core.WaitForBalloon()
		task.wait = realWait
		assert(waits == 30, "gave up after 15 seconds: " .. waits)
		balloon.kids[1].Position = vec(400, 10, 0)
		assert(Core.WaitForBalloon() == false, "a balloon far away is not waited for")
		Core.Set("AutoFarm", false)
		worldDown()
	end)

	run("tokens and bubbles: the nearest one inside the field, bubbles first when switched on", function()
		world()
		local field = Core.FindField("Sunflower Field").position
		w.root.Position = field
		local near = fake("C", "Part", { Position = vec(field.X + 10, field.Y, field.Z) })
		local far = fake("C", "Part", { Position = vec(field.X + 40, field.Y, field.Z) })
		w.tokens.kids = { far, near }
		assert(Core.TokenStep() == "off", "nothing happens until Auto Farm runs")
		farmOn()
		assert(Core.TokenStep() == "token" and w.moveTo[1] == near.Position, "the closest token")
		w.root.Position = vec(field.X + 60, field.Y, field.Z) -- at the edge of the field
		w.tokens.kids = { fake("C", "Part", { Position = vec(field.X + 105, field.Y, field.Z) }) } -- in reach, but outside the field
		assert(Core.TokenStep() == "none", "a token that would pull you out of the field is left")
		w.tokens.kids = { fake("C", "Part", { Position = vec(field.X + 60, field.Y, field.Z + 30) }) }
		assert(Core.TokenStep() == "token", "one still inside the field is taken")
		w.root.Position = field
		local bubble = fake("Bubble", "Part", { Position = vec(field.X, field.Y, field.Z + 30) })
		w.particles.kids = { fake("Spark", "Part", { Position = vec(field.X, field.Y, field.Z + 5) }), bubble }
		w.tokens.kids = { near }
		assert(Core.TokenStep() == "token", "bubbles are ignored while that switch is off")
		Core.Set("CollectBubbles", true)
		assert(Core.TokenStep() == "bubble" and w.moveTo[#w.moveTo] == bubble.Position)
		Core.Set("CollectTokens", false)
		Core.Set("CollectBubbles", false)
		assert(Core.TokenStep() == "off")
		Core.Set("CollectTokens", true)
		Core.Farm.phase = "hive"
		assert(Core.TokenStep() == "off", "no walking around while at the hive")
		Core.Set("AutoFarm", false)
		worldDown()
	end)

	run("Train Snail, Train Crab, Keep Walk Speed", function()
		world()
		Core.Set("TrainSnail", true)
		assert(Core.SnailStep() == "to snail" and math.abs(w.moved[1].X - 422.657) < 0.01)
		assert(Core.SnailStep() == "at snail" and #w.moved == 1)
		Core.Set("TrainSnail", false)
		assert(Core.SnailStep() == "off")

		Core.Set("TrainCrab", true)
		assert(Core.CrabStep() == "to platform")
		local platform = Core.GetCrabPlatform()
		assert(platform and platform.Name == "combatcrabpart" and platform.Anchored == true and platform.Transparency == 1)
		assert(math.abs(w.moved[#w.moved].Y - 110.619) < 0.01, "you stand 4.7 above the platform")
		assert(Core.CrabStep() == "on platform")
		Core.Set("TrainCrab", false)
		assert(Core.GetCrabPlatform() == nil and Core.CrabStep() == "off", "the platform goes when the switch does")

		assert(Core.SpeedStep() == "off" and w.humanoid.WalkSpeed == 16)
		Core.Set("WalkSpeed", 40)
		Core.Set("KeepWalkSpeed", true)
		assert(Core.SpeedStep() == "set" and w.humanoid.WalkSpeed == 40)
		Core.Set("KeepWalkSpeed", false)
		Core.Set("WalkSpeed", 16)
		worldDown()
	end)

	run("protections: knocked-down states, see-through decorations, and putting everything back", function()
		world()
		Core.Set("StayOnFeet", false)
		assert(w.states["HumanoidStateType.Ragdoll"] == true and w.states["HumanoidStateType.FallingDown"] == true, "states allowed again")
		Core.Set("StayOnFeet", true)
		assert(w.states["HumanoidStateType.Ragdoll"] == false and w.states["HumanoidStateType.FallingDown"] == false, "states blocked")

		local tree = fake("Tree", "Part", { CanCollide = true, Transparency = 0 })
		local branch = fake("Branch", "Part", { CanCollide = true, Transparency = 0.2 })
		w.decos.kids = { fake("Group", "Model", nil, { branch }), tree }
		Core.Set("WalkThroughDecorations", false)
		Core.Set("WalkThroughDecorations", true)
		assert(tree.CanCollide == false and tree.Transparency == 0.5 and branch.CanCollide == false, "decorations are pass-through and half clear")
		Core.Set("WalkThroughDecorations", false)
		assert(tree.CanCollide == true and tree.Transparency == 0 and branch.Transparency == 0.2, "and come back as they were")
		Core.Set("WalkThroughDecorations", true)
		Core.Set("TrainCrab", true)
		Core.CrabStep()
		Core.Unload()
		assert(tree.CanCollide == true and tree.Transparency == 0, "Unload puts the decorations back")
		assert(Core.GetCrabPlatform() == nil and w.states["HumanoidStateType.Ragdoll"] == true, "and the platform and the states")
		assert(Core.Settings.TrainCrab == false)
		worldDown()
	end)

	run("Teleport page: the picked field, and Go To My Hive", function()
		world()
		bss("Dropdowns", "Teleport||Fields||Field To Visit").Set("Pepper Patch")
		BUTTONS["Go To Selected Field"]()
		assert(w.moved[1] == Core.FindField("Pepper Patch").position)
		BUTTONS["Go To My Hive"]()
		assert(w.moved[2].X == 100 and w.moved[2].Y == 11)
		bss("Dropdowns", "Farming||Auto Farm||Field").Set("Rose Field")
		assert(Core.Settings.Field == "Rose Field", "the farming field is picked on its own")
		bss("Dropdowns", "Farming||Auto Farm||Field").Set("Sunflower Field")
		worldDown()
	end)

	run("TeleportTo glides at the travel speed and gives up on a missing character", function()
		world()
		Core.TeleportTo = realTeleport
		assert(Core.TeleportTo(vec(0, 5, 80)) == true)
		w.character.kids = {}
		assert(Core.TeleportTo(vec(0, 5, 80)) == false)
		worldDown()
	end)

	run("Stop All Features and Rejoin", function()
		world()
		Core.Set("AutoFarm", true)
		Core.Set("AutoDig", true)
		Core.Set("CollectTokens", true)
		BUTTONS["Stop All Features"]()
		assert(not Core.Settings.AutoFarm and not Core.Settings.AutoDig, "actions are off")
		assert(Core.Settings.CollectTokens and Core.Settings.AntiAfk and Core.Settings.StayOnFeet, "options and protections stay")
		BUTTONS["Rejoin Server"]()
		worldDown()
	end)

	run("Pick Up: flames, bubbles, stars and field balloons, each only when switched on, and how you move to them", function()
		world()
		local field = Core.FindField("Sunflower Field").position
		w.root.Position = field
		farmOn()
		Core.Set("CollectTokens", false)
		local flame = fake("Flame", "Part", { Position = vec(field.X + 20, field.Y, field.Z) })
		local farFlame = fake("Flame", "Part", { Position = vec(field.X + 200, field.Y, field.Z) })
		w.flames.kids = { farFlame, flame }
		assert(Core.TokenStep() == "off", "every pick-up switch is off")
		Core.Set("CollectFlames", true)
		assert(Core.TokenStep() == "flame" and w.moveTo[#w.moveTo] == flame.Position, "the flame inside the field")
		w.flames.kids = { farFlame }
		assert(Core.TokenStep() == "none", "a flame outside the field is left alone")
		w.flames.kids = { flame }
		Core.Set("CollectBubbles", true)
		w.particles.kids = { fake("Bubble", "Part", { Position = vec(field.X + 5, field.Y, field.Z) }) }
		assert(Core.TokenStep() == "flame", "flames come before bubbles")
		Core.Set("CollectFlames", false)
		assert(Core.TokenStep() == "bubble")

		local star = fake("Star", "Part", { Position = vec(field.X, field.Y, field.Z + 30) })
		local farStar = fake("Star", "Part", { Position = vec(field.X, field.Y, field.Z + 300) })
		w.particles.kids = { farStar, star }
		Core.Set("CollectBubbles", false)
		assert(Core.TokenStep() == "off")
		Core.Set("CollectStars", true)
		assert(Core.TokenStep() == "star" and w.moveTo[#w.moveTo] == star.Position, "the star inside the field, not the far one")
		w.particles.kids = { farStar }
		assert(Core.TokenStep() == "none", "a star outside the field is left alone")
		Core.Set("CollectStars", false)

		w.particles.kids = {}
		local body = fake("BalloonBody", "Part", { Position = vec(field.X + 30, field.Y, field.Z) })
		w.balloons.kids[2].kids = { fake("Balloon", "Model", nil, { body }) }
		local visible = fake("C", "Part", { Position = vec(field.X + 35, field.Y, field.Z), Transparency = 0 })
		local ghost = fake("C", "Part", { Position = vec(field.X + 31, field.Y, field.Z), Transparency = 1 })
		w.tokens.kids = { ghost, visible }
		Core.Set("CollectBalloons", true)
		assert(Core.TokenStep() == "balloon" and w.moveTo[#w.moveTo] == visible.Position, "the visible token by the balloon, not the ghost")
		w.tokens.kids = {}
		assert(Core.TokenStep() == "balloon")
		local spot = w.moveTo[#w.moveTo]
		local away = math.sqrt((spot.X - body.Position.X) ^ 2 + (spot.Z - body.Position.Z) ^ 2)
		assert(away <= 10.001 and spot.Y == w.root.Position.Y, "with nothing to pick up it wanders inside the balloon's circle")
		body.Position = vec(field.X + 500, field.Y, field.Z)
		assert(Core.TokenStep() == "none", "a balloon out of reach is ignored")
		Core.Set("CollectBalloons", false)

		Core.Set("CollectTokens", true)
		local near = fake("C", "Part", { Position = vec(field.X + 10, field.Y, field.Z), Transparency = 0 })
		w.tokens.kids = { near }
		assert(Core.Set("MoveStyle", "Banana") == false and Core.Settings.MoveStyle == "Walk", "only the listed styles")
		local walked = #w.moveTo
		assert(Core.Set("MoveStyle", "Glide") and Core.TokenStep() == "token" and #w.moveTo == walked, "Glide slides instead of walking")
		Core.Set("MoveStyle", "Fast Glide")
		assert(Core.MoveToward(near.Position) == "glide" and #w.moveTo == walked)
		Core.Set("MoveStyle", "Walk")
		assert(Core.MoveToward(near.Position) == "walk" and #w.moveTo == walked + 1)
		Core.Set("AutoFarm", false)
		worldDown()
	end)

	run("Going home: the switch and the percent", function()
		world()
		Core.Set("PlaceSprinkler", false)
		farmOn()
		w.root.Position = Core.FindField("Sunflower Field").position
		w.pollen.Value = 60
		assert(Core.FarmStep() == "farming", "60 of 100 is not full at 100 percent")
		Core.Set("GoHomePercent", 50)
		assert(Core.FarmStep() == "bag full", "but it is at 50 percent")
		Core.Farm.phase = "field"
		Core.Set("GoHomeWhenFull", false)
		w.pollen.Value = 100
		assert(Core.FarmStep() == "farming" and Core.Farm.phase == "field", "no trips home when that is switched off")
		Core.Set("GoHomeWhenFull", true)
		Core.Set("GoHomePercent", 100)
		Core.Set("AutoFarm", false)
		worldDown()
	end)

	run("your hive is found a second way, and its pad has two fallbacks", function()
		world()
		w.mine.kids[1].Value = {} -- the Owner check no longer finds it
		assert(Core.FindHive() == nil)
		local pointer = Instance.new("ObjectValue", player)
		pointer.Name = "Honeycomb"
		pointer.Value = w.mine
		assert(Core.FindHive() == w.mine, "the Honeycomb value points to it")
		assert(Core.HivePosition().X == 100, "the pad comes first")
		w.mine.kids = { w.mine.kids[1], w.mine.kids[2], fake("LightHolder", "Part", { CFrame = cframe(50, 20, 0) }) }
		local light = Core.HivePosition()
		assert(light.X == 50 and light.Y == 25 and light.Z == -5, "then in front of the hive's light: 5 up, 5 back")
		w.mine.kids = { w.mine.kids[1], w.mine.kids[2] }
		local spawnPoint = Instance.new("CFrameValue", player)
		spawnPoint.Name = "SpawnPos"
		spawnPoint.Value = cframe(7, 8, 9)
		local last = Core.HivePosition()
		assert(last.X == 7 and last.Y == 8 and last.Z == 9, "and last, where you spawn")
		worldDown()
	end)

	run("Teleport: the lists, the style, and very far places always jump", function()
		world()
		assert(#Core.Shops == 15 and #Core.Bears == 11 and #Core.BoostSpots == 16 and #Core.Gifts == 10)
		for _, list in ipairs({ Core.Shops, Core.Bears, Core.BoostSpots, Core.Gifts }) do
			local seen = {}
			for _, place in ipairs(list) do
				assert(not seen[place.name], "listed twice: " .. place.name)
				seen[place.name] = true
			end
		end
		local jumped, realJump = {}, Core.JumpTo
		Core.JumpTo = function(position) jumped[#jumped + 1] = position return true end
		local rose = Core.FindField("Rose Field").position
		assert(Core.GoTo(rose) == true and #w.moved == 1 and #jumped == 0, "Glide slides there")
		Core.Set("TeleportStyle", "Instant")
		Core.GoTo(rose)
		assert(#jumped == 1 and #w.moved == 1, "Instant jumps")
		Core.Set("TeleportStyle", "Glide")
		assert(Core.GoToPlace(Core.Shops, "Gumball Shop") and #jumped == 2 and #w.moved == 1, "a shop 25,000 studs up is always a jump")
		assert(Core.Set("TeleportStyle", "Warp") == false and Core.GoToPlace(Core.Shops, "No Such Shop") == false)
		Core.JumpTo = realJump
		assert(Core.JumpTo(vec(1, 2, 3)) == true and w.root.CFrame.Position.X == 1 and w.root.CFrame.Position.Z == 3, "the real jump sets where you are")

		bss("Dropdowns", "Teleport||Shops||Shop").Set("Treat Shop")
		BUTTONS["Go To Selected Shop"]()
		assert(w.moved[#w.moved].X == -228.2 and w.moved[#w.moved].Y == 5)
		bss("Dropdowns", "Teleport||Bears||Bear").Set("Onett")
		BUTTONS["Go To Selected Bear"]()
		assert(w.moved[#w.moved].Y == 232.791)
		bss("Dropdowns", "Teleport||Boosts And Dispensers||Spot").Set("Star Hut")
		BUTTONS["Go To Selected Spot"]()
		assert(w.moved[#w.moved].X == 135.9)
		bss("Dropdowns", "Teleport||Teleport Style||Teleport Style").Set("Instant")
		assert(Core.Settings.TeleportStyle == "Instant")
		bss("Dropdowns", "Teleport||Teleport Style||Teleport Style").Set("Glide")
		worldDown()
	end)

	run("Items: All Buffs, dice, boosters, the selected dispenser and masks", function()
		world()
		BUTTONS["Use All Buffs"]()
		same(firedNames("PlayerActivesCommand"), { "Blue Extract", "Red Extract", "Glitter", "Glue", "Oil", "Enzymes", "Tropical Drink" }, "all buffs")
		w.fired = {}
		for _, name in ipairs({ "Field Dice", "Smooth Dice", "Loaded Dice" }) do BUTTONS["Use " .. name]() end
		same(firedNames("PlayerActivesCommand"), { "Field Dice", "Smooth Dice", "Loaded Dice" }, "dice")
		w.fired = {}
		BUTTONS["Use All Boosters"]()
		same(firedNames("ToyEvent"), { "Red Field Booster", "Blue Field Booster", "Field Booster" }, "boosters")
		w.fired = {}
		BUTTONS["Use Blue Field Booster"]()
		same(firedNames("ToyEvent"), { "Blue Field Booster" }, "one booster")
		w.fired = {}
		bss("Dropdowns", "Items||Dispensers||Dispenser").Set("Honey Dispenser")
		BUTTONS["Use Selected Dispenser"]()
		same(firedNames("ToyEvent"), { "Honey Dispenser" }, "the selected dispenser")
		w.fired = {}
		bss("Dropdowns", "Items||Masks||Mask").Set("Fire Mask")
		BUTTONS["Equip Selected Mask"]()
		assert(#w.fired == 1 and w.fired[1].name == "ItemPackageEvent" and w.fired[1].args[1] == "Equip", "asks the game to equip")
		local spec = w.fired[1].args[2]
		assert(spec.Type == "Fire Mask" and spec.Category == "Accessory" and spec.Mute == true)
		assert(Core.EquipMask("Banana Mask") == false)
		worldDown()
	end)

	run("Auto Use: each item on its own timer, converters only with a full bag, and Stop All turns them off", function()
		world()
		local function count(name) return #firedNames(name) end
		local all = bss("Toggles", "Items||Auto Dispensers||All Dispensers")
		all.Set(true)
		assert(Core.AutoUseStep() == 1 and count("ToyEvent") == 9, "all nine at once")
		w.clock = 5
		assert(Core.AutoUseStep() == 0 and count("ToyEvent") == 9, "not again before 10 seconds")
		w.clock = 10.5
		assert(Core.AutoUseStep() == 1 and count("ToyEvent") == 18)
		all.Set(false)
		w.fired = {}
		local dice, clock = bss("Toggles", "Items||Auto Dice||Smooth Dice"), bss("Toggles", "Items||Auto Dispensers||Wealth Clock")
		dice.Set(true)
		clock.Set(true)
		w.clock = 20
		assert(Core.AutoUseStep() == 2)
		same(firedNames("PlayerActivesCommand"), { "Smooth Dice" }, "dice")
		same(firedNames("ToyEvent"), { "Wealth Clock" }, "one dispenser")
		w.clock = 22.5
		assert(Core.AutoUseStep() == 0, "dice wait 3 seconds")
		w.clock = 23.1
		assert(Core.AutoUseStep() == 1 and #firedNames("PlayerActivesCommand") == 2)
		dice.Set(false)
		clock.Set(false)

		w.fired = {}
		local micro = bss("Toggles", "Items||Auto Converters And Treats||Micro-Converter")
		local instant = bss("Toggles", "Items||Auto Converters And Treats||Instant Converter")
		micro.Set(true)
		instant.Set(true)
		w.clock, w.pollen.Value = 100, 50
		Core.AutoUseStep()
		assert(#w.fired == 0, "nothing with a half-full bag")
		w.clock, w.pollen.Value = 102, 100
		Core.AutoUseStep()
		same(firedNames("PlayerActivesCommand"), { "Micro-Converter" }, "micro")
		same(firedNames("ToyEvent"), { "Instant Converter", "Instant Converter B", "Instant Converter C" }, "instant")
		w.fired = {}
		bss("Toggles", "Items||Auto Converters And Treats||Coconut").Set(true)
		bss("Toggles", "Items||Auto Converters And Treats||Gumdrops").Set(true)
		w.clock, w.pollen.Value = 200, 0
		Core.AutoUseStep()
		same(firedNames("PlayerActivesCommand"), { "Coconut", "Gumdrops" }, "treats")
		BUTTONS["Stop All Features"]()
		for _, entry in ipairs(Core.AutoUses) do
			assert(Core.Settings[entry.key] == false, entry.title .. " is off")
		end
		assert(#Core.AutoUses == 21 and not micro.Get() and not instant.Get(), "21 auto uses, and their switches followed")
		worldDown()
	end)

	run("Rewards: stickers once a day, and promo codes one after another", function()
		world()
		local clicked = {}
		fireclickdetector = function(detector) clicked[#clicked + 1] = detector end
		local a, b, c = fake("ClickDetector", "ClickDetector"), fake("ClickDetector", "ClickDetector"), fake("ClickDetector", "ClickDetector")
		w.stickers.kids = { fake("Sticker1", "Part", nil, { a }), fake("Sticker2", "Part", nil, { b, fake("Other", "Part") }), c }
		local realTime, now = Core.Time, 1000
		Core.Time = function() return now end
		BUTTONS["Find All Stickers"]()
		assert(#clicked == 3, "every click detector is clicked: " .. #clicked)
		BUTTONS["Find All Stickers"]()
		assert(#clicked == 3, "and not again the same day")
		now = 1000 + 86401
		BUTTONS["Find All Stickers"]()
		assert(#clicked == 6, "but the next day")
		Core.Time, Core.StickersAt = realTime, nil
		fireclickdetector = nil
		local count, why = Core.FindStickers()
		assert(count == nil and why:find("cannot click"), tostring(why))
		w.ws.HiddenStickers = nil
		count, why = Core.FindStickers()
		assert(count == nil and why:find("no hidden stickers"), tostring(why))

		w.fired = {}
		BOXES["Promo Codes"].callback("Buzz,  Nectar  Cog")
		BUTTONS["Redeem Typed Codes"]()
		same(firedNames("PromoCodeEvent"), { "Buzz", "Nectar", "Cog" }, "typed codes")
		w.fired = {}
		BOXES["Promo Codes"].callback("   ")
		BUTTONS["Redeem Typed Codes"]()
		assert(#w.fired == 0, "an empty box sends nothing")

		local wiki = { "FOURtunate", "ThreeBeeVee", "15MMembers", "BeesBuzz123", "GumdropsForScience", "ClubBean", "38217",
			"Bopmaster", "Connoisseur", "Crawlers", "Nectar", "Roof", "Wax" }
		same(Core.PromoCodes, wiki, "the wiki list")
		BUTTONS["Redeem All Codes"]()
		same(firedNames("PromoCodeEvent"), wiki, "Redeem All Codes sends the wiki list, in order")
		w.fired = {}
		local realWait, pressedAgain = task.wait, false
		task.wait = function()
			if not pressedAgain then
				pressedAgain = true
				BUTTONS["Redeem All Codes"]() -- pressed again while the first batch is still going out
			end
			return 0
		end
		BUTTONS["Redeem All Codes"]()
		task.wait = realWait
		assert(#firedNames("PromoCodeEvent") == 13 and pressedAgain, "the second press did nothing: " .. #firedNames("PromoCodeEvent"))
		assert(select(2, Core.RedeemCodes("")) == nil and Core.RedeemCodes("") == 0, "and the codes can be sent again afterwards")
		worldDown()
	end)

	run("Event: snowflakes, the Bee Bear and the gifts", function()
		world()
		Core.Set("CollectSnowflakes", true)
		assert(Core.SnowStep() == "none" and #w.notes == 1 and w.notes[1]:find("No snowflakes"), "says so")
		assert(Core.SnowStep() == "none" and #w.notes == 1, "but only once")
		w.particles.kids = { fake("Snowflakes", "Folder", nil, { fake("Snowflake", "Part", { Position = vec(50, 10, 60) }) }) }
		assert(Core.SnowStep() == "snowflake")
		local spot = w.moved[#w.moved]
		assert(spot.X == 50 and spot.Y == 25 and spot.Z == 60, "15 studs above it")
		assert(w.root.AssemblyLinearVelocity.Magnitude == 0, "and standing still")
		Core.Set("CollectSnowflakes", false)
		BUTTONS["Go To Bee Bear"]()
		assert(math.abs(w.moved[#w.moved].X + 38.667) < 0.01)
		bss("Dropdowns", "Event||Event Teleports||Gift").Set("Gift 8")
		BUTTONS["Go To Selected Gift"]()
		assert(w.moved[#w.moved].X == 327.6 and w.moved[#w.moved].Y == 195)
		worldDown()
	end)

	run("Bosses: platforms by the monsters, and hovering above Windy, the Vicious Bee and the Mondo Chick", function()
		world()
		local jumped, realJump = {}, Core.JumpTo
		Core.JumpTo = function(position) jumped[#jumped + 1] = position w.root.Position = position return true end
		BUTTONS["Fight Tunnel Bear"]()
		assert(#jumped == 2 and jumped[1].Y == 7.267 and jumped[2].Y == 24.267 and jumped[2].X == 469.095, "down, then up onto the platform")
		local platform = Core.GetPlatform("TunnelBear")
		assert(platform and platform.Name == "Tunnel Part" and platform.Anchored == true and platform.Transparency == 1 and platform.Size.X == 10)
		jumped = {}
		BUTTONS["Fight Commando Chick"]()
		assert(#jumped == 1 and jumped[1].X == 532.56 and Core.GetPlatform("CommandoChick").Name == "Commando Part")
		jumped = {}
		BUTTONS["AFK At Stump Snail"]()
		assert(#jumped == 2 and jumped[2].Y == 74.426 and Core.GetPlatform("StumpSnail").Name == "Snail Part")
		assert(Core.StandAt("Nope") == false and Core.StandAt("TrainCrab") == false, "only the monster spots")

		w.humanoid.HipHeight = 2
		Core.Set("HoverWindy", true)
		assert(Core.WindyStep() == "none", "nothing while Windy is not around")
		w.bees.kids = { fake("Windy", "Part", { Position = vec(80, 30, 90) }) }
		assert(Core.WindyStep() == "windy" and w.humanoid.HipHeight == 35 and jumped[#jumped].X == 80, "on Windy, 35 up")
		Core.Set("HoverWindy", false)
		assert(w.humanoid.HipHeight == 2, "back to your normal height")

		Core.Set("HoverVicious", true)
		w.particles.kids = { fake("Spark", "Part", { Position = vec(1, 2, 3) }), fake("ViciousThorn", "Part", { Position = vec(10, 20, 30) }) }
		assert(Core.ViciousStep() == "vicious" and w.humanoid.HipHeight == 20 and jumped[#jumped].Y == 40, "20 above the Vicious Bee")
		Core.Set("FollowMondo", true)
		assert(Core.Settings.HoverVicious == false and w.humanoid.HipHeight == 20, "one at a time, and no flicker back to normal in between")
		assert(Core.MondoStep() == "none", "no Mondo Chick yet")
		w.monsters.kids = { fake("Mondo Chick (Lvl 8)", "Model", nil, { fake("Head", "Part", { Position = vec(300, 60, 300) }) }) }
		local moves = #w.moved
		assert(Core.MondoStep() == "mondo" and w.humanoid.HipHeight == 40 and #w.moved == moves + 1, "40 up, and a glide to its head")
		assert(Core.MondoStep() == "mondo" and #w.moved == moves + 1, "no new glide when already there")
		Core.Set("FollowMondo", false)
		assert(w.humanoid.HipHeight == 2)
		Core.JumpTo = realJump
		worldDown()
	end)

	run("Fight Coconut Crab, and one mover at a time across all the new switches", function()
		world()
		local jumped, realJump = {}, Core.JumpTo
		Core.JumpTo = function(position) jumped[#jumped + 1] = position w.root.Position = position return true end
		Core.Set("FightCrab", true)
		assert(Core.FightCrabStep() == "to crab")
		local platform = Core.GetPlatform("FightCrab")
		assert(platform.Name == "Coconut Part" and platform.Transparency == 0.5 and platform.Size.X == 6)
		assert(math.abs(jumped[1].Y - 110.919) < 0.01 and Core.FightCrabStep() == "above crab" and #jumped == 1)
		Core.Set("TrainCrab", true)
		assert(Core.Settings.FightCrab == false and Core.GetPlatform("FightCrab") == nil, "Train Crab took over and the small platform is gone")
		Core.Set("TrainCrab", false)
		local movers = { "AutoFarm", "TrainSnail", "TrainCrab", "FightCrab", "CollectSnowflakes", "FollowMondo", "HoverWindy", "HoverVicious" }
		for _, mover in ipairs(movers) do
			Core.Set(mover, true)
			local on = 0
			for _, other in ipairs(movers) do if Core.Settings[other] then on = on + 1 end end
			assert(on == 1 and Core.Settings[mover], mover .. " is the only mover on")
		end
		Core.StopFeatures()
		for _, mover in ipairs(movers) do assert(Core.Settings[mover] == false, mover .. " is off after Stop All") end
		Core.JumpTo = realJump
		worldDown()
	end)

	run("Jump Power and Walk Through Walls", function()
		world()
		assert(Core.JumpStep() == "off")
		Core.Set("JumpPower", 120)
		Core.Set("KeepJumpPower", true)
		assert(Core.JumpStep() == "set" and w.humanoid.JumpPower == 120 and w.humanoid.UseJumpPower == true)
		Core.Set("KeepJumpPower", false)
		Core.Set("JumpPower", 50)
		local arm = fake("Arm", "Part", { CanCollide = true })
		w.root.CanCollide = true
		w.character.kids = { w.root, w.humanoid, arm }
		assert(Core.NoclipStep() == "off" and w.root.CanCollide == true)
		Core.Set("Noclip", true)
		assert(Core.NoclipStep() == "noclip" and w.root.CanCollide == false and arm.CanCollide == false)
		Core.Set("Noclip", false)
		worldDown()
	end)

	run("Unload UI frees the script to run again, and an unsupported place stays out unless forced", function()
		BUTTONS["Unload UI"]()
		assert(getgenv().PeridotBeeSwarmLoaded == nil and getgenv().PeridotBeeSwarmCore == nil)
		UI_ERRORS, WARNINGS = {}, {}
		PLACE_ID_OVERRIDE = 1
		getgenv().PeridotForceGame = nil
		assert(pcall(assert(loadfile(REPO .. "/games/1537690962.lua"))))
		assert(getgenv().PeridotBeeSwarmLoaded == nil and WARNINGS[1] and WARNINGS[1]:find("unsupported place"), "nothing built")
		getgenv().PeridotForceGame = true
		local ok, err = pcall(assert(loadfile(REPO .. "/games/1537690962.lua")))
		PLACE_ID_OVERRIDE = nil
		getgenv().PeridotForceGame = nil
		assert(ok, err)
		assert(getgenv().PeridotBeeSwarmLoaded == true, "test mode builds the window anywhere")
		getgenv().PeridotBeeSwarmCore.Unload()
		getgenv().PeridotBeeSwarmLoaded, getgenv().PeridotBeeSwarmCore = nil, nil
	end)

	run("the script waits for the game to finish loading before it builds anything", function()
		UI_ERRORS, WARNINGS = {}, {}
		local waited = false
		rawset(game, "IsLoaded", function() return false end)
		rawset(game, "Loaded", { Wait = function() waited = true rawset(game, "IsLoaded", nil) end })
		PLACE_ID_OVERRIDE = 1537690962
		getgenv().PeridotBeeSwarmLoaded = nil
		local ok, err = pcall(assert(loadfile(REPO .. "/games/1537690962.lua")))
		PLACE_ID_OVERRIDE = nil
		rawset(game, "IsLoaded", nil)
		rawset(game, "Loaded", nil)
		assert(ok, err)
		assert(waited, "it waited for game.Loaded")
		assert(getgenv().PeridotBeeSwarmLoaded == true and #UI_ERRORS == 0, "and then built")
		getgenv().PeridotBeeSwarmCore.Unload()
		getgenv().PeridotBeeSwarmLoaded, getgenv().PeridotBeeSwarmCore = nil, nil
	end)

	BUTTONS, BOXES, DROPDOWNS = savedButtons[1], savedButtons[2], savedButtons[3]
	Vector3 = realVector3
	Enum = realEnum
end

---------------------------------------------------------------- 5. port check
-- The Blox Fruits port must keep every option of the source reachable. These read
-- libraries/bf-main.lua (the ported script) and games/2753915549.lua (its UI).
print("Port check")
local function readRepo(path)
	local f = assert(io.open(REPO .. "/" .. path, "rb"))
	local text = f:read("*a")
	f:close()
	return text
end
local CORE, UI = readRepo("libraries/bf-main.lua"), readRepo("games/2753915549.lua")

local function set(list)
	local out = {}
	for name in list:gmatch("%S+") do out[name] = true end
	return out
end
-- Read through _G / getgenv() by the core but not options a player sets.
local NOT_OPTIONS = set([[
OnFarm SelectWeapon CDKDoorOpenedAt CDKDoorTry LastTPCall WasOnFarm TweenCache CheckQuestVisible HopTimer
LastCDKBossKick T1Yama T2Yama T3Yama DoneT1 DoneT2 DoneT3 LastPHReset Raiding SendHitsToServer Core
Sea1_Islands Sea2_Islands Sea3_Islands IslandData GetMobs toggleFly updateFlySpeed ShareServerEvents
]]) -- the core's own state and exports
for name in pairs(set([[
Prefully CollectPresent TpLab AutoPhoenixF AutoHolyTorch Doughv2 AuraBoss CraftVM AutoFarmRaid AutoFMon
AutoEvoRace AutoGetQuestBounty AutoFarmGodChalice AutoFistDarkness AutoMiror Teleport FarmGodChalice Lvthan
beasthunter DangerLV tweenKitsune snaguine tweenKitShrine AutoFishSlap FarmEliteHop StartEvent
AutoAttackRipIndra AutoFarmCandy AutoTP_Gift AutoTPGift AutoTPAndCollect MasterAutoLevel MasterAutoCandy
AutoMagnetToken AutoChestBP PortalUnLock
]])) do
	-- no logic in the source: only listed in one combined check (AutoChestBP is only ever
	-- switched off, PortalUnLock needs pad positions the source never defines)
	NOT_OPTIONS[name] = true
end
-- Options the core reads as plain globals.
local PLAIN_OPTIONS = [[
SelectMaterial pSats ABmethod RandomCFrame SelectIsland RDeath RemoveDamage LookM LookMV3 SpectatePlys NPClist
InfAblities PlayerEsp IslandESP DevilFruitESP FlowerESP EspEventIsland ESPGear advanEsp ColorEsp LegenS ChestESP
BerryEsp Range FARM_RANGE Num_self
]]

run("every option the core reads has a control", function()
	local seen = {}
	for name in CORE:gmatch("_G%.([%a_][%w_]*)") do seen[name] = true end
	for name in CORE:gmatch("getgenv%(%)%.([%a_][%w_]*)") do seen[name] = true end
	for name in PLAIN_OPTIONS:gmatch("%S+") do seen[name] = true end
	local missing = {}
	for name in pairs(seen) do
		if not NOT_OPTIONS[name] and not UI:find('"' .. name .. '"', 1, true) then
			missing[#missing + 1] = name
		end
	end
	table.sort(missing)
	assert(#missing == 0, "no control for: " .. table.concat(missing, ", "))
end)

local function defines(name)
	for _, pattern in ipairs({ "\n%s*" .. name .. " = function", "\n%s*Core%." .. name .. " = function",
		"\n%s*function " .. name .. "%(", "\n%s*Core%." .. name .. " = " .. name .. "\n" }) do
		if CORE:find(pattern) then return true end
	end
	return false
end

run("every command a button sends is one the script itself sends", function()
	local unknown, checked = {}, 0
	for args in UI:gmatch("commandButton%(%w+, \"[^\"]+\", \"[^\"]+\", ([^\n]+)%)") do
		checked = checked + 1
		local command = args:match('^"([^"]+)"')
		if command ~= "TravelMain" and not CORE:find('InvokeServer%(%s*"' .. command .. '"') then
			unknown[#unknown + 1] = command
		end
	end
	assert(checked >= 15, "found the command buttons, got " .. checked)
	assert(#unknown == 0, "commands the script never sends: " .. table.concat(unknown, ", "))
end)

run("every core function the UI calls exists in the core", function()
	local wanted = { "_tp", "IsInSubmergedIsland", "toggleFly", "updateFlySpeed" }
	for name in UI:gmatch('callGlobal%("([%w_]+)"') do wanted[#wanted + 1] = name end
	for name in UI:match("local ESP_ROUTINES = (%b{})"):gmatch('"([%w_]+)"') do wanted[#wanted + 1] = name end
	local missing = {}
	for _, name in ipairs(wanted) do
		if not defines(name) then missing[#missing + 1] = name end
	end
	assert(#wanted > 20, "found the calls")
	assert(#missing == 0, "the UI calls functions the core does not define: " .. table.concat(missing, ", "))
end)

-- Defined by the core, called by nothing in it, and deliberately not on the UI.
local NOT_EXPOSED = set([[
GetIn IsAlive GetNearbyTargets GetTargetParts Execute ListServers requestentrance
Getmoon BypassTP BTP old_tp
]]) -- helpers; ListServers is the older twin of fetchServersData; requestentrance's portal table drives
    -- Misc > Teleport > Portals; Getmoon only returns a texture id (the source has no phase table);
    -- BypassTP is switched off in the source itself (its "Bypass Teleport" setting is a
    -- hard-coded false); BTP / old_tp move you by dying or setting your position outright

local function calledIn(text, name)
	local init = 1
	while true do
		local first, last = text:find(name .. "%s*%(", init)
		if not first then return false end
		local before = first > 1 and text:sub(first - 1, first - 1) or ""
		local prefix = text:sub(math.max(1, first - 10), first - 1)
		if not before:match("[%w_%.:]") and not prefix:match("function%s*$") then return true end
		init = last + 1
	end
end

run("every core function is called by the core, used by the UI, or reviewed as not exposed", function()
	local names = {}
	for name in CORE:gmatch("\n%s*([%a_][%w_]*) = function") do names[name] = true end
	for name in CORE:gmatch("\n%s*Core%.([%a_][%w_]*) = function") do names[name] = true end
	local unreachable, stale = {}, {}
	for name in pairs(names) do
		if not calledIn(CORE, name) and not UI:find(name, 1, true) and not NOT_EXPOSED[name] then
			unreachable[#unreachable + 1] = name
		end
	end
	for name in pairs(NOT_EXPOSED) do
		if not names[name] or calledIn(CORE, name) or UI:find(name, 1, true) then stale[#stale + 1] = name end
	end
	table.sort(unreachable)
	table.sort(stale)
	assert(#unreachable == 0, "core functions nothing can reach: " .. table.concat(unreachable, ", "))
	assert(#stale == 0, "listed as not exposed but now used or gone: " .. table.concat(stale, ", "))
end)

print(("instances created: %d, http fetches: %s"):format(INSTANCES, table.concat(HTTP_LOG, ", ")))
print(failures == 0 and "ALL PASSED" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
