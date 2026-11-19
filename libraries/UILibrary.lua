--[[
    UILibrary.lua - Peridot UI
    ---------------------------------------------------------------------------
    Drawing: BananaLib v2 (Banana Cat Hub / Nousigi UI), readable upstream source
    from github.com/BananaHubRemakeFreeVersion, recolored peridot green.
    Peridot API at the bottom (CreateMain / CreatePage / CreateSection /
    Create*, ConfigSystem), which Universal.lua and the Blox Fruits module call.
--]]

local getgenv = getgenv or function() return _G end

local cloneref = cloneref or function(o) return o end
local gethui   = gethui   or function() return cloneref(game:GetService("CoreGui")) end

-- Plain global lookups: executors often expose these through the environment's
-- __index, which rawget(getfenv(0), ...) skips. That made file access look
-- missing, so configs, the theme file and URL backgrounds all failed.
local HasFileSystem =
    type(isfile)     == "function" and
    type(readfile)   == "function" and
    type(writefile)  == "function" and
    type(isfolder)   == "function" and
    type(makefolder) == "function"

-- One-time carry-over of saves from the pre-rename "Vinsers Hub" folder.
-- Skips the Assets cache (it re-downloads) and does nothing once "Peridot" exists.
local function MigrateLegacyFolder()
    if not HasFileSystem or type(listfiles) ~= "function" then return end
    if isfolder("Peridot") or not isfolder("Vinsers Hub") then return end

    local function copy(from, to)
        makefolder(to)
        for _, path in ipairs(listfiles(from)) do
            local name = path:match("([^/\\]+)$")
            if isfolder(path) then
                if name ~= "Assets" then copy(path, to .. "/" .. name) end
            else
                writefile(to .. "/" .. name, readfile(path))
            end
        end
    end
    pcall(copy, "Vinsers Hub", "Peridot") -- ponytail: a failed copy leaves a partial Peridot folder and isn't retried
end
MigrateLegacyFolder()

local GuiParent = gethui()
for _, parent in ipairs({ GuiParent, game:GetService("CoreGui") }) do
	pcall(function()
		for _, v in ipairs(parent:GetChildren()) do
			if v.Name == "Peridot GUI" or v.Name == "Peridot Notification" or v.Name == "Peridot Btn" then
				v:Destroy()
			end
		end
	end)
end
getgenv().PeridotUI = true

local DisableAnimation = game.Players.LocalPlayer.PlayerGui:FindFirstChild('TouchGui')
local T1UIColor = {
	["Border Color"] = Color3.fromRGB(140, 172, 68),
	["Setting Icon Color"] = Color3.fromRGB(230, 230, 230),
	["Logo Image"] = "rbxassetid://97933423096090",
	["Search Icon Color"] = Color3.fromRGB(240, 240, 230),
	["Search Icon Highlight Color"] = Color3.fromRGB(140, 172, 68),
	["GUI Text Color"] = Color3.fromRGB(235, 235, 230),
	["Text Color"] = Color3.fromRGB(235, 235, 230),
	["Placeholder Text Color"] = Color3.fromRGB(170, 170, 160),
	["Title Text Color"] = Color3.fromRGB(140, 172, 68),
	["Background Main Color"] = Color3.fromRGB(18, 18, 22),
	["Background Main Transparency"] = 0, -- the window frame: 0 is solid, the Transparent window style lets the game show through
	["Background 1 Color"] = Color3.fromRGB(28, 28, 34),
	["Background 1 Transparency"] = 0,
	["Section Panel Transparency"] = 0.15, -- follows Background 1 Transparency, see sectionTransparency below
	["Background 2 Color"] = Color3.fromRGB(38, 38, 46),
	["Background 3 Color"] = Color3.fromRGB(48, 48, 56),
	-- window parts: what they look like today (their frame color times the old gradient)
	["Sidebar Color"] = Color3.fromRGB(4, 4, 6),
	["Section Panel Color"] = Color3.fromRGB(9, 9, 12),
	["Outline Color"] = Color3.fromRGB(90, 90, 70),
	["Background Image"] = "",
	["Page Selected Color"] = Color3.fromRGB(140, 172, 68),
	["Section Text Color"] = Color3.fromRGB(220, 220, 210),
	["Section Underline Color"] = Color3.fromRGB(140, 172, 68),
	["Toggle Border Color"] = Color3.fromRGB(140, 172, 68),
	["Toggle Checked Color"] = Color3.fromRGB(140, 172, 68),
	["Toggle Desc Color"] = Color3.fromRGB(185, 185, 185),
	["Button Color"] = Color3.fromRGB(140, 172, 68),
	["Label Color"] = Color3.fromRGB(38, 38, 46),
	["Dropdown Icon Color"] = Color3.fromRGB(230, 230, 230),
	["Dropdown Selected Check Color"] = Color3.fromRGB(120, 150, 56),
	["Box Highlight Color"] = Color3.fromRGB(140, 172, 68),
	["Slider Line Color"] = Color3.fromRGB(140, 172, 68),
	["Slider Highlight Color"] = Color3.fromRGB(96, 124, 44),
	["Tween Animation 1 Speed"] = DisableAnimation and 0 or 0.25,
	["Tween Animation 2 Speed"] = DisableAnimation and 0 or 0.5,
	["Tween Animation 3 Speed"] = DisableAnimation and 0 or 0.1,
	["Text Stroke Transparency"] = 0.5,
	["Tween Easing Style"] = "Quad",
}

-- Live theme: Bind() records every property drawn from a theme key, and writing
-- getgenv().UIColor[key] (gear page, scripts) re-applies it to everything on screen.
local ThemeListeners = {} -- key -> function(value), for values that aren't a plain property (rich text, gradients)
local ThemeBindings = {} -- key -> { {instance, property}, ... }
local ThemeFade = false -- while true, color changes crossfade instead of snapping (presets, reset)
local function FadeTheme(change)
	ThemeFade = not DisableAnimation
	local ok, err = pcall(change)
	ThemeFade = false
	if not ok then
		error(err, 0)
	end
end
local function Bind(instance, property, key)
	local value = T1UIColor[key]
	instance[property] = value
	local list = ThemeBindings[key]
	if not list then
		list = {}
		ThemeBindings[key] = list
	end
	table.insert(list, { instance, property })
	return value
end
getgenv().UIColor = setmetatable({}, {
	__index = T1UIColor,
	__newindex = function(_, key, value)
		T1UIColor[key] = value
		local list = ThemeBindings[key]
		if list then
			for i = #list, 1, -1 do
				local binding = list[i]
				if not pcall(function()
					if ThemeFade and typeof(value) == "Color3" then
						game:GetService("TweenService"):Create(binding[1], TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							[binding[2]] = value
						}):Play()
					else
						binding[1][binding[2]] = value
					end
				end) then
					table.remove(list, i)
				end
			end
		end
		if ThemeListeners[key] then
			pcall(ThemeListeners[key], value)
		end
	end,
})

-- Section panels follow the panel transparency a little further, so a background picture
-- shows through them as well as through the sidebar and the page.
local function sectionTransparency(panel)
	return math.min(0.15 + (tonumber(panel) or 0) * 1.2, 0.9)
end
ThemeListeners["Background 1 Transparency"] = function(value)
	getgenv().UIColor["Section Panel Transparency"] = sectionTransparency(value)
end

-- Animated tweens go through here so the Settings page's easing style applies.
local function TI(speedKey)
	local ok, style = pcall(function()
		return Enum.EasingStyle[getgenv().UIColor["Tween Easing Style"]]
	end)
	return TweenInfo.new(getgenv().UIColor[speedKey], ok and style or Enum.EasingStyle.Quad)
end

-- Theme helpers. The accent keys all follow one color; the Interface Settings page
-- (title-bar gear) changes it live and saves the choice to Peridot/Theme.json.
local AccentKeys = {
	"Border Color", "Search Icon Highlight Color", "Title Text Color", "Page Selected Color",
	"Section Underline Color", "Toggle Border Color", "Toggle Checked Color", "Button Color",
	"Box Highlight Color", "Slider Line Color",
}
local AccentPresets = {
	{ "Peridot", Color3.fromRGB(140, 172, 68) },
	{ "Ocean", Color3.fromRGB(90, 160, 255) },
	{ "Ruby", Color3.fromRGB(220, 70, 80) },
	{ "Amethyst", Color3.fromRGB(155, 105, 230) },
	{ "Gold", Color3.fromRGB(255, 206, 27) },
	{ "Sakura", Color3.fromRGB(240, 130, 170) },
	{ "Mint", Color3.fromRGB(70, 200, 160) },
	{ "Mono", Color3.fromRGB(200, 200, 200) },
}
local function shade(color, factor)
	return Color3.new(math.clamp(color.R * factor, 0, 1), math.clamp(color.G * factor, 0, 1), math.clamp(color.B * factor, 0, 1))
end
local function accentPalette(accent)
	local palette = {}
	for _, key in ipairs(AccentKeys) do
		palette[key] = accent
	end
	palette["Dropdown Selected Check Color"] = shade(accent, 0.86)
	palette["Slider Highlight Color"] = shade(accent, 0.7)
	return palette
end
local function ButtonGradient(accent)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, shade(accent, 1.18)),
		ColorSequenceKeypoint.new(0.4, accent),
		ColorSequenceKeypoint.new(0.6, shade(accent, 0.87)),
		ColorSequenceKeypoint.new(1, shade(accent, 0.74)),
	})
end
local function color3ToList(color)
	return { math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5) }
end

-- Label for the green button on a button row, inferred from the row's title so it says what
-- it does ("Buy", "Rejoin", "Teleport") instead of a generic "Click". A button can set
-- ButtonText itself; anything unrecognised gets "Run".
local ButtonVerbs = {
	teleport = "Teleport", tp = "Teleport", tween = "Go", remove = "Remove", redeem = "Redeem", open = "Open",
	join = "Join", rejoin = "Rejoin", copy = "Copy", refresh = "Refresh", reset = "Reset", save = "Save",
	load = "Load", delete = "Delete", unload = "Unload", stop = "Stop", resume = "Resume", respawn = "Respawn",
	get = "Get", start = "Start", select = "Select", equip = "Equip", use = "Use", claim = "Claim",
	collect = "Collect", clear = "Clear", apply = "Apply", update = "Update", random = "Roll", buy = "Buy",
	kill = "Kill", spawn = "Spawn", show = "Show", hide = "Hide", enable = "Enable", disable = "Disable",
}
local function ButtonVerb(title)
	local lower = tostring(title or ""):lower()
	if lower:match("%$%s*%d") or lower:match("%d%s*f%s*$") then
		return "Buy" -- "Katana $1,000", "Reset Stats 2,500F"
	end
	if lower:match("server hop") then
		return "Hop"
	end
	return ButtonVerbs[lower:match("^%s*(%a+)") or ""] or "Run"
end

local ThemeFile = "Peridot/Theme.json"
local DefaultTheme = {} -- every theme value as shipped, for "Reset theme"
for key, value in pairs(T1UIColor) do
	DefaultTheme[key] = value
end
local RainbowKeys = {} -- theme key -> { s, v } while its rainbow is on
local ThemeSystem = {} -- named themes (built-in, saved, default); filled in near the end of this file
local SavedTheme = {}
if HasFileSystem then
	pcall(function()
		if isfile(ThemeFile) then
			local data = game:GetService("HttpService"):JSONDecode(readfile(ThemeFile))
			if type(data) == "table" then
				SavedTheme = data
			end
		end
	end)
end
local themeSaveQueued = false
local function saveThemeSoon() -- coalesces a slider drag into one write
	if themeSaveQueued or not HasFileSystem then
		return
	end
	themeSaveQueued = true
	task.delay(0.5, function()
		themeSaveQueued = false
		pcall(function()
			if not isfolder("Peridot") then
				makefolder("Peridot")
			end
			writefile(ThemeFile, game:GetService("HttpService"):JSONEncode(SavedTheme))
		end)
	end)
end

-- Apply the saved theme before anything is drawn.
if type(SavedTheme.Accent) == "table" then
	local c = SavedTheme.Accent
	for key, value in pairs(accentPalette(Color3.fromRGB(tonumber(c[1]) or 0, tonumber(c[2]) or 0, tonumber(c[3]) or 0))) do
		T1UIColor[key] = value
	end
end
-- Panels can be see-through up to this. With the Solid window style the dark frame is behind
-- them, so even the maximum stays readable; with Transparent the game shows through them.
local PANEL_MAX = 0.6
if tonumber(SavedTheme.PanelTransparency) then
	-- capped: an old saved value near 0.9 once left the window unreadable
	T1UIColor["Background 1 Transparency"] = math.clamp(tonumber(SavedTheme.PanelTransparency), 0, PANEL_MAX)
end
T1UIColor["Section Panel Transparency"] = sectionTransparency(T1UIColor["Background 1 Transparency"])
local WINDOW_GLASS = 0.92 -- frame transparency of the Transparent window style (the original library's see-through frame)
if SavedTheme.WindowStyle == "Transparent" then
	T1UIColor["Background Main Transparency"] = WINDOW_GLASS
end
if tonumber(SavedTheme.AnimationSpeed) then
	T1UIColor["Tween Animation 2 Speed"] = tonumber(SavedTheme.AnimationSpeed)
end
if tonumber(SavedTheme.AnimationSpeed1) then
	T1UIColor["Tween Animation 1 Speed"] = tonumber(SavedTheme.AnimationSpeed1)
end
if tonumber(SavedTheme.AnimationSpeed3) then
	T1UIColor["Tween Animation 3 Speed"] = tonumber(SavedTheme.AnimationSpeed3)
end
if type(SavedTheme.Easing) == "string" then
	T1UIColor["Tween Easing Style"] = SavedTheme.Easing
end
if type(SavedTheme.Colors) == "table" then -- one-off color edits from the Colors tab
	for key, c in pairs(SavedTheme.Colors) do
		if typeof(T1UIColor[key]) == "Color3" and type(c) == "table" then
			T1UIColor[key] = Color3.fromRGB(tonumber(c[1]) or 0, tonumber(c[2]) or 0, tonumber(c[3]) or 0)
		end
	end
end
if type(SavedTheme.Rainbow) == "table" then
	for key in pairs(SavedTheme.Rainbow) do
		if typeof(T1UIColor[key]) == "Color3" then
			local _, s, v = T1UIColor[key]:ToHSV()
			RainbowKeys[key] = { s = math.max(s, 0.45), v = math.max(v, 0.6) }
		end
	end
end
getgenv().AllControls = {}
getgenv().UIToggled = false


local currcolor = {}
local Library = {};
local Library_Function = {}
local TweenService = game:GetService('TweenService')
local uis = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local function makeDraggable(topBarObject, object)
	local dragging = nil
	local dragInput = nil
	local dragStart = nil
	local startPosition = nil
	topBarObject.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPosition = object.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	topBarObject.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)
	uis.InputChanged:Connect(function(input)
		if input == dragInput and dragging then
			local delta = input.Position - dragStart
			if not djtmemay and cac then
				TweenService:Create(object, TweenInfo.new(DisableAnimation and 0 or 0.35, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
					Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
				}):Play()
			elseif not djtmemay and not cac then
				object.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
			end
		end
	end)
end

Library_Function.Gui = Instance.new('ScreenGui')
Library_Function.Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Library_Function.Gui.Name = 'Peridot GUI'
Library_Function.Gui.Enabled = false

getgenv().ReadyForGuiLoaded = false
spawn(function()
	repeat
		task.wait()
	until getgenv().ReadyForGuiLoaded
	if getgenv().UIToggled then
		Library_Function.Gui.Enabled = true
	end
end)


Library_Function.NotiGui = Instance.new('ScreenGui')
Library_Function.NotiGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Library_Function.NotiGui.Name = 'Peridot Notification'

Library_Function.HideGui = Instance.new('ScreenGui')
Library_Function.HideGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Library_Function.HideGui.Name = 'Peridot Btn'


-- UI toggle button (opens/closes the window): its size is a player option
-- (Interface Settings > UI Toggle), 38px by default. The texture fills the button
-- and stays put; only the outline gets a little stronger while the UI is open.
local ToggleButtonTexture = "rbxassetid://80832574371637"
local ButtonSize = math.clamp(tonumber(SavedTheme.ButtonSize) or 38, 28, 64)
local function buttonImageSize()
	return ButtonSize - 4
end

local btnHide = Instance.new('TextButton', Library_Function.HideGui)
btnHide.BackgroundTransparency = 1
btnHide.Text = ""
btnHide.AutoButtonColor = false -- no hover tint
btnHide.AnchorPoint = Vector2.new(0, 1)
btnHide.Size = UDim2.new(0, ButtonSize, 0, ButtonSize)
btnHide.Position = UDim2.new(0, 12, 1, -12)

local btnHideHolder = Instance.new('Frame', btnHide)
btnHideHolder.Name = "Holder"
btnHideHolder.AnchorPoint = Vector2.new(0.5, 0.5)
btnHideHolder.Position = UDim2.new(0.5, 0, 0.5, 0)
btnHideHolder.Size = UDim2.new(1, 0, 1, 0)
btnHideHolder.BackgroundTransparency = 1
local btnHidePress = Instance.new("UIScale")
btnHidePress.Parent = btnHideHolder

local btnHideFrame = Instance.new('Frame', btnHideHolder)
btnHideFrame.AnchorPoint = Vector2.new(0, 1)
btnHideFrame.Size = UDim2.new(0, ButtonSize, 0, ButtonSize)
btnHideFrame.Position = UDim2.new(0, 0, 1, 0)
btnHideFrame.Name = "dut dit"
Bind(btnHideFrame, "BackgroundColor3", "Background Main Color") -- dark, not the old white circle
btnHideFrame.BackgroundTransparency = 0

local imgHide = Instance.new('ImageLabel', btnHideHolder)
imgHide.AnchorPoint = Vector2.new(0, 0)
imgHide.Image = ToggleButtonTexture
imgHide.ScaleType = Enum.ScaleType.Fit -- tall art on a transparent background: show all of it, centered
imgHide.BackgroundTransparency = 1
imgHide.Size = UDim2.new(0, buttonImageSize(), 0, buttonImageSize())
imgHide.AnchorPoint = Vector2.new(.5, .5)
imgHide.Position = UDim2.new(.5, 0, .5, 0)

local UICornerBtnHide = Instance.new("UICorner")
UICornerBtnHide.Parent = btnHideFrame
UICornerBtnHide.CornerRadius = UDim.new(0, 10) -- rounded square

-- Accent outline, stronger while the window is open. Follows the theme's accent live.
local btnHideStroke = Instance.new("UIStroke")
btnHideStroke.Parent = btnHideFrame
btnHideStroke.Thickness = 1
btnHideStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
btnHideStroke.Transparency = getgenv().UIToggled and 0 or .35
Bind(btnHideStroke, "Color", "Border Color")

local imgHideCorner = Instance.new("UICorner")
imgHideCorner.Parent = imgHide
imgHideCorner.CornerRadius = UDim.new(0, 8) -- texture follows the rounded frame

-- Press feedback: a quick squish and a springy release. Pressing is feedback, not hover.
local function pressToggleButton(down)
	if DisableAnimation then
		return
	end
	TweenService:Create(btnHidePress, down
		and TweenInfo.new(.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		or TweenInfo.new(.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = down and .9 or 1
	}):Play()
end
btnHide.MouseButton1Down:Connect(function()
	pressToggleButton(true)
end)
btnHide.MouseButton1Up:Connect(function()
	pressToggleButton(false)
end)
btnHide.MouseLeave:Connect(function()
	pressToggleButton(false)
end)

-- Open/close: the window fades and pops in from 94%, and fades and shrinks back out.
-- The logical state (UIToggled) changes at once; Gui.Enabled follows after the close animation.
local windowCloseToken = 0
-- the shadow's resting transparency; hidden for a see-through frame, which would show its dark middle
local WindowShadowAlpha = T1UIColor["Background Main Transparency"] > 0 and 1 or .35
Library.ToggleUI = function()
	local opening = not getgenv().UIToggled
	getgenv().UIToggled = opening
	TweenService:Create(btnHideStroke, TweenInfo.new(DisableAnimation and 0 or .25), {
		Transparency = opening and 0 or .35
	}):Play()

	windowCloseToken = windowCloseToken + 1 -- a reopen cancels a close that is still animating
	local token = windowCloseToken
	local scale = Library_Function.WindowScale
	local fade = Library_Function.WindowFade
	local shadow = Library_Function.WindowShadow
	local animated = scale and fade and shadow and not DisableAnimation
	if opening then
		if animated then
			if not Library_Function.Gui.Enabled then -- from closed: start small and clear
				scale.Scale = .94
				fade.GroupTransparency = 1
				shadow.ImageTransparency = 1
			end -- reopened mid-close: carry on from where it is
			TweenService:Create(scale, TweenInfo.new(.26, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Scale = 1
			}):Play()
			TweenService:Create(fade, TweenInfo.new(.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				GroupTransparency = 0
			}):Play()
			TweenService:Create(shadow, TweenInfo.new(.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				ImageTransparency = WindowShadowAlpha
			}):Play()
		end
		Library_Function.Gui.Enabled = true
	elseif animated then
		TweenService:Create(scale, TweenInfo.new(.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Scale = .94
		}):Play()
		TweenService:Create(fade, TweenInfo.new(.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			GroupTransparency = 1
		}):Play()
		TweenService:Create(shadow, TweenInfo.new(.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			ImageTransparency = 1
		}):Play()
		task.delay(.16, function()
			if token == windowCloseToken then -- not reopened in the meantime
				Library_Function.Gui.Enabled = false
				scale.Scale = 1
				fade.GroupTransparency = 0
				shadow.ImageTransparency = WindowShadowAlpha
			end
		end)
	else
		Library_Function.Gui.Enabled = false
	end
end

-- UI toggle button options (Interface Settings > UI Toggle). Both save to Peridot/Theme.json.
function Library_Function.SetButtonSize(px)
	ButtonSize = math.clamp(math.floor(tonumber(px) or 38), 28, 64)
	btnHide.Size = UDim2.new(0, ButtonSize, 0, ButtonSize)
	btnHideFrame.Size = UDim2.new(0, ButtonSize, 0, ButtonSize)
	imgHide.Size = UDim2.new(0, buttonImageSize(), 0, buttonImageSize())
	SavedTheme.ButtonSize = ButtonSize
	saveThemeSoon()
end

function Library_Function.SetButtonVisible(on)
	Library_Function.HideGui.Enabled = on and true or false
	SavedTheme.FloatingButton = on and true or false
	saveThemeSoon()
end

-- Toggle key: opens/closes the window. Lives here, not in the page, so it works from the
-- start and in every script. A key picked on the page is saved by watching the control.
local MenuKeyName = type(SavedTheme.MenuKey) == "string" and SavedTheme.MenuKey or "RightControl"
if getgenv().PeridotMenuKeyConnection then -- re-running the script: drop the old copy's handler
	pcall(function()
		getgenv().PeridotMenuKeyConnection:Disconnect()
	end)
end
getgenv().PeridotMenuKeyConnection = uis.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.Keyboard or uis:GetFocusedTextBox() then
		return
	end
	if input.KeyCode.Name == MenuKeyName then
		Library.ToggleUI()
	end
end)

function Library_Function.SetMenuKey(name)
	name = tostring(name):gsub("^Enum%.KeyCode%.", "")
	MenuKeyName = name
	SavedTheme.MenuKey = name
	saveThemeSoon()
	if Library_Function.MenuKeybind then
		Library_Function.MenuKeybind:Set(name) -- keep the control on the page in step
	end
end

Library.DestroyUI = function()
	for _, gui in ipairs({ Library_Function.Gui, Library_Function.NotiGui, Library_Function.HideGui }) do
		pcall(gui.Destroy, gui)
	end
end

