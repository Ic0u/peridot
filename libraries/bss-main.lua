-- Peridot Bee Swarm Simulator core: Kron's hub plus the extra features of Verbal Hub Sigma BSS,
-- rewritten as readable code. Both copies came out of a decompiler that lost variable names and some
-- branches, so the loops follow what those scripts visibly did (the remotes they fired, their numbers
-- and positions) and how the game's own values work (CoreStats, Honeycombs). Where the two scripts do
-- the same thing, what they agree on is what is used.
-- The interface is games/1537690962.lua; this file only holds the features.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local Core = {}

----------------------------------------------------------------------------
-- Places, items and numbers taken from the scripts
----------------------------------------------------------------------------

-- The spot Kron's script stands on while it farms each field, in the order of its list.
Core.Fields = {
    { name = "Sunflower Field", position = Vector3.new(-216.623, 4.447, 177.560) },
    { name = "Dandelion Field", position = Vector3.new(-34.255, 4.447, 220.865) },
    { name = "Mushroom Field", position = Vector3.new(-97.479, 4.447, 118.509) },
    { name = "Blue Flower Field", position = Vector3.new(148.401, 4.447, 101.386) },
    { name = "Clover Field", position = Vector3.new(154.981, 33.947, 194.575) },
    { name = "Spider Field", position = Vector3.new(-45.043, 20.447, -5.353) },
    { name = "Strawberry Field", position = Vector3.new(-179.034, 20.447, -5.379) },
    { name = "Bamboo Field", position = Vector3.new(132.040, 20.447, -26.614) },
    { name = "Pineapple Patch", position = Vector3.new(251.383, 68.447, -207.936) },
    { name = "Stump Field", position = Vector3.new(420.141, 96.426, -174.963) },
    { name = "Pumpkin Patch", position = Vector3.new(-201.859, 68.447, -184.800) },
    { name = "Cactus Field", position = Vector3.new(-193.710, 68.447, -105.528) },
    { name = "Rose Field", position = Vector3.new(-326.427, 20.397, 126.576) },
    { name = "Pine Tree Forest", position = Vector3.new(-327.461, 68.447, -183.504) },
    { name = "Mountain Top Field", position = Vector3.new(76.492, 176.447, -164.651) },
    { name = "Coconut Field", position = Vector3.new(-262.409, 71.897, 466.452) },
    { name = "Pepper Patch", position = Vector3.new(-488.424, 123.649, 535.532) },
}

-- Verbal Hub's teleport lists.
Core.Shops = {
    { name = "Bee Shop", position = Vector3.new(-136.8, 4.6, 243.4) },
    { name = "First Tool Shop", position = Vector3.new(86, 4.6, 294) },
    { name = "Second Tool Shop (15+ bees)", position = Vector3.new(165, 69, -161) },
    { name = "Mountain Top Shop (25+ bees)", position = Vector3.new(-18, 176, -137) },
    { name = "Spirit Shop (35+ bees)", position = Vector3.new(-501, 52, 474) },
    { name = "Dapper Bear's Shop", position = Vector3.new(456.7, 137.9, -313.8) },
    { name = "Gumball Shop", position = Vector3.new(269, 25257.55, -724.2) },
    { name = "Blue Clubhouse", position = Vector3.new(292, 4, 98) },
    { name = "Red Clubhouse", position = Vector3.new(-334, 21, 216) },
    { name = "Ticket Shop", position = Vector3.new(-12.8, 184, -222.2) },
    { name = "Royal Jelly Shop", position = Vector3.new(-297, 53, 68) },
    { name = "Ticket Royal Jelly Shop", position = Vector3.new(81, 18, 240) },
    { name = "Treat Shop", position = Vector3.new(-228.2, 5, 89.4) },
    { name = "Moon", position = Vector3.new(21, 88, -54) },
    { name = "Nuoc", position = Vector3.new(-426, 70, 38) },
}
Core.Bears = {
    { name = "Black Bear", position = Vector3.new(-258.1, 5, 299.7) },
    { name = "Brown Bear", position = Vector3.new(282, 46, 236) },
    { name = "Panda Bear", position = Vector3.new(106.3, 35, 50.1) },
    { name = "Polar Bear", position = Vector3.new(-106, 119, -77) },
    { name = "Science Bear", position = Vector3.new(267, 103, 20) },
    { name = "Mother Bear", position = Vector3.new(-183.898, 5.641, 83.458) },
    { name = "Spirit Bear", position = Vector3.new(-363.936, 105.284, 485.853) },
    { name = "Gummy Bear", position = Vector3.new(271.624, 25292.9, -850.958) },
    { name = "Tunnel Bear", position = Vector3.new(313.654, 6.812, -46.913) },
    { name = "Onett", position = Vector3.new(-9.416, 232.791, -520.278) },
    { name = "Stick Bug", position = Vector3.new(-129.2, 50.071, 148.288) },
}
Core.BoostSpots = {
    { name = "Ant", position = Vector3.new(125, 32, 495) },
    { name = "Blue Field", position = Vector3.new(113.7, 4, 101.5) },
    { name = "Blue Field Boost", position = Vector3.new(272, 58, 86) },
    { name = "Blueberry Dispenser", position = Vector3.new(307, 5, 134) },
    { name = "Club Honey", position = Vector3.new(44.8, 5, 319.6) },
    { name = "Gumdrop Dispenser", position = Vector3.new(68, 21.8, 26) },
    { name = "Glue Dispenser", position = Vector3.new(269, 25257.547, -724) },
    { name = "Honeystorm Dispenser", position = Vector3.new(238.4, 33.3, 165.6) },
    { name = "Instant Honey Converter", position = Vector3.new(282, 68, -62) },
    { name = "Mountain Top Boost", position = Vector3.new(-40, 176, -191.7) },
    { name = "Nectar Condenser", position = Vector3.new(-416.7, 101.5, 342.8) },
    { name = "Red Field Boost", position = Vector3.new(-315.5, 21, 240) },
    { name = "Sprout Dispenser", position = Vector3.new(-269.26, 26.56, 267.31) },
    { name = "Star Hut", position = Vector3.new(135.9, 64.6, 322.1) },
    { name = "Strawberry Dispenser", position = Vector3.new(-320.5, 46, 272.5) },
    { name = "Treat Dispenser", position = Vector3.new(193.9, 68, -123) },
}
-- The event's gifts. The source listed one more "Gift 3" at a spot that is also the First Tool Shop; it is left out.
Core.Gifts = {
    { name = "Gift 3", position = Vector3.new(39, 5, 99) },
    { name = "Gift 4", position = Vector3.new(-277, 18, 386.8) },
    { name = "Gift 6", position = Vector3.new(-449, 69, -97.5) },
    { name = "Gift 8", position = Vector3.new(327.6, 195, -229.5) },
    { name = "Gift 9", position = Vector3.new(-55.7, 41.5, 719.8) },
    { name = "Gift 10", position = Vector3.new(-421.7, 72.8, 437.6) },
    { name = "Gift 11", position = Vector3.new(-453, 122.8, 336.5) },
    { name = "Gift 13", position = Vector3.new(488, 180, -329) },
    { name = "Gift 14", position = Vector3.new(33.4, 235.8, -581.9) },
    { name = "Gift 16", position = Vector3.new(-19.8, 231.5, -121.3) },
}
Core.BeeBear = Vector3.new(-38.667, 6.391, 283.181)

