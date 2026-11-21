-- Peridot Bee Swarm Simulator module: Kron's hub and Verbal Hub Sigma BSS, in the Peridot window.
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

-- Like the source, wait for the game to finish loading before touching anything.
if not game:IsLoaded() then
    game.Loaded:Wait()
end

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

-- A dropdown over a list of names (strings).
local function pick(section, title, items, default, onPick)
    return section.CreateDropdown({
        Title = title,
        List = items,
        Default = default,
        Search = #items > 8,
    }, safe(title, onPick))
end

Core.OnChange = function(setting, value)
    local handle = handles[setting]
    if handle then
        pcall(handle.Set, value)
    end
end

-- A button that goes to the place picked in the dropdown above it.
local function goTo(section, noun, list, notice)
    local names = Core.Names(list)
    local chosen = names[1]
    pick(section, noun, names, chosen, function(name)
        chosen = name
    end)
    btn(section, "Go To Selected " .. noun, function()
        if not Core.GoToPlace(list, chosen) then
            notify(notice, "Your character is not ready yet.")
        end
    end, "Go")
end

----------------------------------------------------------------------------
-- Home
----------------------------------------------------------------------------

do
    local page = Window.CreatePage({ Page_Name = "Home", Page_Title = "Home" })
    local credits = page.CreateSection("Credits")
    credits.CreateLabel({ Title = "KronHub for Bee Swarm Simulator, now in the Peridot window." })
    credits.CreateLabel({ Title = "Owner: Marcus" })
    credits.CreateLabel({ Title = "Original version: 1.0" })
    credits.CreateLabel({ Title = "More features from Verbal Hub Sigma BSS." })
    credits.CreateLabel({ Title = "To start: pick a field on the Farming page, then turn on Auto Farm and Auto Dig." })

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

    local main = page.CreateSubTab("Auto Farm")
    local farm = main.CreateSection("Auto Farm")
    pick(farm, "Field", Core.FieldNames(), Core.Settings.Field, function(name)
        Core.Set("Field", name)
    end)
    tog(farm, "Auto Farm", "AutoFarm", "Farms your field. When your bag is full it flies to your hive, turns the pollen into honey, then flies back.")
    tog(farm, "Auto Dig", "AutoDig", "Swings your tool for you. Use it together with Auto Farm.")
    pick(farm, "Movement While Collecting", { "Walk", "Glide", "Fast Glide" }, Core.Settings.MoveStyle, function(style)
        Core.Set("MoveStyle", style)
    end)
    farm.CreateLabel({ Title = "Walk is the gentlest. Glide and Fast Glide slide you over to what you pick up." })

    local pickUp = main.CreateSection("Pick Up")
    tog(pickUp, "Collect Tokens", "CollectTokens", "While farming, walks over nearby tokens.")
    tog(pickUp, "Collect Bubbles", "CollectBubbles", "While farming, also goes for nearby bubbles.")
    tog(pickUp, "Collect Flames", "CollectFlames", "While farming, goes for flames in the field first.")
    tog(pickUp, "Collect Stars", "CollectStars", "While farming, goes for stars in the field.")
    tog(pickUp, "Collect Balloons", "CollectBalloons", "While farming, stays near a field balloon and picks up what is around it.")

    local bag = main.CreateSection("Bag And Hive")
    tog(bag, "Go Home When Bag Is Full", "GoHomeWhenFull", "Flies to your hive to make honey when your bag is full. Turn it off to just keep farming.")
    num(bag, "Go Home At (% Full)", "GoHomePercent", 50, 100)
    tog(bag, "Convert Hive Balloon", "ConvertBalloons", "After the honey is made, stays at your hive for up to 15 seconds while your hive balloon is nearby.")

    local sprinkler = main.CreateSection("Sprinkler")
    tog(sprinkler, "Place Sprinkler", "PlaceSprinkler", "Places a sprinkler each time you arrive at the field.")

    local rewards = page.CreateSubTab("Rewards")
    local stickers = rewards.CreateSection("Stickers")
    btn(stickers, "Find All Stickers", function()
        local count, why = Core.FindStickers()
        if count then
            notify("Stickers", "Collected " .. count .. " stickers. The game gives hidden stickers once a day.", 6)
        else
            notify("Stickers", why, 6)
        end
    end, "Find")
    stickers.CreateLabel({ Title = "Clicks every hidden sticker for you." })

    local codes = rewards.CreateSection("Promo Codes")
    local typedCodes = ""
    codes.CreateBox({
        Title = "Promo Codes",
        Placeholder = "type one or more codes",
        Default = "",
        NoSave = true,
    }, function(text)
        typedCodes = text
    end)
    btn(codes, "Redeem Codes", function()
        if typedCodes:gsub("%s", "") == "" then
            return notify("Promo Codes", "Type a code first. Use spaces between several.")
        end
        local sent = Core.RedeemCodes(typedCodes)
        notify("Promo Codes", "Sent " .. sent .. (sent == 1 and " code." or " codes.") .. " The game does not say which ones worked.", 6)
    end, "Redeem")
end

----------------------------------------------------------------------------
-- Combat
----------------------------------------------------------------------------

