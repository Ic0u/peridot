-- Peridot Bee Swarm Simulator core: Kron's hub, rewritten as readable code.
-- The copy it was ported from came out of a decompiler that lost its variable names and some
-- of its branches, so the loops here follow what that script visibly did (which remotes it
-- fired, which numbers it used) and how the game's own values (CoreStats, Honeycombs) work.
-- The interface is games/1537690962.lua; this file only holds the features.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local Core = {}

----------------------------------------------------------------------------
-- Places and numbers taken from the script
----------------------------------------------------------------------------

-- The spot the script stands on while it farms each field, in the order of its list.
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

local SNAIL_SPOT = Vector3.new(422.657, 96.426, -175.720) -- beside the Stump Field snail
local CRAB_PLATFORM = Vector3.new(-257.521, 105.919, 457.868) -- the invisible platform for the Coconut Crab
local CRAB_HEIGHT = 4.7 -- how far above the platform you stand

local FIELD_RADIUS = 65 -- farther than this from the field's spot and Auto Farm flies back to it
local HIVE_RADIUS = 10 -- how close to the hive's pad honey making needs you
local TOKEN_RANGE = 50
local BUBBLE_RANGE = 60
local SNAIL_RANGE = 30
local CRAB_RANGE = 60
local BALLOON_RANGE = 25
local BALLOON_WAIT = 15 -- seconds; the source waited without a limit
local HIVE_TIMEOUT = 600 -- seconds; a conversion that takes longer is given up on

Core.BlueBuffs = { "Blue Extract", "Glitter", "Glue", "Oil", "Enzymes", "Tropical Drink" }
Core.RedBuffs = { "Red Extract", "Glitter", "Glue", "Oil", "Enzymes", "Tropical Drink" }
Core.Items = {
    "Blue Extract", "Red Extract", "Glitter", "Glue", "Oil", "Enzymes", "Tropical Drink",
    "Purple Potion", "Super Smoothie", "Marshmallow Bee",
}
Core.Dispensers = {
    "Glue Dispenser", "Wealth Clock", "Coconut Dispenser", "Strawberry Dispenser", "Treat Dispenser",
    "Free Ant Pass Dispenser", "Blueberry Dispenser", "Honey Dispenser", "Free Royal Jelly Dispenser",
}

----------------------------------------------------------------------------
-- Settings. The interface writes them with Core.Set.
----------------------------------------------------------------------------

Core.Settings = {
    Field = Core.Fields[1].name,
    AutoFarm = false,
    AutoDig = false,
    CollectTokens = true,
    CollectBubbles = false,
    PlaceSprinkler = false,
    ConvertBalloons = false,
    TrainSnail = false,
    TrainCrab = false,
    KeepWalkSpeed = false,
    WalkSpeed = 16,
    TravelSpeed = 80, -- studs per second when flying between places
    StayOnFeet = true,
    WalkThroughDecorations = true,
    AntiAfk = true,
}

-- Only one of these can move you at a time.
local MOVERS = { "AutoFarm", "TrainSnail", "TrainCrab" }
local function isMover(name)
    for _, mover in ipairs(MOVERS) do
        if mover == name then
            return true
        end
    end
    return false
end
-- What Stop All Features turns off. The options that only change how Auto Farm works, and the
-- three protections, stay as they were set.
Core.ActionSettings = { "AutoFarm", "AutoDig", "TrainSnail", "TrainCrab", "KeepWalkSpeed" }

Core.Farm = { phase = "field", pressed = false, sprinklerDue = true, hiveSince = 0 }
Core.Notify = function() end -- the interface replaces these two
Core.OnChange = nil -- called as (name, value) when the core flips a setting by itself
Core.Clock = os.clock

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

local function fire(name, ...)
    local events = ReplicatedStorage:FindFirstChild("Events")
    local remote = events and events:FindFirstChild(name)
    if not remote then
        return false, name .. " is not in this game"
    end
    return pcall(remote.FireServer, remote, ...)
end

function Core.FindField(name)
    for _, field in ipairs(Core.Fields) do
        if field.name == name then
            return field
        end
    end
    return Core.Fields[1]
end

