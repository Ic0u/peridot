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
local function service(name)
	if not services[name] then
		local s = newInstance(name)
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
local function color(r, g, b)
	return setmetatable({ r = r, g = g, b = b, R = r, G = g, B = b }, { __index = function() return P end, __type = "Color3" })
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
run("Background dropdown (UI Settings page) loads the picked file", function()
	local entry = lib.ControlRegistry.Dropdowns["UI Settings||Background||Background"]
	assert(entry, "dropdown registered on the UI Settings page")
	local before = getgenv().UIColor["Background 1 Transparency"]
	entry.Set("Waves")
	assert(FILES["Peridot/Backgrounds/waves.webm"] == "webm-bytes", "waves.webm downloaded from assets/backgrounds/")
	assert(getgenv().UIColor["Background 1 Transparency"] == 0.4, "panels see-through")
	entry.Set("None")
	assert(getgenv().UIColor["Background 1 Transparency"] == before, "player's transparency restored")
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

print("Sub-tabs")
run("sub-tabs keep separate config keys and switch", function()
	local w = lib.CreateMain({ Name = "Peridot", Title = "Test Game" })
	local page = w.CreatePage({ Page_Name = "Farm", Page_Title = "Farm" })
	local bounty, lvl = page.CreateSubTab("Bounty Farm"), page.CreateSubTab("Lvl Farm")
	local got = {}
	bounty.CreateSection("Run").CreateToggle({ Title = "Run the rotation" }, function(v) got.bounty = v end)
	lvl.CreateSection("Run").CreateToggle({ Title = "Run the rotation" }, function(v) got.lvl = v end)
	assert(lib.ControlRegistry.Toggles["Farm/Bounty Farm||Run||Run the rotation"], "bounty key")
	assert(lib.ControlRegistry.Toggles["Farm/Lvl Farm||Run||Run the rotation"], "lvl key")
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
	assert(lib.Internal.HideGui.Enabled == false, "floating button hidden")
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