do
    local page = Window.CreatePage({ Page_Name = "Combat", Page_Title = "Combat" })

    local training = page.CreateSubTab("Training")
    local train = training.CreateSection("Training")
    tog(train, "Train Snail", "TrainSnail", "Goes to the Stump Field snail and stays close to it.")
    tog(train, "Train Crab", "TrainCrab", "Puts you on a big invisible platform near the Coconut Crab and keeps you there.")
    tog(train, "Fight Coconut Crab", "FightCrab", "Stands you right above the Coconut Crab so your bees can fight it.")
    train.CreateLabel({ Title = "Only one of Auto Farm and the training and boss switches runs at a time. Turning one on turns the others off." })
    local protection = training.CreateSection("Protection")
    tog(protection, "Stay On Your Feet", "StayOnFeet", "Stops you from being knocked down.")

    local bosses = page.CreateSubTab("Bosses")
    local spots = bosses.CreateSection("Monster Spots")
    btn(spots, "Fight Commando Chick", function()
        Core.StandAt("CommandoChick")
    end, "Go")
    btn(spots, "Fight Tunnel Bear", function()
        Core.StandAt("TunnelBear")
    end, "Go")
    btn(spots, "AFK At Stump Snail", function()
        Core.StandAt("StumpSnail")
    end, "Go")
    spots.CreateLabel({ Title = "Each one puts you on an invisible platform next to the monster so your bees can fight it." })
    local hover = bosses.CreateSection("Floating Above Bosses")
    tog(hover, "Hover Over Windy Bee", "HoverWindy", "While the Windy Bee is around, floats you above it so your bees can fight it.")
    tog(hover, "Hover Over Vicious Bee", "HoverVicious", "While the Vicious Bee is around, floats you above it.")
    tog(hover, "Float Above Mondo Chick", "FollowMondo", "While the Mondo Chick is around, floats you high above it. The script it came from marked this one as still in testing.")
end

----------------------------------------------------------------------------
-- Event
----------------------------------------------------------------------------

do
    local page = Window.CreatePage({ Page_Name = "Event", Page_Title = "Event" })
    local winter = page.CreateSection("Winter Event")
    tog(winter, "Collect Snowflakes", "CollectSnowflakes", "Hops from snowflake to snowflake. It does nothing when there are none.")
    local places = page.CreateSection("Event Teleports")
    btn(places, "Go To Bee Bear", function()
        if not Core.GoToBeeBear() then
            notify("Teleport", "Your character is not ready yet.")
        end
    end, "Go")
    goTo(places, "Gift", Core.Gifts, "Teleport")
end

----------------------------------------------------------------------------
-- Teleport
----------------------------------------------------------------------------

do
    local page = Window.CreatePage({ Page_Name = "Teleport", Page_Title = "Teleport" })

    local fieldsTab = page.CreateSubTab("Fields")
    local style = fieldsTab.CreateSection("Teleport Style")
    pick(style, "Teleport Style", { "Glide", "Instant" }, Core.Settings.TeleportStyle, function(name)
        Core.Set("TeleportStyle", name)
    end)
    style.CreateLabel({ Title = "Glide slides you there at your Travel Speed. Instant jumps at once. Very far places always jump." })
    local fields = fieldsTab.CreateSection("Fields")
    local target = Core.Settings.Field
    pick(fields, "Field To Visit", Core.FieldNames(), target, function(name)
        target = name
    end)
    btn(fields, "Go To Selected Field", function()
        if not Core.TeleportToField(target) then
            notify("Teleport", "Your character is not ready yet.")
        end
    end, "Go")
    local hive = fieldsTab.CreateSection("Hive")
    btn(hive, "Go To My Hive", function()
        local ok, why = Core.TeleportToHive()
        if not ok then
            notify("Hive", why or "Your character is not ready yet.")
        end
    end, "Go")

    local placesTab = page.CreateSubTab("Places")
    goTo(placesTab.CreateSection("Shops"), "Shop", Core.Shops, "Teleport")
    goTo(placesTab.CreateSection("Bears"), "Bear", Core.Bears, "Teleport")
    goTo(placesTab.CreateSection("Boosts And Dispensers"), "Spot", Core.BoostSpots, "Teleport")
end

----------------------------------------------------------------------------
-- Items
----------------------------------------------------------------------------

