-- Peridot Bee Swarm Simulator module: Kron's hub, in the Peridot window.
-- The features are libraries/bss-main.lua; this file only builds the interface.

local MODULE_BASE_URL = "https://raw.githubusercontent.com/Ic0u/peridot/main/"
local SUPPORTED_PLACES = {
    [1537690962] = true,
}
local KRON_DISCORD = "https://discord.gg/QKFNzKyHbw" -- from the original hub's Home tab

local environment = (getgenv and getgenv()) or _G

-- Test mode: getgenv().PeridotForceGame = true builds the window in any game, so the interface can
-- be tried without joining Bee Swarm Simulator. The features need the game itself.
local testMode = not SUPPORTED_PLACES[game.PlaceId]
if testMode and not environment.PeridotForceGame then
    warn("Peridot Bee Swarm Simulator module was loaded in an unsupported place")
    return
end

local PlayersService = game:GetService("Players")
local LocalPlayer = PlayersService.LocalPlayer or PlayersService.PlayerAdded:Wait()
local GameName = testMode and "Bee Swarm Simulator (test mode)" or "Bee Swarm Simulator"
pcall(function()
    if testMode then
        return
    end
    local productInfo = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
    if type(productInfo) == "table" and type(productInfo.Name) == "string" and productInfo.Name ~= "" then
        GameName = productInfo.Name
    end
end)

if environment.PeridotBeeSwarmLoaded then
    warn("Peridot Bee Swarm Simulator is already running")
    return
end
environment.PeridotBeeSwarmLoaded = true

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
UILibrary.SetConfigFolder("Peridot/BeeSwarm")

local function notify(title, desc, duration)
    pcall(UILibrary.CreateNoti, { Title = title, Desc = desc, ShowTime = duration or 4 })
end

local coreLoaded, Core = pcall(loadRemoteModule, "libraries/bss-main.lua")
if not coreLoaded or type(Core) ~= "table" then
    warn("[Peridot] Bee Swarm Simulator core failed: " .. tostring(Core))
    notify("Bee Swarm Simulator", "The feature script failed to load. Rejoin and run again.", 8)
    environment.PeridotBeeSwarmLoaded = nil
    return
end
environment.PeridotBeeSwarmCore = Core
Core.Notify = notify

local Window = UILibrary.CreateMain({
    Name = "Peridot",
    Title = GameName,
    Desc = "",
})

