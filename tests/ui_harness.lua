-- Mock-Roblox smoke test for libraries/UILibrary.lua.
-- Runs scripts/Universal.lua for real (modules come from the local repo), then
-- exercises config save/load, an old-format config, and BloxFruitsUIAdapter.
-- Proves the API wiring; it does not render anything.
-- usage (from the repo root): luajit tests/ui_harness.lua . [--bloxfruits]   (Blox Fruits run: PLACE_ID=2753915549)
local REPO = assert(arg[1], "repo root")
local RUN_BF = arg[2] == "--bloxfruits"

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
local function newInstance(class, parent)
	INSTANCES = INSTANCES + 1
	local props = { ClassName = class, Name = class, Parent = parent }
	local inst = {}
	local methods = {
		IsA = function(_, c) return c == class end,
		Destroy = function() props.Parent = nil end,
		GetChildren = function() return {} end,
		GetDescendants = function() return {} end,
		FindFirstChild = function() return nil end,
		FindFirstChildOfClass = function() return nil end,
		FindFirstChildWhichIsA = function() return nil end,
		WaitForChild = function(_, name) return newInstance(name, inst) end,
	}
	return setmetatable(inst, {
		__index = function(_, k)
			if props[k] ~= nil then return props[k] end
			if methods[k] then return methods[k] end
			return P
		end,
		__newindex = function(_, k, v) props[k] = v end,
		__tostring = function() return props.Name end,
		__type = "Instance",
	})
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
		if k == "PlaceId" then return tonumber(os.getenv("PLACE_ID") or "1") end
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
task = {
	spawn = function(f, ...) if RUN_SPAWNS and type(f) == "function" then f(...) end return P end,
	delay = function(_, f, ...) if RUN_SPAWNS and type(f) == "function" then f(...) end return P end,
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
	assert(getgenv().UIColor["Logo Image"] == "rbxassetid://80832574371637", "back to the main icon, got " .. tostring(getgenv().UIColor["Logo Image"]))
	assert(savedTheme().Logo == nil, "saved custom icon cleared")
end)
RUN_SPAWNS = false

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

---------------------------------------------------------------- 4. Blox Fruits adapter
print("BloxFruitsUIAdapter")
run("every adapter method", function()
	local Adapter = assert(loadfile(REPO .. "/libraries/BloxFruitsUIAdapter.lua"))()
	local window = Adapter.Create(lib, { Name = "Peridot", Title = "Blox Fruits", Desc = "", FloatingButton = false })
	assert(lib.Internal.HideGui.Enabled == false, "UI toggle button hidden")
	local section = window:Tab("Main"):Section("Farm", "Left")
	local got = {}
	local t = section:Toggle("Auto Farm", true, function(v) got.toggle = v end)
	assert(got.toggle == true, "toggle default fired")
	t:Update(false); assert(got.toggle == false, "toggle Update")
	section:Button("Go", function() end)
	section:Label("hello"):Set("world")
	section:Seperator("Divider")
	local d = section:Dropdown("Weapon", { "Melee", "Sword" }, "Melee", function(v) got.dd = v end)
	d:Clear(); d:Add("Gun"); d:Refresh({ "Melee", "Fruit" }); d:Set("Fruit")
	assert(got.dd == "Fruit", "dropdown Set fires callback")
	section:Textbox("Code", "type", function() end)
	section:Slider("Distance", true, 0, 50, 10, function() end)
	section:Slider("Fraction", false, 0, 1, 0.5, function() end)
	local subSection = window:Tab("Farm"):SubTab("Bounty Farm"):Section("Run")
	subSection:Toggle("Run the rotation", false, function() end)
	subSection:Label("Status: off"):Set("Status: on")
end)

---------------------------------------------------------------- 5. full Blox Fruits module (optional)
if RUN_BF then
	print("games/2753915549.lua")
	run("runs top to bottom", function()
		assert(loadfile(REPO .. "/games/2753915549.lua"))()
	end)
end

print(("instances created: %d, http fetches: %s"):format(INSTANCES, table.concat(HTTP_LOG, ", ")))
print(failures == 0 and "ALL PASSED" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