function Core.FieldNames()
    local names = {}
    for _, field in ipairs(Core.Fields) do
        names[#names + 1] = field.name
    end
    return names
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

-- Glides your character to a point in a straight line at Settings.TravelSpeed.
function Core.TeleportTo(position)
    local root = rootPart()
    if not root then
        return false
    end
    local seconds = math.max((root.Position - position).Magnitude / Core.Settings.TravelSpeed, 0.1)
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
    return true
end

function Core.TeleportToField(name)
    return Core.TeleportTo(Core.FindField(name).position)
end

----------------------------------------------------------------------------
-- Your hive
----------------------------------------------------------------------------

local function hives()
    local container = Workspace:FindFirstChild("Honeycombs")
    return container and container:GetChildren() or {}
end

function Core.FindHive()
    for _, hive in ipairs(hives()) do
        local owner = hive:FindFirstChild("Owner")
        if owner and owner.Value == LocalPlayer then
            return hive
        end
    end
    return nil
end

-- Where to stand to make honey: the hive's pad, one stud up.
function Core.HivePosition()
    local hive = Core.FindHive()
    local arrow = hive and hive:FindFirstChild("patharrow")
    local base = arrow and arrow:FindFirstChild("Base")
    if base then
        return base.Position + Vector3.new(0, 1, 0)
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
    return Core.TeleportTo(position)
end

-- Starts or stops turning your pollen into honey (the same button as standing on the pad).
function Core.MakeHoney()
    return fire("PlayerHiveCommand", "ToggleHoneyMaking")
end

----------------------------------------------------------------------------
-- Items and dispensers
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

function Core.PlaceSprinkler()
    task.wait(0.5)
    local hum = humanoid()
    if hum then
        hum.Jump = true
    end
    Core.UseItem("Sprinkler Builder")
    task.wait(0.5)
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
        if capacity > 0 and pollen >= capacity then
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

-- While farming a field, walks to the nearest bubble, then the nearest token.
function Core.TokenStep()
    local settings = Core.Settings
    if not (settings.AutoFarm and Core.Farm.phase == "field" and (settings.CollectTokens or settings.CollectBubbles)) then
        return "off"
    end
    local root, hum = rootPart(), humanoid()
    if not (root and hum) then
        return "no character"
    end
    if settings.CollectBubbles then
        local particles = Workspace:FindFirstChild("Particles")
        local bubble = particles and nearest(particles, root.Position, BUBBLE_RANGE, function(part)
            return part.Name == "Bubble"
        end)
        if bubble then
            hum:MoveTo(bubble.Position)
            return "bubble"
        end
    end
    if settings.CollectTokens then
        local tokens = Workspace:FindFirstChild("Collectibles")
        local field = Core.FindField(settings.Field)
        local token = tokens and nearest(tokens, root.Position, TOKEN_RANGE, function(part)
            return (part.Position - field.position).Magnitude <= FIELD_RADIUS + 10 -- never chase one out of the field
        end)
        if token then
            hum:MoveTo(token.Position)
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

local crabPlatform
local function ensureCrabPlatform()
    if crabPlatform and crabPlatform.Parent then
        return crabPlatform
    end
    local part = Instance.new("Part")
    part.Name = "combatcrabpart"
    part.Anchored = true
    part.Transparency = 1
    part.Size = Vector3.new(90, 1, 90)
    part.Position = CRAB_PLATFORM
    part.CanCollide = true
    part.Parent = Workspace
    crabPlatform = part
    return part
end

function Core.GetCrabPlatform()
    return crabPlatform
end

function Core.CrabStep()
    if not Core.Settings.TrainCrab then
        return "off"
    end
    local root = rootPart()
    if not root then
        return "no character"
    end
    ensureCrabPlatform()
    local standing = CRAB_PLATFORM + Vector3.new(0, CRAB_HEIGHT, 0)
    if (root.Position - standing).Magnitude > CRAB_RANGE then
        Core.TeleportTo(standing)
        return "to platform"
    end
    return "on platform"
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

----------------------------------------------------------------------------
-- Passive options
----------------------------------------------------------------------------

-- The script stopped the game from putting your character into its knocked-down states.
local function applyStates(character)
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    if not hum then
        return
    end
    local allowed = not Core.Settings.StayOnFeet
    pcall(hum.SetStateEnabled, hum, Enum.HumanoidStateType.Ragdoll, allowed)
    pcall(hum.SetStateEnabled, hum, Enum.HumanoidStateType.FallingDown, allowed)
end

-- The script made field trees and decorations pass-through and half see-through.
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
        if not on and crabPlatform then
            crabPlatform:Destroy()
            crabPlatform = nil
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

-- Stores a setting. Turning one mover on turns the other two off. Returns false for a name or
-- a value of the wrong kind.
function Core.Set(name, value)
    local settings = Core.Settings
    if settings[name] == nil or type(settings[name]) ~= type(value) then
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
    loop("Tokens", 0.2, Core.TokenStep)
    loop("Snail", 0.5, Core.SnailStep)
    loop("Crab", 1, Core.CrabStep)
    loop("Walk Speed", 0, Core.SpeedStep)

    connections.character = LocalPlayer.CharacterAdded:Connect(function(character)
        character:WaitForChild("Humanoid")
        applyStates(character)
    end)
    applyStates(LocalPlayer.Character)
    setAntiAfk(Core.Settings.AntiAfk)
    task.spawn(function()
        local ok, err = pcall(setDecorations, Core.Settings.WalkThroughDecorations)
        if not ok then
            Core.Warn("Decorations", err)
        end
        if not Core.ClaimHive() then
            Core.Notify("Hive", "You do not have a hive and none is free. Auto Farm needs one.")
        end
    end)
end

-- Turns every farm and training switch off.
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
    if crabPlatform then
        crabPlatform:Destroy()
        crabPlatform = nil
    end
    local hum = humanoid()
    if hum then
        pcall(hum.SetStateEnabled, hum, Enum.HumanoidStateType.Ragdoll, true)
        pcall(hum.SetStateEnabled, hum, Enum.HumanoidStateType.FallingDown, true)
    end
end

return Core