-- Invisible platforms you stand on. `steps` are the points the script teleported to, in order.
local PLATFORMS = {
    TrainCrab = { name = "combatcrabpart", transparency = 1, size = Vector3.new(90, 1, 90), at = Vector3.new(-257.521, 105.919, 457.868) },
    FightCrab = { name = "Coconut Part", transparency = 0.5, size = Vector3.new(6, 1, 6), at = Vector3.new(-307.521, 105.919, 467.868) },
    CommandoChick = {
        name = "Commando Part", transparency = 1, size = Vector3.new(10, 1, 10), at = Vector3.new(532.56, 68.198, 162.801),
        steps = { Vector3.new(532.56, 68.198, 162.801) },
    },
    StumpSnail = {
        name = "Snail Part", transparency = 1, size = Vector3.new(10, 1, 10), at = Vector3.new(424.483, 71.426, -174.811),
        steps = { Vector3.new(424.483, 68.426, -174.811), Vector3.new(424.483, 74.426, -174.811) },
    },
    TunnelBear = {
        name = "Tunnel Part", transparency = 1, size = Vector3.new(10, 1, 10), at = Vector3.new(469.095, 23.267, -46.392),
        steps = { Vector3.new(469.095, 7.267, -46.392), Vector3.new(469.095, 24.267, -46.392) },
    },
}
local CRAB_HEIGHT = 4.7 -- how far above the Train Crab platform you stand
local FIGHT_CRAB_SPOT = Vector3.new(-307.521, 110.919, 467.868)
local SNAIL_SPOT = Vector3.new(422.657, 96.426, -175.720) -- beside the Stump Field snail

local FIELD_RADIUS = 65 -- farther than this from the field's spot and Auto Farm flies back to it
local HIVE_RADIUS = 10 -- how close to the hive's pad honey making needs you
local TOKEN_RANGE = 50
local BUBBLE_RANGE = 60
local BALLOON_FIELD_RANGE = 40 -- a field balloon this close is farmed around
local BALLOON_CIRCLE = 10 -- and you stay inside this circle around it
local SNAIL_RANGE = 30
local CRAB_RANGE = 60
local BALLOON_RANGE = 25
local BALLOON_WAIT = 15 -- seconds; Kron's script waited without a limit
local HIVE_TIMEOUT = 600 -- seconds; a conversion that takes longer is given up on
local FAR_TELEPORT = 3000 -- a destination this far away is always an instant jump

Core.BlueBuffs = { "Blue Extract", "Glitter", "Glue", "Oil", "Enzymes", "Tropical Drink" }
Core.RedBuffs = { "Red Extract", "Glitter", "Glue", "Oil", "Enzymes", "Tropical Drink" }
Core.AllBuffs = { "Blue Extract", "Red Extract", "Glitter", "Glue", "Oil", "Enzymes", "Tropical Drink" } -- no potions, no Marshmallow Bee
Core.Items = {
    "Blue Extract", "Red Extract", "Glitter", "Glue", "Oil", "Enzymes", "Tropical Drink",
    "Purple Potion", "Super Smoothie", "Marshmallow Bee",
}
Core.Dispensers = {
    "Glue Dispenser", "Wealth Clock", "Coconut Dispenser", "Strawberry Dispenser", "Treat Dispenser",
    "Free Ant Pass Dispenser", "Blueberry Dispenser", "Honey Dispenser", "Free Royal Jelly Dispenser",
}
Core.Dice = { "Field Dice", "Smooth Dice", "Loaded Dice" }
Core.Boosters = { "Red Field Booster", "Blue Field Booster", "Field Booster" }
Core.Masks = { "Gummy Mask", "Demon Mask", "Diamond Mask", "Bubble Mask", "Fire Mask", "Honey Mask" }
Core.InstantConverters = { "Instant Converter", "Instant Converter B", "Instant Converter C" }

----------------------------------------------------------------------------
-- Settings. The interface writes them with Core.Set.
----------------------------------------------------------------------------

