-- Peridot Murder Mystery 2 module. The features are libraries/mm2-main.lua (the Noir script).
-- This file gives it the Peridot window: the script builds its controls through host.CreateTab(),
-- and the adapter below turns each of them into a Peridot control.

local MODULE_BASE_URL = "https://raw.githubusercontent.com/Ic0u/peridot/main/"
local SUPPORTED_PLACES = {
    [142823291] = true,
}

if not SUPPORTED_PLACES[game.PlaceId] then
    warn("Peridot Murder Mystery 2 module was loaded in an unsupported place")
    return
end

local PlayersService = game:GetService("Players")
local LocalPlayer = PlayersService.LocalPlayer or PlayersService.PlayerAdded:Wait()
local GameName = "Murder Mystery 2"
pcall(function()
    local productInfo = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
    if type(productInfo) == "table" and type(productInfo.Name) == "string" and productInfo.Name ~= "" then
        GameName = productInfo.Name
    end
end)

local environment = (getgenv and getgenv()) or _G
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
-- Pages. The script names its sections with the page they belong on ("MAIN • FLY",
-- "VISUAL • ...", "⚡ Fling", ...); unnamed ones are the aim sections. All pages are
-- made up front so sections the script adds later keep the sidebar in this order.
----------------------------------------------------------------------------

local PAGE_ORDER = { "Combat", "Main", "Visual", "World", "Troll", "Emotes", "Map", "Misc" }
local pages = {}
for _, name in ipairs(PAGE_ORDER) do
    pages[name] = Window.CreatePage({ Page_Name = name, Page_Title = name })
end

local PREFIX_PAGES = {
    MAIN = "Main", WORLD = "World", VISUAL = "Visual", EMOTES = "Emotes",
    MISC = "Misc", TROLL = "Troll", MAP = "Map", FARM = "World",
}
local WORLD_TAGS = { "Fling", "⚡", "🤖", "📋", "⚙", "🔘", "🔑" }
local NAMED_PAGES = {
    ["Visuals"] = "Visual", ["Object ESP"] = "Visual",
    ["Bomb Jump+"] = "World", ["Gold Bomb Jump+"] = "World",
    ["FE Animations"] = "Emotes", ["About"] = "Emotes",
    ["Inventory Unlimiter V5"] = "Misc", ["Pm-WallHop"] = "Misc",
    ["Backshots"] = "Troll",
}

-- page and shown title for one of the script's section names
local function routeSection(name)
    local prefix, rest = name:match("^(%u+)%s+(.*)$")
    if prefix and PREFIX_PAGES[prefix] then
        -- drop the bullet after the prefix (one section spells it as the text "u{2022}")
        local shown = rest:gsub("^u{2022}%s*", ""):gsub("^[^%w]+", ""):gsub("%s+$", "")
        return PREFIX_PAGES[prefix], shown ~= "" and shown or PREFIX_PAGES[prefix]
    end
    if NAMED_PAGES[name] then
        return NAMED_PAGES[name], name
    end
    for _, tag in ipairs(WORLD_TAGS) do
        if name:find(tag, 1, true) then
            return "World", name
        end
    end
    return "Combat", name
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