if true then
	local button = btnHide -- Assuming this is a TextButton or ImageButton
	local UIS = game:GetService("UserInputService")
	
	local dragging = false
	local dragInput, dragStart, startPos
	local holdTime = 0.1 -- Time to hold before dragging is enabled
	local holdStarted = 0
	
	-- Function to update the button's position
	local function update(input)
		local delta = input.Position - dragStart
		button.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
	end
	
	-- Function to detect the start of dragging (for both mouse and touch)
	local function onInputBegan(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			holdStarted = tick() -- Record the time when holding starts
			dragStart = input.Position
			startPos = button.Position
	
			-- Listen for release to stop dragging
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					holdStarted = 0 -- Reset the hold timer
				end
			end)
		end
	end
	
	-- Function to detect when dragging stops
	local function onInputEnded(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
			holdStarted = 0 -- Reset the hold timer
		end
	end
	
	-- Detect input movement (for both mouse and touch)
	local function onInputChanged(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end
	
	-- Connect the events
	button.InputBegan:Connect(onInputBegan)
	button.InputEnded:Connect(onInputEnded)
	button.InputChanged:Connect(onInputChanged)
	
	-- RenderStepped updates the position while dragging
	RunService.RenderStepped:Connect(function()
		if holdStarted > 0 and (tick() - holdStarted >= holdTime) and not dragging then
			dragging = true
		end
	
		if dragging and dragInput then
			update(dragInput)
		end
	end)
		
end

btnHide.MouseButton1Click:Connect(function() 
	Library.ToggleUI()
end)

local NotiContainer = Instance.new("Frame")
local NotiList = Instance.new("UIListLayout")

NotiContainer.Name = "NotiContainer"
NotiContainer.Parent = Library_Function.NotiGui
NotiContainer.AnchorPoint = Vector2.new(1, 1)
NotiContainer.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
NotiContainer.BackgroundTransparency = 1.000
NotiContainer.Position = UDim2.new(1, -5, 1, -5)
NotiContainer.Size = UDim2.new(0, 350, 1, -10)

NotiList.Name = "NotiList"
NotiList.Parent = NotiContainer
NotiList.SortOrder = Enum.SortOrder.LayoutOrder
NotiList.VerticalAlignment = Enum.VerticalAlignment.Bottom
NotiList.Padding = UDim.new(0, 5)


Library_Function.Gui.Parent = GuiParent
Library_Function.Gui.AncestryChanged:Connect(function(_, parent)
	if not parent then
		pcall(function()
			Library_Function.HideGui:Destroy()
		end)
	end
end)
Library_Function.NotiGui.Parent = GuiParent
Library_Function.HideGui.Parent = GuiParent

function Library_Function.Getcolor(color)
	return {
		math.floor(color.r * 255),
		math.floor(color.g * 255),
		math.floor(color.b * 255)
	}
end

-- Theme values that aren't a plain bound property.
local ButtonGradients = {}
ThemeListeners["Button Color"] = function(color)
	for _, gradient in ipairs(ButtonGradients) do
		gradient.Color = ButtonGradient(color)
	end
end
ThemeListeners["Title Text Color"] = function()
	if Library_Function.RefreshTitle then
		Library_Function.RefreshTitle()
	end
end

-- One theme color, live + saved. Picking an accent preset later resets the accent keys.
function Library_Function.SetThemeColor(key, color)
	getgenv().UIColor[key] = color
	SavedTheme.Colors = SavedTheme.Colors or {}
	SavedTheme.Colors[key] = color3ToList(color)
	saveThemeSoon()
end

-- Accent: every accent key (and its two shades) at once, live + saved.
function Library_Function.SetAccent(accent, presetName)
	for key, value in pairs(accentPalette(accent)) do
		getgenv().UIColor[key] = value
		if SavedTheme.Colors then
			SavedTheme.Colors[key] = nil -- the accent wins over earlier one-off edits of these keys
		end
		if SavedTheme.Rainbow then
			SavedTheme.Rainbow[key] = nil -- a rainbow left running would come back after a reload
		end
		RainbowKeys[key] = nil
	end
	SavedTheme.Accent = color3ToList(accent)
	SavedTheme.Preset = presetName or "Custom"
	saveThemeSoon()
	if Library_Function.OnAccentChanged then
		Library_Function.OnAccentChanged()
	end
end

-- Rainbow: cycles a theme color's hue (keeping its saturation/brightness). Saved per key.
function Library_Function.SetRainbow(key, on)
	if on then
		local h, s, v = getgenv().UIColor[key]:ToHSV()
		RainbowKeys[key] = { s = math.max(s, 0.45), v = math.max(v, 0.6) }
	else
		RainbowKeys[key] = nil
	end
	SavedTheme.Rainbow = SavedTheme.Rainbow or {}
	SavedTheme.Rainbow[key] = on and true or nil
	saveThemeSoon()
end
-- Rainbow for the whole accent at once (every accent key keeps its own shade).
-- Turning it off freezes the accent at the color it had reached and saves that.
function Library_Function.SetAccentRainbow(on)
	if on then
		for key in pairs(accentPalette(getgenv().UIColor["Title Text Color"])) do
			Library_Function.SetRainbow(key, true)
		end
	else
		local frozen = getgenv().UIColor["Title Text Color"]
		Library_Function.SetAccent(frozen, "Custom")
	end
end

-- Back to the shipped theme (Interface Settings > Window > Reset theme).
function Library_Function.ResetTheme()
	for key in pairs(RainbowKeys) do
		RainbowKeys[key] = nil
	end
	for key, value in pairs(DefaultTheme) do
		getgenv().UIColor[key] = value
	end
	for key in pairs(SavedTheme) do
		SavedTheme[key] = nil
	end
	saveThemeSoon()
	if Library_Function.ClearBackground then
		Library_Function.ClearBackground() -- the shipped look has no background picture
	end
end

RunService.Heartbeat:Connect(function()
	if next(RainbowKeys) then
		local hue = (tick() % 6) / 6
		for key, base in pairs(RainbowKeys) do
			getgenv().UIColor[key] = Color3.fromHSV(hue, base.s, base.v)
		end
	end
end)

local libCreateNoti = function(Setting)
	getgenv().TitleNameNoti = Setting.Title or ""; 
	local Description = Setting.Description or Setting.Desc or Setting.Content or ""; 
	local Duration = Setting.Duration or Setting.Timeshow or Setting.Delay or 10;

	local NotiFrame = Instance.new("Frame")
	local Noticontainer = Instance.new("Frame")
	local UICorner = Instance.new("UICorner")
	local Topnoti = Instance.new("Frame")
	local Ruafimg = Instance.new("ImageLabel")
	local RuafimgCorner = Instance.new("UICorner")
	local TextLabelNoti = Instance.new("TextLabel")
	local CloseContainer = Instance.new("Frame")
	local CloseImage = Instance.new("ImageLabel")
	local TextButton = Instance.new("TextButton")
	local TextLabelNoti2 = Instance.new("TextLabel")

	NotiFrame.Name = "NotiFrame"
	NotiFrame.Parent = NotiContainer
	NotiFrame.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
	NotiFrame.BackgroundTransparency = 1.000
	NotiFrame.ClipsDescendants = true
	NotiFrame.Position = UDim2.new(0, 0, 0, 0)
	NotiFrame.Size = UDim2.new(1, 0, 0, 0)
	NotiFrame.AutomaticSize = Enum.AutomaticSize.Y

	Noticontainer.Name = "Noticontainer"
	Noticontainer.Parent = NotiFrame
	Noticontainer.Position = UDim2.new(1, 0, 0, 0)
	Noticontainer.Size = UDim2.new(1, 0, 1, 6)
	Noticontainer.AutomaticSize = Enum.AutomaticSize.Y
	Bind(Noticontainer, "BackgroundColor3", "Background 3 Color")
	UICorner.CornerRadius = UDim.new(0, 4)
	UICorner.Parent = Noticontainer

	Topnoti.Name = "Topnoti"
	Topnoti.Parent = Noticontainer
	Topnoti.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
	Topnoti.BackgroundTransparency = 1.000
	Topnoti.Position = UDim2.new(0, 0, 0, 5)
	Topnoti.Size = UDim2.new(1, 0, 0, 25)

	Ruafimg.Name = "Ruafimg"
	Ruafimg.Parent = Topnoti
	Ruafimg.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
	Ruafimg.BackgroundTransparency = 1.000
	Ruafimg.Position = UDim2.new(0, 5, 0, getgenv().T1 and 5 or 0)
	Ruafimg.Size = UDim2.new(0, getgenv().T1 and 30 or 25, 0, getgenv().T1 and 15 or 25)
	Bind(Ruafimg, "Image", "Logo Image")
	Ruafimg.ScaleType = Enum.ScaleType.Fit -- any logo shape, never stretched

	RuafimgCorner.CornerRadius = UDim.new(1, 0)
	RuafimgCorner.Name = "RuafimgCorner"
	RuafimgCorner.Parent = Ruafimg
	
	local colorR = tostring(Library_Function.Getcolor(getgenv().UIColor['Title Text Color'])[1])
	local colorG = tostring(Library_Function.Getcolor(getgenv().UIColor['Title Text Color'])[2])
	local colorB = tostring(Library_Function.Getcolor(getgenv().UIColor['Title Text Color'])[3])
	local color = colorR .. ',' .. colorG .. ',' .. colorB
    TextLabelNoti.Text = "<font color=\"rgb(" .. tostring(color or "140,172,68") .. ")\">" .. tostring(getgenv().HubName or "Peridot") .. "</font> " .. tostring(getgenv().TitleNameNoti or "")
    
	TextLabelNoti.Name = "TextLabelNoti"
	TextLabelNoti.Parent = Topnoti
	TextLabelNoti.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
	TextLabelNoti.BackgroundTransparency = 1.000
	TextLabelNoti.Position = UDim2.new(0, getgenv().T1 and 40 or 35, 0, 0)
	TextLabelNoti.Size = UDim2.new(1, getgenv().T1 and -40 or -35, 1, 0)
	TextLabelNoti.Font = Enum.Font.GothamBold
	TextLabelNoti.TextSize = 14.000
	TextLabelNoti.TextWrapped = true
	TextLabelNoti.TextXAlignment = Enum.TextXAlignment.Left
	TextLabelNoti.RichText = true
	Bind(TextLabelNoti, "TextColor3", "GUI Text Color")

	CloseContainer.Name = "CloseContainer"
	CloseContainer.Parent = Topnoti
	CloseContainer.AnchorPoint = Vector2.new(1, 0.5)
	CloseContainer.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
	CloseContainer.BackgroundTransparency = 1.000
	CloseContainer.Position = UDim2.new(1, -4, 0.5, 0)
	CloseContainer.Size = UDim2.new(0, 22, 0, 22)

	CloseImage.Name = "CloseImage"
	CloseImage.Parent = CloseContainer
	CloseImage.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
	CloseImage.BackgroundTransparency = 1.000
	CloseImage.Size = UDim2.new(1, 0, 1, 0)
	CloseImage.Image = "rbxassetid://3926305904"
	CloseImage.ImageRectOffset = Vector2.new(284, 4)
	CloseImage.ImageRectSize = Vector2.new(24, 24)
	Bind(CloseImage, "ImageColor3", "Search Icon Color")

	TextButton.Parent = CloseContainer
	TextButton.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
	TextButton.BackgroundTransparency = 1.000
	TextButton.Size = UDim2.new(1, 0, 1, 0)
	TextButton.Font = Enum.Font.SourceSans
	TextButton.Text = ""
	TextButton.TextColor3 = Color3.fromRGB(0, 0, 0)
	TextButton.TextSize = 14.000

	if Description then
		TextLabelNoti2.Name = 'TextColor'
		TextLabelNoti2.Parent = Noticontainer
		TextLabelNoti2.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
		TextLabelNoti2.BackgroundTransparency = 1.000
		TextLabelNoti2.Position = UDim2.new(0, 10, 0, 35)
		TextLabelNoti2.Size = UDim2.new(1, -15, 0, 0)
		TextLabelNoti2.Font = Enum.Font.GothamBold
		TextLabelNoti2.Text = Description
		TextLabelNoti2.TextSize = 14.000
		TextLabelNoti2.TextXAlignment = Enum.TextXAlignment.Left
		TextLabelNoti2.RichText = true
		Bind(TextLabelNoti2, "TextColor3", "Text Color")
		TextLabelNoti2.AutomaticSize = Enum.AutomaticSize.Y
		TextLabelNoti2.TextWrapped = true
	end

	local function remove()
		TweenService:Create(Noticontainer, TI("Tween Animation 1 Speed"), {
			Position = UDim2.new(1, 0, 0, 0)
		}):Play()
		wait(.25)
		NotiFrame:Destroy()
	end

	TweenService:Create(Noticontainer, TI("Tween Animation 1 Speed"), {
		Position = UDim2.new(0, 0, 0, 0)
	}):Play()

	TextButton.MouseEnter:Connect(function()
		TweenService:Create(CloseImage, TI("Tween Animation 1 Speed"), {
			ImageColor3 = getgenv().UIColor["Search Icon Highlight Color"]
		}):Play()
	end)

	TextButton.MouseLeave:Connect(function()
		TweenService:Create(CloseImage, TI("Tween Animation 1 Speed"), {
			ImageColor3 = getgenv().UIColor["Search Icon Color"]
		}):Play()
	end)

	TextButton.MouseButton1Click:Connect(function()
		wait(.25)
		remove()
	end)

	spawn(function()
		wait(Duration)
		remove()
	end)

end

function Library:Notify(Setting, bypass)
	if not getgenv().Config or bypass then
		local s, e = pcall(function()
			libCreateNoti(Setting)
		end)
		if e then
			print(e)
		end
	end
end

function Library:CreateWindow(Setting)
    local TitleNameMain = Setting.Title or "Peridot"
    getgenv().MainDesc = Setting.Desc or Setting.Subtitle or ""
    local SidebarTitle = Setting.SidebarTitle or TitleNameMain -- header above the tab list (the game name)
    -- Page switchers, so the gear can open Interface Settings and then go back to where you were.
    local CurrentSelect, PreviousSelect, UISettingsSelect, UISettingsPage
    local HiddenTabs = {} -- tab buttons kept out of the sidebar (Interface Settings)
    local SubTabRestorers = {} -- re-hide other sub-tabs' sections after a search is cleared
    
    if Setting.Image then
        getgenv().UIColor["Logo Image"] = Setting.Image
    end
    
	local djtmemay = false
	cac = false

	local Main = Instance.new("Frame")
	local maingui = Instance.new("ImageLabel")
	local MainCorner = Instance.new("UICorner")
	local TopMain = Instance.new("Frame")
	local Ruafimg = Instance.new("ImageLabel")
	local TextLabelMain = Instance.new("TextLabel")
	local PageControl = Instance.new("Frame")
	local UICorner = Instance.new("UICorner")
	local ControlList = Instance.new("ScrollingFrame")
	local UIListLayout = Instance.new("UIListLayout")
	local ControlTitle = Instance.new("TextLabel")
	local MainPage = Instance.new("Frame")
	local UIPage = Instance.new("UIPageLayout")
	local Concacontainer = Instance.new("Frame")
	local Concacmain = Instance.new("Frame")
	local MainContainer

	Main.Name = "Main"
	Main.Parent = Library_Function.Gui
	Main.BackgroundColor3 = Color3.fromRGB(42, 42, 42)
	Main.BackgroundTransparency = 1.000
	Main.Position = UDim2.new(0.5, 0, 0.5, 0)
	Main.AnchorPoint = Vector2.new(0.5, 0.5)
	Main.Size = UDim2.new(0, 629, 0, 359)

	makeDraggable(Main, Main)

	local WindowScale = Instance.new("UIScale") -- pop-in / pop-out on open and close
	WindowScale.Name = "WindowScale"
	WindowScale.Parent = Main
	Library_Function.WindowScale = WindowScale

	maingui.Name = "maingui"
	maingui.Parent = Main
	maingui.AnchorPoint = Vector2.new(0.5, 0.5)
	maingui.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
	maingui.BackgroundTransparency = 1.000
	maingui.Position = UDim2.new(0.5, 0, 0.5, 0)
	maingui.Selectable = true
	maingui.Size = UDim2.new(1, 30, 1, 30)
	maingui.Image = "rbxassetid://8068653048"
	maingui.ScaleType = Enum.ScaleType.Slice
	maingui.SliceCenter = Rect.new(15, 15, 175, 175)
	maingui.SliceScale = 1.300
	Bind(maingui, "ImageColor3", "Border Color")
	maingui.ImageTransparency = 1

	maingui.ImageColor3 = getgenv().UIColor['Title Text Color']

	-- Everything visible except the shadow lives in a CanvasGroup, so the window can fade as
	-- one piece (GroupTransparency). A CanvasGroup clips to its bounds, so it is 4px larger
	-- than the window on every side and the container sits inside, leaving room for its outline.
	local Body = Instance.new("CanvasGroup")
	Body.Name = "Body"
	Body.Parent = Main
	Body.AnchorPoint = Vector2.new(0.5, 0.5)
	Body.Position = UDim2.new(0.5, 0, 0.5, 0)
	Body.Size = UDim2.new(1, 8, 1, 8)
	Body.BackgroundTransparency = 1
	Body.BorderSizePixel = 0
	Library_Function.WindowFade = Body

	MainContainer = Instance.new("ImageLabel")
	MainContainer.Name = "MainContainer"
	MainContainer.Parent = Body
	MainContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	MainContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
	Bind(MainContainer, "BackgroundColor3", "Background Main Color")
	Bind(MainContainer, "BackgroundTransparency", "Background Main Transparency")
	MainContainer.Size = UDim2.new(1, -8, 1, -8)
	Library_Function.MainContainer = MainContainer -- SetBackground draws on it
	if Library_Function.RestoreBackground then
		pcall(Library_Function.RestoreBackground) -- the picture the last session (or the default theme) ended with
	end

	local uistr = Instance.new("UIStroke", MainContainer);
	uistr.Thickness = 1;
	Bind(uistr, "Color", "Outline Color")

	local uigradient = Instance.new("UIGradient", MainContainer);
	uigradient.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 200))
	}
	uigradient.Rotation = 90
	uigradient.Transparency = NumberSequence.new(0) -- solid dark frame; the game must never show through the window

	getgenv().ReadyForGuiLoaded = true
	
	MainCorner.CornerRadius = UDim.new(0, 5)
	MainCorner.Name = "MainCorner"
	MainCorner.Parent = MainContainer

	Concacontainer.Name = "Concacontainer"
	Concacontainer.Parent = MainContainer
	Concacontainer.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Concacontainer.BackgroundTransparency = 1.000
	Concacontainer.ClipsDescendants = true
	Concacontainer.Position = UDim2.new(0, 0, 0, 30)
	Concacontainer.Size = UDim2.new(1, 0, 1, -30)
	
	Concacmain.Name = "Concacmain"
	Concacmain.Parent = Concacontainer
	Concacmain.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Concacmain.BackgroundTransparency = 1.000
	Concacmain.Selectable = true
	Concacmain.Size = UDim2.new(1, 0, 1, 0)
	
	TopMain.Name = "TopMain"
	TopMain.Parent = MainContainer
	TopMain.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	TopMain.BackgroundTransparency = 1.000
	TopMain.Size = UDim2.new(1, 0, 0, 25)
	
	local TopStroke = Instance.new("Frame", TopMain)
	TopStroke.Name = "TopStroke"
	Bind(TopStroke, "BackgroundColor3", "Outline Color")
	TopStroke.BackgroundTransparency = 0.6
	TopStroke.BorderSizePixel = 0
	TopStroke.Position = UDim2.new(0, 0, 1, -1)
	TopStroke.Size = UDim2.new(1, 0, 0, 1)
	
	Ruafimg.Name = "Ruafimg"
	Ruafimg.Parent = TopMain
	Ruafimg.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Ruafimg.BackgroundTransparency = 1.000
	Ruafimg.Position = UDim2.new(0, 5, 0, 0)
	Ruafimg.Size = UDim2.new(0, 25, 0, 25)
	Bind(Ruafimg, "Image", "Logo Image")
	Ruafimg.ScaleType = Enum.ScaleType.Fit -- any logo shape, never stretched

	TextLabelMain.Name = "TextLabelMain"
	TextLabelMain.Parent = TopMain
	TextLabelMain.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
	TextLabelMain.BackgroundTransparency = 1.000
	TextLabelMain.Position = UDim2.new(0, 35, 0, 0) -- top-left, right after the logo
	TextLabelMain.Size = UDim2.new(1, -70, 1, 0) -- leaves room for the gear on the right
	TextLabelMain.Font = Enum.Font.GothamBold
	TextLabelMain.RichText = true
	TextLabelMain.TextSize = 16.000
	TextLabelMain.TextWrapped = true
	TextLabelMain.TextXAlignment = Enum.TextXAlignment.Left
	Bind(TextLabelMain, "TextColor3", "GUI Text Color")

	local colorR = tostring(Library_Function.Getcolor(getgenv().UIColor['Title Text Color'])[1])
	local colorG = tostring(Library_Function.Getcolor(getgenv().UIColor['Title Text Color'])[2])
	local colorB = tostring(Library_Function.Getcolor(getgenv().UIColor['Title Text Color'])[3])
	local color = colorR .. ',' .. colorG .. ',' .. colorB
    TextLabelMain.Text = "<font color=\"rgb(" .. tostring(color or "140,172,68") .. ")\">" .. tostring(TitleNameMain or "Peridot") .. "</font> " .. tostring(getgenv().MainDesc or "")

	-- Rebuilt when the accent changes (the title color lives inside rich text).
	Library_Function.RefreshTitle = function()
		local c = Library_Function.Getcolor(getgenv().UIColor["Title Text Color"])
		TextLabelMain.Text = "<font color=\"rgb(" .. c[1] .. "," .. c[2] .. "," .. c[3] .. ")\">" .. tostring(TitleNameMain or "Peridot") .. "</font> " .. tostring(getgenv().MainDesc or "")
	end

	-- Settings gear, top right: toggles the Interface Settings page (theme, window options).
	local SettingsGear = Instance.new("ImageButton")
	SettingsGear.Name = "SettingsGear"
	SettingsGear.Parent = TopMain
	SettingsGear.AnchorPoint = Vector2.new(1, 0.5)
	SettingsGear.Position = UDim2.new(1, -8, 0.5, 0)
	SettingsGear.Size = UDim2.new(0, 20, 0, 20)
	SettingsGear.BackgroundTransparency = 1
	SettingsGear.AutoButtonColor = false
	SettingsGear.Image = "rbxassetid://7397332215"
	Bind(SettingsGear, "ImageColor3", "Setting Icon Color")
	SettingsGear.ZIndex = 2
	SettingsGear.MouseEnter:Connect(function()
		TweenService:Create(SettingsGear, TI("Tween Animation 3 Speed"), {
			ImageColor3 = getgenv().UIColor["Search Icon Highlight Color"]
		}):Play()
	end)
	SettingsGear.MouseLeave:Connect(function()
		TweenService:Create(SettingsGear, TI("Tween Animation 3 Speed"), {
			ImageColor3 = getgenv().UIColor["Setting Icon Color"]
		}):Play()
	end)
	SettingsGear.MouseButton1Click:Connect(function()
		if Library_Function.ToggleUISettings then
			Library_Function.ToggleUISettings()
		end
		TweenService:Create(SettingsGear, DisableAnimation and TweenInfo.new(0)
			or TweenInfo.new(.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Rotation = SettingsGear.Rotation + 180
		}):Play()
	end)

	PageControl.Name = "Background1"
	PageControl.Parent = Concacmain
	PageControl.Position = UDim2.new(0, 5, 0, 0)
	PageControl.Size = UDim2.new(0, 180, 0, 325)
	Bind(PageControl, "BackgroundColor3", "Sidebar Color")
	Bind(PageControl, "BackgroundTransparency", "Background 1 Transparency")

	local pageControlStroke = Instance.new("UIStroke", PageControl)
	Bind(pageControlStroke, "Color", "Outline Color")
	pageControlStroke.Thickness = 1

	-- the gradient only shades the Sidebar color (darker at the top), it never sets a color of its own
	local pageControlGradient = Instance.new("UIGradient", PageControl)
	pageControlGradient.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, Color3.fromRGB(188, 188, 188)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255))
	}
	pageControlGradient.Rotation = 90
	pageControlGradient.Transparency = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.03),
		NumberSequenceKeypoint.new(1, 0.06)
	}

	UICorner.CornerRadius = UDim.new(0, 4)
	UICorner.Parent = PageControl

	ControlList.Name = "ControlList"
	ControlList.Parent = PageControl
	ControlList.Active = true
	ControlList.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
	ControlList.BackgroundTransparency = 1.000
	ControlList.BorderColor3 = Color3.fromRGB(27, 42, 53)
	ControlList.BorderSizePixel = 0
	ControlList.Position = UDim2.new(0, 0, 0, 58) -- below the game name (0-25) and the search bar (28-53)
	ControlList.Size = UDim2.new(1, -5, 1, -58)
	ControlList.BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
	ControlList.CanvasSize = UDim2.new(0, 0, 0, 0)
	ControlList.ScrollBarThickness = 5
	ControlList.TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"

	UIListLayout.Parent = ControlList
	UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	UIListLayout.Padding = UDim.new(0, 5)

	ControlTitle.Name = "GUITextColor"
	ControlTitle.Parent = PageControl
	ControlTitle.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
	ControlTitle.BackgroundTransparency = 1.000
	ControlTitle.Position = UDim2.new(0, 5, 0, 0)
	ControlTitle.Size = UDim2.new(1, -10, 0, 25)
	ControlTitle.Font = Enum.Font.GothamBold
	ControlTitle.Text = SidebarTitle
	ControlTitle.TextSize = 14.000
	ControlTitle.TextXAlignment = Enum.TextXAlignment.Left
	ControlTitle.TextTruncate = Enum.TextTruncate.AtEnd -- long game names end in "..."
	Bind(ControlTitle, "TextColor3", "GUI Text Color")

	local PageSearch = Instance.new("Frame")
	local PageSearchCorner = Instance.new("UICorner")
	local SearchFrame = Instance.new("Frame")
	local SearchIcon = Instance.new("ImageLabel")
	local SearchBox = Instance.new("TextBox")

	PageSearch.Name = "PageSearch"
	PageSearch.Parent = PageControl
	PageSearch.AnchorPoint = Vector2.new(1, 0)
	PageSearch.BackgroundColor3 = Color3.fromRGB(38, 38, 46)
	PageSearch.Position = UDim2.new(1, -5, 0, 28) -- under the game name
	PageSearch.Size = UDim2.new(0, 170, 0, 25)
	PageSearch.ClipsDescendants = true

	PageSearchCorner.Parent = PageSearch
	PageSearchCorner.CornerRadius = UDim.new(0, 4)

	SearchFrame.Name = "SearchFrame"
	SearchFrame.Parent = PageSearch
	SearchFrame.BackgroundColor3 = Color3.fromRGB(163, 162, 165)
	SearchFrame.BackgroundTransparency = 1
	SearchFrame.Size = UDim2.new(0, 25, 1, 0)

	SearchIcon.Name = "SearchIcon"
	SearchIcon.Parent = SearchFrame
	SearchIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	SearchIcon.BackgroundColor3 = Color3.fromRGB(163, 162, 165)
	SearchIcon.BackgroundTransparency = 1
	SearchIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
	SearchIcon.Size = UDim2.new(0, 16, 0, 16)
	SearchIcon.Image = "rbxassetid://8154282545"
	SearchIcon.ImageColor3 = Color3.fromRGB(240, 240, 230)

    SearchBox.Name = "SearchBox"
    SearchBox.Parent = PageSearch
    SearchBox.Active = true
    SearchBox.BackgroundColor3 = Color3.fromRGB(163, 162, 165)
    SearchBox.BackgroundTransparency = 1
    SearchBox.CursorPosition = -1
    SearchBox.Position = UDim2.new(0, 30, 0, 0)
    SearchBox.Size = UDim2.new(1, -30, 1, 0)
    SearchBox.Font = Enum.Font.GothamBold
    SearchBox.PlaceholderColor3 = Color3.fromRGB(170, 170, 160)
    SearchBox.PlaceholderText = "Search functions..." -- fits the 140px box; the longer text got cut off
    SearchBox.Text = ""
    SearchBox.TextColor3 = Color3.fromRGB(235, 235, 230)
    SearchBox.TextSize = 14
    SearchBox.TextXAlignment = Enum.TextXAlignment.Left

	MainPage.Name = "MainPage"
	MainPage.Parent = Concacmain
	MainPage.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
	MainPage.BackgroundTransparency = 1.000
	MainPage.ClipsDescendants = true
	MainPage.Position = UDim2.new(0, 190, 0, 0)
	MainPage.Size = UDim2.new(0, 435, 0, 325)

	UIPage.Name = "UIPage"
	UIPage.Parent = MainPage
	UIPage.FillDirection = Enum.FillDirection.Vertical
	UIPage.SortOrder = Enum.SortOrder.LayoutOrder
	UIPage.EasingDirection = Enum.EasingDirection.InOut
	UIPage.EasingStyle = Enum.EasingStyle.Quart
	UIPage.Padding = UDim.new(0, 10)
	Bind(UIPage, "TweenTime", "Tween Animation 1 Speed")

	UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		ControlList.CanvasSize = UDim2.new(0, 0, 0, UIListLayout.AbsoluteContentSize.Y + 5)
	end)

	local Shadow = Instance.new("ImageLabel", Main)
	Shadow.Name = "Shadow"
	Library_Function.WindowShadow = Shadow -- fades with the window
	Shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	Shadow.BackgroundColor3 = Color3.fromRGB(163, 162, 165)
	Shadow.BackgroundTransparency = 1
	Shadow.Position = UDim2.new(0.5, 0, 0.5, 0)
	Shadow.Size = UDim2.new(1, 40, 1, 40)
	Shadow.ZIndex = 0
	Shadow.Image = "rbxassetid://5028857084"
	Shadow.ImageTransparency = WindowShadowAlpha
	Shadow.ScaleType = Enum.ScaleType.Slice
	Shadow.SliceCenter = Rect.new(24, 24, 276, 276)

    -- Thêm biến để lưu thông tin section
    local sectionInfo = {}
    
    -- Tạo hàm GlobalSearch nếu chưa tồn tại
    local GlobalSearch
    do -- rebuilt per window: a global from an earlier run would point at a destroyed GUI
        GlobalSearch = function(searchText)
            searchText = string.lower(searchText)
            
            if searchText == "" then
                -- Hiển thị tất cả như cũ
                for _, control in pairs(getgenv().AllControls) do
                    control.TabButton.Visible = not HiddenTabs[control.TabButton]
                    control.Section.Visible = true
                    control.Element.Visible = true
                end
                -- Hiển thị tất cả tab
                for _, tab in pairs(ControlList:GetChildren()) do
                    if not tab:IsA('UIListLayout') then
                        tab.Visible = not HiddenTabs[tab]
                    end
                end
                for _, restore in ipairs(SubTabRestorers) do
                    restore()
                end
                return
            end
            
            -- Ẩn tất cả trước
            for _, control in pairs(getgenv().AllControls) do
                control.Section.Visible = false
                control.Element.Visible = false
            end
            
            -- Ẩn tất cả tab
            for _, tab in pairs(ControlList:GetChildren()) do
                if not tab:IsA('UIListLayout') then
                    tab.Visible = false
                end
            end
            
            -- Tạo bản đồ section
            local sectionsWithElements = {}
            local elementsInSection = {}
            
            -- Phân tích từng control
            for _, control in pairs(getgenv().AllControls) do
                local elementName = string.lower(control.Name or "")
                local sectionName = string.lower(control.SectionName or "")
                
                -- Kiểm tra phần tử (sử dụng string.find thay vì string.match)
                local elementFound = string.find(elementName, searchText, 1, true) ~= nil
                -- Kiểm tra section
                local sectionFound = string.find(sectionName, searchText, 1, true) ~= nil
                
                -- Tạo bản đồ section
                if not elementsInSection[control.Section] then
                    elementsInSection[control.Section] = {}
                end
                table.insert(elementsInSection[control.Section], {
                    control = control,
                    elementFound = elementFound,
                    sectionFound = sectionFound
                })
                
                -- Đánh dấu section có phần tử khớp
                if elementFound then
                    sectionsWithElements[control.Section] = true
                end
            end
            
            -- Xử lý hiển thị
            local foundTabs = {}
            
            for section, elements in pairs(elementsInSection) do
                local shouldShowSection = false
                local hasElementMatch = false
                
                -- Kiểm tra section có khớp không
                for _, elementInfo in ipairs(elements) do
                    if elementInfo.sectionFound then
                        shouldShowSection = true
                    end
                    if elementInfo.elementFound then
                        hasElementMatch = true
                    end
                end
                
                -- Logic hiển thị
                for _, elementInfo in ipairs(elements) do
                    local control = elementInfo.control
                    
                    if elementInfo.elementFound then
                        -- Phần tử khớp: hiển thị phần tử
                        control.Element.Visible = true
                        
                        -- Nếu section cũng khớp hoặc có phần tử khớp: hiện section
                        if elementInfo.sectionFound or hasElementMatch then
                            control.Section.Visible = true
                        end
                        
                        foundTabs[control.TabName] = true
                        control.TabButton.Visible = true
                    elseif elementInfo.sectionFound and not hasElementMatch then
                        -- Section khớp nhưng không có phần tử khớp: chỉ hiện section
                        control.Section.Visible = true
                        control.Element.Visible = false
                        
                        foundTabs[control.TabName] = true
                        control.TabButton.Visible = true
                    end
                end
            end
            
            -- Hiển thị các tab có kết quả
            for tabName, _ in pairs(foundTabs) do
                for _, tab in pairs(ControlList:GetChildren()) do
                    if not tab:IsA('UIListLayout') and string.find(tab.Name, tabName, 1, true) then
                        tab.Visible = true
                    end
                end
            end
            
            -- Nếu không tìm thấy gì cả, hiển thị thông báo
            if not next(foundTabs) then
                -- Có thể thêm thông báo "Không tìm thấy kết quả" ở đây nếu muốn
            end
        end
    end
    
    -- Kết nối sự kiện search (giữ nguyên)
    SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        GlobalSearch(SearchBox.Text)
    end)

	local Main_Function = {}

	local LayoutOrderBut = -1
	local LayoutOrder = -1
	local PageCounter = 1

	function Main_Function:AddTab(PageName, TabOptions)
		local Hidden = TabOptions and TabOptions.Hidden -- no sidebar button (Interface Settings, opened by the gear)

		local Page_Name = tostring(PageName)
		local Page_Title = Page_Name

		LayoutOrder = LayoutOrder + 1
		LayoutOrderBut = LayoutOrderBut + 1

		--Control 
		local PageName = Instance.new("Frame")
		local Frame = Instance.new("Frame")
		local TabNameCorner = Instance.new("UICorner")
		local Line = Instance.new("Frame")
		local InLine = Instance.new("Frame")
		local LineCorner = Instance.new("UICorner")
		local TabTitleContainer = Instance.new("Frame")
		local TabTitle = Instance.new("TextLabel")
		local PageButton = Instance.new("TextButton")


		PageName.Name = Page_Name .. "_Control"
		PageName.Parent = ControlList
		PageName.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
		PageName.BackgroundTransparency = 1.000
		PageName.Size = UDim2.new(1, -10, 0, 25)
		PageName.LayoutOrder = LayoutOrderBut
		if Hidden then
			PageName.Visible = false
			PageName.LayoutOrder = 100000
			HiddenTabs[PageName] = true
		end

		Frame.Parent = PageName
		Frame.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
		Frame.BackgroundTransparency = 1.000
		Frame.Position = UDim2.new(0, 5, 0, 0)
		Frame.Size = UDim2.new(1, -5, 1, 0)

		TabNameCorner.CornerRadius = UDim.new(0, 4)
		TabNameCorner.Name = "TabNameCorner"
		TabNameCorner.Parent = Frame

		Line.Name = "Line"
		Line.Parent = Frame
		Line.AnchorPoint = Vector2.new(0, 0.5)
		Line.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
		Line.BackgroundTransparency = 1.000
		Line.Position = UDim2.new(0, 0, 0.5, 0)
		Line.Size = UDim2.new(0, 14, 1, 0)

		InLine.Name = "PageInLine"
		InLine.Parent = Line
		InLine.AnchorPoint = Vector2.new(0.5, 0.5)
		InLine.BorderSizePixel = 0
		InLine.Position = UDim2.new(0.5, 0, 0.5, 0)
		InLine.Size = UDim2.new(1, -10, 1, -10)
		Bind(InLine, "BackgroundColor3", "Page Selected Color")
		InLine.BackgroundTransparency = 1.000

		LineCorner.Name = "LineCorner"
		LineCorner.Parent = InLine

		TabTitleContainer.Name = "TabTitleContainer"
		TabTitleContainer.Parent = Frame
		TabTitleContainer.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
		TabTitleContainer.BackgroundTransparency = 1.000
		TabTitleContainer.Position = UDim2.new(0, 15, 0, 0)
		TabTitleContainer.Size = UDim2.new(1, -15, 1, 0)

		TabTitle.Name = "GUITextColor"
		TabTitle.Parent = TabTitleContainer
		TabTitle.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
		TabTitle.BackgroundTransparency = 1.000
		TabTitle.Size = UDim2.new(1, 0, 1, 0)
		TabTitle.Font = Enum.Font.GothamBold
		TabTitle.Text = Page_Name
		TabTitle.TextColor3 = Color3.fromRGB(230, 230, 230)
		TabTitle.TextSize = 14.000
		TabTitle.TextXAlignment = Enum.TextXAlignment.Left
		Bind(TabTitle, "TextColor3", "GUI Text Color")

		PageButton.Name = "PageButton"
		PageButton.Parent = PageName
		PageButton.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
		PageButton.BackgroundTransparency = 1.000
		PageButton.Size = UDim2.new(1, 0, 1, 0)
		PageButton.Font = Enum.Font.SourceSans
		PageButton.Text = ""
		PageButton.TextColor3 = Color3.fromRGB(0, 0, 0)
		PageButton.TextSize = 14.000

		-- Container

		local PageContainer = Instance.new("Frame")
		local UICorner = Instance.new("UICorner")
		local PageTitle = Instance.new("TextLabel")
		local PageList = Instance.new("ScrollingFrame")
		local Pagelistlayout = Instance.new("UIListLayout")

		local CurrentPage = PageCounter
		PageCounter = PageCounter + 1
		PageContainer.Name = "Page" .. CurrentPage
		PageContainer.Parent = MainPage
		Bind(PageContainer, "BackgroundColor3", "Background 1 Color")
		PageContainer.Position = UDim2.new(0, 190, 0, 30)
		PageContainer.Size = UDim2.new(0, 435, 0, 325)
		PageContainer.LayoutOrder = Hidden and 100000 or LayoutOrder -- never the page shown at start
		Bind(PageContainer, "BackgroundTransparency", "Background 1 Transparency")

		UICorner.CornerRadius = UDim.new(0, 4)
		UICorner.Parent = PageContainer

		PageTitle.Name = "GUITextColor"
		PageTitle.Parent = PageContainer
		PageTitle.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
		PageTitle.BackgroundTransparency = 1.000
		PageTitle.Position = UDim2.new(0, 5, 0, 0)
		PageTitle.Size = UDim2.new(1, 0, 0, 25)
		PageTitle.Font = Enum.Font.GothamBold
		PageTitle.Text = Page_Title
		PageTitle.TextSize = 16.000
		PageTitle.TextXAlignment = Enum.TextXAlignment.Left
		Bind(PageTitle, "TextColor3", "GUI Text Color")

		PageList.Name = "PageList"
		PageList.Parent = PageContainer
		PageList.Active = true
		PageList.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
		PageList.BackgroundTransparency = 1.000
		PageList.BorderColor3 = Color3.fromRGB(27, 42, 53)
		PageList.BorderSizePixel = 0
		PageList.Position = UDim2.new(0, 5, 0, 30)
		PageList.Size = UDim2.new(1, -10, 1, -30)
		PageList.BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
		PageList.ScrollBarThickness = 5
		PageList.TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
		PageList.ScrollingEnabled = true
		PageList.VerticalScrollBarInset = Enum.ScrollBarInset.Always

		Pagelistlayout.Name = "Pagelistlayout"
		Pagelistlayout.Parent = PageList
		Pagelistlayout.SortOrder = Enum.SortOrder.LayoutOrder
		Pagelistlayout.Padding = UDim.new(0, 5)
		-- Room for the sections' 1px outline: it's drawn outside each section, and the
		-- scroll area clipped it on the left, the top of the first and the bottom of the last.
		local PageListPadding = Instance.new("UIPadding")
		PageListPadding.PaddingTop = UDim.new(0, 2)
		PageListPadding.PaddingBottom = UDim.new(0, 2)
		PageListPadding.PaddingLeft = UDim.new(0, 2)
		PageListPadding.Parent = PageList
		Pagelistlayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			PageList.CanvasSize = UDim2.new(0, 0, 0, Pagelistlayout.AbsoluteContentSize.Y + 4)
		end)

		-- Sub-tab state: which sub-tab owns each section frame, and which one is showing.
		local SectionOwner, ActiveSubTab = {}, nil

		local PageSearch = Instance.new("Frame")
		local PageSearchCorner = Instance.new("UICorner")
		local SearchFrame = Instance.new("Frame")
		local SearchIcon = Instance.new("ImageLabel")
		local SearchButton = Instance.new("TextButton")
		local SearchBox = Instance.new("TextBox")

		PageSearch.Name = "Page Search"
		PageSearch.Parent = PageContainer
		PageSearch.AnchorPoint = Vector2.new(1, 0)
		Bind(PageSearch, "BackgroundColor3", "Background 2 Color")
		PageSearch.Position = UDim2.new(1, -5, 0, 5)
		PageSearch.Size = UDim2.new(0, 20, 0, 20)
		PageSearch.ClipsDescendants = true

		PageSearchCorner.CornerRadius = UDim.new(0, 2)
		PageSearchCorner.Name = "PageSearchCorner"
		PageSearchCorner.Parent = PageSearch

		SearchFrame.Name = "SearchFrame"
		SearchFrame.Parent = PageSearch
		SearchFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		SearchFrame.BackgroundTransparency = 1.000
		SearchFrame.Size = UDim2.new(0, 20, 0, 20)

		SearchIcon.Name = "SearchIcon"
		SearchIcon.Parent = SearchFrame
		SearchIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		SearchIcon.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		SearchIcon.BackgroundTransparency = 1.000
		SearchIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
		SearchIcon.Size = UDim2.new(0, 16, 0, 16)
		SearchIcon.Image = "rbxassetid://8154282545"
		Bind(SearchIcon, "ImageColor3", "Search Icon Color")

		SearchButton.Name = "Search Button"
		SearchButton.Parent = SearchFrame
		SearchButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		SearchButton.BackgroundTransparency = 1.000
		SearchButton.Size = UDim2.new(1, 0, 1, 0)
		SearchButton.Font = Enum.Font.SourceSans
		SearchButton.Text = ""
		SearchButton.TextColor3 = Color3.fromRGB(0, 0, 0)
		SearchButton.TextSize = 14.000

		SearchBox.Name = "Search Box"
		SearchBox.Parent = PageSearch
		SearchBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		SearchBox.BackgroundTransparency = 1.000
		SearchBox.Position = UDim2.new(0, 30, 0, 0)
		SearchBox.Size = UDim2.new(1, -30, 1, 0)
		SearchBox.Font = Enum.Font.GothamBold
		SearchBox.Text = ""
		SearchBox.TextSize = 14.000
		SearchBox.TextXAlignment = Enum.TextXAlignment.Left
		SearchBox.PlaceholderText = "Search Section name"
		Bind(SearchBox, "PlaceholderColor3", "Placeholder Text Color")
		Bind(SearchBox, "TextColor3", "Text Color")
		
		local Openned = false 

		SearchButton.MouseEnter:Connect(function()
			TweenService:Create(SearchIcon, TI("Tween Animation 3 Speed"), {
				ImageColor3 = getgenv().UIColor["Search Icon Highlight Color"]
			}):Play()
		end)

		SearchButton.MouseLeave:Connect(function()
			TweenService:Create(SearchIcon, TI("Tween Animation 3 Speed"), {
				ImageColor3 = getgenv().UIColor["Search Icon Color"]
			}):Play()
		end)

		SearchButton.MouseButton1Click:Connect(function()
			Openned = not Openned
			local size = Openned and UDim2.new(0, 175, 0, 20) or  UDim2.new(0, 20, 0, 20)
			game.TweenService:Create(PageSearch, TI("Tween Animation 2 Speed"), {
				Size = size
			}):Play()
		end)

		local function hideOtherFrame()
			for i, v in next, PageList:GetChildren() do 
				if v:IsA('GuiObject') then -- UIPadding and other layout children have no Visible
					v.Visible = false
				end
			end
		end
		
		local function showFrameName()
			for i, v in pairs(PageList:GetChildren()) do
				if v:IsA('GuiObject') then
					local inActiveSubTab = SectionOwner[v] == nil or SectionOwner[v] == ActiveSubTab
					if inActiveSubTab and string.find(string.lower(v.Name), string.lower(SearchBox.Text)) then
						v.Visible = true
					end
				end
			end
		end
		
		SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
			hideOtherFrame()
			showFrameName()
		end)

		for i, v in pairs(ControlList:GetChildren()) do
			if not (v:IsA('UIListLayout')) then
				if i == 2 then 
					v.Frame.Line.PageInLine.BackgroundTransparency = 0
				end
			end
		end

		local function selectPage()
			if tostring(UIPage.CurrentPage) == PageContainer.Name then
				return
			end
			CurrentSelect = selectPage

			for i, v in pairs(MainPage:GetChildren()) do
				if v:IsA('GuiObject') then
					v.Visible = false
				end
			end

			PageContainer.Visible = true 
			UIPage:JumpTo(PageContainer)

			for i, v in next, ControlList:GetChildren() do
				if not (v:IsA('UIListLayout')) then
					if v.Name == Page_Name .. "_Control" then 
						TweenService:Create(v.Frame.Line.PageInLine, TI("Tween Animation 1 Speed"), {
							BackgroundTransparency = 0
						}):Play()
					else
						TweenService:Create(v.Frame.Line.PageInLine, TI("Tween Animation 1 Speed"), {
							BackgroundTransparency = 1
						}):Play()
					end
				end
			end
		end
		PageButton.MouseButton1Click:Connect(selectPage)
		if Hidden then
			UISettingsSelect = selectPage
		elseif not CurrentSelect then
			CurrentSelect = selectPage -- the first page is the one showing at start
		end

		local pageFunction = {}

		function pageFunction:AddSection(Section_Name, Toggleable, SectionGap, SectionColor)
			local Toggleable = Toggleable or false
			local Section = Instance.new("Frame")
			local UICorner = Instance.new("UICorner")
			local Topsec = Instance.new("Frame")
			local Sectiontitle = Instance.new("TextLabel")
			local Linesec = Instance.new("Frame")
			local UIGradient = Instance.new("UIGradient")
			local SectionList = Instance.new("UIListLayout")
			
			Section.Name = Section_Name .. "_Dot"
			Section.Parent = PageList
			Section.Size = UDim2.new(1, -5, 0, 30)
			Bind(Section, "BackgroundColor3", "Section Panel Color")
			Bind(Section, "BackgroundTransparency", "Section Panel Transparency")
			Section.ClipsDescendants = true

			local sectionStroke = Instance.new("UIStroke", Section)
			Bind(sectionStroke, "Color", "Outline Color")
			sectionStroke.Thickness = 1

			-- shades the Section panel color (darker at the top); it never sets a color of its own
			local sectionGradient = Instance.new("UIGradient", Section)
			sectionGradient.Color = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(201, 201, 201)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255))
			}
			sectionGradient.Rotation = 90
			sectionGradient.Transparency = NumberSequence.new{
				NumberSequenceKeypoint.new(0, 0.05),
				NumberSequenceKeypoint.new(1, 0.15)
			}

			UICorner.CornerRadius = UDim.new(0, 4)
			UICorner.Parent = Section

			Topsec.Name = "Topsec"
			Topsec.Parent = Section
			Topsec.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
			Topsec.BackgroundTransparency = 1.000
			Topsec.Size = UDim2.new(0, 415, 0, 30)

			Sectiontitle.Name = "Sectiontitle"
			Sectiontitle.Parent = Topsec
			Sectiontitle.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
			Sectiontitle.BackgroundTransparency = 1.000
			Sectiontitle.Size = UDim2.new(1, 0, 1, 0)
			Sectiontitle.Font = Enum.Font.GothamBold
			Sectiontitle.Text = Section_Name
			Sectiontitle.TextSize = 14.000
			Bind(Sectiontitle, "TextColor3", "Section Text Color")

			Linesec.Name = "Linesec"
			Linesec.Parent = Topsec
			Linesec.AnchorPoint = Vector2.new(0.5, 1)
			Linesec.BorderSizePixel = 0
			Linesec.Position = UDim2.new(0.5, 0, 1, -2)
			Linesec.Size = UDim2.new(1, -10, 0, 2)
			Bind(Linesec, "BackgroundColor3", "Section Underline Color")

			local LineShadow = Instance.new("ImageLabel", Linesec)
			LineShadow.Name = "LineShadow"
			LineShadow.AnchorPoint = Vector2.new(0.5, 0.5)
			LineShadow.BackgroundColor3 = Color3.fromRGB(163,162,165)
			LineShadow.BackgroundTransparency = 1
			LineShadow.Position = UDim2.new(0.5, 0, 0.5, 0)
			LineShadow.Size = UDim2.new(1, 8, 1, 8)
			LineShadow.ZIndex = 0
			LineShadow.Image = "rbxassetid://5028857084"
			LineShadow.ImageTransparency = 0.6
			LineShadow.ScaleType = Enum.ScaleType.Slice
			LineShadow.SliceCenter = Rect.new(24, 24, 276, 276)

			UIGradient.Transparency = NumberSequence.new{
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(0.51, 0.02),
				NumberSequenceKeypoint.new(1, 1)
			}
			UIGradient.Parent = Linesec

			SectionList.Name = "SectionList"
			SectionList.Parent = Section
			SectionList.SortOrder = Enum.SortOrder.LayoutOrder
			SectionList.Padding = UDim.new(0, 5)

			local SizeSectionY
			local sectionIsVisible = false
			if Toggleable then
				local VisibilitySectionFrame = Instance.new("Frame")
				local VisibilitySectionFrameCorner = Instance.new("UICorner")
				local visibility = Instance.new("ImageButton")
				local visibility_off = Instance.new("ImageButton")
				local VisibilityButton = Instance.new("TextButton")
				VisibilityButton.Name = "VisibilityButton"
				VisibilityButton.Parent = Topsec
				VisibilityButton.AnchorPoint = Vector2.new(1, 0.5)
				VisibilityButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				VisibilityButton.BackgroundTransparency = 1.000
				VisibilityButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
				VisibilityButton.BorderSizePixel = 0
				VisibilityButton.Font = Enum.Font.SourceSans
				VisibilityButton.Text = ""
				VisibilityButton.TextColor3 = Color3.fromRGB(0, 0, 0)
				VisibilityButton.TextSize = 14.000
				VisibilityButton.ZIndex = 2
				VisibilityButton.Position = UDim2.new(1, -5, 0.5, 0)
				VisibilityButton.Size = UDim2.new(0, 20, 0, 20)
				VisibilitySectionFrame.Name = "VisibilitySectionFrame"
				VisibilitySectionFrame.Parent = Topsec
				VisibilitySectionFrame.AnchorPoint = Vector2.new(1, 0.5)
				VisibilitySectionFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
				VisibilitySectionFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
				VisibilitySectionFrame.BorderSizePixel = 0
				VisibilitySectionFrame.Position = UDim2.new(1, -5, 0.5, 0)
				VisibilitySectionFrame.Size = UDim2.new(0, 20, 0, 20)
				VisibilitySectionFrameCorner.CornerRadius = UDim.new(0, 4)
				VisibilitySectionFrameCorner.Name = "VisibilitySectionFrameCorner"
				VisibilitySectionFrameCorner.Parent = VisibilitySectionFrame
				visibility.Name = "visibility"
				visibility.Parent = VisibilitySectionFrame
				visibility.AnchorPoint = Vector2.new(0.5, 0.5)
				visibility.BackgroundTransparency = 1.000
				visibility.LayoutOrder = 4
				visibility.Position = UDim2.new(0.5, 0, 0.5, 0)
				visibility.Size = UDim2.new(1, -4, 1, -4)
				visibility.ZIndex = 2
				visibility.Image = "rbxassetid://3926307971"
				visibility.ImageRectOffset = Vector2.new(84, 44)
				visibility.ImageRectSize = Vector2.new(36, 36)
				visibility.ImageTransparency = 1
				visibility_off.Name = "visibility_off"
				visibility_off.Parent = VisibilitySectionFrame
				visibility_off.AnchorPoint = Vector2.new(0.5, 0.5)
				visibility_off.BackgroundTransparency = 1.000
				visibility_off.LayoutOrder = 4
				visibility_off.Position = UDim2.new(0.5, 0, 0.5, 0)
				visibility_off.Size = UDim2.new(1, -4, 1, -4)
				visibility_off.ZIndex = 2
				visibility_off.Image = "rbxassetid://3926307971"
				visibility_off.ImageRectOffset = Vector2.new(564, 44)
				visibility_off.ImageRectSize = Vector2.new(36, 36)
				visibility_off.ImageTransparency = 0
				VisibilityButton.MouseButton1Down:Connect(function()
					sectionIsVisible = not sectionIsVisible
					TweenService:Create(visibility, TweenInfo.new(getgenv().UIColor["Tween Animation 1 Speed"] / 2), {
						ImageTransparency = sectionIsVisible and 0 or 1
					}):Play()
					wait(getgenv().UIColor["Tween Animation 1 Speed"] / 4)
					TweenService:Create(visibility_off, TweenInfo.new(getgenv().UIColor["Tween Animation 1 Speed"] / 2), {
						ImageTransparency = sectionIsVisible and 1 or 0
					}):Play()
					TweenService:Create(Section, TI("Tween Animation 1 Speed"), {
						Size =  UDim2.new(1, -5, 0, (sectionIsVisible and SizeSectionY or 30))
					}):Play()
				end)
			end
			if SectionGap then
				local SectionGap = Instance.new("Frame")
				SectionGap.Name = "SectionGap"
				SectionGap.Parent = PageList
				SectionGap.Size = UDim2.new(1, -5, 0, 30)
				SectionGap.ClipsDescendants = true
				SectionGap.Transparency = 1
			end

			SectionList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
				if (not Toggleable) then
					Section.Size = UDim2.new(1, -5, 0, SectionList.AbsoluteContentSize.Y + 5)
				end
				SizeSectionY = SectionList.AbsoluteContentSize.Y + 5
				if sectionIsVisible then
					TweenService:Create(Section, TI("Tween Animation 1 Speed"), {
						Size =  UDim2.new(1, -5, 0, SizeSectionY)
					}):Play()
				end
			end)
			local sectionFunction = { Frame = Section } -- sub-tabs show/hide sections through this
			function sectionFunction:AddToggle(idk,Setting)
				local Title = tostring(Setting.Text or Setting.Title) or ""
				local Desc = Setting.Desc or Setting.Description
				local Default = Setting.Default
				if Default == nil then
					Default = false
				end
				local Callback = Setting.Callback
				local ToggleFrame = Instance.new("Frame")
				local TogFrame1 = Instance.new("Frame")
				local checkbox = Instance.new("ImageLabel")
				local check = Instance.new("Frame")
				local ToggleDesc = Instance.new("TextLabel")
				local ToggleTitle = Instance.new("TextLabel")
				local ToggleBg = Instance.new("Frame")
				local ToggleCorner = Instance.new("UICorner")
				local ToggleButton = Instance.new("TextButton")
				local ToggleList = Instance.new("UIListLayout")
				ToggleFrame.Name = "ToggleFrame"
				ToggleFrame.Parent = Section
				ToggleFrame.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
				ToggleFrame.BackgroundTransparency = 1.000
				ToggleFrame.Position = UDim2.new(0, 0, 0.300000012, 0)
				ToggleFrame.Size = UDim2.new(1, 0 , 0, 0)
				ToggleFrame.AutomaticSize = Enum.AutomaticSize.Y
				TogFrame1.Name = "TogFrame1"
				TogFrame1.Parent = ToggleFrame
				TogFrame1.AnchorPoint = Vector2.new(0.5, 0.5)
				TogFrame1.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
				TogFrame1.BackgroundTransparency = 1.000
				TogFrame1.Position = UDim2.new(0.5, 0, 0.5, 0)
				TogFrame1.Size = UDim2.new(1, -10, 0, 0)
				TogFrame1.AutomaticSize = Enum.AutomaticSize.Y
				checkbox.Name = "checkbox"
				checkbox.Parent = TogFrame1
				checkbox.AnchorPoint = Vector2.new(1, 0.5)
				checkbox.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
				checkbox.BackgroundTransparency = 1.000
				checkbox.Position = UDim2.new(1, -5, 0.5, 3)
				checkbox.Size = UDim2.new(0, 25, 0, 25)
				checkbox.Image = "rbxassetid://4552505888"
				Bind(checkbox, "ImageColor3", "Toggle Border Color")
				check.Name = "check"
				check.Parent = checkbox
				check.AnchorPoint = Vector2.new(0.5, 0.5)
				Bind(check, "BackgroundColor3", "Toggle Checked Color")
				check.Position = UDim2.new(0.5, 0, 0.5, 0)
				local cac = 5
				if Desc then
					cac = 0
					ToggleDesc.Name = "ToggleDesc"
					ToggleDesc.Parent = TogFrame1
					ToggleDesc.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
					ToggleDesc.BackgroundTransparency = 1.000
					ToggleDesc.Position = UDim2.new(0, 15, 0, 20)
					ToggleDesc.Size = UDim2.new(1, -50, 0, 0)
					ToggleDesc.Font = Enum.Font.GothamBlack
					ToggleDesc.Text = Desc
					ToggleDesc.TextSize = 13.000
					ToggleDesc.TextWrapped = true
					ToggleDesc.TextXAlignment = Enum.TextXAlignment.Left
					ToggleDesc.RichText = true
					ToggleDesc.AutomaticSize = Enum.AutomaticSize.Y
					Bind(ToggleDesc, "TextColor3", "Toggle Desc Color")
				else
					ToggleDesc.Text = ''
				end
				ToggleTitle.Name = "TextColor"
				ToggleTitle.Parent = TogFrame1
				ToggleTitle.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
				ToggleTitle.BackgroundTransparency = 1.000
				ToggleTitle.Position = UDim2.new(0, 10, 0, cac)
				ToggleTitle.Size = UDim2.new(1, -10, 0, 20)
				ToggleTitle.Font = Enum.Font.GothamBlack
				ToggleTitle.Text = Title
				ToggleTitle.TextSize = 14.000
				ToggleTitle.TextXAlignment = Enum.TextXAlignment.Left
				ToggleTitle.TextYAlignment = Enum.TextYAlignment.Center
				ToggleTitle.RichText = true
				ToggleTitle.AutomaticSize = Enum.AutomaticSize.Y
				Bind(ToggleTitle, "TextColor3", "Text Color")
				ToggleBg.Name = "Background1"
				ToggleBg.Parent = TogFrame1
				ToggleBg.Size = UDim2.new(1, 0, 1, 6)
				ToggleBg.ZIndex = 0
				Bind(ToggleBg, "BackgroundColor3", "Background 1 Color")
				Bind(ToggleBg, "BackgroundTransparency", "Background 1 Transparency")
				ToggleCorner.CornerRadius = UDim.new(0, 4)
				ToggleCorner.Name = "ToggleCorner"
				ToggleCorner.Parent = ToggleBg
				ToggleButton.Name = "ToggleButton"
				ToggleButton.Parent = TogFrame1
				ToggleButton.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
				ToggleButton.BackgroundTransparency = 1.000
				ToggleButton.AnchorPoint = Vector2.new(1, 0.5)
				ToggleButton.Size = UDim2.new(0, 25, 0, 25)
				ToggleButton.Position = UDim2.new(1, -5, 0.5, 3)
				ToggleButton.Font = Enum.Font.SourceSans
				ToggleButton.Text = ""
				ToggleButton.TextColor3 = Color3.fromRGB(0, 0, 0)
				ToggleButton.TextSize = 14.000
				ToggleList.Name = "ToggleList"
				ToggleList.Parent = ToggleFrame
				ToggleList.HorizontalAlignment = Enum.HorizontalAlignment.Center
				ToggleList.SortOrder = Enum.SortOrder.LayoutOrder
				ToggleList.VerticalAlignment = Enum.VerticalAlignment.Center
				ToggleList.Padding = UDim.new(0, 5)
				local function ChangeStage(val)
					local csize = val and UDim2.new(0.5, 0, 0.5, 0) or UDim2.new(0, 0, 0, 0)
					local pos = val and UDim2.new(0.5, 0, 0.5, 0) or UDim2.new(0.5, 0, 0.5, 0)
					local apos = val and Vector2.new(0.5, 0.5) or Vector2.new(0.5, 0.5)
					game.TweenService:Create(check, TI("Tween Animation 1 Speed"), {
						Size = csize,
						Position = pos,
						AnchorPoint = apos
					}):Play()
				end
				ChangeStage(Default)
				local function ButtonClick()
					Default = not Default
				    ChangeStage(Default)
				    if Callback then
				        pcall(Callback, Default)
				    end
				end
				ToggleButton.MouseButton1Down:Connect(function()
					ButtonClick()
				end)
				local toggleFunction = {}
				function toggleFunction.SetStage(value)
					if value ~= Default then
						ButtonClick()
					end
				end
				local controlData = {
                    Name = Title,
                    Section = Section,
                    Element = ToggleFrame,
                    SectionName = Section_Name,
                    TabName = Page_Name,
                    TabButton = PageName
                }
                table.insert(getgenv().AllControls, controlData)
                
				return toggleFunction
			end
        function sectionFunction:AddButton(Setting, Callback)
        	local Title = Setting.Title or Setting.Text or ""
        	local Callback = Setting.Callback or Setting.Func or Callback or function() end -- also accept AddButton(Setting, Callback)
            local Button = Instance.new("Frame")
            local RowBG_1 = Instance.new("Frame")
            local UICorner_1 = Instance.new("UICorner")
            local RowHover_1 = Instance.new("Frame")
            local UICorner_2 = Instance.new("UICorner")
            local TextColor_1 = Instance.new("TextLabel")
            local ClickArea_1 = Instance.new("Frame")
            local UICorner_3 = Instance.new("UICorner")
            local UIGradient_1 = Instance.new("UIGradient")
            local ImageLabel_1 = Instance.new("ImageLabel")
            local Frame_1 = Instance.new("Frame")
            local UICorner_4 = Instance.new("UICorner")
            local UIScale_1 = Instance.new("UIScale")
            local Button_1 = Instance.new("TextButton")
            
            Button.Name = "Button"
            Button.Parent = Section
            Button.BackgroundColor3 = Color3.fromRGB(163,162,165)
            Button.BackgroundTransparency = 1
            Button.Size = UDim2.new(1, 0,0, 40)
             
            RowBG_1.Name = "RowBG"
            RowBG_1.Parent = Button
            RowBG_1.AnchorPoint = Vector2.new(0.5, 0.5)
            Bind(RowBG_1, "BackgroundColor3", "Background 1 Color")
            Bind(RowBG_1, "BackgroundTransparency", "Background 1 Transparency")
            RowBG_1.Position = UDim2.new(0.5, 0,0.5, 0)
            RowBG_1.Size = UDim2.new(1, -10,1, 0)
             
            UICorner_1.Parent = RowBG_1
            UICorner_1.CornerRadius = UDim.new(0,10)
             
            RowHover_1.Name = "RowHover"
            RowHover_1.Parent = RowBG_1
            Bind(RowHover_1, "BackgroundColor3", "Background 2 Color")
            RowHover_1.BackgroundTransparency = 1
            RowHover_1.Size = UDim2.new(1, 0,1, 0)
            RowHover_1.ZIndex = 2
             
            UICorner_2.Parent = RowHover_1
            UICorner_2.CornerRadius = UDim.new(0,10)
             
            TextColor_1.Name = "TextColor"
            TextColor_1.Parent = RowBG_1
             TextColor_1.BackgroundColor3 = Color3.fromRGB(163,162,165)
             TextColor_1.BackgroundTransparency = 1
             TextColor_1.Position = UDim2.new(0, 12,0, 0)
             TextColor_1.Size = UDim2.new(1, -110,1, 0)
             TextColor_1.Font = Enum.Font.GothamBold
             TextColor_1.Text = Title
             Bind(TextColor_1, "TextColor3", "GUI Text Color")
             TextColor_1.TextSize = 14
             TextColor_1.TextStrokeTransparency = 0.8500000238418579
             TextColor_1.TextXAlignment = Enum.TextXAlignment.Left
             
             ClickArea_1.Name = "ClickArea"
             ClickArea_1.Parent = RowBG_1
             ClickArea_1.AnchorPoint = Vector2.new(1, 0.5)
             Bind(ClickArea_1, "BackgroundColor3", "Button Color")
             ClickArea_1.Position = UDim2.new(1, -8,0.5, 0)
             ClickArea_1.Size = UDim2.new(0, 94,0, 30)
             ClickArea_1.ClipsDescendants = true  -- THÊM DÒNG NÀY: Ngăn ripple tràn ra
             
             UICorner_3.Parent = ClickArea_1
             UICorner_3.CornerRadius = UDim.new(0,12)
             
             UIGradient_1.Parent = ClickArea_1
             UIGradient_1.Color = ButtonGradient(getgenv().UIColor["Button Color"]) -- follows the accent
             table.insert(ButtonGradients, UIGradient_1)
             UIGradient_1.Rotation = 90
             
             ImageLabel_1.Parent = ClickArea_1
             ImageLabel_1.AnchorPoint = Vector2.new(0.5, 0.5)
             ImageLabel_1.BackgroundColor3 = Color3.fromRGB(163,162,165)
             ImageLabel_1.BackgroundTransparency = 1
             ImageLabel_1.Position = UDim2.new(0.5, 0,0.5, 0)
             ImageLabel_1.Size = UDim2.new(1, 14,1, 14)
             ImageLabel_1.ZIndex = 0
             ImageLabel_1.Image = "rbxassetid://5028857084"
             ImageLabel_1.ImageTransparency = 0.7
             ImageLabel_1.ScaleType = Enum.ScaleType.Slice
             ImageLabel_1.SliceCenter = Rect.new(24, 24, 276, 276)
             
             Frame_1.Parent = ClickArea_1
             Frame_1.AnchorPoint = Vector2.new(0.5, 0)
             Frame_1.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
             Frame_1.BackgroundTransparency = 0.8
             Frame_1.Position = UDim2.new(0.5, 0,0, 2)
             Frame_1.Size = UDim2.new(1, -6,0, 10)
             Frame_1.ZIndex = 2
             
             UICorner_4.Parent = Frame_1
             UICorner_4.CornerRadius = UDim.new(0,10)
             
             UIScale_1.Parent = ClickArea_1
             
             Button_1.Name = "Button"
             Button_1.Parent = ClickArea_1
             Button_1.Active = true
             Button_1.AutoButtonColor = false
             Button_1.BackgroundColor3 = Color3.fromRGB(163,162,165)
             Button_1.BackgroundTransparency = 1
             Button_1.Size = UDim2.new(1, 0,1, 0)
             Button_1.Font = Enum.Font.GothamBold
             Button_1.Text = Setting.ButtonText or ButtonVerb(Title) -- Peridot: says what the button does
             Button_1.TextColor3 = Color3.fromRGB(240, 240, 240)
             Button_1.TextSize = 13

             -- UIScale mặc định
             UIScale_1.Scale = 1
             
             -- HOVER (chỉ phóng to)
             local scaleHover = TweenService:Create(UIScale_1, TweenInfo.new(0.12, Enum.EasingStyle.Sine), { Scale = 1.05 })
             local scaleNormal = TweenService:Create(UIScale_1, TweenInfo.new(0.12, Enum.EasingStyle.Sine), { Scale = 1 })
             
             Button_1.MouseEnter:Connect(function()
             	scaleHover:Play()
             end)
             
             Button_1.MouseLeave:Connect(function()
             	scaleNormal:Play()
             end)
             
                Button_1.MouseButton1Down:Connect(function()
                    
                    -- Lấy kích thước thực tế của ClickArea
                    local w = ClickArea_1.AbsoluteSize.X
                    local h = ClickArea_1.AbsoluteSize.Y
                    
                    -- Tạo ripple với hình dạng bo góc giống button (chữ nhật bo góc)
                    local ripple = Instance.new("Frame")
                    ripple.AnchorPoint = Vector2.new(0.5, 0.5)
                    ripple.Position = UDim2.new(0.5, 0, 0.5, 0)
                    ripple.Size = UDim2.new(0, 0, 0, 0)
                    ripple.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                    ripple.BackgroundTransparency = 0.6
                    ripple.ZIndex = 20
                    ripple.Parent = ClickArea_1
                    
                    -- Tạo UICorner cho ripple với bo góc y hệt button
                    local rippleCorner = Instance.new("UICorner")
                    rippleCorner.CornerRadius = UICorner_3.CornerRadius -- Lấy góc bo từ button
                    rippleCorner.Parent = ripple
                    
                    -- Animation ripple mở rộng từ tâm ra đầy đủ button
                    local rippleTween = TweenService:Create(
                        ripple,
                        TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                        {
                            Size = UDim2.new(1, 0, 1, 0),
                            BackgroundTransparency = 1,
                            Position = UDim2.new(0.5, 0, 0.5, 0)
                        }
                    )
                    
                    rippleTween:Play()
                    rippleTween.Completed:Connect(function()
                        ripple:Destroy()
                    end)
                    
                    Callback()
                end)
                local f = {}
                function f:SetTitle(vl)
                    TextColor_1.Text = vl
                end
                local controlData = {
                    Name = Title,
                    Section = Section,
                    Element = Button,
                    SectionName = Section_Name,
                    TabName = Page_Name,
                    TabButton = PageName
                }
                table.insert(getgenv().AllControls, controlData)
                
                return f
            end
        
			function sectionFunction:AddLabel(text)
				local Title = text
                local LabelFrame = Instance.new("Frame")
                local LabelBG = Instance.new("Frame")
                local UICorner = Instance.new("UICorner")
                local TextColor = Instance.new("TextLabel")
                
                LabelFrame.Name = "LabelFrame"
                LabelFrame.Parent = Section
                LabelFrame.AutomaticSize = Enum.AutomaticSize.Y
                LabelFrame.BackgroundColor3 = Color3.fromRGB(163,162,165)
                LabelFrame.BackgroundTransparency = 1
                LabelFrame.Size = UDim2.new(1, 0,0, 0)
                
                LabelBG.Name = "LabelBG"
                LabelBG.Parent = LabelFrame
                LabelBG.AnchorPoint = Vector2.new(0.5, 0)
                LabelBG.AutomaticSize = Enum.AutomaticSize.Y
                Bind(LabelBG, "BackgroundColor3", "Label Color")
                LabelBG.BackgroundTransparency = 0.25
                LabelBG.Position = UDim2.new(0.5, 0,0, 0)
                LabelBG.Size = UDim2.new(1, -10,0, -10)
                
                UICorner.Parent = LabelBG
                UICorner.CornerRadius = UDim.new(0,6)
                
                
                TextColor.Name = "TextColor"
                TextColor.Parent = LabelBG
                TextColor.AutomaticSize = Enum.AutomaticSize.Y
                TextColor.BackgroundColor3 = Color3.fromRGB(163,162,165)
                TextColor.BackgroundTransparency = 1
                TextColor.Position = UDim2.new(0, 12,0, 6)
                TextColor.Size = UDim2.new(1, -24,1, -12)
                TextColor.Font = Enum.Font.GothamMedium
                TextColor.Text = Title
                TextColor.TextColor3 = Color3.fromRGB(240,240,230)
                TextColor.TextSize = 14
                TextColor.TextStrokeTransparency = 0.8500000238418579
                TextColor.TextWrapped = true
                TextColor.TextXAlignment = Enum.TextXAlignment.Left
				local labelFunction = {}
				function labelFunction:SetText(text)
					TextColor.Text = text
				end
				function labelFunction.SetColor(color)
					TextColor.TextColor3 = color
				end
				local controlData = {
                    Name = Title,
                    Section = Section,
                    Element = LabelFrame,
                    SectionName = Section_Name,
                    TabName = Page_Name,
                    TabButton = PageName
                }
                table.insert(getgenv().AllControls, controlData)
                
				return labelFunction
			end
            function sectionFunction:AddDropdownSection(Setting)
                local Title = tostring(Setting.Text or Setting.Title or "")
                local Search = Setting.Search or false
              
                local DropdownFrame = Instance.new("Frame")
                local Dropdownbg = Instance.new("Frame")
                local Dropdowncorner = Instance.new("UICorner")
                local Topdrop = Instance.new("Frame")
                local UICorner = Instance.new("UICorner")
                local ImgDrop = Instance.new("ImageLabel")
                local DropdownButton = Instance.new("TextButton")
                local Dropdownlisttt = Instance.new("Frame")
                local DropdownScroll = Instance.new("ScrollingFrame")
                local ScrollContainer = Instance.new("Frame")
                local ScrollContainerList = Instance.new("UIListLayout")
                
                DropdownFrame.Name = Title .. "DropdownSectionFrame"
                DropdownFrame.Parent = Section
                DropdownFrame.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
                DropdownFrame.BackgroundTransparency = 1.000
                DropdownFrame.Position = UDim2.new(0, 0, 0.473684222, 0)
                DropdownFrame.Size = UDim2.new(1, 0, 0, 25)
                
                Dropdownbg.Name = "Background1"
                Dropdownbg.Parent = DropdownFrame
                Dropdownbg.AnchorPoint = Vector2.new(0.5, 0.5)
                Dropdownbg.Position = UDim2.new(0.5, 0, 0.5, 0)
                Dropdownbg.Size = UDim2.new(1, -10, 1, 0)
                Dropdownbg.ClipsDescendants = true
                Bind(Dropdownbg, "BackgroundColor3", "Background 1 Color")
                Dropdownbg.BackgroundTransparency = 0.25
                
                Dropdowncorner.CornerRadius = UDim.new(0, 4)
                Dropdowncorner.Name = "Dropdowncorner"
                Dropdowncorner.Parent = Dropdownbg
                
                Topdrop.Name = "Background2"
                Topdrop.Parent = Dropdownbg
                Topdrop.Size = UDim2.new(1, 0, 0, 25)
                Bind(Topdrop, "BackgroundColor3", "Background 2 Color")
                Bind(Topdrop, "BackgroundTransparency", "Background 1 Transparency")
                
                UICorner.CornerRadius = UDim.new(0, 4)
                UICorner.Parent = Topdrop
                
                local Dropdowntitle
                if Search then
                    Dropdowntitle = Instance.new("TextBox")
                    Dropdowntitle.PlaceholderText = Title
                    Bind(Dropdowntitle, "PlaceholderColor3", "Placeholder Text Color")
                else
                    Dropdowntitle = Instance.new("TextLabel")
                    Dropdowntitle.Text = Title
                end
                
                Dropdowntitle.Name = "TextColorPlaceholder"
                Dropdowntitle.Parent = Topdrop
                Dropdowntitle.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
                Dropdowntitle.BackgroundTransparency = 1.000
                Dropdowntitle.Position = UDim2.new(0, 10, 0, 0)
                Dropdowntitle.Size = UDim2.new(1, -40, 1, 0)
                Dropdowntitle.Font = Enum.Font.GothamBlack
                Dropdowntitle.TextSize = 14.000
                Dropdowntitle.TextXAlignment = Enum.TextXAlignment.Left
                Dropdowntitle.ClipsDescendants = true
                Bind(Dropdowntitle, "TextColor3", "Text Color")
                
                ImgDrop.Name = "ImgDrop"
                ImgDrop.Parent = Topdrop
                ImgDrop.AnchorPoint = Vector2.new(1, 0.5)
                ImgDrop.BackgroundTransparency = 1.000
                ImgDrop.BorderColor3 = Color3.fromRGB(27, 42, 53)
                ImgDrop.Position = UDim2.new(1, -6, 0.5, 0)
                ImgDrop.Size = UDim2.new(0, 15, 0, 15)
                ImgDrop.Image = "rbxassetid://6954383209"
                Bind(ImgDrop, "ImageColor3", "Dropdown Icon Color")
                
                DropdownButton.Name = "DropdownButton"
                DropdownButton.Parent = Topdrop
                DropdownButton.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
                DropdownButton.BackgroundTransparency = 1.000
                DropdownButton.Size = Search and UDim2.new(0, 30, 0, 30) or UDim2.new(1, 0, 1 , 0)
                DropdownButton.Position = Search and UDim2.new(1, -35, 0, 0) or UDim2.new(0 , 0 , 0 , 0)
                DropdownButton.Font = Enum.Font.GothamBold
                DropdownButton.Text = ""
                DropdownButton.TextColor3 = Color3.fromRGB(230, 230, 230)
                DropdownButton.TextSize = 14.000
                
                Dropdownlisttt.Name = "Dropdownlisttt"
                Dropdownlisttt.Parent = Dropdownbg
                Dropdownlisttt.BackgroundTransparency = 1.000
                Dropdownlisttt.BorderSizePixel = 0
                Dropdownlisttt.Position = UDim2.new(0, 0, 0, 25)
                Dropdownlisttt.Size = UDim2.new(1, 0, 0, 0)
                Dropdownlisttt.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
                
                DropdownScroll.Name = "DropdownScroll"
                DropdownScroll.Parent = Dropdownlisttt
                DropdownScroll.Active = true
                DropdownScroll.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
                DropdownScroll.BackgroundTransparency = 1.000
                DropdownScroll.BorderSizePixel = 0
                DropdownScroll.Size = UDim2.new(1, 0, 1, 0)
                DropdownScroll.BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
                DropdownScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
                DropdownScroll.ScrollBarThickness = 5
                DropdownScroll.TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
                DropdownScroll.ScrollingEnabled = true
                DropdownScroll.VerticalScrollBarInset = Enum.ScrollBarInset.Always
                
                ScrollContainer.Name = "ScrollContainer"
                ScrollContainer.Parent = DropdownScroll
                ScrollContainer.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
                ScrollContainer.BackgroundTransparency = 1.000
                ScrollContainer.Position = UDim2.new(0, 5, 0, 5)
                ScrollContainer.Size = UDim2.new(1, -15, 1, -5)
                
                ScrollContainerList.Name = "ScrollContainerList"
                ScrollContainerList.Parent = ScrollContainer
                ScrollContainerList.SortOrder = Enum.SortOrder.LayoutOrder
                ScrollContainerList.Padding = UDim.new(0, 5)
                
                -- Tạo internal section để chứa các control
                local InternalSection = Instance.new("Frame")
                InternalSection.Name = "InternalSection"
                InternalSection.Parent = ScrollContainer
                InternalSection.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
                InternalSection.BackgroundTransparency = 1.000
                InternalSection.Size = UDim2.new(1, 0, 0, 0)
                InternalSection.AutomaticSize = Enum.AutomaticSize.Y
                
                local InternalList = Instance.new("UIListLayout")
                InternalList.Name = "InternalList"
                InternalList.Parent = InternalSection
                InternalList.SortOrder = Enum.SortOrder.LayoutOrder
                InternalList.Padding = UDim.new(0, 5)
                
                local isOpen = false
                
                DropdownButton.MouseButton1Click:Connect(function()
                    isOpen = not isOpen
                    
                    local listsize = isOpen and UDim2.new(1, 0, 0, 200) or UDim2.new(1, 0, 0, 0)
                    local mainsize = isOpen and UDim2.new(1, 0, 0, 230) or UDim2.new(1, 0, 0, 25)
                    local DropCRotation = isOpen and 90 or 0
                    
                    TweenService:Create(Dropdownlisttt, TI("Tween Animation 2 Speed"), {
                        Size = listsize
                    }):Play()
                    TweenService:Create(DropdownFrame, TI("Tween Animation 2 Speed"), {
                        Size = mainsize
                    }):Play()
                    TweenService:Create(ImgDrop, TI("Tween Animation 2 Speed"), {
                        Rotation = DropCRotation
                    }):Play()
                end)
                
                ScrollContainerList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                    DropdownScroll.CanvasSize = UDim2.new(0, 0, 0, 10 + ScrollContainerList.AbsoluteContentSize.Y + 5)
                end)
                
                InternalList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                    local contentHeight = math.min(InternalList.AbsoluteContentSize.Y + 10, 300)
                    local listsize = isOpen and UDim2.new(1, 0, 0, contentHeight) or UDim2.new(1, 0, 0, 0)
                    local mainsize = isOpen and UDim2.new(1, 0, 0, contentHeight + 25) or UDim2.new(1, 0, 0, 25)
                    
                    if isOpen then
                        TweenService:Create(Dropdownlisttt, TI("Tween Animation 2 Speed"), {
                            Size = listsize
                        }):Play()
                        TweenService:Create(DropdownFrame, TI("Tween Animation 2 Speed"), {
                            Size = mainsize
                        }):Play()
                    end
                end)
                
                -- Tạo dropdown section functions (CHỈ CÓ SLIDER)
                local dropdownSectionFunction = {}
                
                -- HÀM TẠO SLIDER (RỘNG HƠN, SÁT VIỀN)
                function dropdownSectionFunction:AddSlider(Setting)
                    local TitleText = tostring(Setting.Text or Setting.Title) or ""
                    local minValue = tonumber(Setting.Min) or 0
                    local maxValue = tonumber(Setting.Max) or 100
                    local Precise = Setting.Precise or false
                    local DefaultValue = tonumber(Setting.Default) or 0
                    local Callback = Setting.Callback
                    local Rounding = Setting.Rouding or Setting.Rounding
                    
                    local SliderFrame = Instance.new("Frame")
                    local SliderCorner = Instance.new("UICorner")
                    local SliderBG = Instance.new("Frame")
                    local SliderBGCorner = Instance.new("UICorner")
                    local SliderTitle = Instance.new("TextLabel")
                    local SliderBar = Instance.new("Frame")
                    local SliderButton = Instance.new("TextButton")
                    local SliderBarCorner = Instance.new("UICorner")
                    local Bar = Instance.new("Frame")
                    local BarCorner = Instance.new("UICorner")
                    local Sliderboxframe = Instance.new("Frame")
                    local Sliderbox = Instance.new("UICorner")
                    local Sliderbox_2 = Instance.new("TextBox")
                    
                    SliderFrame.Name = TitleText
                    SliderFrame.Parent = InternalSection
                    SliderFrame.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
                    SliderFrame.BackgroundTransparency = 1.000
                    SliderFrame.Size = UDim2.new(1, 0, 0, 50)  -- Chiếm toàn bộ chiều rộng
                    
                    SliderCorner.CornerRadius = UDim.new(0, 4)
                    SliderCorner.Name = "SliderCorner"
                    SliderCorner.Parent = SliderFrame
                    
                    SliderBG.Name = "Background1"
                    SliderBG.Parent = SliderFrame
                    SliderBG.AnchorPoint = Vector2.new(0.5, 0.5)
                    SliderBG.Position = UDim2.new(0.5, 0, 0.5, 0)
                    SliderBG.Size = UDim2.new(1, -5, 1, 0)  -- Chiếm gần toàn bộ (trừ 5 pixel)
                    SliderBG.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
                    SliderBG.BackgroundTransparency = 0.25
                    
                    SliderBGCorner.CornerRadius = UDim.new(0, 4)
                    SliderBGCorner.Name = "SliderBGCorner"
                    SliderBGCorner.Parent = SliderBG
                    
                    SliderTitle.Name = "TextColor"
                    SliderTitle.Parent = SliderBG
                    SliderTitle.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
                    SliderTitle.BackgroundTransparency = 1.000
                    SliderTitle.Position = UDim2.new(0, 10, 0, 0)
                    SliderTitle.Size = UDim2.new(0.65, -10, 0, 25)  -- Title chiếm 65%
                    SliderTitle.Font = Enum.Font.GothamBlack
                    SliderTitle.Text = TitleText
                    SliderTitle.TextSize = 14.000
                    SliderTitle.RichText = true
                    SliderTitle.TextXAlignment = Enum.TextXAlignment.Left
                    Bind(SliderTitle, "TextColor3", "Text Color")
                    
                    SliderBar.Name = "SliderBar"
                    SliderBar.Parent = SliderFrame
                    SliderBar.AnchorPoint = Vector2.new(0.5, 0.5)
                    SliderBar.Position = UDim2.new(0.5, 0, 0.5, 14)
                    SliderBar.Size = UDim2.new(0.9, 0, 0, 6)  -- Thanh slider rộng 90%
                    Bind(SliderBar, "BackgroundColor3", "Background 2 Color")
                    
                    SliderButton.Name = "SliderButton"
                    SliderButton.Parent = SliderBar
                    SliderButton.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
                    SliderButton.BackgroundTransparency = 1.000
                    SliderButton.Size = UDim2.new(1, 0, 1, 0)
                    SliderButton.Font = Enum.Font.GothamBold
                    SliderButton.Text = ""
                    SliderButton.TextColor3 = Color3.fromRGB(230, 230, 230)
                    SliderButton.TextSize = 14.000
                    
                    SliderBarCorner.CornerRadius = UDim.new(1, 0)
                    SliderBarCorner.Name = "SliderBarCorner"
                    SliderBarCorner.Parent = SliderBar
                    
                    Bar.Name = "Bar"
                    Bar.BorderSizePixel = 0
                    Bar.Parent = SliderBar
                    Bar.Size = UDim2.new(0, 0, 1, 0)
                    Bind(Bar, "BackgroundColor3", "Slider Line Color")
                    
                    BarCorner.CornerRadius = UDim.new(1, 0)
                    BarCorner.Name = "BarCorner"
                    BarCorner.Parent = Bar
                    
                    Sliderboxframe.Name = "Background2"
                    Sliderboxframe.Parent = SliderFrame
                    Sliderboxframe.AnchorPoint = Vector2.new(1, 0)
                    Sliderboxframe.Position = UDim2.new(1, -10, 0, 5)
                    Sliderboxframe.Size = UDim2.new(0.25, 0, 0, 25)  -- Textbox chiếm 25%
                    Bind(Sliderboxframe, "BackgroundColor3", "Background 2 Color")
                    
                    Sliderbox.CornerRadius = UDim.new(0, 4)
                    Sliderbox.Name = "Sliderbox"
                    Sliderbox.Parent = Sliderboxframe
                    
                    Sliderbox_2.Name = "TextColor"
                    Sliderbox_2.Parent = Sliderboxframe
                    Sliderbox_2.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
                    Sliderbox_2.BackgroundTransparency = 1.000
                    Sliderbox_2.Size = UDim2.new(1, 0, 1, 0)
                    Sliderbox_2.Font = Enum.Font.GothamBold
                    Sliderbox_2.Text = ""
                    Sliderbox_2.TextSize = 14.000
                    Bind(Sliderbox_2, "TextColor3", "Text Color")
                    
                    SliderButton.MouseEnter:Connect(function()
                        TweenService:Create(Bar, TI("Tween Animation 2 Speed"), {
                            BackgroundColor3 = getgenv().UIColor["Slider Highlight Color"]
                        }):Play()
                    end)
                    
                    SliderButton.MouseLeave:Connect(function()
                        TweenService:Create(Bar, TI("Tween Animation 2 Speed"), {
                            BackgroundColor3 = getgenv().UIColor["Slider Line Color"]
                        }):Play()
                    end)
                    
                    local callBackAndSetText = function(val)
                        Sliderbox_2.Text = tostring(val)
                        Callback(tonumber(val))
                    end
                    if DefaultValue then
                        if DefaultValue <= minValue then
                            DefaultValue = minValue
                        elseif DefaultValue >= maxValue then
                            DefaultValue = maxValue
                        end
                        Bar.Size = UDim2.new(1 - ((maxValue - DefaultValue) / (maxValue - minValue)), 0, 0, 6)
                        Sliderbox_2.Text = tostring(DefaultValue)
                    end
                    
                    
                    local dragging = false
                    local dragInput
                    local holdTime = 0
                    local holdStarted = 0
                    
                    local function onInputBegan(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                            holdStarted = tick()
                            
                            input.Changed:Connect(function()
                                if input.UserInputState == Enum.UserInputState.End then
                                    dragging = false
                                    holdStarted = 0
                                end
                            end)
                        end
                    end
                    
                    local function onInputEnded(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                            dragging = false
                            holdStarted = 0
                        end
                    end
                    
                    local function onInputChanged(input)
                        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                            dragInput = input
                        end
                    end
                    
                    SliderButton.InputBegan:Connect(onInputBegan)
                    SliderButton.InputEnded:Connect(onInputEnded)
                    SliderButton.InputChanged:Connect(onInputChanged)
                    
                    RunService.RenderStepped:Connect(function()
                        if holdStarted > 0 and (tick() - holdStarted >= holdTime) and not dragging then
                            dragging = true
                        end
                        
                        if dragging and dragInput then
                            local barWidth = math.clamp(dragInput.Position.X - Bar.AbsolutePosition.X, 0, SliderBar.AbsoluteSize.X)
                            local percentage = barWidth / SliderBar.AbsoluteSize.X
                            local value = minValue + (maxValue - minValue) * percentage
                            
                            if Rounding then
                                value = tonumber(string.format("%.".. Rounding .."f", value))
                            elseif not Precise then
                                value = math.floor(value)
                            end
                            
                            value = math.clamp(value, minValue, maxValue)
                            
                            pcall(function()
                                callBackAndSetText(value)
                            end)
                            Bar.Size = UDim2.new(percentage, 0, 1, 0)
                        end
                    end)
                    
                    local function GetSliderValue(Value)
                        Value = tonumber(Value) or minValue
                        Value = math.clamp(Value, minValue, maxValue)
                        
                        if Rounding then
                            Value = tonumber(string.format("%.".. Rounding .."f", Value))
                        elseif not Precise then
                            Value = math.floor(Value)
                        end
                        
                        local percentage = (Value - minValue) / (maxValue - minValue)
                        Bar.Size = UDim2.new(percentage, 0, 1, 0)
                        callBackAndSetText(Value)
                    end
                    
                    Sliderbox_2.FocusLost:Connect(function()
                        GetSliderValue(Sliderbox_2.Text)
                    end)
                    
                    local slider_function = {}
                    function slider_function.SetValue(Value)
                        GetSliderValue(Value)
                    end
                    
                    function slider_function.GetValue()
                        return tonumber(Sliderbox_2.Text) or minValue
                    end
                    
                    return slider_function
                end
                
                function dropdownSectionFunction:SetOpen(state)
                    if state ~= isOpen then
                        DropdownButton.MouseButton1Click:Fire()
                    end
                end
                
                function dropdownSectionFunction:GetOpen()
                    return isOpen
                end
                
                function dropdownSectionFunction:SetTitle(newTitle)
                    if Search then
                        Dropdowntitle.PlaceholderText = newTitle
                    else
                        Dropdowntitle.Text = newTitle
                    end
                end
                
                local controlData = {
                    Name = Title,
                    Section = Section,
                    Element = DropdownFrame,
                    SectionName = Section_Name,
                    TabName = Page_Name,
                    TabButton = PageName
                }
                table.insert(getgenv().AllControls, controlData)
                
                return dropdownSectionFunction
            end
            
			function sectionFunction:AddDropdown(idk, Setting)
				local Title = tostring(Setting.Text or Setting.Title) or ""
				local List = Setting.Values
				local Search = Setting.Search or false
				local Selected = Setting.Selected or Setting.Multi or false
				local Slider = Setting.Slider or false
				local SliderRelease = Setting.SliderRelease or false
				local Default = (function ()
                    if Setting.Default then
                        if type(Setting.Default) == "number" then
                            return List[Setting.Default]
                        elseif type(Setting.Default) == "string" then
                            return Setting.Default
                        end
                    end
                    return nil
                end)()
				local Callback = Setting.Callback
				local pairs = Setting.SortPairs or pairs
				local DropdownFrame = Instance.new("Frame")
				local Dropdownbg = Instance.new("Frame")
				local Dropdowncorner = Instance.new("UICorner")
				local Topdrop = Instance.new("Frame")
				local UICorner = Instance.new("UICorner")
				local ImgDrop = Instance.new("ImageLabel")
				local DropdownButton = Instance.new("TextButton")
				local Dropdownlisttt = Instance.new("Frame")
				local DropdownScroll = Instance.new("ScrollingFrame")
				local ScrollContainer = Instance.new("Frame")
				local ScrollContainerList = Instance.new("UIListLayout")
				local dropdownLeave = false
				local Dropdowntitle;
				if Search then
					Dropdowntitle = Instance.new("TextBox")
				else
					Dropdowntitle = Instance.new("TextLabel")
				end
				DropdownFrame.Name = Title .. "DropdownFrame"
				DropdownFrame.Parent = Section
				DropdownFrame.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
				DropdownFrame.BackgroundTransparency = 1.000
				DropdownFrame.Position = UDim2.new(0, 0, 0.473684222, 0)
				DropdownFrame.Size = UDim2.new(1, 0, 0, 25)
				Dropdownbg.Name = "Background1"
				Dropdownbg.Parent = DropdownFrame
				Dropdownbg.AnchorPoint = Vector2.new(0.5, 0.5)
				Dropdownbg.Position = UDim2.new(0.5, 0, 0.5, 0)
				Dropdownbg.Size = UDim2.new(1, -10, 1, 0)
				Dropdownbg.ClipsDescendants = true
				Bind(Dropdownbg, "BackgroundColor3", "Background 1 Color")
				Bind(Dropdownbg, "BackgroundTransparency", "Background 1 Transparency")
				Dropdowncorner.CornerRadius = UDim.new(0, 4)
				Dropdowncorner.Name = "Dropdowncorner"
				Dropdowncorner.Parent = Dropdownbg
				Topdrop.Name = "Background2"
				Topdrop.Parent = Dropdownbg
				Topdrop.Size = UDim2.new(1, 0, 0, 25)
				Bind(Topdrop, "BackgroundColor3", "Background 2 Color")
				Bind(Topdrop, "BackgroundTransparency", "Background 1 Transparency")
				UICorner.CornerRadius = UDim.new(0, 4)
				UICorner.Parent = Topdrop
				Dropdowntitle.Name = "TextColorPlaceholder"
				Dropdowntitle.Parent = Topdrop
				Dropdowntitle.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
				Dropdowntitle.BackgroundTransparency = 1.000
				Dropdowntitle.Position = UDim2.new(0, 10, 0, 0)
				Dropdowntitle.Size = UDim2.new(1, -40, 1, 0)
				Dropdowntitle.Font = Enum.Font.GothamBlack
				Dropdowntitle.Text = ''
				Dropdowntitle.TextSize = 14.000
				Dropdowntitle.TextXAlignment = Enum.TextXAlignment.Left
				Dropdowntitle.ClipsDescendants = true
				local Sel = Instance.new("StringValue", Dropdowntitle)
				Sel.Value = ""
				if Default and table.find(List, Default) then
					Sel.Value = Default
				end
				if not Selected then
					if Search then
						Bind(Dropdowntitle, "PlaceholderColor3", "Placeholder Text Color")
						Dropdowntitle.PlaceholderText = Title .. ': ' .. tostring(Default or "");
					else
						Dropdowntitle.Text = Title .. ': ' .. tostring(Default or "");
					end
				else
					if Search then
						Bind(Dropdowntitle, "PlaceholderColor3", "Placeholder Text Color")
						Dropdowntitle.PlaceholderText = Title .. ': ' .. tostring(Default or "");
					else
						Dropdowntitle.Text = Title .. ': ' .. tostring(Default or "");
					end
				end
				Bind(Dropdowntitle, "TextColor3", "Text Color")
				ImgDrop.Name = "ImgDrop"
				ImgDrop.Parent = Topdrop
				ImgDrop.AnchorPoint = Vector2.new(1, 0.5)
				ImgDrop.BackgroundTransparency = 1.000
				ImgDrop.BorderColor3 = Color3.fromRGB(27, 42, 53)
				ImgDrop.Position = UDim2.new(1, -6, 0.5, 0)
				ImgDrop.Size = UDim2.new(0, 15, 0, 15)
				ImgDrop.Image = "rbxassetid://6954383209"
				Bind(ImgDrop, "ImageColor3", "Dropdown Icon Color")
				DropdownButton.Name = "DropdownButton"
				DropdownButton.Parent = Topdrop
				DropdownButton.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
				DropdownButton.BackgroundTransparency = 1.000
				DropdownButton.Size = Search and UDim2.new(0, 30, 0, 30) or UDim2.new(1, 0, 1 , 0)
				DropdownButton.Position = Search and UDim2.new(1, -35, 0, 0) or UDim2.new(0 , 0 , 0 , 0)
				DropdownButton.Font = Enum.Font.GothamBold
				DropdownButton.Text = ""
				DropdownButton.TextColor3 = Color3.fromRGB(230, 230, 230)
				DropdownButton.TextSize = 14.000
				Dropdownlisttt.Name = "Dropdownlisttt"
				Dropdownlisttt.Parent = Dropdownbg
				Dropdownlisttt.BackgroundTransparency = 1.000
				Dropdownlisttt.BorderSizePixel = 0
				Dropdownlisttt.Position = UDim2.new(0, 0, 0, 25)
				Dropdownlisttt.Size = UDim2.new(1, 0, 0, 25)
				Dropdownlisttt.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
				DropdownScroll.Name = "DropdownScroll"
				DropdownScroll.Parent = Dropdownlisttt
				DropdownScroll.Active = true
				DropdownScroll.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
				DropdownScroll.BackgroundTransparency = 1.000
				DropdownScroll.BorderSizePixel = 0
				DropdownScroll.Size = UDim2.new(1, 0, 1, 0)
				DropdownScroll.BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
				DropdownScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
				DropdownScroll.ScrollBarThickness = 5
				DropdownScroll.TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
				DropdownScroll.ScrollingEnabled = true
				DropdownScroll.VerticalScrollBarInset = Enum.ScrollBarInset.Always
				ScrollContainer.Name = "ScrollContainer"
				ScrollContainer.Parent = DropdownScroll
				ScrollContainer.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
				ScrollContainer.BackgroundTransparency = 1.000
				ScrollContainer.Position = UDim2.new(0, 5, 0, 5)
				ScrollContainer.Size = UDim2.new(1, -15, 1, -5)
				ScrollContainerList.Name = "ScrollContainerList"
				ScrollContainerList.Parent = ScrollContainer
				ScrollContainerList.SortOrder = Enum.SortOrder.LayoutOrder
				ScrollContainerList.Padding = UDim.new(0, 5)
				ScrollContainerList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
					DropdownScroll.CanvasSize = UDim2.new(0, 0, 0, 10 + ScrollContainerList.AbsoluteContentSize.Y + 5)
				end)
				local isbusy = false
				local found = {}
				local searchtable = {}
				local function edit()
					for i in pairs(found) do
						found[i] = nil
					end
					for h, l in pairs(ScrollContainer:GetChildren()) do
						if not l:IsA("UIListLayout") and not l:IsA("UIPadding") and not l:IsA('UIGridLayout') then
							l.Visible = false
						end
					end
					Dropdowntitle.Text = string.lower(Dropdowntitle.Text)
				end
				local function SearchDropdown()
					local Results = {}
					for i, v in pairs(searchtable) do
						if string.find(v, Dropdowntitle.Text) then
							table.insert(found, v)
						end
					end
					for a, b in pairs(ScrollContainer:GetChildren()) do
						for c, d in pairs(found) do
							if d == b.Name then
								b.Visible = true
							end
						end
					end
				end
				local function clear_object_in_list()
					for i, v in next, ScrollContainer:GetChildren() do
						if v:IsA('Frame') then
							v:Destroy()
						end
					end
				end
				local ListNew
                local OrderedList = {} -- Thêm biến lưu thứ tự
                if Selected then
                    ListNew = {}
                    for _, value in ipairs(List) do
                        -- Kiểm tra nếu value trùng với Default thì set true
                        ListNew[value] = (value == Default)
                        table.insert(OrderedList, value) -- Lưu thứ tự
                    end
                else
                    ListNew = List
                end
				local function refreshlist(SortPairs)
					pairs = SortPairs or pairs
					clear_object_in_list()
					searchtable = {}
					for i, v in pairs(ListNew) do
						if Selected then
							table.insert(searchtable, string.lower(i))
						elseif Slider then
							table.insert(searchtable, string.lower(v['Title']))
						else
							table.insert(searchtable, string.lower(v))
						end
					end
					if Selected then
                        for _, i in ipairs(OrderedList) do
                            local v = ListNew[i]
							local SampleItem = Instance.new("Frame")
							local SampleItemCorner = Instance.new("UICorner")
							local SampleItemBG = Instance.new("Frame")
							local SampleItemBGCorner = Instance.new("UICorner")
							local SampleItemTitle = Instance.new("TextLabel")
							local SampleItemCheck = Instance.new("ImageButton")
							local SampleItemButton = Instance.new("TextButton")
							SampleItem.Name = string.lower(i)
							SampleItem.Parent = ScrollContainer
							SampleItem.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
							SampleItem.BackgroundTransparency = 1.000
							SampleItem.BorderColor3 = Color3.fromRGB(27, 42, 53)
							SampleItem.LayoutOrder = 1
							SampleItem.Position = UDim2.new(0, 0, 0.208333328, 0)
							SampleItem.Size = UDim2.new(1, 0, 0, 25)
							SampleItemCorner.CornerRadius = UDim.new(0, 4)
							SampleItemCorner.Name = "SampleItemCorner"
							SampleItemCorner.Parent = SampleItem
							SampleItemBG.Name = "SampleItemBG"
							SampleItemBG.Parent = SampleItem
							SampleItemBG.AnchorPoint = Vector2.new(0.5, 0.5)
							SampleItemBG.BackgroundColor3 = v and getgenv().UIColor["Dropdown Selected Check Color"] or Color3.fromRGB(255, 255, 255)
							SampleItemBG.BackgroundTransparency = v and .5 or 1
							SampleItemBG.BorderColor3 = Color3.fromRGB(27, 42, 53)
							SampleItemBG.Position = UDim2.new(0.5, 0, 0.5, 0)
							SampleItemBG.Size = UDim2.new(1, 0, 1, 0)
							SampleItemBGCorner.CornerRadius = UDim.new(0, 4)
							SampleItemBGCorner.Name = "SampleItemBGCorner"
							SampleItemBGCorner.Parent = SampleItemBG
							SampleItemTitle.Name = "SampleItemTitle"
							SampleItemTitle.Parent = SampleItemBG
							SampleItemTitle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
							SampleItemTitle.BackgroundTransparency = 1.000
							SampleItemTitle.BorderColor3 = Color3.fromRGB(27, 42, 53)
							SampleItemTitle.Position = UDim2.new(0, 10, 0, 0)
							SampleItemTitle.Size = UDim2.new(1, -40, 0, 25)
							SampleItemTitle.Font = Enum.Font.GothamBlack
							SampleItemTitle.Text = tostring(i)
							SampleItemTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
							SampleItemTitle.TextSize = 14.000
							SampleItemTitle.TextStrokeTransparency = 0.500
							SampleItemTitle.TextXAlignment = Enum.TextXAlignment.Left
							SampleItemCheck.Name = "SampleItemCheck"
							SampleItemCheck.Parent = SampleItemBG
							SampleItemCheck.AnchorPoint = Vector2.new(1, 0.5)
							SampleItemCheck.BackgroundTransparency = 1.000
							SampleItemCheck.Position = UDim2.new(1, 0, 0.5, 0)
							SampleItemCheck.Size = UDim2.new(0, 25, 0, 25)
							SampleItemCheck.ZIndex = 2
							SampleItemCheck.Image = "rbxassetid://3926305904"
							Bind(SampleItemCheck, "ImageColor3", "Dropdown Selected Check Color")
							SampleItemCheck.ImageRectOffset = Vector2.new(312, 4)
							SampleItemCheck.ImageRectSize = Vector2.new(24, 24)
							SampleItemCheck.ImageTransparency = v and 0 or 1
							SampleItemButton.Name = "SampleItemButton"
							SampleItemButton.Parent = SampleItem
							SampleItemButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
							SampleItemButton.BackgroundTransparency = 1.000
							SampleItemButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
							SampleItemButton.BorderSizePixel = 0
							SampleItemButton.Size = UDim2.new(1, 0, 1, 0)
							SampleItemButton.Font = Enum.Font.SourceSans
							Bind(SampleItemButton, "TextColor3", "Text Color")
							SampleItemButton.TextSize = 14.000
							SampleItemButton.TextTransparency = 1.000
							SampleItemButton.MouseEnter:Connect(function()
								if v then
									return
								end
								TweenService:Create(
											SampleItemBG,
											TI("Tween Animation 1 Speed"), {
									BackgroundColor3 = Color3.fromRGB(255, 255, 255)
								}
										):Play()
								TweenService:Create(
											SampleItemBG,
											TI("Tween Animation 1 Speed"), {
									BackgroundTransparency = .7
								}
										):Play()
							end)
							SampleItemButton.MouseLeave:Connect(function()
								if v then
									return
								end
								TweenService:Create(
											SampleItemBG,
											TI("Tween Animation 1 Speed"), {
									BackgroundColor3 = Color3.fromRGB(255, 255, 255)
								}
										):Play()
								TweenService:Create(
											SampleItemBG,
											TI("Tween Animation 1 Speed"), {
									BackgroundTransparency = 1
								}
										):Play()
							end)
							SampleItemButton.MouseButton1Click:Connect(function()
								v = not v
								TweenService:Create(
											SampleItemCheck,
											TI("Tween Animation 1 Speed"), {
									ImageTransparency = v and 0 or 1
								}
										):Play()
								TweenService:Create(
											SampleItemBG,
											TI("Tween Animation 1 Speed"), {
									BackgroundColor3 = v and getgenv().UIColor["Dropdown Selected Check Color"] or Color3.fromRGB(255, 255, 255)
								}
										):Play()
								TweenService:Create(
											SampleItemBG,
											TI("Tween Animation 1 Speed"), {
									BackgroundTransparency = v and .5 or 1
								}
										):Play()
								if Callback then
									Callback(i, v)
									ListNew[i] = v
								end
								if Search then
									Dropdowntitle.PlaceholderText = Title .. ': '
								else
									Dropdowntitle.Text = Title .. ': '
								end
							end)
						end
					elseif Slider then
						for i, v in pairs(ListNew) do
							local TitleText = tostring(v.Title) or ""
							local minValue = tonumber(v.Min) or 0
							local maxValue = tonumber(v.Max) or 100
							local Precise = v.Precise or false
							local DefaultValue = tonumber(v.Default) or minValue
							local SizeChia = 365;
							local SliderFrame = Instance.new("Frame")
							local SliderCorner = Instance.new("UICorner")
							local SliderBG = Instance.new("Frame")
							local SliderBGCorner = Instance.new("UICorner")
							local SliderTitle = Instance.new("TextLabel")
							local SliderBar = Instance.new("Frame")
							local SliderButton = Instance.new("TextButton")
							local SliderBarCorner = Instance.new("UICorner")
							local Bar = Instance.new("Frame")
							local BarCorner = Instance.new("UICorner")
							local Sliderboxframe = Instance.new("Frame")
							local Sliderbox = Instance.new("UICorner")
							local Sliderbox_2 = Instance.new("TextBox")
							SliderFrame.Name = string.lower(v['Title'])
							SliderFrame.Parent = ScrollContainer
							SliderFrame.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
							SliderFrame.BackgroundTransparency = 1.000
							SliderFrame.Position = UDim2.new(0, 0, 0.208333328, 0)
							SliderFrame.Size = UDim2.new(1, 0, 0, 50)
							SliderCorner.CornerRadius = UDim.new(0, 4)
							SliderCorner.Name = "SliderCorner"
							SliderCorner.Parent = SliderFrame
							SliderBG.Name = "Background1"
							SliderBG.Parent = SliderFrame
							SliderBG.AnchorPoint = Vector2.new(0.5, 0.5)
							SliderBG.Position = UDim2.new(0.5, 0, 0.5, 0)
							SliderBG.Size = UDim2.new(1, -10, 1, 0)
							Bind(SliderBG, "BackgroundColor3", "Background 1 Color")
							Bind(SliderBG, "BackgroundTransparency", "Background 1 Transparency")
							SliderBGCorner.CornerRadius = UDim.new(0, 4)
							SliderBGCorner.Name = "SliderBGCorner"
							SliderBGCorner.Parent = SliderBG
							SliderTitle.Name = "TextColor"
							SliderTitle.Parent = SliderBG
							SliderTitle.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
							SliderTitle.BackgroundTransparency = 1.000
							SliderTitle.Position = UDim2.new(0, 10, 0, 0)
							SliderTitle.Size = UDim2.new(1, -10, 0, 25)
							SliderTitle.Font = Enum.Font.GothamBlack
							SliderTitle.Text = TitleText
							SliderTitle.TextSize = 14.000
							SliderTitle.TextXAlignment = Enum.TextXAlignment.Left
							Bind(SliderTitle, "TextColor3", "Text Color")
							SliderBar.Name = "SliderBar"
							SliderBar.Parent = SliderFrame
							SliderBar.AnchorPoint = Vector2.new(.5, 0.5)
							SliderBar.Position = UDim2.new(.5, 0, 0.5, 14)
							SliderBar.Size = UDim2.new(1, -20, 0, 6)
							Bind(SliderBar, "BackgroundColor3", "Background 2 Color")
							SliderButton.Name = "SliderButton "
							SliderButton.Parent = SliderBar
							SliderButton.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
							SliderButton.BackgroundTransparency = 1.000
							SliderButton.Size = UDim2.new(1, 0, 1, 0)
							SliderButton.Font = Enum.Font.GothamBold
							SliderButton.Text = ""
							SliderButton.TextColor3 = Color3.fromRGB(230, 230, 230)
							SliderButton.TextSize = 14.000
							SliderBarCorner.CornerRadius = UDim.new(1, 0)
							SliderBarCorner.Name = "SliderBarCorner"
							SliderBarCorner.Parent = SliderBar
							Bar.Name = "Bar"
							Bar.BorderSizePixel = 0
							Bar.Parent = SliderBar
							Bar.Size = UDim2.new(0, 0, 1, 0)
							Bind(Bar, "BackgroundColor3", "Slider Line Color")
							BarCorner.CornerRadius = UDim.new(1, 0)
							BarCorner.Name = "BarCorner"
							BarCorner.Parent = Bar
							Sliderboxframe.Name = "Background2"
							Sliderboxframe.Parent = SliderFrame
							Sliderboxframe.AnchorPoint = Vector2.new(1, 0)
							Sliderboxframe.Position = UDim2.new(1, -10, 0, 5)
							Sliderboxframe.Size = UDim2.new(0, 150, 0, 25)
							Bind(Sliderboxframe, "BackgroundColor3", "Background 2 Color")
							Sliderbox.CornerRadius = UDim.new(0, 4)
							Sliderbox.Name = "Sliderbox"
							Sliderbox.Parent = Sliderboxframe
							Sliderbox_2.Name = "TextColor"
							Sliderbox_2.Parent = Sliderboxframe
							Sliderbox_2.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
							Sliderbox_2.BackgroundTransparency = 1.000
							Sliderbox_2.Size = UDim2.new(1, 0, 1, 0)
							Sliderbox_2.Font = Enum.Font.GothamBold
							Sliderbox_2.Text = ""
							Sliderbox_2.TextSize = 14.000
							Bind(Sliderbox_2, "TextColor3", "Text Color")
							SliderButton.MouseEnter:Connect(function()
								TweenService:Create(Bar, TI("Tween Animation 2 Speed"), {
									BackgroundColor3 = getgenv().UIColor["Slider Highlight Color"]
								}):Play()
							end)
							SliderButton.MouseLeave:Connect(function()
								TweenService:Create(Bar, TI("Tween Animation 2 Speed"), {
									BackgroundColor3 = getgenv().UIColor["Slider Line Color"]
								}):Play()
							end)
							local callBackAndSetText = function(val)
								Sliderbox_2.Text = val
								ListNew[i].Default = val
								Callback(i, v)
							end
							if DefaultValue then
								if DefaultValue <= minValue then
									DefaultValue = minValue
								elseif DefaultValue >= maxValue then
									DefaultValue = maxValue
								end
								Bar.Size = UDim2.new(1 - ((maxValue - DefaultValue) / (maxValue - minValue)), 0, 0, 6)
								callBackAndSetText(DefaultValue)
							end
							if SliderRelease then
								local dragging = false
								local dragInput
								local holdTime = 0
								local holdStarted = 0

										-- Function to detect the start of dragging (for both mouse and touch)
								local function onInputBegan(input)
									if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
										holdStarted = tick() -- Record the time when holding starts
										
												-- Listen for release to stop dragging
										input.Changed:Connect(function()
											if input.UserInputState == Enum.UserInputState.End then
												dragging = false
												holdStarted = 0 -- Reset the hold timer
											end
										end)
									end
								end
										
										-- Function to detect when dragging stops
								local function onInputEnded(input)
									if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
										dragging = false
										holdStarted = 0 -- Reset the hold timer
									end
								end

										-- Detect input movement (for both mouse and touch)
								local function onInputChanged(input)
									if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
										dragInput = input
									end
								end
										
										-- Connect the events
								SliderButton.InputBegan:Connect(onInputBegan)
								SliderButton.InputEnded:Connect(onInputEnded)
								SliderButton.InputChanged:Connect(onInputChanged)
										
										-- RenderStepped updates the position while dragging
								RunService.RenderStepped:Connect(function()
									if holdStarted > 0 and (tick() - holdStarted >= holdTime) and not dragging then
										dragging = true
									end
									if dragging and dragInput then
										local value = Precise and  tonumber(string.format("%.1f", (((tonumber(maxValue) - tonumber(minValue)) / SizeChia) * Bar.AbsoluteSize.X) + tonumber(minValue))) or math.floor((((tonumber(maxValue) - tonumber(minValue)) / SizeChia) * Bar.AbsoluteSize.X) + tonumber(minValue))
										pcall(function()
											callBackAndSetText(value)
										end)
										Bar.Size = UDim2.new(0, math.clamp(dragInput.Position.X - Bar.AbsolutePosition.X, 0, SizeChia), 0, 6)
									end
								end)
							else
								local dragging = false
								local dragInput
								local holdTime = 0 -- Time to hold before dragging is enabled
								local holdStarted = 0

										-- Function to detect the start of dragging (for both mouse and touch)
								local function onInputBegan(input)
									if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
										holdStarted = tick() -- Record the time when holding starts
										
												-- Listen for release to stop dragging
										input.Changed:Connect(function()
											if input.UserInputState == Enum.UserInputState.End then
												dragging = false
												holdStarted = 0 -- Reset the hold timer
											end
										end)
									end
								end
										
										-- Function to detect when dragging stops
								local function onInputEnded(input)
									if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
										dragging = false
										holdStarted = 0 -- Reset the hold timer
									end
								end

										-- Detect input movement (for both mouse and touch)
								local function onInputChanged(input)
									if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
										dragInput = input
									end
								end
										
										-- Connect the events
								SliderButton.InputBegan:Connect(onInputBegan)
								SliderButton.InputEnded:Connect(onInputEnded)
								SliderButton.InputChanged:Connect(onInputChanged)
										
										-- RenderStepped updates the position while dragging
								RunService.RenderStepped:Connect(function()
									if holdStarted > 0 and (tick() - holdStarted >= holdTime) and not dragging then
										dragging = true
									end
									if dragging and dragInput then
										local value = Precise and  tonumber(string.format("%.1f", (((tonumber(maxValue) - tonumber(minValue)) / SizeChia) * Bar.AbsoluteSize.X) + tonumber(minValue))) or math.floor((((tonumber(maxValue) - tonumber(minValue)) / SizeChia) * Bar.AbsoluteSize.X) + tonumber(minValue))
										pcall(function()
											callBackAndSetText(value)
										end)
										Bar.Size = UDim2.new(0, math.clamp(dragInput.Position.X - Bar.AbsolutePosition.X, 0, SizeChia), 0, 6)
									end
								end)
							end
							local function GetSliderValue(Value)
								if tonumber(Value) <= minValue then
									Bar.Size = UDim2.new(0, (0 * SizeChia), 0, 6)
									callBackAndSetText(minValue)
								elseif tonumber(Value) >= maxValue then
									Bar.Size = UDim2.new(0, (maxValue  /  maxValue * SizeChia), 0, 6)
									callBackAndSetText(maxValue)
								else
									Bar.Size = UDim2.new(1 - ((maxValue - Value) / (maxValue - minValue)), 0, 0, 6)
									callBackAndSetText(Value)
								end
							end
							Sliderbox_2.FocusLost:Connect(function()
								GetSliderValue(Sliderbox_2.Text)
							end)
						end
					else
						for i, v in pairs (ListNew) do
							if typeof(v) == "string" then
								local SampleItem = Instance.new("Frame")
								local SampleItemCorner = Instance.new("UICorner")
								local SampleItemBG = Instance.new("Frame")
								local SampleItemBGCorner = Instance.new("UICorner")
								local SampleItemTitle = Instance.new("TextLabel")
								local SampleItemCheck = Instance.new("ImageButton")
								local SampleItemButton = Instance.new("TextButton")
								SampleItem.Name = string.lower(v)
								SampleItem.Parent = ScrollContainer
								SampleItem.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
								SampleItem.BackgroundTransparency = 1.000
								SampleItem.BorderColor3 = Color3.fromRGB(27, 42, 53)
								SampleItem.LayoutOrder = 1
								SampleItem.Position = UDim2.new(0, 0, 0.208333328, 0)
								SampleItem.Size = UDim2.new(1, 0, 0, 25)
								SampleItemCorner.CornerRadius = UDim.new(0, 4)
								SampleItemCorner.Name = "SampleItemCorner"
								SampleItemCorner.Parent = SampleItem
								SampleItemBG.Name = "SampleItemBG"
								SampleItemBG.Parent = SampleItem
								SampleItemBG.AnchorPoint = Vector2.new(0.5, 0.5)
								SampleItemBG.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
								SampleItemBG.BackgroundTransparency = 1
								SampleItemBG.BorderColor3 = Color3.fromRGB(27, 42, 53)
								SampleItemBG.Position = UDim2.new(0.5, 0, 0.5, 0)
								SampleItemBG.Size = UDim2.new(1, 0, 1, 0)
								SampleItemBGCorner.CornerRadius = UDim.new(0, 4)
								SampleItemBGCorner.Name = "SampleItemBGCorner"
								SampleItemBGCorner.Parent = SampleItemBG
								SampleItemTitle.Name = "SampleItemTitle"
								SampleItemTitle.Parent = SampleItemBG
								SampleItemTitle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
								SampleItemTitle.BackgroundTransparency = 1.000
								SampleItemTitle.BorderColor3 = Color3.fromRGB(27, 42, 53)
								SampleItemTitle.Position = UDim2.new(0, 10, 0, 0)
								SampleItemTitle.Size = UDim2.new(1, -40, 0, 25)
								SampleItemTitle.Font = Enum.Font.GothamBlack
								SampleItemTitle.Text = v
								SampleItemTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
								SampleItemTitle.TextSize = 14.000
								SampleItemTitle.TextStrokeTransparency = 0.500
								SampleItemTitle.TextXAlignment = Enum.TextXAlignment.Left
								SampleItemCheck.Name = "SampleItemCheck"
								SampleItemCheck.Parent = SampleItemBG
								SampleItemCheck.AnchorPoint = Vector2.new(1, 0.5)
								SampleItemCheck.BackgroundTransparency = 1.000
								SampleItemCheck.Position = UDim2.new(1, 0, 0.5, 0)
								SampleItemCheck.Size = UDim2.new(0, 25, 0, 25)
								SampleItemCheck.ZIndex = 2
								SampleItemCheck.Image = "rbxassetid://3926305904"
								Bind(SampleItemCheck, "ImageColor3", "Dropdown Selected Check Color")
								SampleItemCheck.ImageRectOffset = Vector2.new(312, 4)
								SampleItemCheck.ImageRectSize = Vector2.new(24, 24)
								SampleItemCheck.ImageTransparency = 1
								SampleItemButton.Name = "SampleItemButton"
								SampleItemButton.Parent = SampleItem
								SampleItemButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
								SampleItemButton.BackgroundTransparency = 1.000
								SampleItemButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
								SampleItemButton.BorderSizePixel = 0
								SampleItemButton.Size = UDim2.new(1, 0, 1, 0)
								SampleItemButton.Font = Enum.Font.SourceSans
								Bind(SampleItemButton, "TextColor3", "Text Color")
								SampleItemButton.TextSize = 14.000
								SampleItemButton.TextTransparency = 1.000
								SampleItemButton.MouseEnter:Connect(function()
									if Sel.Value == v then
										return
									end
									TweenService:Create(
												SampleItemBG,
												TI("Tween Animation 1 Speed"), {
										BackgroundColor3 = Color3.fromRGB(255, 255, 255)
									}
											):Play()
									TweenService:Create(
												SampleItemBG,
												TI("Tween Animation 1 Speed"), {
										BackgroundTransparency = .7
									}
											):Play()
								end)
								SampleItemButton.MouseLeave:Connect(function()
									if Sel.Value == v then
										return
									end
									TweenService:Create(
												SampleItemBG,
												TI("Tween Animation 1 Speed"), {
										BackgroundColor3 = Color3.fromRGB(255, 255, 255)
									}
											):Play()
									TweenService:Create(
												SampleItemBG,
												TI("Tween Animation 1 Speed"), {
										BackgroundTransparency = 1
									}
											):Play()
								end)
								SampleItemButton.MouseButton1Click:Connect(function()
									if Search then
										Dropdowntitle.PlaceholderText = Title .. ': ' .. v or ""
										Sel.Value = v
									else
										Dropdowntitle.Text = Title .. ': ' .. v or ""
										Sel.Value = v
									end
									TweenService:Create(
												SampleItemBG,
												TI("Tween Animation 1 Speed"), {
										BackgroundColor3 = getgenv().UIColor["Dropdown Selected Check Color"]
									}
											):Play()
									TweenService:Create(
												SampleItemBG,
												TI("Tween Animation 1 Speed"), {
										BackgroundTransparency = .5
									}
											):Play()
									if Callback then
										Callback(v)
									end
									if Search then
										Dropdowntitle.Text = ""
									end
									refreshlist()
								end)
								if Sel.Value == v then
									SampleItemBG.BackgroundTransparency = .5;
									Bind(SampleItemBG, "BackgroundColor3", "Dropdown Selected Check Color")
									SampleItem.LayoutOrder = 0
								end
							end
						end
					end
				end
				if Search then
					Dropdowntitle.Changed:Connect(function()
						edit()
						SearchDropdown()
					end)
				end
				if typeof(Default) ~= 'table' then
					if Search then
						Dropdowntitle.PlaceholderText = Title .. ': ' .. tostring(Default or "")
					else
						Dropdowntitle.Text = Title .. ': ' .. tostring(Default or "")
					end
				elseif Slider then
					Dropdowntitle.Text = ''
					Dropdowntitle.PlaceholderText = Title .. ': '
				elseif Selected then
					if Search then
						Dropdowntitle.PlaceholderText = Title .. ': '
					else
						Dropdowntitle.Text = Title .. ': '
					end
				end
				DropdownButton.MouseButton1Click:Connect(function()
					refreshlist()
					isbusy = not isbusy
					local listsize = isbusy and UDim2.new(1, 0, 0, 170) or UDim2.new(1, 0, 0, 0)
					local mainsize = isbusy and UDim2.new(1, 0, 0, 200) or UDim2.new(1, 0, 0, 25)
					local DropCRotation = isbusy and 90 or 0
					TweenService:Create(Dropdownlisttt, TI("Tween Animation 2 Speed"), {
						Size = listsize
					}):Play()
					TweenService:Create(DropdownFrame, TI("Tween Animation 2 Speed"), {
						Size = mainsize
					}):Play()
					TweenService:Create(ImgDrop, TI("Tween Animation 2 Speed"), {
						Rotation = DropCRotation
					}):Play()
				end)
				local dropdownFunction = {
					rf = refreshlist
				}
				function dropdownFunction:ClearText(v)
					if not Selected then
						if Search then
							Dropdowntitle.PlaceholderText = Title .. ': ' .. (v or "")
						else
							Dropdowntitle.Text = Title .. ': ' .. (v or "")
						end
					else
						Dropdowntitle.Text = Title .. ': ' .. (v or "")
					end
				end
				function dropdownFunction:GetNewList(List)
					Sel.Value = ""
							--refreshlist()
					isbusy = false
					local listsize = isbusy and UDim2.new(1, 0, 0, 170) or UDim2.new(1, 0, 0, 0)
					local mainsize = isbusy and UDim2.new(1, 0, 0, 200) or UDim2.new(1, 0, 0, 25)
					local DropCRotation = isbusy and 90 or 0
					TweenService:Create(Dropdownlisttt, TI("Tween Animation 2 Speed"), {
						Size = listsize
					}):Play()
					TweenService:Create(DropdownFrame, TI("Tween Animation 2 Speed"), {
						Size = mainsize
					}):Play()
					TweenService:Create(ImgDrop, TI("Tween Animation 2 Speed"), {
						Rotation = DropCRotation
					}):Play()
					ListNew = {}
					ListNew = List
					refreshlist()
					if Search then
						Dropdowntitle.PlaceholderText = Title .. ': '
					else
						Dropdowntitle.Text = Title .. ': '
					end
				end
				-- THÊM ĐOẠN NÀY
                function dropdownFunction:SetValue(value)
                    if not Selected then
                        -- Dropdown đơn lẻ (single)
                        if table.find(ListNew, value) then
                            Sel.Value = value
                            if Search then
                                Dropdowntitle.PlaceholderText = Title .. ': ' .. value
                            else
                                Dropdowntitle.Text = Title .. ': ' .. value
                            end
                            if Callback then
                                Callback(value)
                            end
                            refreshlist()
                        end
                    else
                        -- Dropdown multi-select
                        if ListNew[value] ~= nil then
                            ListNew[value] = true
                            if Search then
                                Dropdowntitle.PlaceholderText = Title .. ': '
                            else
                                Dropdowntitle.Text = Title .. ': '
                            end
                            if Callback then
                                Callback(value, true)
                            end
                            refreshlist()
                        end
                    end
                end
                
                function dropdownFunction:GetValue()
                    if not Selected then
                        return Sel.Value
                    else
                        local result = {}
                        for key, val in pairs(ListNew) do
                            if val == true then
                                table.insert(result, key)
                            end
                        end
                        return result
                    end
                end
				local controlData = {
                    Name = Title,
                    Section = Section,
                    Element = DropdownFrame,
                    SectionName = Section_Name,
                    TabName = Page_Name,
                    TabButton = PageName,
                    SetValue = dropdownFunction.SetValue,  -- THÊM DÒNG NÀY
                    GetValue = dropdownFunction.GetValue   -- THÊM DÒNG NÀY
                }
                table.insert(getgenv().AllControls, controlData)
                
                return dropdownFunction
			end

function sectionFunction:AddKeyBind(Setting, Callback)
    local TitleText = tostring(Setting.Title or Setting.Text) or ""
    local Default = Setting.Default or Setting.Key or "F"
    local Mode = Setting.Mode or "Toggle" -- Hold hoặc Toggle
    local Callback = Setting.Callback or Callback or function() end
    
    local function GetKeyString(key)
        local keyStr = tostring(key)
        keyStr = keyStr:gsub("Enum.UserInputType.", "")
        keyStr = keyStr:gsub("Enum.KeyCode.", "")
        return keyStr
    end
    
    local CurrentKey = GetKeyString(Default)
    local CurrentMode = Mode
    local Picking = false
    local ToggleState = false
    local HoldActive = false
    
    -- UI Elements (BỎ ModeButton)
    local BindFrame = Instance.new("Frame")
    local BindCorner = Instance.new("UICorner")
    local BindBG = Instance.new("Frame")
    local ButtonCorner = Instance.new("UICorner")
    local BindButtonTitle = Instance.new("TextLabel")
    local BindCor = Instance.new("Frame")
    local ButtonCorner_2 = Instance.new("UICorner")
    local Bindkey = Instance.new("TextButton")
    
    BindFrame.Name = TitleText .. "bguvl"
    BindFrame.Parent = Section
    BindFrame.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    BindFrame.BackgroundTransparency = 1.000
    BindFrame.Position = UDim2.new(0, 0, 0.208333328, 0)
    BindFrame.Size = UDim2.new(1, 0, 0, 35)
    
    BindCorner.CornerRadius = UDim.new(0, 4)
    BindCorner.Name = "BindCorner"
    BindCorner.Parent = BindFrame
    
    BindBG.Name = "Background1"
    BindBG.Parent = BindFrame
    BindBG.AnchorPoint = Vector2.new(0.5, 0.5)
    BindBG.Position = UDim2.new(0.5, 0, 0.5, 0)
    BindBG.Size = UDim2.new(1, -10, 1, 0)
    Bind(BindBG, "BackgroundColor3", "Background 1 Color")
    Bind(BindBG, "BackgroundTransparency", "Background 1 Transparency")
    
    ButtonCorner.CornerRadius = UDim.new(0, 4)
    ButtonCorner.Name = "ButtonCorner"
    ButtonCorner.Parent = BindBG
    
    BindButtonTitle.Name = "TextColor"
    BindButtonTitle.Parent = BindBG
    BindButtonTitle.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
    BindButtonTitle.BackgroundTransparency = 1.000
    BindButtonTitle.Position = UDim2.new(0, 10, 0, 0)
    BindButtonTitle.Size = UDim2.new(1, -10, 1, 0)
    BindButtonTitle.Font = Enum.Font.GothamBlack
    BindButtonTitle.Text = TitleText
    BindButtonTitle.TextSize = 14.000
    BindButtonTitle.TextXAlignment = Enum.TextXAlignment.Left
    Bind(BindButtonTitle, "TextColor3", "Text Color")
    
    BindCor.Name = "Background2"
    BindCor.Parent = BindBG
    BindCor.AnchorPoint = Vector2.new(1, 0.5)
    BindCor.Position = UDim2.new(1, -5, 0.5, 0)
    BindCor.Size = UDim2.new(0, 150, 0, 25)
    Bind(BindCor, "BackgroundColor3", "Background 2 Color")
    
    ButtonCorner_2.CornerRadius = UDim.new(0, 4)
    ButtonCorner_2.Name = "ButtonCorner"
    ButtonCorner_2.Parent = BindCor
    
    Bindkey.Name = "Bindkey"
    Bindkey.Parent = BindCor
    Bindkey.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
    Bindkey.BackgroundTransparency = 1.000
    Bindkey.Size = UDim2.new(1, 0, 1, 0)
    Bindkey.Font = Enum.Font.GothamBold
    Bindkey.Text = CurrentKey
    Bindkey.TextSize = 14.000
    Bind(Bindkey, "TextColor3", "Text Color")
    
    -- Change Key
    Bindkey.MouseButton1Click:Connect(function()
        if Picking then return end
        
        Picking = true
        Bindkey.Text = "..."
        
        task.wait(0.2)
        
        local Connection
        Connection = uis.InputBegan:Connect(function(input)
            if Picking then
                local Key
                
                if input.UserInputType == Enum.UserInputType.Keyboard then
                    Key = input.KeyCode.Name
                elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
                    Key = "MouseLeft"
                elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
                    Key = "MouseRight"
                end
                
                if Key then
                    Picking = false
                    CurrentKey = Key
                    Bindkey.Text = Key
                    Connection:Disconnect()
                end
            end
        end)
    end)
    
    -- Input Began (Press)
    uis.InputBegan:Connect(function(input, gpe)
        if gpe or Picking then return end
        if uis:GetFocusedTextBox() then return end
        
        local pressedKey
        if input.UserInputType == Enum.UserInputType.Keyboard then
            pressedKey = input.KeyCode.Name
        elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
            pressedKey = "MouseLeft"
        elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
            pressedKey = "MouseRight"
        end
        
        if pressedKey == CurrentKey then
            if CurrentMode == "Toggle" then
                ToggleState = not ToggleState
                pcall(Callback, ToggleState)
            elseif CurrentMode == "Hold" then
                HoldActive = true
                pcall(Callback, true)
            end
        end
    end)
    
    -- Input Ended (Release) - Only for Hold mode
    uis.InputEnded:Connect(function(input)
        if Picking then return end
        if uis:GetFocusedTextBox() then return end
        
        local releasedKey
        if input.UserInputType == Enum.UserInputType.Keyboard then
            releasedKey = input.KeyCode.Name
        elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
            releasedKey = "MouseLeft"
        elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
            releasedKey = "MouseRight"
        end
        
        if releasedKey == CurrentKey and CurrentMode == "Hold" and HoldActive then
            HoldActive = false
            pcall(Callback, false)
        end
    end)
    
    local controlData = {
        Name = TitleText,
        Section = Section,
        Element = BindFrame,
        SectionName = Section_Name,
        TabName = Page_Name,
        TabButton = PageName
    }
    table.insert(getgenv().AllControls, controlData)
    
    local keybindFunction = {}
    
    function keybindFunction:Set(newKey)
        CurrentKey = GetKeyString(newKey)
        Bindkey.Text = CurrentKey
    end
    
    function keybindFunction:Get()
        return CurrentKey
    end
    
    function keybindFunction:SetMode(mode)
        if mode == "Hold" or mode == "Toggle" then
            CurrentMode = mode
            ToggleState = false
            HoldActive = false
        end
    end
    
    function keybindFunction:GetMode()
        return CurrentMode
    end
    
    function keybindFunction:GetState()
        if CurrentMode == "Toggle" then
            return ToggleState
        elseif CurrentMode == "Hold" then
            return HoldActive
        end
        return false
    end
    
    return keybindFunction
end
			function sectionFunction:AddInput(idk, Setting)
				local TitleText = tostring(Setting.Text or Setting.Title) or ""
				local Placeholder = tostring(Setting.Placeholder) or ""
				local Default = Setting.Default or false
				local Number_Only = Setting.Numeric or false
				local Callback = Setting.Callback
				local BoxFrame = Instance.new("Frame")
				local BoxCorner = Instance.new("UICorner")
				local BoxBG = Instance.new("Frame")
				local ButtonCorner = Instance.new("UICorner")
				local Boxtitle = Instance.new("TextLabel")
				local BoxCor = Instance.new("Frame")
				local ButtonCorner_2 = Instance.new("UICorner")
				local Boxxx = Instance.new("TextBox")
				local Lineeeee = Instance.new("Frame")
				local UICorner = Instance.new("UICorner")
				BoxFrame.Name = "BoxFrame"
				BoxFrame.Parent = Section
				BoxFrame.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
				BoxFrame.BackgroundTransparency = 1.000
				BoxFrame.Position = UDim2.new(0, 0, 0.208333328, 0)
				BoxFrame.Size = UDim2.new(1, 0, 0, 60)
				BoxCorner.CornerRadius = UDim.new(0, 4)
				BoxCorner.Name = "BoxCorner"
				BoxCorner.Parent = BoxFrame
				BoxBG.Name = "Background1"
				BoxBG.Parent = BoxFrame
				BoxBG.AnchorPoint = Vector2.new(0.5, 0.5)
				BoxBG.Position = UDim2.new(0.5, 0, 0.5, 0)
				BoxBG.Size = UDim2.new(1, -10, 1, 0)
				Bind(BoxBG, "BackgroundColor3", "Background 1 Color")
				Bind(BoxBG, "BackgroundTransparency", "Background 1 Transparency")
				ButtonCorner.CornerRadius = UDim.new(0, 4)
				ButtonCorner.Name = "ButtonCorner"
				ButtonCorner.Parent = BoxBG
				Boxtitle.Name = "TextColor"
				Boxtitle.Parent = BoxBG
				Boxtitle.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
				Boxtitle.BackgroundTransparency = 1.000
				Boxtitle.Position = UDim2.new(0, 10, 0, 0)
				Boxtitle.Size = UDim2.new(1, -10, 0.5, 0)
				Boxtitle.Font = Enum.Font.GothamBlack
				Boxtitle.Text = TitleText
				Boxtitle.TextSize = 14.000
				Boxtitle.TextXAlignment = Enum.TextXAlignment.Left
				Bind(Boxtitle, "TextColor3", "Text Color")
				BoxCor.Name = "Background2"
				BoxCor.Parent = BoxBG
				BoxCor.AnchorPoint = Vector2.new(1, 0.5)
				BoxCor.ClipsDescendants = true
				BoxCor.Position = UDim2.new(1, -5, 0, 40)
				BoxCor.Size = UDim2.new(1, -10, 0, 25)
				Bind(BoxCor, "BackgroundColor3", "Background 2 Color")
				ButtonCorner_2.CornerRadius = UDim.new(0, 4)
				ButtonCorner_2.Name = "ButtonCorner"
				ButtonCorner_2.Parent = BoxCor
				Boxxx.Name = "TextColorPlaceholder"
				Boxxx.Parent = BoxCor
				Boxxx.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
				Boxxx.BackgroundTransparency = 1.000
				Boxxx.Position = UDim2.new(0, 5, 0, 0)
				Boxxx.Size = UDim2.new(1, -5, 1, 0)
				Boxxx.Font = Enum.Font.GothamBold
				Boxxx.PlaceholderText = Placeholder
				Boxxx.Text = ""
				Boxxx.TextSize = 14.000
				Boxxx.TextXAlignment = Enum.TextXAlignment.Left
				Bind(Boxxx, "PlaceholderColor3", "Placeholder Text Color")
				Bind(Boxxx, "TextColor3", "Text Color")
				Lineeeee.Name = "TextNSBoxLineeeee"
				Lineeeee.Parent = BoxCor
				Lineeeee.BackgroundTransparency = 1.000
				Lineeeee.Position = UDim2.new(0, 0, 1, -2)
				Lineeeee.Size = UDim2.new(1, 0, 0, 6)
				Bind(Lineeeee, "BackgroundColor3", "Box Highlight Color")
				UICorner.CornerRadius = UDim.new(1, 0)
				UICorner.Parent = Lineeeee
				Boxxx.Focused:Connect(function()
					TweenService:Create(Lineeeee, TI("Tween Animation 2 Speed"), {
						BackgroundTransparency = 0
					}):Play()
				end)
				if Number_Only then
					Boxxx:GetPropertyChangedSignal("Text"):Connect(function()
						if tonumber(Boxxx.Text) then
						else
							Boxxx.PlaceholderText = Placeholder
							Boxxx.Text = ''
						end
					end)
				end
				Boxxx.FocusLost:Connect(function()
					TweenService:Create(Lineeeee, TI("Tween Animation 2 Speed"), {
						BackgroundTransparency = 1
					}):Play()
					if Boxxx.Text ~= '' then
						Callback(Boxxx.Text)
					end
				end)
				local textbox_function = {}
				if Default then
					Boxxx.Text = Default
				end
				function textbox_function.SetValue(Value)
					Boxxx.Text = Value
					Callback(Value)
				end
				local controlData = {
                    Name = TitleText,
                    Section = Section,
                    Element = BoxFrame,
                    SectionName = Section_Name,
                    TabName = Page_Name,
                    TabButton = PageName
                }
                table.insert(getgenv().AllControls, controlData)
                
				return textbox_function;
			end
			function sectionFunction:AddSlider(Setting)
				local TitleText = tostring(Setting.Text or Setting.Title) or ""
				local minValue = tonumber(Setting.Min) or 0
				local maxValue = tonumber(Setting.Max) or 100
				local Precise = Setting.Precise or false
				local DefaultValue = tonumber(Setting.Default) or 0
				local Callback = Setting.Callback
				local SizeChia = 400;
				local SliderFrame = Instance.new("Frame")
				local SliderCorner = Instance.new("UICorner")
				local SliderBG = Instance.new("Frame")
				local SliderBGCorner = Instance.new("UICorner")
				local SliderTitle = Instance.new("TextLabel")
				local SliderBar = Instance.new("Frame")
				local SliderButton = Instance.new("TextButton")
				local SliderBarCorner = Instance.new("UICorner")
				local Bar = Instance.new("Frame")
				local BarCorner = Instance.new("UICorner")
				local Sliderboxframe = Instance.new("Frame")
				local Sliderbox = Instance.new("UICorner")
				local Sliderbox_2 = Instance.new("TextBox")
				SliderFrame.Name = TitleText .. 'buda'
				SliderFrame.Parent = Section
				SliderFrame.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
				SliderFrame.BackgroundTransparency = 1.000
				SliderFrame.Position = UDim2.new(0, 0, 0.208333328, 0)
				SliderFrame.Size = UDim2.new(1, 0, 0, 50)
				SliderCorner.CornerRadius = UDim.new(0, 4)
				SliderCorner.Name = "SliderCorner"
				SliderCorner.Parent = SliderFrame
				SliderBG.Name = "Background1"
				SliderBG.Parent = SliderFrame
				SliderBG.AnchorPoint = Vector2.new(0.5, 0.5)
				SliderBG.Position = UDim2.new(0.5, 0, 0.5, 0)
				SliderBG.Size = UDim2.new(1, -10, 1, 0)
				Bind(SliderBG, "BackgroundColor3", "Background 1 Color")
				Bind(SliderBG, "BackgroundTransparency", "Background 1 Transparency")
				SliderBGCorner.CornerRadius = UDim.new(0, 4)
				SliderBGCorner.Name = "SliderBGCorner"
				SliderBGCorner.Parent = SliderBG
				SliderTitle.Name = "TextColor"
				SliderTitle.Parent = SliderBG
				SliderTitle.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
				SliderTitle.BackgroundTransparency = 1.000
				SliderTitle.Position = UDim2.new(0, 10, 0, 0)
				SliderTitle.Size = UDim2.new(1, -10, 0, 25)
				SliderTitle.Font = Enum.Font.GothamBlack
				SliderTitle.Text = TitleText
				SliderTitle.TextSize = 14.000
				SliderTitle.RichText = true
				SliderTitle.TextXAlignment = Enum.TextXAlignment.Left
				Bind(SliderTitle, "TextColor3", "Text Color")
				SliderBar.Name = "SliderBar"
				SliderBar.Parent = SliderFrame
				SliderBar.AnchorPoint = Vector2.new(.5, 0.5)
				SliderBar.Position = UDim2.new(.5, 0, 0.5, 14)
				SliderBar.Size = UDim2.new(0, 400, 0, 6)
				Bind(SliderBar, "BackgroundColor3", "Background 2 Color")
				SliderButton.Name = "SliderButton "
				SliderButton.Parent = SliderBar
				SliderButton.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
				SliderButton.BackgroundTransparency = 1.000
				SliderButton.Size = UDim2.new(1, 0, 1, 0)
				SliderButton.Font = Enum.Font.GothamBold
				SliderButton.Text = ""
				SliderButton.TextColor3 = Color3.fromRGB(230, 230, 230)
				SliderButton.TextSize = 14.000
				SliderBarCorner.CornerRadius = UDim.new(1, 0)
				SliderBarCorner.Name = "SliderBarCorner"
				SliderBarCorner.Parent = SliderBar
				Bar.Name = "Bar"
				Bar.BorderSizePixel = 0
				Bar.Parent = SliderBar
				Bar.Size = UDim2.new(0, 0, 1, 0)
				Bind(Bar, "BackgroundColor3", "Slider Line Color")
				BarCorner.CornerRadius = UDim.new(1, 0)
				BarCorner.Name = "BarCorner"
				BarCorner.Parent = Bar
				Sliderboxframe.Name = "Background2"
				Sliderboxframe.Parent = SliderFrame
				Sliderboxframe.AnchorPoint = Vector2.new(1, 0)
				Sliderboxframe.Position = UDim2.new(1, -10, 0, 5)
				Sliderboxframe.Size = UDim2.new(0, 150, 0, 25)
				Bind(Sliderboxframe, "BackgroundColor3", "Background 2 Color")
				Sliderbox.CornerRadius = UDim.new(0, 4)
				Sliderbox.Name = "Sliderbox"
				Sliderbox.Parent = Sliderboxframe
				Sliderbox_2.Name = "TextColor"
				Sliderbox_2.Parent = Sliderboxframe
				Sliderbox_2.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
				Sliderbox_2.BackgroundTransparency = 1.000
				Sliderbox_2.Size = UDim2.new(1, 0, 1, 0)
				Sliderbox_2.Font = Enum.Font.GothamBold
				Sliderbox_2.Text = ""
				Sliderbox_2.TextSize = 14.000
				Bind(Sliderbox_2, "TextColor3", "Text Color")
				SliderButton.MouseEnter:Connect(function()
					TweenService:Create(Bar, TI("Tween Animation 2 Speed"), {
						BackgroundColor3 = getgenv().UIColor["Slider Highlight Color"]
					}):Play()
				end)
				SliderButton.MouseLeave:Connect(function()
					TweenService:Create(Bar, TI("Tween Animation 2 Speed"), {
						BackgroundColor3 = getgenv().UIColor["Slider Line Color"]
					}):Play()
				end)
				local callBackAndSetText = function(val)
					Sliderbox_2.Text = val
					Callback(tonumber(val))
				end
				if DefaultValue then
					if DefaultValue <= minValue then
						DefaultValue = minValue
					elseif DefaultValue >= maxValue then
						DefaultValue = maxValue
					end
					Sliderbox_2.Text = tostring(DefaultValue)
					Bar.Size = UDim2.new(1 - ((maxValue - DefaultValue) / (maxValue - minValue)), 0, 0, 6)
				end
				local dragging = false
				local dragInput
				local holdTime = 0 -- Time to hold before dragging is enabled
				local holdStarted = 0

						-- Function to detect the start of dragging (for both mouse and touch)
				local function onInputBegan(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						holdStarted = tick() -- Record the time when holding starts
						
								-- Listen for release to stop dragging
						input.Changed:Connect(function()
							if input.UserInputState == Enum.UserInputState.End then
								dragging = false
								holdStarted = 0 -- Reset the hold timer
							end
						end)
					end
				end
						
						-- Function to detect when dragging stops
				local function onInputEnded(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						dragging = false
						holdStarted = 0 -- Reset the hold timer
					end
				end

						-- Detect input movement (for both mouse and touch)
				local function onInputChanged(input)
					if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
						dragInput = input
					end
				end
						
						-- Connect the events
				SliderButton.InputBegan:Connect(onInputBegan)
				SliderButton.InputEnded:Connect(onInputEnded)
				SliderButton.InputChanged:Connect(onInputChanged)
						
						-- RenderStepped updates the position while dragging
				RunService.RenderStepped:Connect(function()
					if holdStarted > 0 and (tick() - holdStarted >= holdTime) and not dragging then
						dragging = true
					end
					if dragging and dragInput then
						local value = Setting.Rouding and  tonumber(string.format("%." .. (Setting.Rouding or 1) .. "f", (((tonumber(maxValue) - tonumber(minValue)) / SizeChia) * Bar.AbsoluteSize.X) + tonumber(minValue))) or math.floor((((tonumber(maxValue) - tonumber(minValue)) / SizeChia) * Bar.AbsoluteSize.X) + tonumber(minValue))
						pcall(function()
							callBackAndSetText(value)
						end)
						Bar.Size = UDim2.new(0, math.clamp(dragInput.Position.X - Bar.AbsolutePosition.X, 0, SizeChia), 0, 6)
					end
				end)
				local function GetSliderValue(Value)
					if tonumber(Value) <= minValue then
						Bar.Size = UDim2.new(0, (0 * SizeChia), 0, 6)
						callBackAndSetText(minValue)
					elseif tonumber(Value) >= maxValue then
						Bar.Size = UDim2.new(0, (maxValue  /  maxValue * SizeChia), 0, 6)
						callBackAndSetText(maxValue)
					else
						Bar.Size = UDim2.new(1 - ((maxValue - Value) / (maxValue - minValue)), 0, 0, 6)
						callBackAndSetText(Value)
					end
				end
				Sliderbox_2.FocusLost:Connect(function()
					GetSliderValue(Sliderbox_2.Text)
				end)
				local slider_function = {}
				function slider_function.SetValue(Value)
					GetSliderValue(Value)
				end
				local controlData = {
                    Name = TitleText,
                    Section = Section,
                    Element = SliderFrame,
                    SectionName = Section_Name,
                    TabName = Page_Name,
                    TabButton = PageName
                }
                table.insert(getgenv().AllControls, controlData)
                
				return slider_function
			end

			-- Color picker (Peridot addition): a row with a swatch; clicking it opens a
			-- saturation/brightness square, a hue bar, a hex box and a Rainbow button.
			-- Setting: Title, Default (Color3), Callback(color),
			--          Rainbow = { Get = fn() -> bool, Set = fn(on) } to own rainbow state (theme keys);
			--          without it the picker cycles the hue itself and calls Callback.
			function sectionFunction:AddColorPicker(Setting)
				local Title = tostring(Setting.Title or Setting.Text or "")
				local Callback = Setting.Callback
				local color = typeof(Setting.Default) == "Color3" and Setting.Default or Color3.new(1, 1, 1)
				local hue, sat, val = color:ToHSV()
				local opened = false
				local dragging
				local localRainbow

				local PickerFrame = Instance.new("Frame")
				PickerFrame.Name = Title .. "ColorPicker"
				PickerFrame.Parent = Section
				PickerFrame.BackgroundTransparency = 1
				PickerFrame.ClipsDescendants = true
				PickerFrame.Size = UDim2.new(1, 0, 0, 35)

				local PickerBG = Instance.new("Frame")
				PickerBG.Name = "Background1"
				PickerBG.Parent = PickerFrame
				PickerBG.AnchorPoint = Vector2.new(0.5, 0)
				PickerBG.Position = UDim2.new(0.5, 0, 0, 0)
				PickerBG.Size = UDim2.new(1, -10, 1, 0)
				Bind(PickerBG, "BackgroundColor3", "Background 1 Color")
				Bind(PickerBG, "BackgroundTransparency", "Background 1 Transparency")
				local PickerCorner = Instance.new("UICorner")
				PickerCorner.CornerRadius = UDim.new(0, 4)
				PickerCorner.Parent = PickerBG

				local PickerTitle = Instance.new("TextButton")
				PickerTitle.Name = "TextColor"
				PickerTitle.Parent = PickerBG
				PickerTitle.BackgroundTransparency = 1
				PickerTitle.AutoButtonColor = false
				PickerTitle.Position = UDim2.new(0, 10, 0, 0)
				PickerTitle.Size = UDim2.new(1, -70, 0, 35)
				PickerTitle.Font = Enum.Font.GothamBlack
				PickerTitle.Text = Title
				PickerTitle.TextSize = 14
				PickerTitle.TextXAlignment = Enum.TextXAlignment.Left
				Bind(PickerTitle, "TextColor3", "Text Color")

				local Swatch = Instance.new("TextButton")
				Swatch.Name = "Swatch"
				Swatch.Parent = PickerBG
				Swatch.AnchorPoint = Vector2.new(1, 0)
				Swatch.Position = UDim2.new(1, -8, 0, 7)
				Swatch.Size = UDim2.new(0, 44, 0, 21)
				Swatch.AutoButtonColor = false
				Swatch.Text = ""
				Swatch.BackgroundColor3 = color
				local SwatchCorner = Instance.new("UICorner")
				SwatchCorner.CornerRadius = UDim.new(0, 4)
				SwatchCorner.Parent = Swatch
				local SwatchStroke = Instance.new("UIStroke")
				Bind(SwatchStroke, "Color", "Outline Color")
				SwatchStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				SwatchStroke.Parent = Swatch

				-- saturation (left -> right) / brightness (top -> bottom) square over the hue color
				local SV = Instance.new("TextButton")
				SV.Name = "SaturationValue"
				SV.Parent = PickerBG
				SV.Position = UDim2.new(0, 10, 0, 40)
				SV.Size = UDim2.new(0, 150, 0, 100)
				SV.AutoButtonColor = false
				SV.Text = ""
				local SVCorner = Instance.new("UICorner")
				SVCorner.CornerRadius = UDim.new(0, 4)
				SVCorner.Parent = SV
				local SVImage = Instance.new("ImageLabel")
				SVImage.Parent = SV
				SVImage.BackgroundTransparency = 1
				SVImage.Size = UDim2.new(1, 0, 1, 0)
				SVImage.Image = "rbxassetid://4155801252" -- white-to-clear / clear-to-black overlay (the old library's picker)
				local SVImageCorner = Instance.new("UICorner")
				SVImageCorner.CornerRadius = UDim.new(0, 4)
				SVImageCorner.Parent = SVImage
				local SVCursor = Instance.new("Frame")
				SVCursor.Parent = SV
				SVCursor.AnchorPoint = Vector2.new(0.5, 0.5)
				SVCursor.Size = UDim2.new(0, 8, 0, 8)
				SVCursor.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				SVCursor.ZIndex = 3
				local SVCursorCorner = Instance.new("UICorner")
				SVCursorCorner.CornerRadius = UDim.new(1, 0)
				SVCursorCorner.Parent = SVCursor
				local SVCursorStroke = Instance.new("UIStroke")
				SVCursorStroke.Color = Color3.fromRGB(20, 20, 20)
				SVCursorStroke.Parent = SVCursor

				-- hue bar, top (0) to bottom (1)
				local HueBar = Instance.new("TextButton")
				HueBar.Name = "Hue"
				HueBar.Parent = PickerBG
				HueBar.Position = UDim2.new(0, 170, 0, 40)
				HueBar.Size = UDim2.new(0, 14, 0, 100)
				HueBar.AutoButtonColor = false
				HueBar.Text = ""
				HueBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				local HueCorner = Instance.new("UICorner")
				HueCorner.CornerRadius = UDim.new(0, 4)
				HueCorner.Parent = HueBar
				local HueGradient = Instance.new("UIGradient")
				local hueKeys = {}
				for i = 0, 6 do
					table.insert(hueKeys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6 % 1, 1, 1)))
				end
				HueGradient.Color = ColorSequence.new(hueKeys)
				HueGradient.Rotation = 90
				HueGradient.Parent = HueBar
				local HueCursor = Instance.new("Frame")
				HueCursor.Parent = HueBar
				HueCursor.AnchorPoint = Vector2.new(0.5, 0.5)
				HueCursor.Size = UDim2.new(1, 4, 0, 3)
				HueCursor.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				HueCursor.BorderSizePixel = 0
				HueCursor.ZIndex = 3

				local HexBox = Instance.new("TextBox")
				HexBox.Name = "Hex"
				HexBox.Parent = PickerBG
				HexBox.Position = UDim2.new(0, 196, 0, 40)
				HexBox.Size = UDim2.new(1, -206, 0, 25)
				HexBox.Font = Enum.Font.GothamBold
				HexBox.TextSize = 14
				HexBox.PlaceholderText = "#RRGGBB"
				HexBox.ClearTextOnFocus = false
				Bind(HexBox, "BackgroundColor3", "Background 2 Color")
				Bind(HexBox, "TextColor3", "Text Color")
				Bind(HexBox, "PlaceholderColor3", "Placeholder Text Color")
				local HexCorner = Instance.new("UICorner")
				HexCorner.CornerRadius = UDim.new(0, 4)
				HexCorner.Parent = HexBox

				local RainbowButton = Instance.new("TextButton")
				RainbowButton.Name = "Rainbow"
				RainbowButton.Parent = PickerBG
				RainbowButton.Position = UDim2.new(0, 196, 0, 72)
				RainbowButton.Size = UDim2.new(1, -206, 0, 25)
				RainbowButton.AutoButtonColor = false
				RainbowButton.Font = Enum.Font.GothamBold
				RainbowButton.TextSize = 14
				Bind(RainbowButton, "BackgroundColor3", "Background 2 Color")
				Bind(RainbowButton, "TextColor3", "Text Color")
				local RainbowCorner = Instance.new("UICorner")
				RainbowCorner.CornerRadius = UDim.new(0, 4)
				RainbowCorner.Parent = RainbowButton

				local function rainbowOn()
					if Setting.Rainbow then
						return Setting.Rainbow.Get()
					end
					return localRainbow ~= nil
				end
				local function refreshRainbowText()
					RainbowButton.Text = rainbowOn() and "Rainbow: on" or "Rainbow: off"
				end

				local function show(fire)
					color = Color3.fromHSV(hue, sat, val)
					Swatch.BackgroundColor3 = color
					SV.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
					SVCursor.Position = UDim2.new(sat, 0, 1 - val, 0)
					HueCursor.Position = UDim2.new(0.5, 0, hue, 0)
					HexBox.Text = string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
					if fire and Callback then
						pcall(Callback, color)
					end
				end

				local function setRainbow(on)
					if Setting.Rainbow then
						Setting.Rainbow.Set(on)
					elseif on and not localRainbow then
						localRainbow = RunService.Heartbeat:Connect(function()
							if not PickerFrame.Parent then
								localRainbow:Disconnect()
								return
							end
							hue = (tick() % 6) / 6
							sat, val = math.max(sat, 0.45), math.max(val, 0.6)
							show(true)
						end)
					elseif not on and localRainbow then
						localRainbow:Disconnect()
						localRainbow = nil
					end
					refreshRainbowText()
				end

				local function pick(position)
					if dragging == "sv" then
						sat = math.clamp((position.X - SV.AbsolutePosition.X) / SV.AbsoluteSize.X, 0, 1)
						val = 1 - math.clamp((position.Y - SV.AbsolutePosition.Y) / SV.AbsoluteSize.Y, 0, 1)
					elseif dragging == "hue" then
						hue = math.clamp((position.Y - HueBar.AbsolutePosition.Y) / HueBar.AbsoluteSize.Y, 0, 0.999)
					end
					show(true)
				end
				local function startDrag(kind)
					return function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
							if rainbowOn() then
								setRainbow(false) -- picking a color stops the rainbow
							end
							dragging = kind
							pick(input.Position)
						end
					end
				end
				SV.InputBegan:Connect(startDrag("sv"))
				HueBar.InputBegan:Connect(startDrag("hue"))
				uis.InputChanged:Connect(function(input)
					if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
						pick(input.Position)
					end
				end)
				uis.InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						dragging = nil
					end
				end)

				HexBox.FocusLost:Connect(function()
					local hex = HexBox.Text:gsub("#", "")
					if hex:match("^%x%x%x%x%x%x$") then
						if rainbowOn() then
							setRainbow(false)
						end
						hue, sat, val = Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)):ToHSV()
						show(true)
					else
						show(false) -- put the current color back
					end
				end)

				RainbowButton.MouseButton1Click:Connect(function()
					setRainbow(not rainbowOn())
				end)

				local function toggleOpen()
					opened = not opened
					TweenService:Create(PickerFrame, TI("Tween Animation 2 Speed"), {
						Size = UDim2.new(1, 0, 0, opened and 150 or 35)
					}):Play()
				end
				Swatch.MouseButton1Click:Connect(toggleOpen)
				PickerTitle.MouseButton1Click:Connect(toggleOpen)

				show(false)
				refreshRainbowText()

				local controlData = {
					Name = Title,
					Section = Section,
					Element = PickerFrame,
					SectionName = Section_Name,
					TabName = Page_Name,
					TabButton = PageName
				}
				table.insert(getgenv().AllControls, controlData)

				local picker = {}
				function picker.SetValue(newColor)
					hue, sat, val = newColor:ToHSV()
					show(false)
				end
				function picker.GetValue()
					return color
				end
				function picker.RefreshRainbow()
					refreshRainbowText()
				end
				-- the swatch follows a theme key live (e.g. while its rainbow runs)
				function picker.FollowKey(key)
					Bind(Swatch, "BackgroundColor3", key)
				end
				return picker
			end
			return sectionFunction
		end
		-- Sub-tabs: a strip under the page title; each sub-tab shows only its own sections.
		local SubTabBar
		local SubTabs = {}
		local SubTabCount = 0
		local function applySubTabVisibility()
			for frame, owner in pairs(SectionOwner) do
				frame.Visible = owner == ActiveSubTab
			end
		end
		local function selectSubTab(name)
			ActiveSubTab = name
			for subName, sub in pairs(SubTabs) do
				local selected = subName == name
				TweenService:Create(sub.Button, TI("Tween Animation 3 Speed"), {
					TextColor3 = selected and getgenv().UIColor["GUI Text Color"] or getgenv().UIColor["Placeholder Text Color"]
				}):Play()
				TweenService:Create(sub.Underline, TI("Tween Animation 1 Speed"), {
					Size = selected and UDim2.new(1, 0, 0, 2) or UDim2.new(0, 0, 0, 2)
				}):Play()
			end
			applySubTabVisibility()
			PageList.CanvasPosition = Vector2.new(0, 0)
		end

        local pagefunc = {}
        function pagefunc:AddLeftGroupbox(name)
            return pageFunction:AddSection(name)
        end
        function pagefunc:AddRightGroupbox(name)
            return pageFunction:AddSection(name)
        end
		function pagefunc:AddSubTab(name)
			name = tostring(name)
			if not SubTabBar then
				SubTabBar = Instance.new("ScrollingFrame")
				SubTabBar.Name = "SubTabBar"
				SubTabBar.Parent = PageContainer
				SubTabBar.BackgroundTransparency = 1
				SubTabBar.BorderSizePixel = 0
				SubTabBar.Position = UDim2.new(0, 5, 0, 28)
				SubTabBar.Size = UDim2.new(1, -10, 0, 26)
				SubTabBar.ScrollingDirection = Enum.ScrollingDirection.X -- scrolls sideways when the tabs don't fit
				SubTabBar.ScrollBarThickness = 0
				SubTabBar.CanvasSize = UDim2.new(0, 0, 0, 0)
				SubTabBar.AutomaticCanvasSize = Enum.AutomaticSize.X
				local layout = Instance.new("UIListLayout")
				layout.Parent = SubTabBar
				layout.FillDirection = Enum.FillDirection.Horizontal
				layout.SortOrder = Enum.SortOrder.LayoutOrder
				layout.Padding = UDim.new(0, 14)
				local padding = Instance.new("UIPadding")
				padding.PaddingLeft = UDim.new(0, 4)
				padding.PaddingRight = UDim.new(0, 4)
				padding.Parent = SubTabBar
				-- sections start below the strip
				PageList.Position = UDim2.new(0, 5, 0, 58)
				PageList.Size = UDim2.new(1, -10, 1, -58)
				table.insert(SubTabRestorers, applySubTabVisibility)
			end

			SubTabCount = SubTabCount + 1
			local button = Instance.new("TextButton")
			button.Name = name .. "_SubTab"
			button.Parent = SubTabBar
			button.LayoutOrder = SubTabCount
			button.AutomaticSize = Enum.AutomaticSize.X
			button.Size = UDim2.new(0, 0, 1, 0)
			button.BackgroundTransparency = 1
			button.AutoButtonColor = false
			button.Font = Enum.Font.GothamBold
			button.Text = name
			button.TextSize = 14
			Bind(button, "TextColor3", "Placeholder Text Color")

			local underline = Instance.new("Frame")
			underline.Name = "Underline"
			underline.Parent = button
			underline.AnchorPoint = Vector2.new(0.5, 1)
			underline.Position = UDim2.new(0.5, 0, 1, 0)
			underline.Size = UDim2.new(0, 0, 0, 2)
			underline.BorderSizePixel = 0
			Bind(underline, "BackgroundColor3", "Page Selected Color")
			local underlineCorner = Instance.new("UICorner")
			underlineCorner.CornerRadius = UDim.new(1, 0)
			underlineCorner.Parent = underline

			SubTabs[name] = { Button = button, Underline = underline }
			button.MouseButton1Click:Connect(function()
				selectSubTab(name)
			end)
			if not ActiveSubTab then
				selectSubTab(name) -- the first sub-tab starts selected
			end

			local subTab = {}
			function subTab:AddSection(sectionName, ...)
				local section = pageFunction:AddSection(sectionName, ...)
				SectionOwner[section.Frame] = name
				section.Frame.Visible = ActiveSubTab == name
				return section
			end
			subTab.AddLeftGroupbox = subTab.AddSection
			subTab.AddRightGroupbox = subTab.AddSection
			function subTab:Select()
				selectSubTab(name)
			end
			return subTab
		end
		return pagefunc
        end

	-- Interface Settings: the page behind the title-bar gear, like the old library's
	-- customizer. Sub-tabs: Theme (accent, logo), Colors (a picker per theme color,
	-- each with Rainbow), Window (panels, animation, reset), plus any the script adds
	-- (Universal: Background). Everything saves to Peridot/Theme.json. Built on first
	-- use so it sorts after the script's own pages.
	local ColorGroups = {
		{ "Main", { "Title Text Color", "Setting Icon Color", "Search Icon Color", "Search Icon Highlight Color" } },
		{ "Text", { "GUI Text Color", "Text Color", "Placeholder Text Color", "Section Text Color", "Toggle Desc Color" } },
		{ "Background", { "Background Main Color", "Sidebar Color", "Section Panel Color", "Background 1 Color", "Background 2 Color", "Background 3 Color", "Label Color" } },
		{ "Outline", { "Outline Color", "Border Color" } },
		{ "Controls", { "Page Selected Color", "Section Underline Color", "Toggle Border Color", "Toggle Checked Color", "Button Color",
			"Dropdown Icon Color", "Dropdown Selected Check Color", "Box Highlight Color", "Slider Line Color", "Slider Highlight Color" } },
	}
	-- Border Color is the ring around the floating toggle button; the rest are named after their key
	local ColorTitles = { ["Border Color"] = "Toggle button border" }
	local AnimationSliders = {
		{ "Tween Animation 1 Speed", "Page & toggle speed", 0.75, "AnimationSpeed1" },
		{ "Tween Animation 2 Speed", "Dropdown & slider speed", 1, "AnimationSpeed" },
		{ "Tween Animation 3 Speed", "Hover speed", 0.5, "AnimationSpeed3" },
	}

	function Main_Function:GetUISettingsPage()
		if UISettingsPage then
			return UISettingsPage
		end
		UISettingsPage = Main_Function:AddTab("Interface Settings", { Hidden = true })
		local themeTab = UISettingsPage:AddSubTab("Theme")
		local colorsTab = UISettingsPage:AddSubTab("Colors")
		local windowTab = UISettingsPage:AddSubTab("Window")
		local toggleTab = UISettingsPage:AddSubTab("UI Toggle")
		local pickers = {}
		local sliders = {}

		-- Theme: accent presets / custom accent, logo
		local accentSection = themeTab:AddSection("Accent")
		local presetNames = {}
		for _, preset in ipairs(AccentPresets) do
			table.insert(presetNames, preset[1])
		end
		local accentDropdown = accentSection:AddDropdown(nil, {
			Title = "Preset",
			Values = presetNames,
			Default = SavedTheme.Preset or "Peridot",
			Callback = function(name)
				for _, preset in ipairs(AccentPresets) do
					if preset[1] == name then
						FadeTheme(function()
							Library_Function.SetAccent(preset[2], name)
						end)
					end
				end
			end,
		})
		-- Any color: square + hue bar + hex box, and Rainbow for the whole accent.
		local fromAccentPicker = false -- the picker's own drags must not reset it through OnAccentChanged
		local accentPicker = accentSection:AddColorPicker({
			Title = "Accent color",
			Default = getgenv().UIColor["Title Text Color"],
			Callback = function(color)
				fromAccentPicker = true
				Library_Function.SetAccent(color, "Custom")
				fromAccentPicker = false
				accentDropdown:ClearText("Custom")
			end,
			Rainbow = {
				Get = function()
					return RainbowKeys["Title Text Color"] ~= nil
				end,
				Set = function(on)
					Library_Function.SetAccentRainbow(on)
				end,
			},
		})
		accentPicker.FollowKey("Title Text Color") -- the swatch shows the live accent, rainbow included
		local logoSection = themeTab:AddSection("Icon")
		logoSection:AddInput(nil, {
			Title = "Icon image",
			Placeholder = "rbxassetid://, image URL or workspace file",
			Callback = function(text)
				local ok, err = Library_Function.SetLogo(text)
				if not ok then
					Library:Notify({ Title = "Icon", Desc = tostring(err), Duration = 4 }, true)
				end
			end,
		})
		logoSection:AddButton({
			Title = "Reset Icon",
			ButtonText = "Reset", -- back to the main Peridot icon
			Callback = function()
				Library_Function.SetLogo("")
			end,
		})

		-- Themes: whole looks (every color, panels, animation, icon, background picture) that can be
		-- picked, saved, shared and made the default. The library behind it is ThemeSystem.
		local function themeNotice(text)
			Library:Notify({ Title = "Themes", Desc = text, Duration = 4 }, true)
		end
		local themeList = ThemeSystem.ListBuiltIn()
		local pickedBuiltIn
		local themesSection = themeTab:AddSection("Preinstalled Themes")
		themesSection:AddDropdown(nil, {
			Title = "Theme list",
			Values = themeList,
			Search = true,
			Callback = function(name)
				pickedBuiltIn = name
				local ok, err = ThemeSystem.Apply(name)
				if not ok then
					themeNotice(tostring(err))
				end
			end,
		})
		themesSection:AddLabel("A theme sets all the colors. Most also bring their own background picture.")
		themesSection:AddButton({
			Title = "Set as default",
			ButtonText = "Set",
			Callback = function()
				if not pickedBuiltIn then
					return themeNotice("Pick a theme from the list first.")
				end
				local ok, err = ThemeSystem.SetDefault(pickedBuiltIn)
				themeNotice(ok and (pickedBuiltIn .. " now loads every time you run Peridot.") or tostring(err))
				Library_Function.RefreshDefaultTheme()
			end,
		})

		local customSection = themeTab:AddSection("My Themes")
		local typedThemeName, pickedCustom = "", nil
		customSection:AddInput(nil, {
			Title = "Custom theme name",
			Placeholder = "name",
			Callback = function(text)
				typedThemeName = text
			end,
		})
		local customDropdown
		local function refreshCustomThemes()
			if customDropdown then
				customDropdown:GetNewList(ThemeSystem.List())
			end
			pickedCustom = nil -- the dropdown clears its selection when its list changes
		end
		customSection:AddButton({
			Title = "Create theme",
			ButtonText = "Create",
			Callback = function()
				local ok, err = ThemeSystem.Create(typedThemeName)
				themeNotice(ok and ("Saved " .. typedThemeName .. " from your current look.") or tostring(err))
				if ok then
					refreshCustomThemes()
				end
			end,
		})
		customDropdown = customSection:AddDropdown(nil, {
			Title = "Custom themes",
			Values = ThemeSystem.List(),
			Callback = function(name)
				pickedCustom = name
			end,
		})
		local function withPickedCustom(action)
			if not pickedCustom or pickedCustom == "" then
				return themeNotice("Pick one of your themes from the list first.")
			end
			action(pickedCustom)
		end
		customSection:AddButton({
			Title = "Load theme",
			ButtonText = "Load",
			Callback = function()
				withPickedCustom(function(name)
					local ok, err = ThemeSystem.Apply(name)
					themeNotice(ok and ("Loaded " .. name) or tostring(err))
				end)
			end,
		})
		customSection:AddButton({
			Title = "Overwrite theme",
			ButtonText = "Overwrite",
			Callback = function()
				withPickedCustom(function(name)
					local ok, err = ThemeSystem.Save(name)
					themeNotice(ok and ("Saved your current look over " .. name) or tostring(err))
				end)
			end,
		})
		customSection:AddButton({
			Title = "Delete theme",
			ButtonText = "Delete",
			Callback = function()
				withPickedCustom(function(name)
					local ok, err = ThemeSystem.Delete(name)
					themeNotice(ok and ("Deleted " .. name) or tostring(err))
					refreshCustomThemes()
					Library_Function.RefreshDefaultTheme()
				end)
			end,
		})
		customSection:AddButton({
			Title = "Refresh list",
			ButtonText = "Refresh",
			Callback = refreshCustomThemes,
		})
		customSection:AddButton({
			Title = "Set as default",
			ButtonText = "Set",
			Callback = function()
				withPickedCustom(function(name)
					local ok, err = ThemeSystem.SetDefault(name)
					themeNotice(ok and (name .. " now loads every time you run Peridot.") or tostring(err))
					Library_Function.RefreshDefaultTheme()
				end)
			end,
		})
		customSection:AddButton({
			Title = "Reset default",
			ButtonText = "Reset",
			Callback = function()
				ThemeSystem.ClearDefault()
				themeNotice("No theme loads at start now.")
				Library_Function.RefreshDefaultTheme()
			end,
		})
		local defaultThemeLabel = customSection:AddLabel("Current default theme: none")
		Library_Function.RefreshDefaultTheme = function()
			defaultThemeLabel:SetText("Current default theme: " .. (ThemeSystem.GetDefault() or "none"))
		end
		Library_Function.RefreshDefaultTheme()
		customSection:AddLabel("The default theme loads at the start. Changes you make while playing are kept until then.")

		local shareSection = themeTab:AddSection("Share Theme")
		local themeJson = ""
		local themeJsonBox = shareSection:AddInput(nil, {
			Title = "Theme JSON",
			Placeholder = "paste theme JSON here",
			Callback = function(text)
				themeJson = text
			end,
		})
		shareSection:AddButton({
			Title = "Import theme",
			ButtonText = "Import",
			Callback = function()
				local ok, err = ThemeSystem.Import(themeJson)
				themeNotice(ok and "Imported the pasted theme." or tostring(err))
			end,
		})
		shareSection:AddButton({
			Title = "Export current theme",
			ButtonText = "Export",
			Callback = function()
				local text = ThemeSystem.Export()
				themeJsonBox.SetValue(text)
				local copied = type(setclipboard) == "function" and pcall(setclipboard, text)
				themeNotice(copied and "Theme JSON copied to the clipboard." or "Theme JSON is in the box above.")
			end,
		})

		-- Colors: one picker per theme color, grouped like the old customizer
		for _, group in ipairs(ColorGroups) do
			local section = colorsTab:AddSection(group[1])
			for _, key in ipairs(group[2]) do
				local picker = section:AddColorPicker({
					Title = ColorTitles[key] or (key:gsub(" Color$", "")),
					Default = getgenv().UIColor[key],
					Callback = function(color)
						Library_Function.SetThemeColor(key, color)
					end,
					Rainbow = {
						Get = function()
							return RainbowKeys[key] ~= nil
						end,
						Set = function(on)
							Library_Function.SetRainbow(key, on)
						end,
					},
				})
				picker.FollowKey(key) -- the swatch shows the live color, rainbow included
				pickers[key] = picker
			end
		end
		-- accent presets change several colors at once; keep the pickers in step
		Library_Function.OnAccentChanged = function()
			if not fromAccentPicker then
				accentPicker.SetValue(getgenv().UIColor["Title Text Color"])
				accentPicker.RefreshRainbow()
			end
			for key, picker in pairs(pickers) do
				picker.SetValue(getgenv().UIColor[key])
				picker.RefreshRainbow()
			end
		end

		-- Window: panel transparency, animation speeds, easing, reset
		local panelSection = windowTab:AddSection("Window Look")
		local styleDropdown = panelSection:AddDropdown(nil, {
			Title = "Window style",
			Values = { "Solid", "Transparent" },
			Default = SavedTheme.WindowStyle or "Solid",
			Callback = function(style)
				Library_Function.SetWindowStyle(style)
			end,
		})
		sliders.transparency = panelSection:AddSlider({
			Title = "Panel transparency",
			Min = 0,
			Max = PANEL_MAX,
			Rouding = 2,
			Default = getgenv().UIColor["Background 1 Transparency"],
			Callback = function(value)
				getgenv().UIColor["Background 1 Transparency"] = value
				SavedTheme.PanelTransparency = value
				saveThemeSoon()
			end,
		})
		panelSection:AddLabel("Solid: a dark window.\nTransparent: the game shows through, like glass.\nPanel transparency: how much shows through the menus.")
		local animationSection = windowTab:AddSection("Animation")
		for _, spec in ipairs(AnimationSliders) do
			sliders[spec[1]] = animationSection:AddSlider({
				Title = spec[2],
				Min = 0,
				Max = spec[3],
				Rouding = 2,
				Default = getgenv().UIColor[spec[1]],
				Callback = function(value)
					getgenv().UIColor[spec[1]] = value
					SavedTheme[spec[4]] = value
					saveThemeSoon()
				end,
			})
		end
		local easingDropdown = animationSection:AddDropdown(nil, {
			Title = "Easing style",
			Values = { "Quad", "Quint", "Back", "Sine", "Linear" },
			Default = getgenv().UIColor["Tween Easing Style"],
			Callback = function(style)
				getgenv().UIColor["Tween Easing Style"] = style
				SavedTheme.Easing = style
				saveThemeSoon()
			end,
		})
		-- UI Toggle: the button that opens/closes the UI, and the key that does the same
		local buttonSection = toggleTab:AddSection("UI Toggle button")
		local showToggle = buttonSection:AddToggle(nil, {
			Title = "Show button",
			Default = Library_Function.HideGui.Enabled,
			Callback = function(on)
				Library_Function.SetButtonVisible(on)
			end,
		})
		local sizeSlider = buttonSection:AddSlider({
			Title = "Button size",
			Min = 28,
			Max = 64,
			Default = ButtonSize,
			Callback = function(value)
				Library_Function.SetButtonSize(value)
			end,
		})
		local menuSection = toggleTab:AddSection("UI Toggle key")
		local menuKeybind = menuSection:AddKeyBind({
			Title = "Toggle key",
			Default = MenuKeyName,
			Mode = "Toggle",
		}, function() end) -- the key itself is handled by the library, so it works before this page exists
		menuSection:AddLabel("Opens and closes the UI, even with the button hidden.")
		Library_Function.MenuKeybind = menuKeybind
		-- Picking a new key on the control is saved by watching it.
		local menuKeyWatcher
		menuKeyWatcher = RunService.Heartbeat:Connect(function()
			if not Library_Function.Gui.Parent then
				menuKeyWatcher:Disconnect()
				return
			end
			local key = menuKeybind:Get()
			if key ~= MenuKeyName then
				MenuKeyName = key
				SavedTheme.MenuKey = key
				saveThemeSoon()
			end
		end)

		-- picking a background picture sets the panel transparency too; keep the slider in step
		Library_Function.OnPanelsChanged = function()
			sliders.transparency.SetValue(getgenv().UIColor["Background 1 Transparency"])
		end

		-- a theme changes the accent, colors, panels, speeds and easing at once; show the new values
		Library_Function.OnThemeApplied = function()
			Library_Function.OnAccentChanged()
			styleDropdown:ClearText(SavedTheme.WindowStyle or "Solid")
			accentDropdown:ClearText(SavedTheme.Preset or "Peridot")
			easingDropdown:ClearText(getgenv().UIColor["Tween Easing Style"])
			sliders.transparency.SetValue(getgenv().UIColor["Background 1 Transparency"])
			for _, spec in ipairs(AnimationSliders) do
				sliders[spec[1]].SetValue(getgenv().UIColor[spec[1]])
			end
		end

		windowTab:AddSection("Reset"):AddButton({
			Title = "Reset theme",
			ButtonText = "Reset",
			Callback = function()
				FadeTheme(function()
					Library_Function.ResetTheme()
				end)
				Library_Function.OnAccentChanged()
				accentDropdown:ClearText("Peridot")
				styleDropdown:ClearText("Solid")
				easingDropdown:ClearText(DefaultTheme["Tween Easing Style"])
				sliders.transparency.SetValue(DefaultTheme["Background 1 Transparency"])
				for _, spec in ipairs(AnimationSliders) do
					sliders[spec[1]].SetValue(DefaultTheme[spec[1]])
				end
				-- Interface options too
				sizeSlider.SetValue(38)
				showToggle.SetStage(Library_Function.DefaultFloatingButton ~= false)
				Library_Function.SetMenuKey("RightControl")
			end,
		})
		return UISettingsPage
	end

	-- Gear: open Interface Settings, or go back to the page you came from.
	Library_Function.ToggleUISettings = function()
		Main_Function:GetUISettingsPage()
		if CurrentSelect == UISettingsSelect then
			if PreviousSelect then
				PreviousSelect()
			end
		else
			PreviousSelect = CurrentSelect
			UISettingsSelect()
		end
	end

	return Main_Function