Core.Settings = {
    Field = Core.Fields[1].name,
    AutoFarm = false,
    AutoDig = false,
    MoveStyle = "Walk", -- how Auto Farm gets to what it picks up: Walk, Glide or Fast Glide
    CollectTokens = true,
    CollectBubbles = false,
    CollectFlames = false,
    CollectStars = false,
    CollectBalloons = false,
    GoHomeWhenFull = true,
    GoHomePercent = 100,
    PlaceSprinkler = false,
    ConvertBalloons = false,
    TrainSnail = false,
    TrainCrab = false,
    FightCrab = false,
    CollectSnowflakes = false,
    FollowMondo = false,
    HoverWindy = false,
    HoverVicious = false,
    KeepWalkSpeed = false,
    WalkSpeed = 16,
    KeepJumpPower = false,
    JumpPower = 50,
    Noclip = false,
    TravelSpeed = 80, -- studs per second when gliding between places
    TeleportStyle = "Glide", -- Glide or Instant, for the Teleport page
    StayOnFeet = true,
    WalkThroughDecorations = true,
    AntiAfk = true,
    GoToHiveOnLoad = true, -- Kron's script flew you to your hive as soon as it loaded
}

-- Settings with a fixed list of values.
local ALLOWED = {
    MoveStyle = { Walk = true, Glide = true, ["Fast Glide"] = true },
    TeleportStyle = { Glide = true, Instant = true },
}

-- Only one of these can move you at a time.
local MOVERS = {
    "AutoFarm", "TrainSnail", "TrainCrab", "FightCrab", "CollectSnowflakes", "FollowMondo", "HoverWindy", "HoverVicious",
}
local function isMover(name)
    for _, mover in ipairs(MOVERS) do
        if mover == name then
            return true
        end
    end
    return false
end

Core.Farm = { phase = "field", pressed = false, sprinklerDue = true, hiveSince = 0 }
Core.Notify = function() end -- the interface replaces these two
Core.OnChange = nil -- called as (name, value) when the core flips a setting by itself
Core.Clock = os.clock
Core.Time = os.time

local alive = false
local connections = {}
local lastWarned = {}

function Core.Warn(label, err)
    local now = Core.Clock()
    if (lastWarned[label] or -100) + 10 < now then
        lastWarned[label] = now
        warn("[Peridot] Bee Swarm " .. label .. ": " .. tostring(err))
    end
end

-- A notification that is not repeated within `every` seconds.
local saidAt = {}
function Core.Say(key, title, text, every)
    local now = Core.Clock()
    if (saidAt[key] or -1000) + (every or 30) < now then
        saidAt[key] = now
        Core.Notify(title, text)
    end
end

----------------------------------------------------------------------------
-- Looking things up
----------------------------------------------------------------------------

local function rootPart()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function humanoid()
    local character = LocalPlayer.Character
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function readStats()
    local stats = LocalPlayer:FindFirstChild("CoreStats")
    local pollen = stats and stats:FindFirstChild("Pollen")
    local capacity = stats and stats:FindFirstChild("Capacity")
    return pollen and pollen.Value or 0, capacity and capacity.Value or 0
end

-- The text on the button at the bottom of the screen ("Make Honey" while you are not making any).
local function activateText()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    local screen = gui and gui:FindFirstChild("ScreenGui")
    local button = screen and screen:FindFirstChild("ActivateButton")
    local box = button and button:FindFirstChild("TextBox")
    return box and box.Text or ""
end

local function events()
    return ReplicatedStorage:FindFirstChild("Events")
end

local function fire(name, ...)
    local folder = events()
    local remote = folder and folder:FindFirstChild(name)
    if not remote then
        return false, name .. " is not in this game"
    end
    return pcall(remote.FireServer, remote, ...)
end

local function invoke(name, ...)
    local folder = events()
    local remote = folder and folder:FindFirstChild(name)
    if not remote then
        return false, name .. " is not in this game"
    end
    return pcall(remote.InvokeServer, remote, ...)
end

local function positionOf(item)
    if item:IsA("BasePart") then
        return item.Position
    end
    if item:IsA("Model") then
        local ok, pivot = pcall(item.GetPivot, item)
        if ok and pivot then
            return pivot.Position
        end
    end
    return nil
end

local function findNamed(list, name)
    for _, entry in ipairs(list) do
        if entry.name == name then
            return entry
        end
    end
    return nil
end

function Core.FindField(name)
    return findNamed(Core.Fields, name) or Core.Fields[1]
end

