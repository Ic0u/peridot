-- Peridot Blox Fruits module. The game logic is libraries/BloxFruitsCore.lua;
-- this file only builds the interface and writes the option flags the core reads.

local MODULE_BASE_URL = "https://raw.githubusercontent.com/Ic0u/peridot/main/"
local SUPPORTED_PLACES = {
    [2753915549] = true,
    [4442272183] = true,
    [7449423635] = true,
    [85211729168715] = true,
    [79091703265657] = true,
    [100117331123089] = true,
}

if not SUPPORTED_PLACES[game.PlaceId] then
    warn("Peridot Blox Fruits module was loaded in an unsupported place")
    return
end

local PlayersService = game:GetService("Players")
local LocalPlayer = PlayersService.LocalPlayer or PlayersService.PlayerAdded:Wait()
local GameName = "Blox Fruits"
pcall(function()
    local productInfo = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
    if type(productInfo) == "table" and type(productInfo.Name) == "string" and productInfo.Name ~= "" then
        GameName = productInfo.Name
    end
end)

local environment = (getgenv and getgenv()) or _G
if environment.PeridotBloxFruitsLoaded then
    warn("Peridot Blox Fruits is already running")
    return
end
environment.PeridotBloxFruitsLoaded = true

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
UILibrary.SetConfigFolder("Peridot/BloxFruits")

local TEAM_NAMES = {
    pirates = "Pirates",
    marines = "Marines",
}

local function normalizeTeamName(teamName)
    return TEAM_NAMES[string.lower(tostring(teamName or ""))]
end

environment.Team = normalizeTeamName(environment.Team) or "Pirates"

local function requestTeam(teamName)
    local normalizedTeam = normalizeTeamName(teamName)
    if not normalizedTeam then
        return false, "Unknown team"
    end

    local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
    local commandRemote = remotes and remotes:FindFirstChild("CommF_")
    if not commandRemote then
        return false, "Team remote is not ready"
    end

    local ok, response = pcall(commandRemote.InvokeServer, commandRemote, "SetTeam", normalizedTeam)
    if ok then
        environment.Team = normalizedTeam
    end
    return ok, response
end

-- The core waits for the game's loading screen, which needs a team. Some
-- executors start before Blox Fruits mounts its team picker, so retry for a
-- short, bounded window instead of blocking forever.
task.spawn(function()
    for attempt = 1, 8 do
        if LocalPlayer.Team then
            return
        end

        requestTeam(environment.Team)
        if attempt < 8 then
            task.wait(attempt < 3 and 0.5 or 1)
        end
    end
end)

local coreLoaded, coreError = pcall(loadRemoteModule, "libraries/BloxFruitsCore.lua")
if not coreLoaded then
    warn("[Peridot] Blox Fruits core failed: " .. tostring(coreError))
end

local Core = type(environment.Core) == "table" and environment.Core or {}

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------

local Window = UILibrary.CreateMain({
    Name = "Peridot",
    Title = GameName,
    Desc = "",
})

local function notify(title, desc, duration)
    pcall(UILibrary.CreateNoti, { Title = title, Desc = desc, ShowTime = duration or 4 })
end