end

--------------------------------------------------------------------------------
-- Peridot API
-- Universal.lua and the Blox Fruits module (through BloxFruitsUIAdapter) were
-- written against the old SeaUI-style API. This layer keeps that API and draws
-- everything with BananaLib above, so none of those scripts had to change.
--------------------------------------------------------------------------------

local HttpService = game:GetService("HttpService")

local Peridot = {
	VERSION = "BananaLib v2 (Peridot)",
	HasFileSystem = HasFileSystem,
	Banana = Library, -- raw BananaLib API, for new code that wants it directly
	Internal = {
		Gui = Library_Function.Gui,
		NotiGui = Library_Function.NotiGui,
		HideGui = Library_Function.HideGui,
	},
}

--------------------------------------------------------------------------------
-- Config save / load
-- Keys are "page||section||title" and the file layout matches the old library,
-- so configs saved before the switch still load.
--------------------------------------------------------------------------------

local ControlRegistry = { Toggles = {}, Sliders = {}, Dropdowns = {}, Keybinds = {}, Boxes = {} }

-- Controls inside a sub-tab keep the plain page key, so configs saved before a page
-- was split into sub-tabs still load. Only when that key is already taken (two
-- sub-tabs reusing a section + title) does the sub-tab name go into the key.
local function register(kind, pageKey, sectionKey, title, entry, subTabPageKey)
	local function keyFor(page)
		return tostring(page) .. "||" .. tostring(sectionKey) .. "||" .. tostring(title)
	end
	local key = keyFor(pageKey)
	if subTabPageKey and ControlRegistry[kind][key] then
		key = keyFor(subTabPageKey)
	end
	ControlRegistry[kind][key] = entry