do
    local page = Window.CreatePage({ Page_Name = "Items", Page_Title = "Items" })

    local now = page.CreateSubTab("Use Now")
    local sets = now.CreateSection("Buff Sets")
    btn(sets, "Use All Blue Buffs", function()
        Core.UseItems(Core.BlueBuffs)
    end, "Use")
    btn(sets, "Use All Red Buffs", function()
        Core.UseItems(Core.RedBuffs)
    end, "Use")
    btn(sets, "Use All Buffs", function()
        Core.UseItems(Core.AllBuffs)
    end, "Use")
    sets.CreateLabel({ Title = "Blue is Blue Extract, Glitter, Glue, Oil, Enzymes and Tropical Drink. Red swaps Blue Extract for Red Extract. All Buffs is every one of them, but no potions and no Marshmallow Bee." })

    local single = now.CreateSection("Single Items")
    for _, name in ipairs(Core.Items) do
        btn(single, "Use " .. name, function()
            Core.UseItem(name)
        end, "Use")
    end

    local dispensers = now.CreateSection("Dispensers")
    btn(dispensers, "Use All Dispensers", function()
        Core.UseAllDispensers()
    end, "Use")
    local dispenser = Core.Dispensers[1]
    pick(dispensers, "Dispenser", Core.Dispensers, dispenser, function(name)
        dispenser = name
    end)
    btn(dispensers, "Use Selected Dispenser", function()
        Core.UseDispenser(dispenser)
    end, "Use")
    dispensers.CreateLabel({ Title = "Honey, Treat, Blueberry, Strawberry, Coconut and Glue dispensers, the Free Ant Pass and Free Royal Jelly dispensers, and the Wealth Clock." })

    local dice = now.CreateSection("Dice")
    for _, name in ipairs(Core.Dice) do
        btn(dice, "Use " .. name, function()
            Core.UseItem(name)
        end, "Use")
    end

    local boosters = now.CreateSection("Boosters")
    btn(boosters, "Use All Boosters", function()
        Core.UseAllBoosters()
    end, "Use")
    for _, name in ipairs(Core.Boosters) do
        btn(boosters, "Use " .. name, function()
            Core.UseDispenser(name)
        end, "Use")
    end

    local masks = now.CreateSection("Masks")
    local mask = Core.Masks[1]
    pick(masks, "Mask", Core.Masks, mask, function(name)
        mask = name
    end)
    btn(masks, "Equip Selected Mask", function()
        local ok = Core.EquipMask(mask)
        notify("Mask", ok and ("Asked the game to put on the " .. mask .. ".") or "The game would not take that.")
    end, "Equip")

    local auto = page.CreateSubTab("Auto Use")
    local autoDispensers = auto.CreateSection("Auto Dispensers")
    tog(autoDispensers, "All Dispensers", "AutoAllDispensers", "Uses every dispenser again every 10 seconds.")
    for _, name in ipairs(Core.Dispensers) do
        tog(autoDispensers, name, Core.AutoKey(name), "Uses it again every 10 seconds.")
    end
    local autoDice = auto.CreateSection("Auto Dice")
    for _, name in ipairs(Core.Dice) do
        tog(autoDice, name, Core.AutoKey(name), "Rolls it again every 3 seconds.")
    end
    local autoBoosters = auto.CreateSection("Auto Boosters")
    tog(autoBoosters, "All Field Boosters", "AutoAllBoosters", "Uses all three boosters again every 5 seconds.")
    for _, name in ipairs(Core.Boosters) do
        tog(autoBoosters, name, Core.AutoKey(name), "Uses it again every 5 seconds.")
    end
    local autoOther = auto.CreateSection("Auto Converters And Treats")
    tog(autoOther, "Micro-Converter", "AutoMicroConverter", "Uses a Micro-Converter whenever your bag is full.")
    tog(autoOther, "Instant Converter", "AutoInstantConverter", "Uses the three Instant Converters whenever your bag is full.")
    tog(autoOther, "Coconut", "AutoCoconut", "Eats a Coconut every 11 seconds.")
    tog(autoOther, "Gumdrops", "AutoGumdrops", "Uses Gumdrops every 3 seconds.")
end

----------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------

do
    local page = Window.CreatePage({ Page_Name = "Settings", Page_Title = "Settings" })

    local options = page.CreateSubTab("Options")
    local walking = options.CreateSection("Walking")
    num(walking, "Walk Speed", "WalkSpeed", 16, 150)
    tog(walking, "Keep Walk Speed", "KeepWalkSpeed", "Keeps your walk speed at the slider value, also while Auto Farm runs.")
    num(walking, "Jump Power", "JumpPower", 1, 200)
    tog(walking, "Keep Jump Power", "KeepJumpPower", "Keeps your jump power at the slider value.")
    local travel = options.CreateSection("Travel")
    num(travel, "Travel Speed", "TravelSpeed", 40, 150)
    travel.CreateLabel({ Title = "How fast you glide to your field, hive and other places. Lower is slower but looks more natural." })
    local extras = options.CreateSection("Extras")
    tog(extras, "Walk Through Walls", "Noclip", "Lets your character pass through walls and objects.")
    tog(extras, "Walk Through Field Decorations", "WalkThroughDecorations", "Makes field trees and decorations see-through so you can walk through them.")
    tog(extras, "Anti-AFK", "AntiAfk", "Stops the game from kicking you for standing still.")
    tog(extras, "Go To Hive When Loaded", "GoToHiveOnLoad", "Flies you to your hive when the script starts, as Kron's hub does.")

    UILibrary.AddConfigSection(page.CreateSubTab("Config"))

    local utility = page.CreateSubTab("Utility").CreateSection("Utility")
    btn(utility, "Stop All Features", function()
        Core.StopFeatures()
        notify("Stopped", "Auto Farm, Auto Dig, training, hovering, Auto Use, Walk Through Walls and the speed switches are off.")
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