local function namesOf(list)
    local names = {}
    for _, entry in ipairs(list) do
        names[#names + 1] = entry.name
    end
    return names
end

Core.Names = namesOf -- the names in a list of { name, position }

function Core.FieldNames()
    return namesOf(Core.Fields)
end

-- The nearest part of `container` within `range` of `from` that `accept` likes.
local function nearest(container, from, range, accept)
    local best, bestDistance
    for _, item in ipairs(container:GetDescendants()) do
        if item:IsA("BasePart") and accept(item) then
            local distance = (from - item.Position).Magnitude
            if distance <= range and (not bestDistance or distance < bestDistance) then
                best, bestDistance = item, distance
            end
        end
    end
    return best
end

----------------------------------------------------------------------------
-- Moving
----------------------------------------------------------------------------

-- Glides your root part to a point in a straight line over `seconds`.
local function glide(root, position, seconds)
    local tween = TweenService:Create(root, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { CFrame = CFrame.new(position) })
    local finished = false
    tween.Completed:Connect(function()
        finished = true
    end)
    tween:Play()
    local waited = 0
    while not finished and waited < seconds + 2 do -- the limit keeps a cancelled tween from hanging a loop
        task.wait(0.05)
        waited = waited + 0.05
    end
end

-- Glides your character to a point at Settings.TravelSpeed.
function Core.TeleportTo(position)
    local root = rootPart()
    if not root then
        return false
    end
    glide(root, position, math.max((root.Position - position).Magnitude / Core.Settings.TravelSpeed, 0.1))
    return true
end

-- Puts your character at a point at once.
function Core.JumpTo(position)
    local root = rootPart()
    if not root then
        return false
    end
    root.CFrame = CFrame.new(position)
    return true
end

-- What the Teleport page uses: Settings.TeleportStyle, and always an instant jump to somewhere very far.
function Core.GoTo(position)
    local root = rootPart()
    if not root then
        return false
    end
    if Core.Settings.TeleportStyle == "Instant" or (root.Position - position).Magnitude > FAR_TELEPORT then
        return Core.JumpTo(position)
    end
    return Core.TeleportTo(position)
end

function Core.TeleportToField(name)
    return Core.GoTo(Core.FindField(name).position)
end

-- Goes to a place from one of the lists (Shops, Bears, BoostSpots, Gifts).
function Core.GoToPlace(list, name)
    local place = findNamed(list, name)
    if not place then
        return false
    end
    return Core.GoTo(place.position)
end

function Core.GoToBeeBear()
    return Core.GoTo(Core.BeeBear)
end

-- One step toward something Auto Farm wants to pick up, the way Settings.MoveStyle says.
function Core.MoveToward(position)
    local root, hum = rootPart(), humanoid()
    if not (root and hum) then
        return false
    end
    local style = Core.Settings.MoveStyle
    if style == "Walk" then
        hum:MoveTo(position)
        return "walk"
    end
    glide(root, Vector3.new(position.X, root.Position.Y, position.Z), style == "Fast Glide" and 0.1 or 0.4)
    return "glide"
end

----------------------------------------------------------------------------
-- Your hive
----------------------------------------------------------------------------

local function hives()
    local container = Workspace:FindFirstChild("Honeycombs")
    return container and container:GetChildren() or {}
end

-- Your hive: the one whose Owner is you (Kron's script), or the one your Honeycomb value points to (Verbal Hub's).
function Core.FindHive()
    for _, hive in ipairs(hives()) do
        local owner = hive:FindFirstChild("Owner")
        if owner and owner.Value == LocalPlayer then
            return hive
        end
    end
    local mine = LocalPlayer:FindFirstChild("Honeycomb")
    if mine and mine.Value then
        return mine.Value
    end
    return nil
end

-- Where to stand to make honey: the hive's pad one stud up (Kron's script), else in front of its
-- light (Verbal Hub's), else where you spawn (Verbal Hub's Teleport To Hive).
function Core.HivePosition()
    local hive = Core.FindHive()
    local arrow = hive and hive:FindFirstChild("patharrow")
    local base = arrow and arrow:FindFirstChild("Base")
    if base then
        return base.Position + Vector3.new(0, 1, 0)
    end
    local light = hive and hive:FindFirstChild("LightHolder")
    if light then
        return (light.CFrame * CFrame.new(0, 5, -5)).Position
    end
    local spawnPoint = hive and LocalPlayer:FindFirstChild("SpawnPos")
    if spawnPoint and spawnPoint.Value then
        return spawnPoint.Value.Position
    end
    return nil
end

-- True once you own a hive: yours already, or the first free one that accepts the claim.
function Core.ClaimHive()
    if Core.FindHive() then
        return true
    end
    for _, hive in ipairs(hives()) do
        local owner, id = hive:FindFirstChild("Owner"), hive:FindFirstChild("HiveID")
        if owner and id and owner.Value == nil then
            fire("ClaimHive", id.Value)
            for _ = 1, 20 do
                task.wait(0.15)
                if Core.FindHive() then
                    return true
                end
            end
        end
    end
    return false
end

function Core.TeleportToHive()
    local position = Core.HivePosition()
    if not position then
        if not Core.ClaimHive() then
            return false, "You do not have a hive yet and none is free."
        end
        position = Core.HivePosition()
    end
    if not position then
        return false, "Your hive's pad could not be found."
    end
    return Core.GoTo(position)
end

-- Starts or stops turning your pollen into honey (the same button as standing on the pad).
function Core.MakeHoney()
    return fire("PlayerHiveCommand", "ToggleHoneyMaking")
end

----------------------------------------------------------------------------
-- Items, dispensers, masks, stickers and codes
----------------------------------------------------------------------------

function Core.UseItem(name)
    return fire("PlayerActivesCommand", { Name = name })
end

function Core.UseItems(list)
    for _, name in ipairs(list) do
        Core.UseItem(name)
        task.wait(0.01)
    end
end

function Core.UseDispenser(name)
    return fire("ToyEvent", name)
end

function Core.UseAllDispensers()
    for _, name in ipairs(Core.Dispensers) do
        Core.UseDispenser(name)
        task.wait(0.01)
    end
end

function Core.UseAllBoosters()
    for _, name in ipairs(Core.Boosters) do
        Core.UseDispenser(name) -- boosters are toys too
    end
end

function Core.PlaceSprinkler()
    task.wait(0.5)
    local hum = humanoid()
    if hum then
        hum.Jump = true
    end
    Core.UseItem("Sprinkler Builder")
    task.wait(0.5)
end

function Core.EquipMask(name)
    if not table.find(Core.Masks, name) then
        return false, "Unknown mask"
    end
    return invoke("ItemPackageEvent", "Equip", { Mute = true, Type = name, Category = "Accessory" })
end

-- Clicks every hidden sticker. The game limits them to once a day, so a second try in the same
-- day is refused here too. Returns the number clicked, or nil and why not.
function Core.FindStickers()
    local now = Core.Time()
    if Core.StickersAt and now - Core.StickersAt < 86400 then
        return nil, "You already collected your stickers today. Try again tomorrow."
    end
    local folder = Workspace:FindFirstChild("HiddenStickers")
    if not folder then
        return nil, "There are no hidden stickers in this game."
    end
    if type(fireclickdetector) ~= "function" then
        return nil, "Your executor cannot click things, so stickers cannot be collected."
    end
    local count = 0
    for _, item in ipairs(folder:GetDescendants()) do
        if item:IsA("ClickDetector") then
            pcall(fireclickdetector, item)
            count = count + 1
        end
    end
    if count > 0 then
        Core.StickersAt = now
    end
    return count