end

local ConfigFolder = "Peridot/Configs"

local function SetConfigFolder(path)
	ConfigFolder = tostring(path or "Peridot/Configs")
	return ConfigFolder
end

local function GetConfigFolder()
	return ConfigFolder
end

local function ensureConfigFolder()
	if not HasFileSystem then
		return false, "Executor has no file access"
	end
	local path = ""
	for part in ConfigFolder:gmatch("[^/]+") do
		path = path == "" and part or (path .. "/" .. part)
		if not isfolder(path) then
			makefolder(path)
		end
	end
	return true
end

local function configPath(name)
	return ConfigFolder .. "/" .. name .. ".json"
end

local ConfigSystem = {}

function ConfigSystem.List()
	if not ensureConfigFolder() or type(listfiles) ~= "function" then
		return {}
	end
	local names = {}
	for _, path in ipairs(listfiles(ConfigFolder)) do
		local name = path:match("([^/\\]+)%.json$")
		if name then
			table.insert(names, name)
		end
	end
	return names
end

local function validName(name)
	if not name or name == "" then
		return false, "No config name"
	end
	if tostring(name):find("[/\\]") then
		return false, "Config names cannot contain slashes"
	end
	return true
end

-- Every saved control value, in the shape a config file holds.
local function snapshot()
	local data = { Toggles = {}, Sliders = {}, Dropdowns = {}, Keybinds = {}, Boxes = {} }
	for kind, entries in pairs(ControlRegistry) do
		for key, entry in pairs(entries) do
			local ok, value = pcall(entry.Get)
			if ok then
				data[kind][key] = value
			end
		end
	end
	return data