-- No control may throw: a game error here would stop the whole page from building.
local function safe(where, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            warn("[Peridot] " .. tostring(where) .. ": " .. tostring(err))
        end
    end
end

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------

local handles = {} -- setting name -> its switch, so the core can flip it (one mover turns the others off)

local function btn(section, title, fn, text)
    return section.CreateButton({ Title = title, ButtonText = text }, safe(title, fn))
end

-- A switch for one of the core's settings.
local function tog(section, title, setting, desc)
    local handle = section.CreateToggle({
        Title = title,
        Desc = desc,
        Default = Core.Settings[setting] == true,
    }, safe(title, function(on)
        Core.Set(setting, on and true or false)
    end))
    handles[setting] = handle
    return handle
end

local function num(section, title, setting, min, max)
    return section.CreateSlider({
        Title = title,
        Min = min,
        Max = max,
        Default = Core.Settings[setting],
    }, safe(title, function(value)
        Core.Set(setting, tonumber(value) or Core.Settings[setting])
    end))
end

Core.OnChange = function(setting, value)
    local handle = handles[setting]
    if handle then
        pcall(handle.Set, value)
    end
end

local function field(section, title, onPick, default)
    return section.CreateDropdown({
        Title = title,
        List = Core.FieldNames(),
        Default = default,
        Search = true,
    }, safe(title, onPick))
end

----------------------------------------------------------------------------
-- Home
----------------------------------------------------------------------------

do
    local page = Window.CreatePage({ Page_Name = "Home", Page_Title = "Home" })
    local about = page.CreateSection("Welcome")
    about.CreateLabel({ Title = "Bee Swarm Simulator hub by Kron, now in the Peridot window." })
    about.CreateLabel({ Title = "To start: pick a field on the Farming page, then turn on Auto Farm and Auto Dig." })

    local quick = page.CreateSection("Quick Actions")
    btn(quick, "Rejoin Server", function()
        game:GetService("TeleportService"):Teleport(game.PlaceId, LocalPlayer)
    end, "Rejoin")
    btn(quick, "Copy Kron's Discord", function()
        local copied = type(setclipboard) == "function" and pcall(setclipboard, KRON_DISCORD)
        notify("Discord", copied and "The invite link is copied." or ("Your executor cannot copy. The invite is " .. KRON_DISCORD), copied and 4 or 8)
    end, "Copy")
end

----------------------------------------------------------------------------
-- Farming
----------------------------------------------------------------------------

do
    local page = Window.CreatePage({ Page_Name = "Farming", Page_Title = "Farming" })
    local farm = page.CreateSection("Auto Farm")
    field(farm, "Field", function(name)
        Core.Set("Field", name)
    end, Core.Settings.Field)
    tog(farm, "Auto Farm", "AutoFarm", "Farms your field. When your bag is full it flies to your hive, turns the pollen into honey, then flies back.")
    tog(farm, "Auto Dig", "AutoDig", "Swings your tool for you. Use it together with Auto Farm.")

    local options = page.CreateSection("Farm Options")
    tog(options, "Collect Tokens", "CollectTokens", "While farming, walks over nearby tokens.")
    tog(options, "Collect Bubbles", "CollectBubbles", "While farming, also walks to nearby bubbles.")
    tog(options, "Place Sprinkler", "PlaceSprinkler", "Places a sprinkler each time you arrive at the field.")
    tog(options, "Convert Hive Balloon", "ConvertBalloons", "After the honey is made, stays at your hive for up to 15 seconds while your hive balloon is nearby.")
end

----------------------------------------------------------------------------
-- Combat
----------------------------------------------------------------------------

do
    local page = Window.CreatePage({ Page_Name = "Combat", Page_Title = "Combat" })
    local training = page.CreateSection("Training")
    tog(training, "Train Snail", "TrainSnail", "Goes to the Stump Field snail and stays close to it.")
    tog(training, "Train Crab", "TrainCrab", "Puts you on an invisible platform at the Coconut Crab and keeps you there.")
    training.CreateLabel({ Title = "Only one of Auto Farm, Train Snail and Train Crab runs at a time. Turning one on turns the others off." })

    local protection = page.CreateSection("Protection")
    tog(protection, "Stay On Your Feet", "StayOnFeet", "Stops you from being knocked down.")
end

----------------------------------------------------------------------------
-- Teleport
----------------------------------------------------------------------------

do
    local page = Window.CreatePage({ Page_Name = "Teleport", Page_Title = "Teleport" })
    local fields = page.CreateSection("Fields")
    local target = Core.Settings.Field
    field(fields, "Field To Visit", function(name)
        target = name
    end, target)
    btn(fields, "Go To Selected Field", function()
        if not Core.TeleportToField(target) then
            notify("Teleport", "Your character is not ready yet.")
        end
    end, "Go")

    local hive = page.CreateSection("Hive")
    btn(hive, "Go To My Hive", function()
        local ok, why = Core.TeleportToHive()
        if not ok then
            notify("Hive", why or "Your character is not ready yet.")
        end
    end, "Go")
end

----------------------------------------------------------------------------
-- Items
----------------------------------------------------------------------------

do
    local page = Window.CreatePage({ Page_Name = "Items", Page_Title = "Items" })
    local sets = page.CreateSection("Buff Sets")
    btn(sets, "Use All Blue Buffs", function()
        Core.UseItems(Core.BlueBuffs)
    end, "Use")
    btn(sets, "Use All Red Buffs", function()
        Core.UseItems(Core.RedBuffs)
    end, "Use")
    sets.CreateLabel({ Title = "Blue is Blue Extract, Glitter, Glue, Oil, Enzymes and Tropical Drink. Red swaps Blue Extract for Red Extract." })

    local single = page.CreateSection("Single Items")
    for _, name in ipairs(Core.Items) do
        btn(single, "Use " .. name, function()
            Core.UseItem(name)
        end, "Use")
    end

    local dispensers = page.CreateSection("Dispensers")
    btn(dispensers, "Use All Dispensers", function()
        Core.UseAllDispensers()
    end, "Use")
    dispensers.CreateLabel({ Title = "Honey, Treat, Blueberry, Strawberry, Coconut and Glue dispensers, the Free Ant Pass and Free Royal Jelly dispensers, and the Wealth Clock." })
end

----------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------

do
    local page = Window.CreatePage({ Page_Name = "Settings", Page_Title = "Settings" })

    local options = page.CreateSubTab("Options")
    local walking = options.CreateSection("Walking")
    num(walking, "Walk Speed", "WalkSpeed", 16, 55)
    tog(walking, "Keep Walk Speed", "KeepWalkSpeed", "Keeps your walk speed at the slider value.")
    local travel = options.CreateSection("Travel")
    num(travel, "Travel Speed", "TravelSpeed", 40, 150)
    travel.CreateLabel({ Title = "How fast you glide to your field, hive and other places. Lower is slower but looks more natural." })
    local extras = options.CreateSection("Extras")
    tog(extras, "Walk Through Field Decorations", "WalkThroughDecorations", "Makes field trees and decorations see-through so you can walk through them.")
    tog(extras, "Anti-AFK", "AntiAfk", "Stops the game from kicking you for standing still.")

    UILibrary.AddConfigSection(page.CreateSubTab("Config"))

    local utility = page.CreateSubTab("Utility").CreateSection("Utility")
    btn(utility, "Stop All Features", function()
        Core.StopFeatures()
        notify("Stopped", "Auto Farm, Auto Dig, training and Keep Walk Speed are off.")
    end, "Stop")
    btn(utility, "Unload UI", function()
        Core.Unload()
        environment.PeridotBeeSwarmLoaded = nil
        environment.PeridotBeeSwarmCore = nil
        UILibrary.Unload()
    end, "Unload")
    utility.CreateLabel({ Title = "After unloading, run the loadstring again to bring the UI back." })
end

-- Interface Settings (the gear) already holds the theme, colors, window and UI toggle options;
-- the background picker is added to it here, as in the other scripts.
UILibrary.AddBackgroundSection(Window, MODULE_BASE_URL)

Core.Start()
notify("Bee Swarm Simulator", "Loaded. Pick a field on the Farming page to start.", 5)