end

-- Sends promo codes, one a second, the way Verbal Hub did. Codes are separated by spaces or commas.
function Core.RedeemCodes(text)
    local count = 0
    for code in tostring(text or ""):gmatch("[^%s,;]+") do
        fire("PromoCodeEvent", code)
        count = count + 1
        task.wait(1)
    end
    return count
end

-- Stays by your hive balloon for a little while, so a balloon that is still there gets used up.
function Core.WaitForBalloon()
    local balloons = Workspace:FindFirstChild("Balloons")
    local folder = balloons and balloons:FindFirstChild("HiveBalloons")
    local root = rootPart()
    if not (folder and root) then
        return false
    end
    local target, best = nil, BALLOON_RANGE
    for _, balloon in ipairs(folder:GetChildren()) do
        local body = balloon.Name == "HiveBalloonInstance" and balloon:FindFirstChild("BalloonBody")
        if body then
            local distance = (body.Position - root.Position).Magnitude
            if distance <= best then
                target, best = balloon, distance
            end
        end
    end
    if not target then
        return false
    end
    local waited = 0
    while target.Parent and waited < BALLOON_WAIT and alive and Core.Settings.AutoFarm do
        task.wait(0.5)
        waited = waited + 0.5
    end
    return true
end

----------------------------------------------------------------------------
-- Auto Use: things used again and again while their switch is on
----------------------------------------------------------------------------

Core.AutoUses = {} -- { key, title, every, run }
local autoByKey = {}
local nextRun = {}