end

local function applyData(data)
	-- Configs saved by the old library also carry a UITheme block. It is skipped
	-- on purpose: it holds the old blue accent.
	for kind, entries in pairs(ControlRegistry) do
		local saved = type(data[kind]) == "table" and data[kind] or {}
		for key, value in pairs(saved) do
			local entry = entries[key]
			if entry then
				task.spawn(function()
					local ok, err = pcall(entry.Set, value)
					if not ok then
						warn("[Peridot Config]", kind, key, err)
					end
				end)
			end
		end
	end
end

function ConfigSystem.Exists(name)
	return HasFileSystem and validName(name) and isfile(configPath(name)) or false
end

function ConfigSystem.Save(name)
	local valid, nameErr = validName(name)
	if not valid then
		return false, nameErr
	end
	local ready, folderErr = ensureConfigFolder()
	if not ready then
		return false, folderErr
	end
	return pcall(writefile, configPath(name), HttpService:JSONEncode(snapshot()))
end

-- Save under a new name only; Save itself overwrites.
function ConfigSystem.Create(name)
	if ConfigSystem.Exists(name) then
		return false, "A config named " .. tostring(name) .. " already exists"
	end
	return ConfigSystem.Save(name)
end

function ConfigSystem.Load(name)
	local valid, nameErr = validName(name)
	if not valid then
		return false, nameErr
	end
	local ready, folderErr = ensureConfigFolder()
	if not ready then
		return false, folderErr
	end
	if not isfile(configPath(name)) then
		return false, "Config not found"
	end
	local decoded, data = pcall(function()
		return HttpService:JSONDecode(readfile(configPath(name)))
	end)
	if not decoded or type(data) ~= "table" then
		return false, "Invalid config data"
	end
	applyData(data)
	return true