-- Blox Fruits kicks the client on script errors, so no control may throw.
local function safe(where, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            warn("[Peridot] " .. tostring(where) .. ": " .. tostring(err))
        end
    end
end

-- The core reads most options from _G, some from getgenv() and a few from plain
-- globals. Those names are written to both places.
local ENV_FLAGS = {}
for name in string.gmatch([[
AutoMaterial SelectMob SelectIslandMastery SelectMaterial AutoCraftVolcanic TweenSpeedNear TweenSpeedFar
SelectFruit NoClipShip NoClip Observation AutoStartLawRaids AutoPressW AutoGetFruit AutoDoughKing
AutoBuyMicrochipLaw AutoBuyFruitSniper FindPrehistoric HopServerAdmin PlayersList SelectIsland pSats ABmethod
RandomCFrame RDeath RemoveDamage LookM LookMV3 SpectatePlys NPClist InfAblities PlayerEsp IslandESP
DevilFruitESP FlowerESP EspEventIsland ESPGear advanEsp ColorEsp LegenS ChestESP BerryEsp Range FARM_RANGE
Num_self
]], "%S+") do
    ENV_FLAGS[name] = true
end

local function setFlag(name, value)
    _G[name] = value
    if ENV_FLAGS[name] then
        environment[name] = value
    end
end

local function readList(value)
    local items = {}
    if type(value) == "table" then
        for _, item in ipairs(value) do
            items[#items + 1] = tostring(item)
        end
    end
    return items
end

local function sortedKeys(map)
    local keys = {}
    if type(map) == "table" then
        for key in pairs(map) do
            keys[#keys + 1] = tostring(key)
        end
    end
    table.sort(keys)
    return keys
end

-- 1, 2 or 3 once the core has said which sea this is. While it is unknown
-- nothing is hidden. Controls for another sea would do nothing, so they are not built.
local SEA = (environment.World1 and 1) or (environment.World2 and 2) or (environment.World3 and 3) or nil
local SEA1, SEA2, SEA3, SEA23 = { 1 }, { 2 }, { 3 }, { 2, 3 }

local function inSea(seas)
    if not SEA or not seas then
        return true
    end
    for _, sea in ipairs(seas) do
        if sea == SEA then
            return true
        end
    end
    return false
end

local function callGlobal(name, ...)
    local fn = environment[name] or _G[name] or Core[name]
    if type(fn) ~= "function" then
        notify("Unavailable", name .. " is not loaded in this server.")
        return nil
    end
    return fn(...)
end

local tracked = {}

local function tog(section, title, flags, desc, seas)
    if not inSea(seas) then
        return nil
    end
    if type(flags) == "string" then
        flags = { flags }
    end
    local entry = { flags = flags, last = false }
    entry.handle = section.CreateToggle({ Title = title, Desc = desc }, safe(title, function(on)
        entry.last = on and true or false
        for _, name in ipairs(flags) do
            setFlag(name, entry.last)
        end
    end))
    tracked[#tracked + 1] = entry
    return entry.handle
end

-- quiet skips the "list is empty" line, for lists that report their own state.
local function pick(section, title, flag, items, default, search, quiet)
    items = readList(items)
    if default ~= nil then
        setFlag(flag, default)
    end
    local dropdown = section.CreateDropdown({
        Title = title,
        List = items,
        Default = default,
        Search = search or #items > 10,
    }, safe(title, function(value)
        setFlag(flag, value)
    end))
    if #items == 0 and not quiet then
        section.CreateLabel({ Title = title .. ": nothing to list in this server" })
    end
    return dropdown
end

-- opts.scale multiplies the slider value before it is stored; opts.zeroIsNil clears the flag at 0.
local function num(section, title, flag, min, max, default, opts)
    opts = opts or {}
    local function apply(value)
        value = tonumber(value) or default
        if opts.zeroIsNil and value == 0 then
            setFlag(flag, nil)
        else
            setFlag(flag, value * (opts.scale or 1))
        end
    end
    apply(default)
    return section.CreateSlider({
        Title = title,
        Min = min,
        Max = max,
        Default = default,
        Precise = opts.precise,
    }, safe(title, apply))
end

local function btn(section, title, fn, text)
    return section.CreateButton({ Title = title, ButtonText = text }, safe(title, fn))
end

-- A dropdown filled from live game data. It shows how many entries it found,
-- says what to do when there are none, and Refresh re-reads the list.
local function listPick(section, title, flag, source, noun, hint)
    local function read()
        local ok, list = pcall(source)
        return ok and readList(list) or {}
    end
    local items = read()
    local dropdown = pick(section, title, flag, items, nil, true, true)
    local status = section.CreateLabel({ Title = noun })
    local function describe(list)
        status.SetText(#list > 0 and (#list .. " " .. noun .. " found") or ("No " .. noun .. " found. " .. hint))
    end
    describe(items)
    btn(section, "Refresh " .. title .. " List", function()
        local list = read()
        dropdown.GetNewList(list)
        setFlag(flag, nil) -- the dropdown clears its selection when its list changes
        describe(list)
        notify(title, #list > 0 and (#list .. " " .. noun .. " found. Pick one again.") or ("No " .. noun .. " found."))
    end, "Refresh")
    return dropdown
end

-- Keep switches in step when the core turns a feature off by itself (a finished
-- quest, a stopped farm) so the saved config never says "on" for something idle.
task.spawn(function()
    while true do
        task.wait(1)
        for _, entry in ipairs(tracked) do
            pcall(function()
                local name = entry.flags[1]
                local fromG, fromEnv = _G[name], environment[name]
                local now = entry.last
                if type(fromG) == "boolean" and fromG ~= entry.last then
                    now = fromG
                elseif type(fromEnv) == "boolean" and fromEnv ~= entry.last then
                    now = fromEnv
                end
                if now ~= entry.last then
                    entry.handle.Set(now)
                end
            end)
        end
    end
end)

local function mobNames()
    local ok, list = pcall(function()
        return callGlobal("GetMobs") or {}
    end)
    return ok and readList(list) or {}
end

local function islandNames()
    return sortedKeys(environment.IslandData)
end

local function playerNames()
    local names = {}
    for _, player in ipairs(PlayersService:GetPlayers()) do
        if player ~= LocalPlayer then
            names[#names + 1] = player.Name
        end
    end
    table.sort(names)
    return names
end

local function npcNames()
    local names = {}
    pcall(function()
        for _, npc in ipairs(game:GetService("ReplicatedStorage").NPCs:GetChildren()) do
            names[#names + 1] = npc.Name
        end
    end)
    table.sort(names)
    return names
end

local function rodNames()
    local names, seen = {}, {}
    pcall(function()
        for _, container in ipairs({ LocalPlayer.Backpack, LocalPlayer.Character }) do
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") and tool:FindFirstChild("FishingRodData") and not seen[tool.Name] then
                    seen[tool.Name] = true
                    names[#names + 1] = tool.Name
                end
            end
        end
    end)
    table.sort(names)
    return names
end

local FRUIT_NAMES = {
    "Rocket-Rocket", "Spin-Spin", "Chop-Chop", "Spring-Spring", "Bomb-Bomb", "Smoke-Smoke", "Spike-Spike",
    "Flame-Flame", "Falcon-Falcon", "Ice-Ice", "Sand-Sand", "Dark-Dark", "Ghost-Ghost", "Diamond-Diamond",
    "Light-Light", "Rubber-Rubber", "Barrier-Barrier", "Magma-Magma", "Quake-Quake", "Buddha-Buddha",
    "Love-Love", "Creation-Creation", "Spider-Spider", "Sound-Sound", "Phoenix-Phoenix", "Portal-Portal",
    "Rumble-Rumble", "Pain-Pain", "Blizzard-Blizzard", "Gravity-Gravity", "Mammoth-Mammoth", "T-Rex-T-Rex",
    "Dough-Dough", "Shadow-Shadow", "Venom-Venom", "Control-Control", "Spirit-Spirit", "Dragon-Dragon",
    "Leopard-Leopard", "Kitsune-Kitsune",
}

----------------------------------------------------------------------------
-- Farm
----------------------------------------------------------------------------

do
    local page = Window.CreatePage({ Page_Name = "Farm", Page_Title = "Farm" })

    local level = page.CreateSubTab("Level")
    local auto = level.CreateSection("Auto Farm")
    pick(auto, "Weapon", "ChooseWP", { "Melee", "Sword", "Blox Fruit", "Gun" }, "Melee")
    tog(auto, "Auto Farm Level", "Level")
    tog(auto, "Farm Nearest Mobs", "AutoFarmNear")
    tog(auto, "Farm Selected Mob", "AutoKillMob")
    listPick(auto, "Mob", "SelectMob", mobNames, "mobs", "Press Refresh once the game has finished loading.")
    tog(auto, "Farm Selected Island", "AutoFarmIsland")
    listPick(auto, "Island", "SelectIsland", islandNames, "islands", "Press Refresh once the game has finished loading.")

    local materials = level.CreateSection("Materials")
    pick(materials, "Material", "SelectMaterial", environment.MaterialList)
    tog(materials, "Farm Material", "AutoMaterial")

    local mastery = page.CreateSubTab("Mastery")
    local masteryFarm = mastery.CreateSection("Mastery Farm")
    local targets = inSea(SEA3) and { "Cake", "Bone", "Selected Mob" } or { "Selected Mob" }
    pick(masteryFarm, "Mastery Target", "SelectIslandMastery", targets, targets[1])
    masteryFarm.CreateLabel({ Title = "Selected Mob uses the Mob picked on the Level tab" })
    num(masteryFarm, "Switch To Skills At Health %", "MasteryHealthPct", 5, 100, 70)
    tog(masteryFarm, "Fruit Mastery", { "FarmMastery_Dev", "Auto_Fruit_Mastery" })
    tog(masteryFarm, "Gun Mastery", { "FarmMastery_G", "Auto_Gun_Mastery" })
    tog(masteryFarm, "Sword Mastery", "FarmMastery_S")
    tog(masteryFarm, "All Swords Mastery", "Auto_Mastery_All_Sword")

    local skills = mastery.CreateSection("Mastery Skills")
    local skillOn = { Z = true, X = true, C = true, V = true, F = true }
    local function applySkills()
        local list = {}
        for _, key in ipairs({ "Z", "X", "C", "V", "F" }) do
            if skillOn[key] then
                list[#list + 1] = key
            end
        end
        setFlag("SelectedMasterySkills", list)
    end
    for _, key in ipairs({ "Z", "X", "C", "V", "F" }) do
        skills.CreateToggle({ Title = "Use Skill " .. key, Default = true }, safe("skill " .. key, function(on)
            skillOn[key] = on and true or false
            applySkills()
        end))
    end

    local bosses = page.CreateSubTab("Bosses")
    local boss = bosses.CreateSection("Bosses")
    pick(boss, "Boss", "FindBoss", environment.BossList, nil, true)
    tog(boss, "Farm Selected Boss", "FarmBoss")
    tog(boss, "Farm All Bosses", "AutoFarmAllBoss")
    tog(boss, "Accept Boss Quest", "AcceptQuestBoss")
    tog(boss, "Tyrant of the Skies", "FarmTyrant", nil, SEA3)
    if inSea(SEA3) then
        local elite = bosses.CreateSection("Elite Hunter")
        tog(elite, "Elite Hunter", "FarmEliteHunt")
        tog(elite, "Elite Hunter and Server Hop", "FarmEliteH")

        local bone = page.CreateSubTab("Bones and Cake")
        local bones = bone.CreateSection("Bones")
        tog(bones, "Farm Bones", "AutoFarm_Bone")
        tog(bones, "Accept Bone Quest", "AcceptQuestB")
        tog(bones, "Random Bone Rolls", "Auto_Random_Bone")
        tog(bones, "Pray at Gravestone", "Praying")
        tog(bones, "Try Your Luck at Gravestone", "TryLucky")
        tog(bones, "Hallow Essence (Soul Reaper)", "AutoHytHallow")
        local cake = bone.CreateSection("Cake")
        tog(cake, "Farm Cake Prince", "Auto_Cake_Prince")
        tog(cake, "Accept Cake Quest", "AcceptQuestC")
        tog(cake, "Spawn Cake Prince", "AutoSpawnCP")
        tog(cake, "Dough King", "AutoDoughKing")
        tog(cake, "Attack Dough King", "AutoAttackDoughKing")
        tog(cake, "Hop For Dough King", "AutoHop_Dough")
    end

    local collect = page.CreateSubTab("Collect")
    local chests = collect.CreateSection("Chests and Berries")
    tog(chests, "Farm Chests", "AutoFarmChest")
    tog(chests, "Stop at Chalice or Fist of Darkness", "StopWhenChalice")
    tog(chests, "Collect Berries", "AutoBerry")
    tog(chests, "Collect Berries and Hop", "AutoBerryH")
    tog(chests, "Ectoplasm (Cursed Ship)", "AutoEctoplasm")
    tog(chests, "Farm Pha Binh (Tiki Outpost)", "FarmPhaBinh", nil, SEA3)
end

----------------------------------------------------------------------------
-- Items
----------------------------------------------------------------------------

do
    local page = Window.CreatePage({ Page_Name = "Items", Page_Title = "Items" })

    local swords = page.CreateSubTab("Swords")
    local basic = swords.CreateSection("Swords")
    tog(basic, "Get Saber", "AutoSaber", nil, SEA1)
    tog(basic, "Get Shark Saw", "AutoSaw", nil, SEA1)
    tog(basic, "Get Pole (1st Form)", "AutoPole", nil, SEA1)
    tog(basic, "Get Pole (2nd Form)", "AutoPoleV2")
    tog(basic, "Get Bisento", "Greybeard", nil, SEA1)
    tog(basic, "Get Trident", "AutoTridentW2", nil, SEA2)
    tog(basic, "Get Longsword", "LongsWord", nil, SEA2)
    tog(basic, "Get Dark Blade V3", "DarkBladev3", nil, SEA2)
    tog(basic, "Get Rengoku (Hidden Key)", "KeysRen", nil, SEA2)
    tog(basic, "Kill Awakened Ice Admiral (Rengoku)", "IceBossRen", nil, SEA2)
    tog(basic, "Get Twin Hooks", "TwinHook", nil, SEA3)
    tog(basic, "Get Serpent Bow", "AutoSerpentBow", nil, SEA3)
    if inSea(SEA3) then
        local dual = swords.CreateSection("Dual Katana")
        tog(dual, "Get Tushita", "Auto_Tushita")
        tog(dual, "Get Yama", "Auto_Yama")
        tog(dual, "Get Cursed Dual Katana", "CDK")
        tog(dual, "Do Tushita Trials", "CDK_TS")
        tog(dual, "Do Yama Trials", "CDK_YM")
    end
    local guitar = swords.CreateSection("Soul Guitar")
    tog(guitar, "Get Soul Guitar", "Auto_Soul_Guitar")
    tog(guitar, "Farm Soul Guitar Materials", "AutoMatSoul")
    local dealers = swords.CreateSection("Dealers")
    tog(dealers, "Go To Legendary Sword Dealer", "Tp_LgS")
    tog(dealers, "Go To Haki Color Dealer", "Tp_MasterA")

    local styles = page.CreateSubTab("Fighting Styles")
    local melee = styles.CreateSection("Fighting Styles")
    tog(melee, "Get Superhuman", "Auto_SuperHuman")
    tog(melee, "Get Death Step", "AutoDeathStep")
    tog(melee, "Get Sharkman Karate", "Auto_SharkMan_Karate")
    tog(melee, "Get Electric Claw", "Auto_Electric_Claw")
    tog(melee, "Get Dragon Talon", "AutoDragonTalon", nil, SEA3)
    tog(melee, "Get Godhuman", "Auto_God_Human", nil, SEA23)
    tog(melee, "Get Sanguine Art", "Snaguine", nil, SEA23)

    local gear = page.CreateSubTab("Gear")
    local accessories = gear.CreateSection("Gear and Accessories")
    tog(accessories, "Get Black Spikey Coat", "BlackSpikey", nil, SEA2)
    tog(accessories, "Get Marine Coat", "MarinesCoat", nil, SEA1)
    tog(accessories, "Get Swan Coat", "SwanCoat", nil, SEA1)
    tog(accessories, "Get Swan Glasses", "Auto_SwanGG", nil, SEA2)
    tog(accessories, "Get Dark Coat", "Auto_Def_DarkCoat", nil, SEA2)
    tog(accessories, "Get Cool Shades", "AutoColShad", nil, SEA1)
    tog(accessories, "Get Don Swan Accessories", "Auto_DonAcces", nil, SEA2)
    tog(accessories, "Get Usoap's Hat (PvP Kills)", "AutoGetUsoap")
    if inSea(SEA3) then
        local haki = gear.CreateSection("Haki")
        tog(haki, "Get Rainbow Haki", "Auto_Rainbow_Haki")
        tog(haki, "Get Rainbow Haki (Fast Quest)", "GetQFast")
    end
    local bossKills = gear.CreateSection("Boss Kills")
    tog(bossKills, "Kill Chief Warden", "WardenBoss", nil, SEA1)
    tog(bossKills, "Kill Cursed Captain", "AutoEcBoss", nil, SEA2)
    tog(bossKills, "Kill Kilo Admiral", "AutoKilo", nil, SEA3)
    tog(bossKills, "Kill Beautiful Pirate", "Auto_Cavender", nil, SEA3)
    tog(bossKills, "Kill Cake Queen", "AutoBigmom", nil, SEA3)
    tog(bossKills, "Kill rip_indra", "AutoRipIngay", nil, SEA3)
    tog(bossKills, "Activate rip_indra Summoner Circle", "AutoUnHaki", nil, SEA3)

    local quests = page.CreateSubTab("Quests")
    local unlocks = quests.CreateSection("Quests and Unlocks")
    tog(unlocks, "Second Sea Quest", "TravelDres", nil, SEA1)
    tog(unlocks, "Bartilo Quest", "Bartilo_Quest", nil, SEA2)
    tog(unlocks, "Third Sea Quest", "AutoZou", nil, SEA2)
    tog(unlocks, "Citizen Quest", "CitizenQuest", nil, SEA3)
    tog(unlocks, "Training Dummy", "DummyMan")
end

----------------------------------------------------------------------------
-- Race
----------------------------------------------------------------------------

do
    local page = Window.CreatePage({ Page_Name = "Race", Page_Title = "Race" })

    local race = page.CreateSubTab("Race")
    local quests = race.CreateSection("Race Quests")
    tog(quests, "Mink Quest", "Auto_Mink")
    tog(quests, "Human Quest", "Auto_Human")
    tog(quests, "Skypiea Quest", "Auto_Skypiea")
    tog(quests, "Fishman Quest", "Auto_Fish")
    tog(quests, "Complete Trials", "Complete_Trials")
    tog(quests, "Go To Race Door", "TPDoor")
    tog(quests, "Ancient One", "AcientOne")
    tog(quests, "Temple of Time Prompts", "Lver")
    tog(quests, "Draco Trial Relics", "Relic123")
    local abilities = race.CreateSection("Race Abilities")
    tog(abilities, "Auto Race V3", "RaceClickAutov3")
    tog(abilities, "Auto Race V4", "RaceClickAutov4")
    tog(abilities, "Look At Moon and Activate", "LookM")
    tog(abilities, "Look At Moon and Use V3", "LookMV3")

    local observation = page.CreateSubTab("Observation")
    local ken = observation.CreateSection("Observation")
    tog(ken, "Keep Observation On", "Observation")
    tog(ken, "Observation Farm", "obsFarm")
    tog(ken, "Observation V2 Quest", "AutoKenVTWO")

    if inSea(SEA3) then
        local dragon = page.CreateSubTab("Dragon")
        local dojo = dragon.CreateSection("Dragon Dojo")
        tog(dojo, "Dojo Belt Quests", "Dojoo")
        tog(dojo, "Farm Blaze Ember", "FarmBlazeEM")
        tog(dojo, "Defeat Players", "Defeating")
        tog(dojo, "Collect Fire Flowers", "AutoFireFlowers")
        local race2 = dragon.CreateSection("Dragon Race")
        tog(race2, "Train Dragon Race", "TrainDrago")
        tog(race2, "Upgrade Dragon Race", "UPGDrago")
        tog(race2, "Buy Dragon Race", "BuyDrago")
        tog(race2, "Dragon Race V1", "DragoV1")
        tog(race2, "Dragon Race V3", "DragoV3")
        tog(race2, "Go To Trial Door", "TpDrago_Prehis")
        tog(race2, "Uzoth Quest", "DT_Uzoth")
    end
end

----------------------------------------------------------------------------
-- Sea
----------------------------------------------------------------------------

do
    local page = Window.CreatePage({ Page_Name = "Sea", Page_Title = "Sea" })

    local sailing = page.CreateSubTab("Sailing")
    local boats = sailing.CreateSection("Boats")
    pick(boats, "Boat", "SelectedBoat", environment.AllBoats, "Guardian")
    pick(boats, "Danger Level", "DangerSc", { "Lv 1", "Lv 2", "Lv 3", "Lv 4", "Lv 5", "Lv 6", "Lv Infinite" }, "Lv 1")
    tog(boats, "Sail Boats", "SailBoats")
    tog(boats, "Sail From Hydra Island", "SailBoat_Hydra", nil, SEA3)
    tog(boats, "Boat No Clip", "NoClipShip")
    tog(boats, "Hold W While Seated", "AutoPressW")
    tog(boats, "Go To Frozen Dimension Gate", "FrozenTP", nil, SEA3)

    local events = page.CreateSubTab("Sea Events")
    local beasts = events.CreateSection("Sea Events")
    tog(beasts, "Sea Beast", "SeaBeast1")
    tog(beasts, "Leviathan", "Leviathan1", nil, SEA3)
    tog(beasts, "Pirate Grand Brigade", "PGB")
    tog(beasts, "Shark", "Shark")
    tog(beasts, "Terrorshark", "TerrorShark")
    tog(beasts, "Piranha", "Piranha")
    tog(beasts, "Fish Boat", "FishBoat")
    tog(beasts, "Fish Crew Members", "MobCrew")
    tog(beasts, "Haunted Crew Members", "HCM")

    if inSea(SEA3) then
        local mirage = page.CreateSubTab("Mirage")
        local island = mirage.CreateSection("Mirage Island")
        tog(island, "Find Mirage Island", "FindMirage")
        tog(island, "Go To Mirage Island", "AutoMysticIsland")
        tog(island, "Go To Highest Point", "HighestMirage")
        tog(island, "Go To Gear", "TPGEAR")
        tog(island, "Show Gear Piece", "can")
        tog(island, "Advanced Fruit Dealer", "Addealer")
        tog(island, "Mirage Chests", "FarmChestM")

        local kitsune = page.CreateSubTab("Kitsune")
        local shrine = kitsune.CreateSection("Kitsune Island")
        tog(shrine, "Find Kitsune Island", "AutofindKitIs")
        tog(shrine, "Go To Shrine", "tweenShrine")
        tog(shrine, "Collect Azure Embers", "Collect_Ember")
        tog(shrine, "Trade Embers", "Trade_Ember")

        local prehistoric = page.CreateSubTab("Prehistoric")
        local island2 = prehistoric.CreateSection("Prehistoric Island")
        tog(island2, "Find Prehistoric Island", "FindPrehistoric")
        tog(island2, "Start Event", "AutoStartPrehistoric")
        tog(island2, "Go To Island Head", "Prehis_Find")
        tog(island2, "Remove Lava and Kill Lava Golems", "Prehis_Skills")
        tog(island2, "Collect Dragon Eggs", "Prehis_DE")
        tog(island2, "Collect Dino Bones", "Prehis_DB")
        tog(island2, "Kill Aura", "KillAuraFull")
        num(island2, "Kill Aura Range", "Range", 20, 500, 100)
        tog(island2, "Reset Event", "ResetPH")
        tog(island2, "Craft Volcanic Magnet", "AutoCraftVolcanic")
    end

    local fishing = page.CreateSubTab("Fishing")
    local rod = fishing.CreateSection("Fishing")
    listPick(rod, "Rod", "SelectedRod", rodNames, "fishing rods", "Carry a rod, then press Refresh.")
    tog(rod, "Auto Fishing", "AutoFishing")
    num(rod, "Catch Delay (0 = random)", "FishCatchDelay", 0, 10, 0, { precise = true, zeroIsNil = true })
    local jobs = fishing.CreateSection("Fishing Jobs")
    tog(jobs, "Take Fishing Quest", "AutoFishingQuest")
    tog(jobs, "Hand In Quest", "AutoQuestComplete")
    tog(jobs, "Sell Fish", "AutoSellFish")
    tog(jobs, "Use Skill Z", "AutoSkillZ")
    local bait = fishing.CreateSection("Bait")
    bait.CreateBox({ Title = "Bait To Craft", Placeholder = "bait name" }, safe("bait", function(text)
        setFlag("SelectedBait", text ~= "" and text or nil)
    end))
    tog(bait, "Craft Bait", "AutoBuyBait")
end

----------------------------------------------------------------------------
-- Raid
----------------------------------------------------------------------------

do
    local page = Window.CreatePage({ Page_Name = "Raid", Page_Title = "Raid" })

    if inSea(SEA23) then
        local raid = page.CreateSubTab("Raid")
        local chips = raid.CreateSection("Raid")
        pick(chips, "Chip", "SelectChip", environment.DungeonTables)
        tog(chips, "Auto Start Raid", "Auto_StartRaid")
        tog(chips, "Buy Chip With Beli", "AutoChipBeli")
        tog(chips, "Buy Chip With Fruit", "AutoChipFruit")
        tog(chips, "Awaken Fruit", "Auto_Awakener")
        tog(chips, "Raid Kill Aura", "KillAuraRaid")
        local special = raid.CreateSection("Special Raids")
        tog(special, "Factory Raid", "AutoFactory", nil, SEA2)
        tog(special, "Castle Raid", "AutoRaidCastle", nil, SEA3)
    end

    if inSea(SEA2) then
        local law = page.CreateSubTab("Law")
        local order = law.CreateSection("Law Raid")
        tog(order, "Buy Microchip", "AutoBuyMicrochipLaw")
        tog(order, "Start Law Raid", "AutoStartLawRaids")
        tog(order, "Kill Order", "AutoLawKak")
    end

    local dungeon = page.CreateSubTab("Dungeon")
    local floors = dungeon.CreateSection("Dungeon")
    tog(floors, "Farm Dungeon", "AutoFarmDungeon")
    num(floors, "Farm Range", "FARM_RANGE", 50, 1000, 300)
    tog(floors, "Go To Floor 1", "TPFloor1")
    tog(floors, "Go To Floor 2", "TPFloor2")
    tog(floors, "Go To Floor 3", "TPFloor3")
    tog(floors, "Go To Floor 4", "TPFloor4")
end

----------------------------------------------------------------------------
-- Fruit
----------------------------------------------------------------------------

do
    local page = Window.CreatePage({ Page_Name = "Fruit", Page_Title = "Fruit" })

    local collect = page.CreateSection("Collect")
    tog(collect, "Go To Nearest Fruit", "TwFruits")
    tog(collect, "Collect Fruits", "InstanceF")
    tog(collect, "Store Fruits", "StoreF")
    tog(collect, "Drop Fruits", "DropFruit")
    tog(collect, "Take Stored Fruits", "AutoGetFruit")
    tog(collect, "Random Fruit Spins", "Random_Auto")

    local buy = page.CreateSection("Fruit Dealer")
    local fruitList = pick(buy, "Fruit", "SelectFruit", FRUIT_NAMES, nil, true)
    tog(buy, "Buy Selected Fruit When In Stock", "AutoBuyFruitSniper")

    task.spawn(function()
        local ok, response = pcall(function()
            return game:GetService("ReplicatedStorage").Remotes.CommF_:InvokeServer("GetFruits")
        end)
        if ok and type(response) == "table" then
            local names = {}
            for _, entry in pairs(response) do
                if type(entry) == "table" and type(entry.Name) == "string" then
                    names[#names + 1] = entry.Name
                end
            end
            if #names > 0 then
                table.sort(names)
                fruitList.GetNewList(names)
            end
        end
    end)
end

----------------------------------------------------------------------------
-- Combat
----------------------------------------------------------------------------

do
    local page = Window.CreatePage({ Page_Name = "Combat", Page_Title = "Combat" })

    local combat = page.CreateSubTab("Combat")
    local attack = combat.CreateSection("Attack")
    tog(attack, "Fast Attack", "Seriality")
    tog(attack, "Randomize Attack Position", "RandomCFrame")
    local aim = combat.CreateSection("Aim")
    tog(aim, "Aim Skills", "AimMethod")
    pick(aim, "Aim Target", "ABmethod", { "Aim Player", "Nearest Aim" }, "Aim Player")
    tog(aim, "Aim Camera At Players", "AimCam")

    local players = page.CreateSubTab("Players")
    local target = players.CreateSection("Target Player")
    listPick(target, "Player", "PlayersList", playerNames, "players", "Press Refresh when someone joins.")
    tog(target, "Go To Player", "TpPly")
    tog(target, "Spectate Player", "SpectatePlys")
    local pvp = players.CreateSection("PvP")
    tog(pvp, "Enable PvP", "AutoPvP")
    tog(pvp, "Accept Alliance Requests", "AcceptAlly")
    tog(pvp, "Player Hunter Quest", "AutoReceivePlayerQuest")
    tog(pvp, "Hunt Players", "AutoPlayerHunter")

    local stats = page.CreateSubTab("Stats")
    local points = stats.CreateSection("Stat Points")
    num(points, "Points Per Add", "pSats", 1, 100, 3)
    tog(points, "Melee", "Auto_Melee")
    tog(points, "Defense", "Auto_Defense")
    tog(points, "Sword", "Auto_Sword")
    tog(points, "Gun", "Auto_Gun")
    tog(points, "Blox Fruit", "Auto_DevilFruit")
end

----------------------------------------------------------------------------
-- Misc
----------------------------------------------------------------------------

local flyHandle
local espFlags = {
    "PlayerEsp", "ChestESP", "BerryEsp", "advanEsp", "ColorEsp", "LegenS",
    "IslandESP", "DevilFruitESP", "FlowerESP", "EspEventIsland", "ESPGear",
}

do
    local page = Window.CreatePage({ Page_Name = "Misc", Page_Title = "Misc" })

    local player = page.CreateSubTab("Player")
    local move = player.CreateSection("Movement")
    tog(move, "No Clip", "NoClip")
    tog(move, "Walk On Water", "WalkWater")
    flyHandle = move.CreateToggle({ Title = "Fly" }, safe("Fly", function(on)
        local toggleFly = _G.toggleFly or environment.toggleFly
        if type(toggleFly) == "function" then
            toggleFly(on and true or false)
        end
    end))
    move.CreateSlider({ Title = "Fly Speed", Min = 10, Max = 300, Default = 50 }, safe("Fly Speed", function(value)
        local updateFlySpeed = _G.updateFlySpeed or environment.updateFlySpeed
        if type(updateFlySpeed) == "function" then
            updateFlySpeed(value)
        end
    end))
    num(move, "Tween Speed Near", "TweenSpeedNear", 50, 400, 180)
    num(move, "Tween Speed Far", "TweenSpeedFar", 50, 400, 150)
    listPick(move, "NPC", "NPClist", npcNames, "NPCs", "Press Refresh once the game has finished loading.")
    tog(move, "Go To NPC", "TPNpc")

    local safety = player.CreateSection("Safety")
    tog(safety, "Float High Above (Always)", "SafeMode", "Keeps you 1000 studs above the ground until you turn it off")
    tog(safety, "Float Up At Low Health", "Safemode", "Lifts you 500 studs up while health is below the slider")
    num(safety, "Float Up Below Health %", "Num_self", 5, 90, 25)

    local effects = player.CreateSection("Effects")
    tog(effects, "Force Time Of Day", "daylightN")
    pick(effects, "Time Of Day", "SelectDN", { "Day", "Night" }, "Day")
    tog(effects, "Agility Effect", "InfAblities")
    tog(effects, "Remove Death Effect", "RDeath")
    tog(effects, "Hide Damage Numbers", "RemoveDamage")
    tog(effects, "Remove Hit Effects", "DestroyHit")
    btn(effects, "Low CPU Mode", function()
        callGlobal("LowCpu")
    end, "Enable")
    btn(effects, "Disable Camera Shake", function()
        callGlobal("DisableCameraShake")
    end, "Disable")
    btn(effects, "Remove Dodge Cooldown", function()
        callGlobal("NoCooldown")
    end, "Apply")

    local server = page.CreateSubTab("Server")
    local hop = server.CreateSection("Server")
    tog(hop, "Auto Server Hop", "AutoHopServer")
    num(hop, "Hop Every (Minutes)", "HopDelay", 1, 120, 30, { scale = 60 })
    tog(hop, "Hop When An Admin Joins", "HopServerAdmin")
    btn(hop, "Server Hop", function()
        callGlobal("HopServer")
    end)
    btn(hop, "Rejoin Current Server", function()
        local ok = pcall(function()
            game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end)
        if not ok then
            notify("Server", "Teleport was rejected.")
        end
    end)

    local visual = page.CreateSubTab("Visual")
    local esp = visual.CreateSection("ESP")
    tog(esp, "Players", "PlayerEsp")
    tog(esp, "Chests", "ChestESP")
    tog(esp, "Berries", "BerryEsp")
    tog(esp, "Devil Fruits", "DevilFruitESP")
    tog(esp, "Flowers", "FlowerESP")
    tog(esp, "Islands", "IslandESP")
    tog(esp, "Event Islands", "EspEventIsland")
    tog(esp, "Mirage Gear", "ESPGear")
    tog(esp, "Advanced Fruit Dealer", "advanEsp")
    tog(esp, "Haki Color Dealer", "ColorEsp")
    tog(esp, "Legendary Sword Dealer", "LegenS")
end

-- The core ships the ESP routines but nothing calls them, so run them here while
-- any ESP switch is on, plus one last pass after the last switch goes off so the
-- labels get removed.
task.spawn(function()
    local routines = {
        "EspPly", "LocationEsp", "DevEsp", "flowerEsp", "EventIslandEsp", "gearEsp",
        "AdvanFruitEsp", "HakiClorEsp", "LegenSword", "ChestEsp", "berriesEsp",
    }
    local wasOn = false
    while true do
        task.wait(0.5)
        local anyOn = false
        for _, name in ipairs(espFlags) do
            if environment[name] == true then
                anyOn = true
                break
            end
        end
        if anyOn or wasOn then
            for _, name in ipairs(routines) do
                local routine = Core[name]
                if type(routine) == "function" then
                    pcall(routine)
                end
            end
        end
        wasOn = anyOn
    end
end)

----------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------

do
    local page = Window.CreatePage({ Page_Name = "Settings", Page_Title = "Settings" })

    local config = page.CreateSection("Config")
    local configName = ""
    local configList

    local function refresh()
        local ok, list = pcall(UILibrary.ConfigSystem.List)
        if ok and type(list) == "table" and configList then
            configList.GetNewList(list)
        end
    end

    if not UILibrary.HasFileSystem then
        config.CreateLabel({ Title = "Executor has no file access, so configs are disabled" })
    end

    config.CreateBox({ Title = "Config Name", Placeholder = "name", Default = "" }, safe("Config Name", function(text)
        configName = text
    end))
    configList = config.CreateDropdown({ Title = "Saved Configs", List = {}, Default = "" }, safe("Saved Configs", function(value)
        configName = value
    end))
    btn(config, "Save", function()
        if configName == "" then
            return notify("Config", "Enter a name first.")
        end
        local ok, err = UILibrary.ConfigSystem.Save(configName)
        notify("Config", ok and ("Saved " .. configName) or tostring(err))
        refresh()
    end)
    btn(config, "Load", function()
        if configName == "" then
            return notify("Config", "Pick a config first.")
        end
        local ok, err = UILibrary.ConfigSystem.Load(configName)
        notify("Config", ok and ("Loaded " .. configName) or tostring(err))
    end)
    btn(config, "Delete", function()
        if configName == "" then
            return notify("Config", "Pick a config first.")
        end
        local ok, err = UILibrary.ConfigSystem.Delete(configName)
        notify("Config", ok and ("Deleted " .. configName) or tostring(err))
        configName = ""
        refresh()
    end)
    btn(config, "Refresh List", refresh)
    refresh()

    local utility = page.CreateSection("Utility")
    btn(utility, "Stop All Features", function()
        for _, entry in ipairs(tracked) do
            entry.handle.Set(false)
        end
        if flyHandle then
            flyHandle.Set(false)
        end
        notify("Stopped", "Every farm and feature switch is off.")
    end, "Stop")
    if not coreLoaded then
        utility.CreateLabel({ Title = "Core failed to load. Rejoin and run again." })
    end
end

if not coreLoaded then
    notify("Blox Fruits", "The feature script failed to load, so switches will not work.", 8)
end