-- One section of the script, drawn in the Peridot window. Methods and return values match
-- the Noir host the script was written for.
local function makeSection(name, description)
    pace()
    local pageName, shown = routeSection(name)
    local section = pages[pageName].CreateSection(shown)
    if type(description) == "string" and description ~= "" then
        section.CreateLabel({ Title = description })
    end

    local used = {}
    local function unique(label) -- the same label twice in a section would share a config key
        pace() -- every control passes through here
        label = tostring(label or "")
        local n = (used[label] or 0) + 1
        used[label] = n
        return n == 1 and label or (label .. " (" .. n .. ")")
    end

    local api = { Name = name }

    function api:AddToggle(label, callback)
        local handle = section.CreateToggle({ Title = unique(label) }, safe(label, function(on)
            if callback then
                callback(on)
            end
        end))
        adapterToggles[#adapterToggles + 1] = handle
        return function(value)
            if value == nil then
                value = not handle.Get()
            end
            handle.Set(value == true)
        end
    end

    function api:AddButton(label, callback)
        section.CreateButton({ Title = unique(label) }, safe(label, function()
            if callback then
                callback()
            end
        end))
        return {}
    end

    function api:AddSlider(label, min, max, default, callback)
        min, max = tonumber(min) or 0, tonumber(max) or 100
        local current = math.clamp(math.floor((tonumber(default) or min) + 0.5), min, max)
        local reported = false
        local handle = section.CreateSlider({ Title = unique(label), Min = min, Max = max, Default = current }, safe(label, function(value)
            current = math.clamp(math.floor((tonumber(value) or current) + 0.5), min, max)
            reported = true
            if callback then
                callback(current)
            end
        end))
        if not reported and callback then
            safe(label, callback)(current) -- the script expects its start value once, like Noir did
        end
        return {
            SetValue = function(_, value)
                handle.Set(value)
            end,
            GetValue = function()
                return current
            end,
        }
    end

    function api:AddDropdown(label, values, callback)
        local items, lookup = {}, {}
        local function load(list) -- Peridot lists hold text; keep the script's own values behind them
            items, lookup = {}, {}
            for _, value in ipairs(type(list) == "table" and list or {}) do
                local key = tostring(value)
                items[#items + 1] = key
                lookup[key] = value
            end
        end
        load(values)
        local handle = section.CreateDropdown({
            Title = unique(label),
            List = items,
            Default = items[1],
            Search = #items > 10,
        }, safe(label, function(key)
            if callback and lookup[key] ~= nil then
                callback(lookup[key])
            end
        end))
        local ctl = {}
        function ctl:SetValue(value)
            handle.Set(tostring(value))
        end
        ctl.Select = ctl.SetValue
        function ctl:Refresh(newValues, selected)
            load(newValues)
            handle.GetNewList(items)
            local chosen = selected
            if chosen == nil then
                chosen = (type(newValues) == "table" and newValues[1]) or nil
            end
            if chosen ~= nil then
                handle.Set(tostring(chosen))
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
        return section.CreateDropdown({ Title = unique(label), List = names, Default = "None", Search = true }, safe(label, function(name)
            if callback then
                callback(lookup[name])
            end
        end))
    end

    function api:AddTextBox(label, callback)
        local handle = section.CreateBox({ Title = unique(label), Placeholder = tostring(label or "") }, safe(label, function(text)
            if callback then
                callback(text)
            end
        end))
        return {
            SetValue = function(_, value)
                handle.Set(tostring(value))
            end,
        }
    end

    function api:AddLabel(textValue)
        local current = tostring(textValue or "")
        local handle = section.CreateLabel({ Title = current })
        return {
            SetValue = function(_, value)
                current = tostring(value)
                handle.SetText(current)
            end,
            GetValue = function()
                return current
            end,
        }
    end

    function api:AddParagraph(title, body)
        section.CreateLabel({ Title = tostring(title or "") })
        if body ~= nil and tostring(body) ~= "" then
            section.CreateLabel({ Title = tostring(body) })
        end
        return {}
    end

    function api:AddColorpicker(label, default, callback)
        local colour = typeof(default) == "Color3" and default or Color3.fromRGB(140, 172, 68)
        local handle = section.CreateColorPicker({ Title = unique(label), Default = colour }, safe(label, function(value)
            colour = value
            if callback then
                callback(value)
            end
        end))
        if callback then
            safe(label, callback)(colour) -- the script expects its start color once, like Noir did
        end
        return {
            SetRGBValue = function(_, value)
                if typeof(value) ~= "Color3" then
                    return
                end
                colour = value
                handle.Set(value)
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
        for _, key in ipairs(KEY_NAMES) do
            list[#list + 1] = key
        end
        if not table.find(list, current) then
            table.insert(list, 2, current)
        end
        local handle = section.CreateDropdown({ Title = unique(label), List = list, Default = current, Search = true }, safe(label, function(key)
            current = key
            if callback then
                callback(key)
            end
        end))
        return {
            SetValue = function(_, value)
                current = tostring(value)
                handle.Set(current)
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

function MM2Host.Notify(message, duration)
    local text = tostring(message or ""):gsub("^MM2 Silent Aim: ", "")
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
    local panels = pages.Misc.CreateSection("Noir Panels")
    local function open(page)
        local show = environment.__NoirShowPanel
        if type(show) ~= "function" then
            return notify("Panels", "The features have not finished loading.")
        end
        show(page)
    end
    panels.CreateButton({ Title = "Emote Browser", ButtonText = "Open" }, safe("Emote Browser", function()
        open("emotes")
    end))
    panels.CreateButton({ Title = "Skin Changer", ButtonText = "Open" }, safe("Skin Changer", function()
        open("skins")
    end))
    panels.CreateButton({ Title = "Noir Settings (language, stream mode)", ButtonText = "Open" }, safe("Noir Settings", function()
        open("settings")
    end))
    panels.CreateLabel({ Title = "The panel's minimize button closes it again." })
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
