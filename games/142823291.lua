-- Peridot Murder Mystery 2 module. The features are libraries/mm2-main.lua (the Noir script).
-- This file gives it the Peridot window: the script builds its controls through host.CreateTab(),
-- and the adapter below turns each of them into a Peridot control.

local MODULE_BASE_URL = "https://raw.githubusercontent.com/Ic0u/peridot/main/"
local SUPPORTED_PLACES = {
    [142823291] = true,
}

local environment = (getgenv and getgenv()) or _G

-- Test mode: getgenv().PeridotForceGame = true builds the window in any game, so the
-- interface can be tried without joining Murder Mystery 2. The game features need MM2 itself.
local testMode = not SUPPORTED_PLACES[game.PlaceId]
if testMode and not environment.PeridotForceGame then
    warn("Peridot Murder Mystery 2 module was loaded in an unsupported place")
    return
end

local PlayersService = game:GetService("Players")
local LocalPlayer = PlayersService.LocalPlayer or PlayersService.PlayerAdded:Wait()
local GameName = testMode and "Murder Mystery 2 (test mode)" or "Murder Mystery 2"
pcall(function()
    if testMode then
        return
    end
    local productInfo = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
    if type(productInfo) == "table" and type(productInfo.Name) == "string" and productInfo.Name ~= "" then
        GameName = productInfo.Name
    end
end)

if environment.PeridotMM2Loaded then
    warn("Peridot Murder Mystery 2 is already running")
    return
end
environment.PeridotMM2Loaded = true

local function loadRemoteModule(path)
    local fetched, source = pcall(game.HttpGet, game, MODULE_BASE_URL .. path)
    if not fetched or type(source) ~= "string" or source == "" then
        error("Peridot could not download " .. path)
    end

    local chunk, compileError = loadstring(source)
    if not chunk then
        error("Peridot could not compile " .. path .. ": " .. tostring(compileError))
    end

    local ok, result = pcall(chunk)
    if not ok then
        error("Peridot could not initialize " .. path .. ": " .. tostring(result))
    end

    return result
end

local UILibrary = loadRemoteModule("libraries/UILibrary.lua")
UILibrary.SetConfigFolder("Peridot/MM2")

local Window = UILibrary.CreateMain({
    Name = "Peridot",
    Title = GameName,
    Desc = "",
})

local function notify(title, desc, duration)
    pcall(UILibrary.CreateNoti, { Title = title, Desc = desc, ShowTime = duration or 4 })
end