local function addAuto(key, title, every, run)
    local entry = { key = key, title = title, every = every, run = run }
    Core.AutoUses[#Core.AutoUses + 1] = entry
    autoByKey[key] = entry
    Core.Settings[key] = false
    return entry
end
local function keyFor(prefix, name)
    return prefix .. name:gsub("[^%w]", "")
end
function Core.AutoKey(name) -- the setting behind "Auto use <name>"
    return keyFor("Auto", name)
end

local function bagIsFull()
    local pollen, capacity = readStats()
    return capacity > 0 and pollen >= capacity
end

addAuto("AutoAllDispensers", "All Dispensers", 10, function() Core.UseAllDispensers() end)
for _, name in ipairs(Core.Dispensers) do
    addAuto(keyFor("Auto", name), name, 10, function() Core.UseDispenser(name) end)
end
for _, name in ipairs(Core.Dice) do
    addAuto(keyFor("Auto", name), name, 3, function() Core.UseItem(name) end)
end
addAuto("AutoAllBoosters", "All Field Boosters", 5, function() Core.UseAllBoosters() end)
for _, name in ipairs(Core.Boosters) do
    addAuto(keyFor("Auto", name), name, 5, function() Core.UseDispenser(name) end)
end
addAuto("AutoMicroConverter", "Micro-Converter", 1, function()
    if bagIsFull() then
        Core.UseItem("Micro-Converter")
    end
end)
addAuto("AutoInstantConverter", "Instant Converter", 1, function()
    if bagIsFull() then
        for _, name in ipairs(Core.InstantConverters) do
            Core.UseDispenser(name)
            task.wait(0.3)
        end
    end
end)
addAuto("AutoCoconut", "Coconut", 11, function() Core.UseItem("Coconut") end)
addAuto("AutoGumdrops", "Gumdrops", 3, function() Core.UseItem("Gumdrops") end)

-- What Stop All Features turns off. The options that only change how Auto Farm works, and the
-- protections, stay as they were set.
Core.ActionSettings = {
    "AutoFarm", "AutoDig", "TrainSnail", "TrainCrab", "FightCrab", "CollectSnowflakes", "FollowMondo",
    "HoverWindy", "HoverVicious", "KeepWalkSpeed", "KeepJumpPower", "Noclip",
}
for _, entry in ipairs(Core.AutoUses) do
    Core.ActionSettings[#Core.ActionSettings + 1] = entry.key
end

function Core.AutoUseStep()
    local now = Core.Clock()
    local ran = 0
    for _, entry in ipairs(Core.AutoUses) do
        if Core.Settings[entry.key] and (nextRun[entry.key] or 0) <= now then
            nextRun[entry.key] = now + entry.every
            local ok, err = pcall(entry.run)
            if not ok then
                Core.Warn(entry.title, err)
            end
            ran = ran + 1
        end
    end
    return ran
end

----------------------------------------------------------------------------
-- Platforms you stand on
----------------------------------------------------------------------------

local platforms = {} -- key -> part

local function ensurePlatform(key)
    local existing = platforms[key]
    if existing and existing.Parent then
        return existing
    end
    local spec = PLATFORMS[key]
    local part = Instance.new("Part")
    part.Name = spec.name
    part.Anchored = true
    part.Transparency = spec.transparency
    part.Size = spec.size
    part.Position = spec.at
    part.CanCollide = true
    part.Parent = Workspace
    platforms[key] = part
    return part
end

local function removePlatform(key)
    if platforms[key] then
        platforms[key]:Destroy()
        platforms[key] = nil
    end
end

function Core.GetPlatform(key)
    return platforms[key]
end

function Core.GetCrabPlatform()
    return platforms.TrainCrab
end

-- Puts you on a platform by a monster: a Commando Chick, the Stump Snail or the Tunnel Bear.
function Core.StandAt(key)
    local spec = PLATFORMS[key]
    if not (spec and spec.steps) then
        return false
    end
    ensurePlatform(key)
    for index, position in ipairs(spec.steps) do
        if index > 1 then
            task.wait(0.1)
        end
        if not Core.JumpTo(position) then
            return false
        end
    end
    return true
end

----------------------------------------------------------------------------
-- The loops. Each does one pass per call, so they can be driven one step at a time.
----------------------------------------------------------------------------

local function switchOff(name)
    if Core.Settings[name] == true then
        Core.Set(name, false)
        if Core.OnChange then
            pcall(Core.OnChange, name, false)
        end
    end
end

-- Auto Farm: farm the field; when the bag is full, go to the hive, make honey until the pollen is
-- gone, then fly back to the field.
function Core.FarmStep()
    local settings, farm = Core.Settings, Core.Farm
    if not settings.AutoFarm then
        return "off"
    end
    local root = rootPart()
    if not root then
        return "no character"
    end
    local pollen, capacity = readStats()

    if farm.phase == "field" then
        local full = capacity * math.max(1, math.min(100, settings.GoHomePercent)) / 100
        if settings.GoHomeWhenFull and capacity > 0 and pollen >= full then
            farm.phase, farm.pressed, farm.hiveSince = "hive", false, Core.Clock()
            return "bag full"
        end
        local field = Core.FindField(settings.Field)
        if (root.Position - field.position).Magnitude > FIELD_RADIUS then
            Core.TeleportTo(field.position)
            return "to field"
        end
        if farm.sprinklerDue then
            farm.sprinklerDue = false
            if settings.PlaceSprinkler then
                Core.PlaceSprinkler()
                return "sprinkler"
            end
        end
        return "farming"
    end

    local hive = Core.HivePosition()
    if not hive then
        if not Core.ClaimHive() then
            Core.Notify("Auto Farm", "You do not have a hive and none is free, so Auto Farm stopped.")
            switchOff("AutoFarm")
        end
        return "no hive"
    end
    local moved = false
    if (root.Position - hive).Magnitude > HIVE_RADIUS then
        Core.TeleportTo(hive)
        task.wait(1)
        moved = true
    end
    if not farm.pressed and pollen > 0 then
        Core.MakeHoney()
        farm.pressed = true
        return "making honey"
    end
    if moved and farm.pressed and activateText() == "Make Honey" then
        Core.MakeHoney() -- the walk back left it switched off
    end
    if pollen > 0 and Core.Clock() - farm.hiveSince < HIVE_TIMEOUT then
        return "converting"
    end
    if settings.ConvertBalloons then
        Core.WaitForBalloon()
    end
    farm.phase, farm.sprinklerDue = "field", true
    return "back to field"
end

-- Swings your tool.
function Core.DigStep()
    if Core.Settings.AutoDig then
        fire("ToolCollect")
        return "dig"
    end
    return "off"
end

-- The field balloon nearest to `from`, if one is within reach.
local function fieldBalloonBody(from)
    local balloons = Workspace:FindFirstChild("Balloons")
    local folder = balloons and balloons:FindFirstChild("FieldBalloons")
    if not folder then
        return nil
    end
    local best, bestDistance
    for _, balloon in ipairs(folder:GetChildren()) do
        local body = balloon:FindFirstChild("BalloonBody")
        if body then
            local distance = (body.Position - from).Magnitude
            if distance <= BALLOON_FIELD_RANGE and (not bestDistance or distance < bestDistance) then
                best, bestDistance = body, distance
            end
        end
    end
    return best
end

-- While farming a field, goes for flames, then bubbles, stars, a field balloon, then tokens.
function Core.TokenStep()
    local settings = Core.Settings
    if not (settings.AutoFarm and Core.Farm.phase == "field") then
        return "off"
    end
    if not (settings.CollectTokens or settings.CollectBubbles or settings.CollectFlames or settings.CollectStars or settings.CollectBalloons) then
        return "off"
    end
    local root, hum = rootPart(), humanoid()
    if not (root and hum) then
        return "no character"
    end
    local field = Core.FindField(settings.Field)
    local function inField(part)
        return (part.Position - field.position).Magnitude <= FIELD_RADIUS
    end

    if settings.CollectFlames then
        local flames = Workspace:FindFirstChild("PlayerFlames")
        local flame = flames and nearest(flames, root.Position, math.huge, inField)
        if flame then
            Core.MoveToward(flame.Position)
            return "flame"
        end
    end
    local particles = Workspace:FindFirstChild("Particles")
    if settings.CollectBubbles then
        local bubble = particles and nearest(particles, root.Position, BUBBLE_RANGE, function(part)
            return part.Name == "Bubble"
        end)
        if bubble then
            Core.MoveToward(bubble.Position)
            return "bubble"
        end
    end
    if settings.CollectStars then
        local star = particles and nearest(particles, root.Position, math.huge, function(part)
            return part.Name == "Star" and inField(part)
        end)
        if star then
            Core.MoveToward(star.Position)
            return "star"
        end
    end
    local tokens = Workspace:FindFirstChild("Collectibles")
    if settings.CollectBalloons then
        local body = fieldBalloonBody(root.Position)
        if body then
            local center = body.Position
            local token = tokens and nearest(tokens, center, BALLOON_CIRCLE, function(part)
                return part.Transparency == 0
            end)
            if token then
                Core.MoveToward(token.Position)
            else -- nothing to pick up: wander inside the balloon's circle
                local angle, radius = math.random() * math.pi * 2, math.random() * BALLOON_CIRCLE
                Core.MoveToward(Vector3.new(center.X + math.cos(angle) * radius, root.Position.Y, center.Z + math.sin(angle) * radius))
            end
            return "balloon"
        end
    end
    if settings.CollectTokens then
        local token = tokens and nearest(tokens, root.Position, TOKEN_RANGE, function(part)
            return (part.Position - field.position).Magnitude <= FIELD_RADIUS + 10 -- never chase one out of the field
        end)
        if token then
            Core.MoveToward(token.Position)
            return "token"
        end
    end
    return "none"
end

function Core.SnailStep()
    if not Core.Settings.TrainSnail then
        return "off"
    end
    local root = rootPart()
    if root and (root.Position - SNAIL_SPOT).Magnitude > SNAIL_RANGE then
        Core.TeleportTo(SNAIL_SPOT)
        return "to snail"
    end
    return "at snail"
end

function Core.CrabStep()
    if not Core.Settings.TrainCrab then
        return "off"
    end
    local root = rootPart()
    if not root then
        return "no character"
    end
    ensurePlatform("TrainCrab")
    local standing = PLATFORMS.TrainCrab.at + Vector3.new(0, CRAB_HEIGHT, 0)
    if (root.Position - standing).Magnitude > CRAB_RANGE then
        Core.TeleportTo(standing)
        return "to platform"
    end
    return "on platform"
end

-- Verbal Hub's Kill Crab: stand right above the Coconut Crab.
function Core.FightCrabStep()
    if not Core.Settings.FightCrab then
        return "off"
    end
    local root = rootPart()
    if not root then
        return "no character"
    end
    ensurePlatform("FightCrab")
    if (root.Position - FIGHT_CRAB_SPOT).Magnitude > 3 then
        Core.JumpTo(FIGHT_CRAB_SPOT)
        return "to crab"
    end
    return "above crab"
end

-- Floating above a boss: HipHeight lifts your character, and puts back what it was.
local normalHipHeight
local function hoverAt(height)
    local hum = humanoid()
    if hum then
        normalHipHeight = normalHipHeight or hum.HipHeight
        hum.HipHeight = height
    end
end
local function stopHovering()
    local hum = humanoid()
    if hum and normalHipHeight then
        hum.HipHeight = normalHipHeight
    end
    normalHipHeight = nil
end

-- Verbal Hub's Windy Bee: stand on Windy, 35 studs up.
function Core.WindyStep()
    if not Core.Settings.HoverWindy then
        return "off"
    end
    local bees = Workspace:FindFirstChild("NPCBees")
    local windy = bees and bees:FindFirstChild("Windy")
    local position = windy and positionOf(windy)
    if not (position and rootPart()) then
        return "none"
    end
    hoverAt(35)
    Core.JumpTo(position)
    return "windy"
end

-- Verbal Hub's Vicious Bee: 20 studs above whatever in Particles is named Vicious.
function Core.ViciousStep()
    if not Core.Settings.HoverVicious then
        return "off"
    end
    local root = rootPart()
    local particles = Workspace:FindFirstChild("Particles")
    local vicious = root and particles and nearest(particles, root.Position, math.huge, function(part)
        return part.Name:find("Vicious", 1, true) ~= nil
    end)
    if not vicious then
        return "none"
    end
    hoverAt(20)
    Core.JumpTo(vicious.Position + Vector3.new(0, 20, 0))
    return "vicious"
end

-- Verbal Hub's Mondo Chick (marked "in testing" there): float 40 studs above its head.
function Core.MondoStep()
    if not Core.Settings.FollowMondo then
        return "off"
    end
    local monsters = Workspace:FindFirstChild("Monsters")
    local root = rootPart()
    if not (monsters and root) then
        return "none"
    end
    for _, monster in ipairs(monsters:GetChildren()) do
        if monster.Name:find("Mondo Chick", 1, true) then
            local head = monster:FindFirstChild("Head")
            if head then
                hoverAt(40)
                if (root.Position - head.Position).Magnitude > 20 then
                    Core.TeleportTo(head.Position)
                end
                return "mondo"
            end
        end
    end
    return "none"
end

-- Verbal Hub's snowflake farm: hop above a random snowflake, 15 studs up.
function Core.SnowStep()
    if not Core.Settings.CollectSnowflakes then
        return "off"
    end
    local root = rootPart()
    if not root then
        return "no character"
    end
    local particles = Workspace:FindFirstChild("Particles")
    local folder = particles and particles:FindFirstChild("Snowflakes")
    local flakes = folder and folder:GetChildren() or {}
    if #flakes == 0 then
        Core.Say("snow", "Snowflakes", "No snowflakes found. The winter event may be over.")
        return "none"
    end
    local position = positionOf(flakes[math.random(1, #flakes)])
    if not position then
        return "none"
    end
    Core.TeleportTo(position + Vector3.new(0, 15, 0))
    pcall(function()
        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    end)
    return "snowflake"
end

function Core.SpeedStep()
    if Core.Settings.KeepWalkSpeed then
        local hum = humanoid()
        if hum then
            hum.WalkSpeed = Core.Settings.WalkSpeed
            return "set"
        end
    end
    return "off"
end

function Core.JumpStep()
    if Core.Settings.KeepJumpPower then
        local hum = humanoid()
        if hum then
            pcall(function()
                hum.UseJumpPower = true
            end)
            hum.JumpPower = Core.Settings.JumpPower
            return "set"
        end
    end
    return "off"
end

-- Walk through walls: every part of your character stops colliding.
function Core.NoclipStep()
    if not Core.Settings.Noclip then
        return "off"
    end
    local character = LocalPlayer.Character
    if not character then
        return "no character"
    end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            part.CanCollide = false
        end
    end
    return "noclip"
end

----------------------------------------------------------------------------
-- Passive options
----------------------------------------------------------------------------

-- Kron's script stopped the game from putting your character into its knocked-down states.
local function applyStates(character)
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    if not hum then
        return
    end
    local allowed = not Core.Settings.StayOnFeet
    pcall(hum.SetStateEnabled, hum, Enum.HumanoidStateType.Ragdoll, allowed)
    pcall(hum.SetStateEnabled, hum, Enum.HumanoidStateType.FallingDown, allowed)
end

-- Kron's script made field trees and decorations pass-through and half see-through.
local decorationBackup = {}
local function setDecorations(hidden)
    local folder = Workspace:FindFirstChild("FieldDecos")
    if hidden and folder then
        local seen = 0
        for _, part in ipairs(folder:GetDescendants()) do
            if part:IsA("BasePart") and decorationBackup[part] == nil then
                decorationBackup[part] = { part.CanCollide, part.Transparency }
                part.CanCollide = false
                part.Transparency = 0.5
                seen = seen + 1
                if seen % 200 == 0 then
                    task.wait()
                end
            end
        end
    elseif not hidden then
        for part, saved in pairs(decorationBackup) do
            decorationBackup[part] = nil
            if part.Parent then
                part.CanCollide, part.Transparency = saved[1], saved[2]
            end
        end
    end
end

local function setAntiAfk(on)
    if connections.afk then
        connections.afk:Disconnect()
        connections.afk = nil
    end
    if on then
        connections.afk = LocalPlayer.Idled:Connect(function()
            local input = game:GetService("VirtualInputManager")
            input:SendKeyEvent(true, Enum.KeyCode.W, false, game)
            task.wait()
            input:SendKeyEvent(false, Enum.KeyCode.W, false, game)
        end)
    end
end

local function resetFarm()
    local farm = Core.Farm
    farm.phase, farm.pressed, farm.sprinklerDue, farm.hiveSince = "field", false, true, 0
end

-- What changing a setting does besides storing it.
local effects = {
    AutoFarm = function()
        resetFarm()
    end,
    TrainCrab = function(on)
        if not on then
            removePlatform("TrainCrab")
        end
    end,
    FightCrab = function(on)
        if not on then
            removePlatform("FightCrab")
        end
    end,
    StayOnFeet = function()
        applyStates(LocalPlayer.Character)
    end,
    WalkThroughDecorations = function(on)
        setDecorations(on)
    end,
    AntiAfk = function(on)
        setAntiAfk(on)
    end,
}
local function hoverIfNeeded()
    local settings = Core.Settings
    if not (settings.HoverWindy or settings.HoverVicious or settings.FollowMondo) then
        stopHovering()
    end
end
effects.HoverWindy, effects.HoverVicious, effects.FollowMondo = hoverIfNeeded, hoverIfNeeded, hoverIfNeeded

-- Stores a setting. Turning one mover on turns the others off. Returns false for a name, a value
-- of the wrong kind, or a value that is not on the setting's list.
function Core.Set(name, value)
    local settings = Core.Settings
    if settings[name] == nil or type(settings[name]) ~= type(value) then
        return false
    end
    if ALLOWED[name] and not ALLOWED[name][value] then
        return false
    end
    if settings[name] == value then
        return true
    end
    settings[name] = value
    if value == true and isMover(name) then
        for _, other in ipairs(MOVERS) do
            if other ~= name then
                switchOff(other)
            end
        end
    end
    if autoByKey[name] then
        nextRun[name] = nil -- a switch just turned on runs at once
    end
    if effects[name] then
        local ok, err = pcall(effects[name], value)
        if not ok then
            Core.Warn(name, err)
        end
    end
    return true
end

----------------------------------------------------------------------------
-- Start and stop
----------------------------------------------------------------------------

-- What Kron's script did once as it loaded: made decorations pass-through, claimed a hive if you had
-- none, and flew you to it. The flight is skipped when something else is already moving you.
function Core.Setup()
    local ok, err = pcall(setDecorations, Core.Settings.WalkThroughDecorations)
    if not ok then
        Core.Warn("Decorations", err)
    end
    if not Core.ClaimHive() then
        Core.Notify("Hive", "You do not have a hive and none is free. Auto Farm needs one.")
        return false
    end
    local busy = false
    for _, mover in ipairs(MOVERS) do
        busy = busy or Core.Settings[mover]
    end
    if Core.Settings.GoToHiveOnLoad and not busy then
        Core.TeleportToHive()
    end
    return true
end

function Core.Start()
    if alive then
        return
    end
    alive = true
    local function loop(label, pause, step)
        task.spawn(function()
            while alive do
                local ok, err = pcall(step)
                if not ok then
                    Core.Warn(label, err)
                end
                task.wait(pause)
            end
        end)
    end
    loop("Auto Farm", 0.1, Core.FarmStep)
    loop("Auto Dig", 0.1, Core.DigStep)
    loop("Pick Up", 0.2, Core.TokenStep)
    loop("Snail", 0.5, Core.SnailStep)
    loop("Crab", 1, Core.CrabStep)
    loop("Fight Crab", 0.2, Core.FightCrabStep)
    loop("Snowflakes", 0.5, Core.SnowStep)
    loop("Mondo Chick", 0.3, Core.MondoStep)
    loop("Windy Bee", 0.3, Core.WindyStep)
    loop("Vicious Bee", 0.3, Core.ViciousStep)
    loop("Auto Use", 0.25, Core.AutoUseStep)
    loop("Walk Speed", 0, Core.SpeedStep)
    loop("Jump Power", 0, Core.JumpStep)
    loop("Noclip", 0, Core.NoclipStep)

    connections.character = LocalPlayer.CharacterAdded:Connect(function(character)
        character:WaitForChild("Humanoid")
        applyStates(character)
    end)
    applyStates(LocalPlayer.Character)
    setAntiAfk(Core.Settings.AntiAfk)
    task.spawn(Core.Setup)
end

-- Turns every farm, training and auto-use switch off.
function Core.StopFeatures()
    for _, name in ipairs(Core.ActionSettings) do
        switchOff(name)
    end
end

-- Stops the loops and puts back what the script changed.
function Core.Unload()
    Core.StopFeatures()
    alive = false
    setAntiAfk(false)
    if connections.character then
        connections.character:Disconnect()
        connections.character = nil
    end
    pcall(setDecorations, false)
    for key in pairs(platforms) do
        removePlatform(key)
    end
    stopHovering()
    local hum = humanoid()
    if hum then
        pcall(hum.SetStateEnabled, hum, Enum.HumanoidStateType.Ragdoll, true)
        pcall(hum.SetStateEnabled, hum, Enum.HumanoidStateType.FallingDown, true)
    end
end

return Core