end

-- The current values as JSON text, to share or keep outside the executor.
function ConfigSystem.Export()
	return HttpService:JSONEncode(snapshot())
end

function ConfigSystem.Import(text)
	if type(text) ~= "string" or text == "" then
		return false, "Paste config JSON first"
	end
	local decoded, data = pcall(HttpService.JSONDecode, HttpService, text)
	if not decoded or type(data) ~= "table" then
		return false, "That is not config JSON"
	end
	applyData(data)
	return true
end

local function autoloadPath()
	return ConfigFolder .. "/autoload.txt"
end

function ConfigSystem.GetAutoload()
	if not HasFileSystem then
		return nil
	end
	local ok, name = pcall(function()
		return isfile(autoloadPath()) and readfile(autoloadPath()) or nil
	end)
	return ok and name ~= "" and name or nil
end

function ConfigSystem.SetAutoload(name)
	if not ConfigSystem.Exists(name) then
		return false, "Config not found"
	end
	return pcall(writefile, autoloadPath(), name)
end

function ConfigSystem.ClearAutoload()
	if HasFileSystem and isfile(autoloadPath()) then
		return pcall(delfile, autoloadPath())
	end
	return true
end

function ConfigSystem.Delete(name)
	if not name or name == "" then
		return false, "No config name"
	end
	local ready, folderErr = ensureConfigFolder()
	if not ready then
		return false, folderErr
	end
	if not isfile(configPath(name)) then
		return false, "Config not found"
	end
	return pcall(delfile, configPath(name))