-- Murder Mystery 2 kicks the client on script errors, so no control may throw.
local function safe(where, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            warn("[Peridot] " .. tostring(where) .. ": " .. tostring(err))
        end
    end
end

----------------------------------------------------------------------------
-- Wording and layout. libraries/mm2-text.lua says, in plain English, where every
-- section and control goes and what to call it; anything it does not list is cleaned up
-- (symbols removed, capitals fixed, developer words replaced) and put on the Extras page.
----------------------------------------------------------------------------

local Text = loadRemoteModule("libraries/mm2-text.lua")

----------------------------------------------------------------------------
-- Pages and sub-tabs, made up front so they keep the order in the wording file.
----------------------------------------------------------------------------

local pages, tabs = {}, {}
for _, name in ipairs(Text.pages) do
    pages[name] = Window.CreatePage({ Page_Name = name, Page_Title = name })
    tabs[name] = {}
    for _, tabName in ipairs(Text.tabs[name] or {}) do
        tabs[name][tabName] = pages[name].CreateSubTab(tabName)
    end
end

local function tabFor(pageName, tabName)
    if not pages[pageName] then
        pageName, tabName = Text.fallback.page, Text.fallback.tab
    end
    if not tabs[pageName][tabName] then
        tabs[pageName][tabName] = pages[pageName].CreateSubTab(tabName)
    end
    return tabs[pageName][tabName], pageName, tabName
end

-- Sections are made when their first control arrives, so a section whose controls were all
-- moved elsewhere or hidden never shows up empty.
local madeSections = {}
local function sectionFor(pageName, tabName, title, intro)
    local tab, page, tabKey = tabFor(pageName, tabName)
    local key = page .. "/" .. tabKey .. "/" .. title
    if not madeSections[key] then
        local section = tab.CreateSection(title)
        if type(intro) == "string" and intro ~= "" then
            section.CreateLabel({ Title = intro })
        end
        madeSections[key] = section
    end
    return madeSections[key]
end

local KEY_NAMES = {
    "None", "Q", "E", "R", "T", "Y", "U", "F", "G", "H", "J", "K", "L", "Z", "X", "C", "V", "B", "N", "M",
    "One", "Two", "Three", "Four", "Five", "LeftShift", "RightShift", "LeftControl", "RightControl",
    "LeftAlt", "RightAlt", "Tab", "CapsLock", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8",
    "MouseButton1", "MouseButton2",
}

local adapterToggles = {} -- every toggle the script made, for Stop All Features and Unload UI

-- The script builds hundreds of controls in one go; pause every 16 like Noir's own builder
-- did, so slow devices do not stall or time out while it loads.
local built = 0
local function pace()
    built = built + 1
    if built % 16 == 0 then
        task.wait()
    end
end

-- One section of the script. Methods and return values match the Noir host the script was
-- written for, but each control is placed and worded through mm2-text.lua first.
local function makeSection(name, description)
    pace()
    local key = Text.sectionKey(name)
    local pageName, tabName, title, intro = Text.home(name, description)

    -- where a control goes: its own section, or one the wording file moves it to
    local function target(route)
        if route then
            local routePage, routeTab, routeTitle = route:match("^([^/]+)/([^/]+)/(.+)$")
            if routePage then
                return sectionFor(routePage, routeTab, routeTitle, nil)
            end
        end
        return sectionFor(pageName, tabName, title, intro)
    end

    local used = {}
    local function unique(label) -- the same title twice in a section would share a config key
        pace()
        label = tostring(label or "")
        local n = (used[label] or 0) + 1
        used[label] = n
        return n == 1 and label or (label .. " (" .. n .. ")")
    end

    -- the wording and place for one control; hidden controls return nil
    local function place(kind, label)
        local newTitle, help, route, buttonText = Text.describe(key, kind, label)
        if newTitle == "-" or newTitle == "" then
            return nil
        end
        return newTitle, help, target(route), buttonText
    end

    local api = { Name = name }

    function api:AddToggle(label, callback)
        local newTitle, help, section = place("Toggle", label)
        local state = false
        local handle
        if newTitle then
            handle = section.CreateToggle({ Title = unique(newTitle), Desc = help ~= "" and help or nil }, safe(label, function(on)
                state = on == true
                if callback then
                    callback(on)
                end
            end))
            adapterToggles[#adapterToggles + 1] = handle
        end
        return function(value)
            if value == nil then
                value = not state
            end
            if handle then
                handle.Set(value == true)
            else
                state = value == true
                if callback then
                    safe(label, callback)(state)
                end
            end
        end
    end

    function api:AddButton(label, callback)
        local newTitle, _, section, buttonText = place("Button", label)
        if newTitle then
            section.CreateButton({ Title = unique(newTitle), ButtonText = buttonText }, safe(label, function()
                if callback then
                    callback()
                end
            end))
        end
        return {}
    end

    function api:AddSlider(label, min, max, default, callback)
        min, max = tonumber(min) or 0, tonumber(max) or 100
        local current = math.clamp(math.floor((tonumber(default) or min) + 0.5), min, max)
        local newTitle, _, section = place("Slider", label)
        local handle
        local reported = false
        if newTitle then
            handle = section.CreateSlider({ Title = unique(newTitle), Min = min, Max = max, Default = current }, safe(label, function(value)
                current = math.clamp(math.floor((tonumber(value) or current) + 0.5), min, max)
                reported = true
                if callback then
                    callback(current)
                end
            end))
        end
        if not reported and callback then
            safe(label, callback)(current) -- the script expects its start value once, like Noir did
        end
        return {
            SetValue = function(_, value)
                if handle then
                    handle.Set(value)
                else
                    current = tonumber(value) or current
                    if callback then
                        safe(label, callback)(current)
                    end
                end
            end,
            GetValue = function()
                return current
            end,
        }
    end

    function api:AddDropdown(label, values, callback)
        local items, lookup, shownOf = {}, {}, {}
        local function load(list) -- Peridot lists hold text; keep the script's own values behind them
            items, lookup, shownOf = {}, {}, {}
            for _, value in ipairs(type(list) == "table" and list or {}) do
                local shown = Text.value(label, value)
                items[#items + 1] = shown
                lookup[shown] = value
                shownOf[tostring(value)] = shown
            end
        end
        load(values)
        local newTitle, _, section = place("Dropdown", label)
        local handle
        if newTitle then
            handle = section.CreateDropdown({
                Title = unique(newTitle),
                List = items,
                Default = items[1],
                Search = #items > 10,
            }, safe(label, function(shown)
                if callback and lookup[shown] ~= nil then
                    callback(lookup[shown])
                end
            end))
        elseif callback and items[1] then
            safe(label, callback)(lookup[items[1]])
        end
        local ctl = {}
        function ctl:SetValue(value)
            if handle then
                handle.Set(shownOf[tostring(value)] or tostring(value))
            elseif callback then
                safe(label, callback)(value)
            end
        end
        ctl.Select = ctl.SetValue
        function ctl:Refresh(newValues, selected)
            load(newValues)
            if handle then
                handle.GetNewList(items)
            end
            local chosen = selected
            if chosen == nil then
                chosen = (type(newValues) == "table" and newValues[1]) or nil
            end
            if chosen ~= nil then
                ctl:SetValue(chosen)
            end
        end
        function ctl:ChangeItems(newValues)
            ctl:Refresh(newValues)
        end
        return ctl
    end

    function api:AddPlayerDropdown(label, callback)
        local names, lookup = { "None" }, {}
        for _, player in ipairs(PlayersService:GetPlayers()) do
            if player ~= LocalPlayer then
                names[#names + 1] = player.Name
                lookup[player.Name] = player
            end
        end
        local newTitle, _, section = place("PlayerDropdown", label)
        if not newTitle then
            return {}
        end
        return section.CreateDropdown({ Title = unique(newTitle), List = names, Default = "None", Search = true }, safe(label, function(chosen)
            if callback then
                callback(lookup[chosen])
            end
        end))
    end

    function api:AddTextBox(label, callback)
        local newTitle, help, section = place("TextBox", label)
        local handle
        if newTitle then
            handle = section.CreateBox({ Title = unique(newTitle), Placeholder = help ~= "" and help or newTitle }, safe(label, function(text)
                if callback then
                    callback(text)
                end
            end))
        end
        return {
            SetValue = function(_, value)
                if handle then
                    handle.Set(tostring(value))
                end
            end,
        }
    end

    function api:AddLabel(textValue)
        local current = tostring(textValue or "")
        local newTitle, _, section = place("Label", current)
        local handle = newTitle and section.CreateLabel({ Title = newTitle }) or nil
        return {
            SetValue = function(_, value)
                current = tostring(value)
                if handle then
                    handle.SetText(Text.hasRussian(current) and "" or Text.clean(current))
                end
            end,
            GetValue = function()
                return current
            end,
        }
    end

    function api:AddParagraph(title, body)
        local newTitle, _, section = place("Paragraph", title)
        if newTitle then
            section.CreateLabel({ Title = newTitle })
            if body ~= nil and tostring(body) ~= "" and not Text.hasRussian(body) then
                section.CreateLabel({ Title = Text.words(tostring(body)) })
            end
        end
        return {}
    end

    function api:AddColorpicker(label, default, callback)
        local colour = typeof(default) == "Color3" and default or Color3.fromRGB(140, 172, 68)
        local newTitle, _, section = place("Colorpicker", label)
        local handle
        if newTitle then
            handle = section.CreateColorPicker({ Title = unique(newTitle), Default = colour }, safe(label, function(value)
                colour = value
                if callback then
                    callback(value)
                end
            end))
        end
        if callback then
            safe(label, callback)(colour) -- the script expects its start color once, like Noir did
        end
        return {
            SetRGBValue = function(_, value)
                if typeof(value) ~= "Color3" then
                    return
                end
                colour = value
                if handle then
                    handle.Set(value)
                end
                if callback then
                    safe(label, callback)(value)
                end
            end,
            GetValue = function()
                return colour
            end,
        }
    end

    -- Noir's keybind is a key picker: the script gets the key name and listens for it itself.
    function api:AddKeybind(label, default, callback)
        local current = tostring(default or "None")
        local list = {}
        for _, keyName in ipairs(KEY_NAMES) do
            list[#list + 1] = keyName
        end
        if not table.find(list, current) then
            table.insert(list, 2, current)
        end
        local newTitle, _, section = place("Keybind", label)
        local handle
        if newTitle then
            handle = section.CreateDropdown({ Title = unique(newTitle), List = list, Default = current, Search = true }, safe(label, function(keyName)
                current = keyName
                if callback then
                    callback(keyName)
                end
            end))
        end
        return {
            SetValue = function(_, value)
                current = tostring(value)
                if handle then
                    handle.Set(current)
                end
            end,
            GetValue = function()
                return current
            end,
        }
    end

    return api
end

local MM2Host = {}

function MM2Host.CreateTab()
    local tab = {}
    function tab:AddSection(name, description)
        return makeSection(tostring(name or "Section"), description)
    end
    return tab
end

-- Messages from the script use developer words in places; say them plainly.
function MM2Host.Notify(message, duration)
    local text = Text.words((tostring(message or ""):gsub("^MM2 Silent Aim: ", "")))
    notify("MM2", text, tonumber(duration) or 3)
end

environment.PeridotMM2Host = MM2Host

-- The script guards against running twice itself and replaces its old copy, so it loads on every run.
local coreLoaded, coreError = pcall(loadRemoteModule, "libraries/mm2-main.lua")
if not coreLoaded then
    warn("[Peridot] Murder Mystery 2 features failed: " .. tostring(coreError))
end

----------------------------------------------------------------------------
-- Panels that are not plain controls stay in the script's own window; these open them one at a time.
----------------------------------------------------------------------------

do
    local function open(page)
        local show = environment.__NoirShowPanel
        if type(show) ~= "function" then
            return notify("Panels", "The features have not finished loading.")
        end
        show(page)
    end
    local emoteBox = sectionFor("Emotes", "Browser", "Emote Browser", "Browse hundreds of emotes with pictures, and open the game's own emote buttons.")
    emoteBox.CreateButton({ Title = "Open The Emote Browser", ButtonText = "Open" }, safe("Emote Browser", function()
        open("emotes")
    end))
    local panels = sectionFor("Extras", "Panels", "Extra Panels", "These open in their own window. Use the minimize button there to close them.")
    panels.CreateButton({ Title = "Skin Changer", ButtonText = "Open" }, safe("Skin Changer", function()
        open("skins")
    end))
    panels.CreateButton({ Title = "Language And Streamer Options", ButtonText = "Open" }, safe("Language And Streamer Options", function()
        open("settings")
    end))
end

----------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------

do
    local page = Window.CreatePage({ Page_Name = "Settings", Page_Title = "Settings" })
    UILibrary.AddConfigSection(page.CreateSubTab("Config"))

    local utility = page.CreateSubTab("Utility").CreateSection("Utility")
    local function stopAll()
        for _, handle in ipairs(adapterToggles) do
            pcall(handle.Set, false)
        end
    end
    utility.CreateButton({ Title = "Stop All Features", ButtonText = "Stop" }, safe("Stop All Features", function()
        stopAll()
        notify("Stopped", "Every feature switch is off.")
    end))
    utility.CreateButton({ Title = "Unload UI", ButtonText = "Unload" }, safe("Unload UI", function()
        stopAll()
        local noirGui = environment.__NoirGui
        if typeof(noirGui) == "Instance" then
            pcall(noirGui.Destroy, noirGui)
        end
        environment.PeridotMM2Host = nil
        environment.PeridotMM2Loaded = nil
        UILibrary.Unload()
    end))
    utility.CreateLabel({ Title = "After unloading, run the loadstring again to bring the UI back." })
    if not coreLoaded then
        utility.CreateLabel({ Title = "The features failed to load. Rejoin and run again." })
    end
end

UILibrary.AddBackgroundSection(Window, MODULE_BASE_URL)

if not coreLoaded then
    notify("Murder Mystery 2", "The features failed to load, so switches will not work.", 8)
end
if testMode then
    notify("Test mode", "This is not Murder Mystery 2, so only the interface works here.", 8)
end
