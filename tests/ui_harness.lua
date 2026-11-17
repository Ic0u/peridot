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
	for _, file in ipairs({ "libraries/UILibrary.lua", "scripts/Universal.lua", "games/2753915549.lua" }) do
		for order in read(file):gmatch("DisplayOrder = (%d+)") do
			assert(tonumber(order) < loaderOrder, file .. " sets a ScreenGui at or above the loader: " .. order)
		end
	end
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
	assert(getgenv().UIColor["Background 1 Transparency"] == 0.4, "panels see-through")
	entry.Set("None")
	assert(getgenv().UIColor["Background 1 Transparency"] == before, "player's transparency restored")
	assert(lib.SetBackground("Peridot/Backgrounds/waves.webm"), "local video file")
	local ok, err = lib.SetBackground("Peridot/Backgrounds/nope.png")
	assert(ok == false and tostring(err):find("not found"), "missing local file reported")
end)

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

local registryBefore = {}
for kind, entries in pairs(lib.ControlRegistry) do
	registryBefore[kind] = {}
	for key in pairs(entries) do registryBefore[kind][key] = true end
end

-- Buttons have no handle in the registry, so wrap the section factories while the
-- module builds and keep each button's callback by title.
local BUTTONS = {}
local function recordButtons()
	local realCreateMain = lib.CreateMain
	local function patch(section)
		local realButton = section.CreateButton
		section.CreateButton = function(options, callback)
			BUTTONS[options.Title] = callback
			return realButton(options, callback)
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
	OVERRIDES["libraries/BloxFruitsCore.lua"] = BF_STUB_CORE
	_G.__HARNESS_LIB = lib
	PLACE_ID_OVERRIDE = 2753915549
	getgenv().PeridotBloxFruitsLoaded = nil
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
	assert(_G.TweenSpeedNear == 180 and _G.TweenSpeedFar == 150 and _G.HopDelay == 1800)
	assert(_G.MasteryHealthPct == 70 and _G.pSats == 3 and _G.Num_self == 25 and _G.Range == 100)
	assert(_G.FishCatchDelay == nil, "0 means the core's random delay")
	assert(_G.ABmethod == "Aim Player" and _G.SelectDN == "Day" and _G.SelectIslandMastery == "Cake")
	assert(#_G.SelectedMasterySkills == 5)
end)

run("dropdowns and sliders write their flags", function()
	control("Dropdowns", "||Auto Farm||Weapon").Set("Sword")
	assert(_G.ChooseWP == "Sword")
	control("Dropdowns", "||Auto Farm||Mob").Set("Monkey")
	assert(_G.SelectMob == "Monkey" and getgenv().SelectMob == "Monkey")
	control("Dropdowns", "||Auto Farm||Island").Set("Frozen Village")
	assert(_G.SelectIsland == "Frozen Village")
	control("Dropdowns", "||Bosses||Boss").Set("Bobby")
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
	local esp = control("Toggles", "||ESP||Players")
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
	control("Dropdowns", "||Auto Farm||Mob").Set("Monkey")
	getgenv().GetMobs = function() return { "A", "B", "C" } end
	BUTTONS["Refresh Mob List"]()
	assert(hasLabel("3 mobs found"), "count updated after Refresh")
	assert(_G.SelectMob == nil, "the cleared dropdown no longer leaves a hidden selection")
	getgenv().GetMobs = function() return {} end
	BUTTONS["Refresh Mob List"]()
	assert(hasLabel("No mobs found. Press Refresh once the game has finished loading."), "empty state says what to do")
end)

run("Stop All Features switches everything off", function()
	local farm = control("Toggles", "||Auto Farm||Auto Farm Level")
	farm.Set(true)
	BUTTONS["Stop All Features"]()
	assert(farm.Get() == false and _G.Level == false)
end)

run("config saves and restores the Blox Fruits controls", function()
	local farm = control("Toggles", "||Auto Farm||Auto Farm Level")
	control("Boxes", "Settings||Config||Config Name").Set("bf")
	farm.Set(true)
	control("Sliders", "||Movement||Tween Speed Near").Set(222)
	BUTTONS["Save"]()
	assert(FILES["Peridot/BloxFruits/bf.json"], "config written to the Blox Fruits folder")
	farm.Set(false)
	control("Sliders", "||Movement||Tween Speed Near").Set(100)
	RUN_SPAWNS = true -- Load applies values from task.spawn
	BUTTONS["Load"]()
	RUN_SPAWNS = false
	assert(farm.Get() == true and _G.Level == true, "toggle restored")
	assert(_G.TweenSpeedNear == 222, "slider restored, got " .. tostring(_G.TweenSpeedNear))
	BUTTONS["Delete"]()
	assert(not FILES["Peridot/BloxFruits/bf.json"], "config deleted")
	farm.Set(false)
end)

local function buildSea(world, stubExtra)
	local known = {}
	for _, entries in pairs(lib.ControlRegistry) do
		for _, handle in pairs(entries) do known[handle] = true end
	end
	OVERRIDES["libraries/BloxFruitsCore.lua"] = BF_STUB_CORE .. "\nenv.World" .. world .. " = true\n" .. (stubExtra or "")
	getgenv().PeridotBloxFruitsLoaded = nil
	_G.World1, _G.World2, _G.World3 = nil, nil, nil
	PLACE_ID_OVERRIDE = 2753915549
	UI_ERRORS, WARNINGS = {}, {}
	local ok, err = pcall(assert(loadfile(REPO .. "/games/2753915549.lua")))
	PLACE_ID_OVERRIDE = nil
	assert(ok, err)
	assert(#UI_ERRORS == 0 and #WARNINGS == 0, "errors: " .. tostring(UI_ERRORS[1] or WARNINGS[1]))
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
		{ "Auto Farm Level", "Get Saber", "Get Marine Coat", "Second Sea Quest", "Farm Chests", "Auto Server Hop" },
		{ "Farm Bones", "Dough King", "Get Tushita", "Get Trident", "Factory Raid", "Castle Raid", "Auto Start Raid",
		  "Buy Microchip", "Dojo Belt Quests", "Find Mirage Island", "Find Kitsune Island", "Find Prehistoric Island",
		  "Elite Hunter", "Tyrant of the Skies", "Third Sea Quest" })
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

print(("instances created: %d, http fetches: %s"):format(INSTANCES, table.concat(HTTP_LOG, ", ")))
print(failures == 0 and "ALL PASSED" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