end

getgenv().PeridotConfig = ConfigSystem

--------------------------------------------------------------------------------
-- Controls
--------------------------------------------------------------------------------

local function wrapSection(banana, pageKey, sectionKey, subTabPageKey)
	local section = {}

	-- The old library fired a toggle's callback once with its default; BananaLib
	-- does not, so it is fired here to keep scripts' startup state the same.
	function section.CreateToggle(options, callback)
		options = options or {}
		local state = options.Default == true
		local toggle = banana:AddToggle(nil, {
			Title = tostring(options.Title or ""),
			Desc = options.Desc,
			Default = state,
			Callback = function(value)
				state = value
				if callback then
					callback(value)
				end
			end,
		})
		if callback then
			local ok, err = pcall(callback, state)
			if not ok then
				warn("[Peridot UI] toggle callback:", err)
			end
		end
		local handle = {
			Get = function()
				return state
			end,
			Set = function(value)
				toggle.SetStage(not not value)
			end,
		}
		handle.SetStage = handle.Set
		if not options.NoSave then
			register("Toggles", pageKey, sectionKey, options.Title, handle, subTabPageKey)
		end
		return handle
	end

	function section.CreateButton(options, callback)
		options = options or {}
		local button = banana:AddButton({
			Title = tostring(options.Title or ""),
			ButtonText = options.ButtonText, -- label on the green button; inferred from the title when absent
			Callback = callback or options.Callback,
		})
		return {
			SetTitle = function(text)
				button:SetTitle(tostring(text))
			end,
		}
	end

	function section.CreateLabel(options)
		local text = type(options) == "table" and (options.Title or options.Text) or options
		local label = banana:AddLabel(tostring(text or ""))
		return {
			SetText = function(value)
				label:SetText(tostring(value))
			end,
			SetColor = function(color)
				label.SetColor(color)
			end,
		}
	end

	function section.CreateSlider(options, callback)
		options = options or {}
		local min = tonumber(options.Min) or 0
		local max = tonumber(options.Max) or 100
		local value = math.clamp(tonumber(options.Default) or min, min, max)
		local slider = banana:AddSlider({
			Title = tostring(options.Title or ""),
			Min = min,
			Max = max,
			Default = value,
			Rouding = options.Precise and 2 or nil, -- BananaLib's own (misspelled) key for decimal places
			Callback = function(newValue)
				value = tonumber(newValue) or value
				if callback then
					callback(value)
				end
			end,
		})
		local handle = {
			Get = function()
				return value
			end,
			Set = function(newValue)
				slider.SetValue(tonumber(newValue) or value)
			end,
		}
		handle.SetValue = handle.Set
		register("Sliders", pageKey, sectionKey, options.Title, handle, subTabPageKey)
		return handle
	end

	function section.CreateBox(options, callback)
		options = options or {}
		local text = tostring(options.Default or "")
		local box = banana:AddInput(nil, {
			Title = tostring(options.Title or ""),
			Placeholder = tostring(options.Placeholder or ""),
			Default = text,
			Numeric = options.Numeric or options.Number,
			Callback = function(value)
				text = value
				if callback then
					callback(value)
				end
			end,
		})
		local handle = {
			Get = function()
				return text
			end,
			Set = function(value)
				box.SetValue(tostring(value))
			end,
		}
		handle.SetValue = handle.Set
		if not options.NoSave then
			register("Boxes", pageKey, sectionKey, options.Title, handle, subTabPageKey)
		end
		return handle
	end

	function section.CreateDropdown(options, callback)
		options = options or {}
		local dropdown = banana:AddDropdown(nil, {
			Title = tostring(options.Title or ""),
			Values = options.List or {},
			Default = options.Default,
			Search = options.Search,
			Multi = options.Multi,
			Callback = callback,
		})
		local handle = {}
		-- Works as handle.GetNewList(list) and handle:GetNewList(list).
		function handle.GetNewList(first, second)
			local list = first == handle and second or first
			dropdown:GetNewList(type(list) == "table" and list or {})
		end
		handle.Refresh = handle.GetNewList
		function handle.Set(value)
			dropdown:SetValue(value)
		end
		handle.SetValue = handle.Set
		function handle.Get()
			return dropdown:GetValue()
		end
		-- Shows a value without picking it, so the callback does not run.
		function handle.ClearText(first, second)
			dropdown:ClearText(first == handle and second or first)
		end
		if not options.Multi and not options.NoSave then
			register("Dropdowns", pageKey, sectionKey, options.Title, handle, subTabPageKey)
		end
		return handle
	end

	function section.CreateKeybind(options, callback)
		options = options or {}
		local keybind = banana:AddKeyBind({
			Title = tostring(options.Title or ""),
			Default = options.Default or "F",
			Mode = options.Mode or "Toggle",
		}, function(state)
			if callback then
				callback(state)
			end
		end)
		local handle = {
			Get = function()
				return keybind:Get()
			end,
			Set = function(key)
				keybind:Set(key)
			end,
		}
		register("Keybinds", pageKey, sectionKey, options.Title, handle, subTabPageKey)
		return handle
	end

	-- options: Title, Default (Color3). callback(color). Not saved in configs.
	function section.CreateColorPicker(options, callback)
		options = options or {}
		local picker = banana:AddColorPicker({
			Title = tostring(options.Title or ""),
			Default = options.Default,
			Callback = callback or options.Callback,
		})
		return {
			Get = picker.GetValue,
			Set = picker.SetValue,
		}
	end

	return section
end

local function wrapSubTab(sub, pageKey, subName)
	local subTabPageKey = tostring(pageKey) .. "/" .. tostring(subName or "")
	local subTab = {}
	function subTab.CreateSection(name)
		local sectionKey = tostring(name or "")
		return wrapSection(sub:AddSection(sectionKey), pageKey, sectionKey, subTabPageKey)
	end
	function subTab.Select()
		sub:Select()
	end
	return subTab
end

--------------------------------------------------------------------------------
-- Window, notifications, visibility, background
--------------------------------------------------------------------------------

function Peridot.CreateMain(options)
	options = options or {}
	getgenv().HubName = options.Name or getgenv().HubName or "Peridot"
	-- Old layout: "<Name> <Desc>" top-left in the title bar, the game name (Title)
	-- as the header above the tab list, the gear opening Interface Settings.
	local window = Library:CreateWindow({
		Title = getgenv().HubName,
		Desc = options.Desc or "",
		SidebarTitle = options.Title or getgenv().HubName,
	})

	-- UI toggle button: a script can start with it hidden (FloatingButton = false);
	-- the player's own choice from Interface Settings > UI Toggle wins once saved.
	Library_Function.DefaultFloatingButton = options.FloatingButton ~= false
	local showButton = SavedTheme.FloatingButton
	if showButton == nil then
		showButton = Library_Function.DefaultFloatingButton
	end
	Library_Function.HideGui.Enabled = showButton
	if not getgenv().UIToggled then
		Library.ToggleUI() -- BananaLib starts hidden; the old library opened straight away
	end

	local main = { Banana = window }
	function main.CreatePage(pageOptions)
		pageOptions = pageOptions or {}
		local pageKey = tostring(pageOptions.Page_Name or pageOptions.Page_Title or "Page")
		local tab = window:AddTab(tostring(pageOptions.Page_Title or pageKey))
		local page = {}
		function page.CreateSection(name)
			local sectionKey = tostring(name or "")
			return wrapSection(tab:AddLeftGroupbox(sectionKey), pageKey, sectionKey)
		end
		-- A strip of sub-tabs under the page title; each has its own sections.
		function page.CreateSubTab(subName)
			return wrapSubTab(tab:AddSubTab(tostring(subName or "")), pageKey, subName)
		end
		return page
	end

	-- The gear's Interface Settings page. Scripts add their own sub-tabs to it
	-- (Universal adds "Background"); CreateSection(name) makes a sub-tab with one
	-- section of the same name.
	main.UISettings = {
		CreateSubTab = function(subName)
			-- the page key stays "UI Settings" (not the "Interface Settings" title) so saved configs keep loading
			return wrapSubTab(window:GetUISettingsPage():AddSubTab(tostring(subName or "")), "UI Settings", subName)
		end,
		CreateSection = function(name)
			return main.UISettings.CreateSubTab(name).CreateSection(name)
		end,
	}
	return main
end

function Peridot.CreateNoti(options)
	options = options or {}
	-- bypass = true: BananaLib mutes notifications whenever getgenv().Config is set.
	Library:Notify({
		Title = options.Title,
		Desc = options.Desc or options.Description,
		Duration = options.ShowTime or options.Duration or 5,
	}, true)
end

-- Same as clicking the title-bar gear: opens Interface Settings, or goes back to the previous page.
function Peridot.ToggleUISettings()
	if not Library_Function.ToggleUISettings then
		return false
	end
	Library_Function.ToggleUISettings()
	return true
end

-- Theme from code; all of these save to Peridot/Theme.json like the gear page does.
Peridot.SetThemeColor = Library_Function.SetThemeColor -- (key, Color3), e.g. ("Background 2 Color", c)
Peridot.ButtonVerb = ButtonVerb -- (title) -> label the green button gets by default
Peridot.SetButtonSize = Library_Function.SetButtonSize -- (28-64 px) UI toggle button
Peridot.SetButtonVisible = Library_Function.SetButtonVisible -- (on)
Peridot.SetMenuKey = Library_Function.SetMenuKey -- ("RightControl", "F4", ...) key that opens/closes the window
Peridot.SetRainbow = Library_Function.SetRainbow -- (key, on)
Peridot.SetAccentRainbow = Library_Function.SetAccentRainbow -- (on)
Peridot.ResetTheme = Library_Function.ResetTheme

-- Change the accent from code: a preset name ("Peridot", "Ocean", "Ruby", ...) or a Color3. Saved like the gear's choice.
function Peridot.SetAccent(accent)
	if type(accent) == "string" then
		for _, preset in ipairs(AccentPresets) do
			if preset[1] == accent then
				Library_Function.SetAccent(preset[2], preset[1])
				return true
			end
		end
		return false
	end
	Library_Function.SetAccent(accent, "Custom")
	return true
end

function Peridot.IsVisible()
	return getgenv().UIToggled and true or false
end

function Peridot.Toggle()
	Library.ToggleUI()
end

function Peridot.Show()
	if not getgenv().UIToggled then
		Library.ToggleUI()
	end
end

function Peridot.Hide()
	if getgenv().UIToggled then
		Library.ToggleUI()
	end
end

-- Media (backgrounds, logo): rbxassetid://..., a bare asset id, a file in the
-- executor workspace (e.g. "Peridot/Backgrounds/night.png"), or an http(s) URL,
-- which is downloaded into the workspace first. Images: .png / .jpg; video: .webm
-- (the only video format Roblox plays).
local BackgroundFolder = "Peridot/Backgrounds"
local requestFunction = request or http_request or (syn and syn.request) or (http and http.request) or (fluxus and fluxus.request)
local backgroundLayer

local function ensureFolder(path)
	local built = ""
	for part in path:gmatch("[^/]+") do
		built = built == "" and part or (built .. "/" .. part)
		if not isfolder(built) then
			makefolder(built)
		end
	end
end

local function fetchBinary(url)
	local body
	if requestFunction then -- request() keeps binary bodies intact
		local response = requestFunction({ Url = url, Method = "GET" })
		if response.StatusCode and response.StatusCode >= 400 then
			error("download failed (HTTP " .. tostring(response.StatusCode) .. ")", 0)
		end
		body = response.Body
	else
		body = game:HttpGet(url)
	end
	if type(body) ~= "string" or body == "" then
		error("download failed", 0)
	end
	return body
end

-- Returns something an ImageLabel / VideoFrame can show. URLs are cached in
-- `folder` by file name, so the next run loads them from disk.
-- ponytail: a file replaced on GitHub under the same name keeps the old cached copy; rename it to refresh.
local function resolveMedia(source, folder)
	if source:match("^%d+$") then
		return "rbxassetid://" .. source
	end
	if source:match("^rbxasset") then
		return source
	end
	local getAsset = getcustomasset or getsynasset
	if not (HasFileSystem and getAsset) then
		error("this executor can't show files from its workspace", 0)
	end
	local path = source
	if source:match("^https?://") then
		local name = source:gsub("[?#].*$", ""):match("([^/]+)$") or "media"
		path = folder .. "/" .. name:gsub("[^%w%.%-_]", "_")
		if not isfile(path) then
			ensureFolder(folder)
			writefile(path, fetchBinary(source))
		end
	elseif not isfile(path) then
		error("file not found in the executor workspace: " .. path, 0)
	end
	return getAsset(path)
end

-- Image and video files in workspace/Peridot/Backgrounds (players can drop their own in).
function Peridot.ListBackgrounds()
	if not HasFileSystem or type(listfiles) ~= "function" or not isfolder(BackgroundFolder) then
		return {}
	end
	local paths = {}
	for _, path in ipairs(listfiles(BackgroundFolder)) do
		local lower = path:lower()
		if lower:match("%.png$") or lower:match("%.jpe?g$") or lower:match("%.webm$") then
			table.insert(paths, BackgroundFolder .. "/" .. path:match("([^/\\]+)$"))
		end
	end
	return paths
end

-- Downloads url into workspace/Peridot/Backgrounds/<fileName> unless it's already there.
-- Returns "new", "exists", or nil + error.
function Peridot.DownloadBackground(url, fileName)
	if not HasFileSystem then
		return nil, "Executor has no file access"
	end
	local path = BackgroundFolder .. "/" .. tostring(fileName)
	if isfile(path) then
		return "exists"
	end
	local ok, err = pcall(function()
		ensureFolder(BackgroundFolder)
		writefile(path, fetchBinary(url))
	end)
	if not ok then
		return nil, err
	end
	return "new"
end

-- Logo (title bar, notifications). "" restores the Peridot logo. Saved.
function Library_Function.SetLogo(source)
	source = tostring(source or "")
	local image = DefaultTheme["Logo Image"]
	if source ~= "" then
		local ok, result = pcall(resolveMedia, source, "Peridot/Logos")
		if not ok then
			return false, result
		end
		image = result
	end
	getgenv().UIColor["Logo Image"] = image
	SavedTheme.Logo = source ~= "" and source or nil
	saveThemeSoon()
	return true
end
Peridot.SetLogo = Library_Function.SetLogo

-- A logo picked in an earlier session (URLs come from the workspace cache).
if type(SavedTheme.Logo) == "string" and SavedTheme.Logo ~= "" then
	local ok, image = pcall(resolveMedia, SavedTheme.Logo, "Peridot/Logos")
	if ok then
		getgenv().UIColor["Logo Image"] = image
	end
end

-- What a theme remembers about a background: an asset id, or a plain file name in
-- Peridot/Backgrounds (.png, .jpg or .webm). Nothing else is kept, so a shared theme can
-- never point the client at a link or a path of the sender's choosing.
local PANEL_GLASS = 0.3 -- panel see-through while a background shows: the Window tab slider's maximum
local function cleanBackground(value)
	if type(value) ~= "string" then
		return nil
	end
	local id = value:match("^rbxassetid://(%d+)$") or value:match("^(%d+)$")
	if id then
		return "rbxassetid://" .. id
	end
	local lower = value:lower()
	if value:match("^[%w_%-]+%.%w+$") and (lower:match("%.png$") or lower:match("%.jpe?g$") or lower:match("%.webm$")) then
		return value
	end
	return nil
end
local function backgroundRef(source) -- what to remember about a source given to SetBackground
	source = tostring(source or "")
	return cleanBackground(source) or cleanBackground(source:match("^" .. BackgroundFolder .. "/([^/\\]+)$"))
end

-- With the Transparent window style the picture lets some of the game through as well.
local function pictureTransparency()
	return (tonumber(getgenv().UIColor["Background Main Transparency"]) or 0) * 0.4
end

-- An empty source clears the background; on failure the current one stays. The window gets
-- its own layer, and the choice is remembered (Peridot/Theme.json) when it is portable.
function Peridot.SetBackground(source)
	local container = Library_Function.MainContainer
	if not container then
		return false, "No window yet"
	end
	local media = tostring(source or "")
	local isVideo = media:lower():gsub("[?#].*$", ""):match("%.webm$") ~= nil
	if media ~= "" then
		local ok, result = pcall(resolveMedia, media, BackgroundFolder)
		if not ok then
			return false, result
		end
		media = result
	end

	if backgroundLayer then
		backgroundLayer:Destroy()
		backgroundLayer = nil
	end
	SavedTheme.Background = backgroundRef(source)
	saveThemeSoon()
	if media == "" then
		return true
	end

	-- Its own layer: MainContainer carries a 92%-transparent UIGradient that would wash out anything drawn on it.
	local layer = Instance.new(isVideo and "VideoFrame" or "ImageLabel")
	layer.Name = "PeridotBackground"
	layer.BackgroundTransparency = 1
	layer.Size = UDim2.new(1, 0, 1, 0)
	layer.ZIndex = 0 -- under the window content, which sits at the default ZIndex 1
	if isVideo then
		layer.Video = media
		layer.Looped = true
		layer.Volume = 0
	else
		layer.Image = media
		layer.ScaleType = Enum.ScaleType.Crop
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5) -- same as the window's corners
	corner.Parent = layer

	-- A dark band over the title bar, fading out below it, keeps the title and buttons readable on a bright picture.
	local scrim = Instance.new("Frame")
	scrim.Name = "TitleScrim"
	scrim.BackgroundColor3 = Color3.new(0, 0, 0)
	scrim.BorderSizePixel = 0
	scrim.Size = UDim2.new(1, 0, 0, 50)
	scrim.ZIndex = 0
	local scrimFade = Instance.new("UIGradient")
	scrimFade.Rotation = 90
	scrimFade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.6, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	scrimFade.Parent = scrim
	local scrimCorner = Instance.new("UICorner")
	scrimCorner.CornerRadius = UDim.new(0, 5)
	scrimCorner.Parent = scrim
	scrim.Parent = layer

	layer.Parent = container
	if isVideo then
		layer:Play()
	elseif not DisableAnimation then
		layer.ImageTransparency = 1
		TweenService:Create(layer, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { ImageTransparency = pictureTransparency() }):Play()
	else
		layer.ImageTransparency = pictureTransparency()
	end
	backgroundLayer = layer
	return true
end

-- Panel transparency, live and saved like the Window tab slider does.
local function setPanelTransparency(value)
	getgenv().UIColor["Background 1 Transparency"] = value
	SavedTheme.PanelTransparency = value
	saveThemeSoon()
	if Library_Function.OnPanelsChanged then
		pcall(Library_Function.OnPanelsChanged)
	end
end

-- Shows a remembered background (a theme's, or the one the last session ended with). A picture
-- the hub ships is downloaded the first time it is needed; the file only ever comes from the hub.
local HubBase = "https://raw.githubusercontent.com/Ic0u/peridot/main/"
local function showBackgroundRef(ref, quiet)
	local function fail(message)
		Peridot.CreateNoti({ Title = "Background", Desc = message, ShowTime = 4 })
	end
	local source = ref
	if not ref:match("^rbxassetid://") then
		if not HasFileSystem then
			return not quiet and fail("Your executor can't use files, so the background picture is skipped.")
		end
		source = BackgroundFolder .. "/" .. ref
		if not isfile(source) then
			task.spawn(function()
				local result, err = Peridot.DownloadBackground(HubBase .. "assets/backgrounds/" .. ref, ref)
				if not result then
					return fail("Couldn't download the background picture: " .. tostring(err))
				end
				if SavedTheme.Background == ref then -- unless another theme was picked meanwhile
					local ok, message = Peridot.SetBackground(source)
					if not ok then
						fail(tostring(message))
					end
				end
			end)
			return
		end
	end
	local ok, message = Peridot.SetBackground(source)
	if not ok then
		fail(tostring(message))
	end
end

-- A theme brings its own background, or none: whatever was showing goes first.
local function setThemeBackground(ref)
	if Library_Function.MainContainer then
		Peridot.SetBackground("")
	end
	SavedTheme.Background = ref -- remembered at once, before a window exists or the file arrives
	if ref and Library_Function.MainContainer then
		showBackgroundRef(ref)
	end
	if Library_Function.OnThemeBackground then
		pcall(Library_Function.OnThemeBackground, ref)
	end
end

function Library_Function.RestoreBackground() -- a window just opened
	local ref = cleanBackground(SavedTheme.Background) -- the saved file may have been edited by hand
	SavedTheme.Background = ref
	if ref then
		showBackgroundRef(ref, true)
	end
end

function Library_Function.ClearBackground()
	if Library_Function.MainContainer then
		Peridot.SetBackground("")
	end
	if Library_Function.OnThemeBackground then
		pcall(Library_Function.OnThemeBackground, nil)
	end
end

-- The frame's transparency also decides the shadow (hidden when see-through) and how much a picture lets through.
ThemeListeners["Background Main Transparency"] = function(value)
	WindowShadowAlpha = (tonumber(value) or 0) > 0 and 1 or .35
	local shadow = Library_Function.WindowShadow
	if shadow and getgenv().UIToggled then
		shadow.ImageTransparency = WindowShadowAlpha
	end
	if backgroundLayer and backgroundLayer:IsA("ImageLabel") then
		backgroundLayer.ImageTransparency = pictureTransparency()
	end
end

-- Window style: "Solid" (dark frame) or "Transparent" (the game shows through the frame, and the
-- panels turn a little see-through too; going back to Solid puts the panels back). Saved.
local panelsBeforeGlass
local PANEL_GLASS_STYLE = 0.4 -- panels with the Transparent style: the game shows through the menus too, not just the frame
function Library_Function.SetWindowStyle(style)
	local transparent = style == "Transparent"
	getgenv().UIColor["Background Main Transparency"] = transparent and WINDOW_GLASS or 0
	SavedTheme.WindowStyle = transparent and "Transparent" or nil
	local panels = getgenv().UIColor["Background 1 Transparency"]
	if transparent and panels < PANEL_GLASS_STYLE then
		panelsBeforeGlass = panels
		setPanelTransparency(PANEL_GLASS_STYLE)
	elseif not transparent and panelsBeforeGlass then
		setPanelTransparency(panelsBeforeGlass)
		panelsBeforeGlass = nil
	end
	saveThemeSoon()
end
Peridot.SetWindowStyle = Library_Function.SetWindowStyle

-- The Background section of the Interface Settings page, shared by every script:
-- a picker over workspace/Peridot/Backgrounds, a custom source box, and a first-run
-- download of the hub's own set (assets/backgrounds/backgrounds.json under baseUrl).
function Peridot.AddBackgroundSection(window, baseUrl)
	if baseUrl then
		HubBase = baseUrl -- a theme's picture comes from the same place as the list below
	end
	baseUrl = HubBase
	local function notify(desc)
		Peridot.CreateNoti({ Title = "Background", Desc = desc, ShowTime = 4 })
	end
	local section = window.UISettings.CreateSection("Background")

	local transparencyBefore
	local function applyBackground(source)
		local ok, err = Peridot.SetBackground(source)
		if not ok then
			return notify(tostring(err))
		end
		-- see-through panels while a background shows; the player's own setting comes back when cleared
		if source ~= "" then
			transparencyBefore = transparencyBefore or getgenv().UIColor["Background 1 Transparency"]
			setPanelTransparency(PANEL_GLASS)
		elseif transparencyBefore then
			setPanelTransparency(transparencyBefore)
			transparencyBefore = nil
		end
	end

	local function backgroundTitle(path) -- "Peridot/Backgrounds/persona_5_rainy.jpg" -> "Persona 5 Rainy"
		local words = {}
		for word in path:match("([^/\\]+)$"):gsub("%.%w+$", ""):gmatch("[^_%s]+") do
			table.insert(words, word:sub(1, 1):upper() .. word:sub(2))
		end
		return table.concat(words, " ")
	end
	local function titleOf(ref) -- what the picker shows for a remembered background
		if not ref then
			return "None"
		end
		return ref:match("^rbxassetid://") and "Custom" or backgroundTitle(ref)
	end
	local dropdown
	local shown = titleOf(SavedTheme.Background) -- what the picker says is on the window
	local function refreshList()
		backgroundPaths = {}
		local names = {}
		for _, path in ipairs(Peridot.ListBackgrounds()) do
			local title = backgroundTitle(path)
			if not backgroundPaths[title] then
				backgroundPaths[title] = path
				table.insert(names, title)
			end
		end
		table.sort(names)
		table.insert(names, 1, "None")
		if dropdown then
			dropdown.GetNewList(names)
			dropdown.ClearText(shown) -- a new list blanks the title
		end
		return names
	end

	dropdown = section.CreateDropdown({
		Title = "Background",
		List = refreshList(),
		Default = shown,
		Search = true,
	}, function(name)
		shown = name
		applyBackground(backgroundPaths[name] or "")
	end)
	-- a theme (or Reset theme) changed the picture: show it here without picking it again
	Library_Function.OnThemeBackground = function(ref)
		transparencyBefore = nil -- the theme decides the panels now
		shown = titleOf(ref)
		dropdown.ClearText(shown)
	end
	section.CreateButton({ Title = "Refresh list" }, refreshList)
	section.CreateLabel({ Title = "Add your own: put images or .webm videos in workspace/Peridot/Backgrounds, then Refresh." })

	task.spawn(function()
		local ok, list = pcall(function()
			local http = game:GetService("HttpService")
			return http:JSONDecode(game:HttpGet(baseUrl .. "assets/backgrounds/backgrounds.json"))
		end)
		if not ok or type(list) ~= "table" then
			return
		end
		local added, failed = 0, 0
		for _, file in pairs(list) do
			local result = Peridot.DownloadBackground(baseUrl .. "assets/backgrounds/" .. file, file)
			if result == "new" then
				added = added + 1
			elseif not result then
				failed = failed + 1
			end
		end
		if added > 0 then
			refreshList()
		end
		if failed > 0 then
			notify(failed .. " background(s) couldn't be downloaded")
		end
	end)

	section.CreateBox({
		Title = "Custom Background",
		Placeholder = "rbxassetid://, URL or workspace file",
		Default = "",
	}, function(url)
		if url ~= "" then
			shown = "Custom"
			dropdown.ClearText(shown)
			applyBackground(url)
		end
	end)
end

-- The full config manager, built into a page or sub-tab: create, load, overwrite,
-- delete, autoload and JSON import/export. Its own fields are kept out of configs.
function Peridot.AddConfigSection(container)
	local function notify(desc)
		Peridot.CreateNoti({ Title = "Config", Desc = desc, ShowTime = 4 })
	end
	local typedName, selected, json = "", nil, ""

	local manage = container.CreateSection("Configuration")
	if not HasFileSystem then
		manage.CreateLabel({ Title = "Your executor has no file access, so configs cannot be saved." })
	end
	manage.CreateBox({ Title = "Config name", Placeholder = "name", NoSave = true }, function(text)
		typedName = text
	end)
	local list
	local function refresh()
		local ok, names = pcall(ConfigSystem.List)
		names = ok and type(names) == "table" and names or {}
		table.sort(names)
		if list then
			list.GetNewList(names)
		end
		selected = nil -- the dropdown clears its selection on a new list
		return names
	end
	manage.CreateButton({ Title = "Create config", ButtonText = "Create" }, function()
		local ok, err = ConfigSystem.Create(typedName)
		notify(ok and ("Created " .. typedName) or tostring(err))
		if ok then
			refresh()
		end
	end)
	list = manage.CreateDropdown({ Title = "Config list", List = {}, NoSave = true }, function(name)
		selected = name
	end)
	local function withSelected(action)
		if not selected or selected == "" then
			return notify("Pick a config from the list first.")
		end
		action(selected)
	end
	manage.CreateButton({ Title = "Load config", ButtonText = "Load" }, function()
		withSelected(function(name)
			local ok, err = ConfigSystem.Load(name)
			notify(ok and ("Loaded " .. name) or tostring(err))
		end)
	end)
	manage.CreateButton({ Title = "Overwrite config", ButtonText = "Overwrite" }, function()
		withSelected(function(name)
			local ok, err = ConfigSystem.Save(name)
			notify(ok and ("Saved over " .. name) or tostring(err))
		end)
	end)

	local autoloadLabel
	local function showAutoload()
		autoloadLabel.SetText("Current autoload config: " .. (ConfigSystem.GetAutoload() or "none"))
	end
	manage.CreateButton({ Title = "Delete config", ButtonText = "Delete" }, function()
		withSelected(function(name)
			local ok, err = ConfigSystem.Delete(name)
			notify(ok and ("Deleted " .. name) or tostring(err))
			if ok and ConfigSystem.GetAutoload() == name then
				ConfigSystem.ClearAutoload()
				showAutoload()
			end
			refresh()
		end)
	end)
	manage.CreateButton({ Title = "Refresh list", ButtonText = "Refresh" }, refresh)

	local autoload = container.CreateSection("Autoload")
	autoload.CreateButton({ Title = "Set as autoload", ButtonText = "Set" }, function()
		withSelected(function(name)
			local ok, err = ConfigSystem.SetAutoload(name)
			notify(ok and (name .. " now loads when the script starts") or tostring(err))
			showAutoload()
		end)
	end)
	autoload.CreateButton({ Title = "Reset autoload", ButtonText = "Reset" }, function()
		ConfigSystem.ClearAutoload()
		notify("No config loads at start now.")
		showAutoload()
	end)
	autoloadLabel = autoload.CreateLabel({ Title = "Current autoload config: none" })
	showAutoload()

	local share = container.CreateSection("Config JSON")
	local jsonBox = share.CreateBox({ Title = "Config JSON", Placeholder = "paste config JSON here", NoSave = true }, function(text)
		json = text
	end)
	share.CreateButton({ Title = "Import config", ButtonText = "Import" }, function()
		local ok, err = ConfigSystem.Import(json)
		notify(ok and "Imported the pasted config." or tostring(err))
	end)
	share.CreateButton({ Title = "Export current config", ButtonText = "Export" }, function()
		local text = ConfigSystem.Export()
		jsonBox.Set(text)
		local copied = type(setclipboard) == "function" and pcall(setclipboard, text)
		notify(copied and "Config JSON copied to the clipboard." or "Config JSON is in the box above.")
	end)

	refresh()
	-- Load the autoload config once the script has finished building its controls.
	task.delay(1, function()
		local name = ConfigSystem.GetAutoload()
		if name and ConfigSystem.Exists(name) then
			local ok = ConfigSystem.Load(name)
			if ok then
				notify("Autoloaded " .. name)
			end
		end
	end)
end

-- Removes every Peridot window, notification and the UI toggle button, and the menu key handler.
function Peridot.Unload()
	getgenv().PeridotExecutedIn = nil -- the loader may be run again once the UI is gone
	Library.DestroyUI()
	if getgenv().PeridotMenuKeyConnection then
		pcall(function()
			getgenv().PeridotMenuKeyConnection:Disconnect()
		end)
		getgenv().PeridotMenuKeyConnection = nil
	end
end

--------------------------------------------------------------------------------
-- Theme library. A theme is a look: the colors, panel transparency, animation speeds, easing,
-- the icon and a background picture. Built-in ones are listed here; your own are files in
-- Peridot/Themes. One of them can be the default, which loads each time a script starts.
-- Pasted or loaded theme data is sanitised first: known fields only, values clamped, the icon
-- limited to Roblox asset ids and the background to an asset id or a plain file name, so a
-- shared theme never makes the client fetch a link of the sender's choosing.
--------------------------------------------------------------------------------
local ThemeFolder = "Peridot/Themes"
local THEME_FIELDS = { "Accent", "Preset", "Colors", "PanelTransparency", "AnimationSpeed", "AnimationSpeed1", "AnimationSpeed3", "Easing", "Logo", "Background", "WindowStyle" }
local THEME_EASING = { Quad = true, Quint = true, Back = true, Sine = true, Linear = true }
local THEME_SPEED_LIMITS = { AnimationSpeed1 = 0.75, AnimationSpeed = 1, AnimationSpeed3 = 0.5 }

-- Built-in themes. A palette is ten hex colors; the ones that sit between them (label rows,
-- the softer text, the icons) are made from those, so a theme changes every color of the
-- window. A theme with a picture names a file in assets/backgrounds (downloaded the first
-- time it is used) and lets the panels see through to it. Peridot is the shipped look.
-- name, picture, accent, window frame, sidebar, section panel, page, raised, lifted, outline, text, dim text
local Palettes = {
	{ "Ocean",                 false,                      "5aa0ff", "0e1216", "040507", "080a0d", "171c22", "20262e", "293039", "3a577e", "e4e9f0", "a6afbd" },
	{ "Ruby",                  false,                      "dc4650", "160f10", "070505", "0d090a", "22191a", "2e2224", "392b2d", "723439", "f0e4e6", "bda6aa" },
	{ "Amethyst",              false,                      "9b69e6", "120f16", "050507", "0b090d", "1d1822", "27212e", "312a39", "564076", "e9e4f0", "b1a6bd" },
	{ "Gold",                  false,                      "ffce1b", "161510", "070605", "0d0c09", "22201a", "2e2b23", "39362d", "7e6b27", "f0ede4", "bdb7a6" },
	{ "Sakura",                false,                      "f082aa", "161113", "070506", "0d0a0b", "221b1e", "2e2428", "392e33", "794b5d", "f0e4e9", "bda6af" },
	{ "Mint",                  false,                      "46c8a0", "101614", "050706", "090d0c", "192220", "222e2b", "2c3936", "356b5b", "e4f0ed", "a6bdb7" },
	{ "Mono",                  false,                      "c8c8c8", "161616", "070707", "0d0d0d", "222222", "2e2e2e", "393939", "6b6b6b", "f0f0f0", "bdbdbd" },
	{ "Cyan Neko",             "cyan_neko.jpg",            "54d6c8", "121616", "050707", "0a0d0d", "1c2222", "262e2d", "303939", "3d706b", "e4f0ef", "a6bdbb" },
	{ "Cyberpunk Megalopolis", "cyberpunk_megalopolis.jpg", "fa64be", "0b0e16", "030407", "06080d", "121722", "191f2e", "212839", "6d3d68", "e4e7f0", "a6adbd" },
	{ "Dark River Forest",     "dark_river_forest.jpg",    "80c4a8", "121615", "060706", "0b0d0c", "1d2221", "272e2c", "323937", "4d6a5f", "e4f0ed", "abbdb8" },
	{ "Deepseek Chan",         "deepseek_chan.jpg",        "70a4ff", "0c0a16", "040307", "07060d", "131022", "1b172e", "231f39", "3e4e7e", "e6e4f0", "aaa6bd" },
	{ "Frieren",               "frieren.jpg",              "b0bcdc", "141416", "060607", "0b0c0d", "1f2022", "2a2a2e", "343539", "5f6472", "e6e8f0", "b1b3bd" },
	{ "Green Night Driving",   "green_night_driving.jpg",  "3cd696", "0a1613", "030706", "060d0b", "10221e", "172e28", "1f3933", "297056", "e4f0ed", "a6bdb7" },
	{ "Hacker Room",           "hacker_room.jpg",          "3cf078", "0e1611", "040705", "080d0a", "17221b", "1f2e24", "28392e", "2f7948", "e4f0e8", "a6bdae" },
	{ "Lycoris Monochrome",    "lycoris_monochrome.jpg",   "78c4f0", "0e1216", "040507", "080a0d", "161c22", "1e262e", "273039", "436479", "e4eaf0", "a6b1bd" },
	{ "Monika Lonely",         "monika_lonely.jpg",        "ff6eb4", "130c16", "060407", "0b070d", "1f1422", "291b2e", "342339", "7b3d64", "ede4f0", "b7a6bd" },
	{ "Persona 5 Rainy",       "persona_5_rainy.jpg",      "ff303c", "161414", "070606", "0d0c0c", "222020", "2e2b2b", "393636", "7e3438", "f0e9e9", "bdb5b5" },
	{ "Purple Midnight",       "purple_midnight.jpg",      "a68cff", "0b0a16", "030307", "07060d", "131022", "1a172e", "221f39", "50457e", "e5e4f0", "a9a6bd" },
	{ "Rainy Tokyo",           "rainy_tokyo.jpg",          "e8a0ee", "161116", "070507", "0d0a0d", "221b22", "2e252e", "392f39", "765778", "f0e4f0", "bda6bd" },
	{ "Shorekeeper",           "shorekeeper.jpg",          "60beff", "0c1216", "040507", "070a0d", "141c22", "1b262e", "233039", "38627e", "e4ebf0", "a6b3bd" },
	{ "Skirk Neko",            "skirk_neko.jpg",           "d0a8fa", "120e16", "050407", "0b080d", "1d1722", "271f2e", "312839", "69557d", "eae4f0", "b1a6bd" },
	{ "Snowy Bedroom",         "snowy_bedroom.jpg",        "e8b464", "16130f", "070605", "0d0b09", "221e19", "2e2922", "39332b", "76603f", "f0ebe4", "bdb3a6" },
	{ "Snowy Forest",          "snowy_forest.jpg",         "78d6e8", "0c1316", "040607", "070b0d", "141f22", "1b292e", "233439", "416d76", "e4edf0", "a6b7bd" },
	{ "Witch Cauldron",        "witch_cauldron.jpg",       "b470ff", "16100c", "070504", "0d0907", "221914", "2e221b", "392b23", "644370", "f0e8e4", "bdaea6" },
	{ "Yuta Blade",            "yuta_blade.jpg",           "ff46e1", "160812", "070206", "0d040b", "220d1d", "2e1327", "391a31", "7e296f", "f0e4ed", "bda6b7" },
	{ "Zankou Nte",            "zankou_nte.jpg",           "ff6eaa", "16090e", "070304", "0d0508", "220f17", "2e151f", "391c28", "7e3956", "f0e4e9", "bda6af" },
}

local function hexList(code)
	return { tonumber(code:sub(1, 2), 16), tonumber(code:sub(3, 4), 16), tonumber(code:sub(5, 6), 16) }
end
local function mixList(a, b, amount) -- amount 0 gives a, 1 gives b
	local out = {}
	for i = 1, 3 do
		out[i] = math.floor(a[i] + (b[i] - a[i]) * amount + 0.5)
	end
	return out
end

local BuiltInThemes = { { name = "Peridot", data = {} } }
for _, row in ipairs(Palettes) do
	local name, picture = row[1], row[2]
	local accent, frame, side, section, page = hexList(row[3]), hexList(row[4]), hexList(row[5]), hexList(row[6]), hexList(row[7])
	local raised, lifted, line, text, dim = hexList(row[8]), hexList(row[9]), hexList(row[10]), hexList(row[11]), hexList(row[12])
	BuiltInThemes[#BuiltInThemes + 1] = {
		name = name,
		data = {
			Accent = accent,
			Preset = name,
			Colors = {
				["Background Main Color"] = frame, ["Sidebar Color"] = side, ["Section Panel Color"] = section,
				["Background 1 Color"] = page, ["Background 2 Color"] = raised, ["Background 3 Color"] = lifted,
				["Label Color"] = raised, ["Outline Color"] = line,
				["GUI Text Color"] = text, ["Text Color"] = text, ["Placeholder Text Color"] = dim,
				["Section Text Color"] = mixList(text, dim, 0.25), ["Toggle Desc Color"] = mixList(dim, text, 0.25),
				["Setting Icon Color"] = text, ["Search Icon Color"] = text, ["Dropdown Icon Color"] = text,
			},
			PanelTransparency = picture and PANEL_GLASS or nil,
			Background = picture or nil,
		},
	}
end
-- pacing only: they leave the colors as shipped
BuiltInThemes[#BuiltInThemes + 1] = { name = "Snappy", data = { AnimationSpeed1 = 0.12, AnimationSpeed = 0.25, AnimationSpeed3 = 0.05 } }
BuiltInThemes[#BuiltInThemes + 1] = { name = "Relaxed", data = { AnimationSpeed1 = 0.4, AnimationSpeed = 0.8, AnimationSpeed3 = 0.2 } }

local function copyData(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, item in pairs(value) do
		out[key] = copyData(item)
	end
	return out
end

local function builtInNamed(name)
	local wanted = tostring(name or ""):lower()
	for _, entry in ipairs(BuiltInThemes) do
		if entry.name:lower() == wanted then
			return entry
		end
	end
end

local function themePath(name)
	return ThemeFolder .. "/" .. name .. ".json"
end

local function ensureThemeFolder()
	if not HasFileSystem then
		return false, "Executor has no file access"
	end
	local path = ""
	for part in ThemeFolder:gmatch("[^/]+") do
		path = path == "" and part or (path .. "/" .. part)
		if not isfolder(path) then
			makefolder(path)
		end
	end
	return true
end

local function themeNameError(name)
	name = tostring(name or "")
	if name:gsub("%s", "") == "" then
		return "Enter a theme name first."
	end
	if name:find("[/\\]") then
		return "Theme names cannot contain slashes."
	end
	if #name > 40 then
		return "Theme names can be up to 40 characters."
	end
	return nil
end

local function cleanColorList(value)
	if type(value) ~= "table" then
		return nil
	end
	local r, g, b = tonumber(value[1]), tonumber(value[2]), tonumber(value[3])
	if not (r and g and b) then
		return nil
	end
	return { math.clamp(math.floor(r + 0.5), 0, 255), math.clamp(math.floor(g + 0.5), 0, 255), math.clamp(math.floor(b + 0.5), 0, 255) }
end

local function cleanTheme(data)
	if type(data) ~= "table" then
		return nil, "That is not a theme."
	end
	local out = {}
	local accent = cleanColorList(data.Accent)
	if accent then
		out.Accent = accent
		out.Preset = type(data.Preset) == "string" and data.Preset:sub(1, 24) or "Custom"
	end
	if type(data.Colors) == "table" then
		for key, value in pairs(data.Colors) do
			if typeof(DefaultTheme[key]) == "Color3" then
				local list = cleanColorList(value)
				if list then
					out.Colors = out.Colors or {}
					out.Colors[key] = list
				end
			end
		end
	end
	if tonumber(data.PanelTransparency) then
		out.PanelTransparency = math.clamp(tonumber(data.PanelTransparency), 0, PANEL_MAX)
	end
	for field, limit in pairs(THEME_SPEED_LIMITS) do
		if tonumber(data[field]) then
			out[field] = math.clamp(tonumber(data[field]), 0, limit)
		end
	end
	if THEME_EASING[data.Easing] then
		out.Easing = data.Easing
	end
	if type(data.Logo) == "string" and (data.Logo:match("^rbxassetid://%d+$") or data.Logo:match("^%d+$")) then
		out.Logo = data.Logo
	end
	out.Background = cleanBackground(data.Background)
	if data.WindowStyle == "Transparent" then
		out.WindowStyle = "Transparent"
	end
	return out
end

-- The current look as plain data, in the shape a theme file holds.
local function snapshotTheme()
	local data = {}
	for _, field in ipairs(THEME_FIELDS) do
		if SavedTheme[field] ~= nil then
			data[field] = copyData(SavedTheme[field])
		end
	end
	return data
end

-- Back to the shipped look, then the theme's own values on top. Toggle-button and menu-key
-- choices are not part of a theme and stay as they are.
local function applyTheme(data)
	FadeTheme(function()
		for key in pairs(RainbowKeys) do
			RainbowKeys[key] = nil
		end
		for key, value in pairs(DefaultTheme) do
			getgenv().UIColor[key] = value
		end
		for _, field in ipairs(THEME_FIELDS) do
			SavedTheme[field] = nil
		end
		SavedTheme.Rainbow = nil
		if data.Accent then
			Library_Function.SetAccent(Color3.fromRGB(data.Accent[1], data.Accent[2], data.Accent[3]), data.Preset)
		end
		for key, list in pairs(data.Colors or {}) do
			Library_Function.SetThemeColor(key, Color3.fromRGB(list[1], list[2], list[3]))
		end
		if data.PanelTransparency then
			getgenv().UIColor["Background 1 Transparency"] = data.PanelTransparency
			SavedTheme.PanelTransparency = data.PanelTransparency
		end
		if not DisableAnimation then -- touch devices keep animations off
			local speedKeys = { AnimationSpeed1 = "Tween Animation 1 Speed", AnimationSpeed = "Tween Animation 2 Speed", AnimationSpeed3 = "Tween Animation 3 Speed" }
			for field, key in pairs(speedKeys) do
				if data[field] then
					getgenv().UIColor[key] = data[field]
					SavedTheme[field] = data[field]
				end
			end
		end
		if data.Easing then
			getgenv().UIColor["Tween Easing Style"] = data.Easing
			SavedTheme.Easing = data.Easing
		end
		if data.Logo then
			Library_Function.SetLogo(data.Logo)
		end
		if data.WindowStyle == "Transparent" then
			getgenv().UIColor["Background Main Transparency"] = WINDOW_GLASS
			SavedTheme.WindowStyle = "Transparent"
		end
	end)
	panelsBeforeGlass = nil -- the theme decides the panels now
	setThemeBackground(data.Background)
	saveThemeSoon()
	if Library_Function.OnThemeApplied then
		pcall(Library_Function.OnThemeApplied)
	end
end

function ThemeSystem.ListBuiltIn()
	local names = {}
	for _, entry in ipairs(BuiltInThemes) do
		names[#names + 1] = entry.name
	end
	return names
end

function ThemeSystem.List()
	if not ensureThemeFolder() or type(listfiles) ~= "function" then
		return {}
	end
	local names = {}
	for _, path in ipairs(listfiles(ThemeFolder)) do
		local name = path:match("([^/\\]+)%.json$")
		if name then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	return names
end

function ThemeSystem.Exists(name)
	return HasFileSystem and not themeNameError(name) and isfile(themePath(name)) or false
end

-- A built-in or saved theme as sanitised data.
local function readTheme(name)
	local builtIn = builtInNamed(name)
	if builtIn then
		return cleanTheme(copyData(builtIn.data))
	end
	local nameError = themeNameError(name)
	if nameError then
		return nil, nameError
	end
	if not HasFileSystem or not isfile(themePath(name)) then
		return nil, "Theme not found"
	end
	local decoded, data = pcall(function()
		return HttpService:JSONDecode(readfile(themePath(name)))
	end)
	if not decoded then
		return nil, "That theme file is damaged."
	end
	return cleanTheme(data)
end

function ThemeSystem.Apply(name)
	local data, err = readTheme(name)
	if not data then
		return false, err
	end
	applyTheme(data)
	return true
end

-- Saves the current look under a name that is not taken yet.
function ThemeSystem.Create(name)
	local nameError = themeNameError(name)
	if nameError then
		return false, nameError
	end
	if builtInNamed(name) then
		return false, tostring(name) .. " is a built-in theme name. Pick another."
	end
	if ThemeSystem.Exists(name) then
		return false, "A theme named " .. tostring(name) .. " already exists. Use Overwrite theme."
	end
	return ThemeSystem.Save(name)
end

-- Saves the current look over a saved theme.
function ThemeSystem.Save(name)
	local nameError = themeNameError(name)
	if nameError then
		return false, nameError
	end
	if builtInNamed(name) then
		return false, "Built-in themes cannot be changed."
	end
	local ready, folderError = ensureThemeFolder()
	if not ready then
		return false, folderError
	end
	return pcall(writefile, themePath(name), HttpService:JSONEncode(snapshotTheme()))
end

function ThemeSystem.Delete(name)
	local nameError = themeNameError(name)
	if nameError then
		return false, nameError
	end
	if builtInNamed(name) then
		return false, "Built-in themes cannot be deleted."
	end
	if not ThemeSystem.Exists(name) then
		return false, "Theme not found"
	end
	if ThemeSystem.GetDefault() == name then
		ThemeSystem.ClearDefault()
	end
	return pcall(delfile, themePath(name))
end

-- The current look as JSON text, to share.
function ThemeSystem.Export()
	local data = snapshotTheme()
	data.Version = 1
	return HttpService:JSONEncode(data)
end

function ThemeSystem.Import(text)
	if type(text) ~= "string" or text:gsub("%s", "") == "" then
		return false, "Paste theme JSON first."
	end
	local decoded, data = pcall(HttpService.JSONDecode, HttpService, text)
	if not decoded or type(data) ~= "table" then
		return false, "That is not theme JSON."
	end
	local clean, err = cleanTheme(data)
	if not clean then
		return false, err
	end
	applyTheme(clean)
	return true
end

local function defaultThemePath()
	return ThemeFolder .. "/default.txt"
end

function ThemeSystem.GetDefault()
	if not HasFileSystem then
		return nil
	end
	local ok, name = pcall(function()
		return isfile(defaultThemePath()) and readfile(defaultThemePath()) or nil
	end)
	if ok and name and name ~= "" and (builtInNamed(name) or ThemeSystem.Exists(name)) then
		return name
	end
	return nil
end

function ThemeSystem.SetDefault(name)
	if not (builtInNamed(name) or ThemeSystem.Exists(name)) then
		return false, "Theme not found"
	end
	local ready, folderError = ensureThemeFolder()
	if not ready then
		return false, folderError
	end
	local builtIn = builtInNamed(name)
	return pcall(writefile, defaultThemePath(), builtIn and builtIn.name or name)
end

function ThemeSystem.ClearDefault()
	if HasFileSystem and isfile(defaultThemePath()) then
		return pcall(delfile, defaultThemePath())
	end
	return true
end

-- Runs once, as the library loads and before any window exists.
do
	local default = ThemeSystem.GetDefault()
	if default then
		pcall(ThemeSystem.Apply, default)
	end
end

Peridot.ConfigSystem = ConfigSystem
Peridot.ThemeSystem = ThemeSystem
Peridot.ControlRegistry = ControlRegistry
Peridot.SetConfigFolder = SetConfigFolder
Peridot.GetConfigFolder = GetConfigFolder

return Peridot
