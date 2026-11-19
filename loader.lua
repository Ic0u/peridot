

local Loader = {}

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local BASE_URL = "https://raw.githubusercontent.com/Ic0u/peridot/main/"
local UNIVERSAL_URL = BASE_URL .. "scripts/Universal.lua"
local GUI_NAME = "PeridotLoaderGui"
local LOGO_IMAGE = "rbxassetid://97933423096090" -- the Peridot logo, same as the main window
local ACCENT = Color3.fromRGB(140, 172, 68) -- Peridot green
local DEFAULT_GAMES = {
    ["2753915549"] = "Blox Fruits - First Sea",
    ["4442272183"] = "Blox Fruits - Second Sea",
    ["7449423635"] = "Blox Fruits - Third Sea",
    ["85211729168715"] = "Blox Fruits",
    ["79091703265657"] = "Blox Fruits",
    ["100117331123089"] = "Blox Fruits",
    ["142823291"] = "Murder Mystery 2",
}

local function resolveRequestFunction()
    local environment = (getgenv and getgenv()) or _G
    local synapse = environment.syn
    local fluxus = environment.fluxus
    local http = environment.http

    local candidate = environment.request
        or environment.http_request
        or (synapse and synapse.request)
        or (fluxus and fluxus.request)
        or (http and http.request)

    return type(candidate) == "function" and candidate or nil
end

local requestFunction = resolveRequestFunction()

local function fetchText(url)
    if requestFunction then
        local requested, response = pcall(requestFunction, {
            Url = url,
            Method = "GET",
            Headers = {
                ["Accept"] = "text/plain",
                ["Cache-Control"] = "no-cache",
            },
        })

        if requested and type(response) == "string" and response ~= "" then
            return response
        end

        if requested and type(response) == "table" then
            local statusCode = tonumber(response.StatusCode or response.Status)
            local body = response.Body or response.body
            if type(body) == "string" and body ~= ""
                and response.Success ~= false
                and (not statusCode or (statusCode >= 200 and statusCode < 300)) then
                return body
            end
        end
    end

    local fetched, body = pcall(game.HttpGet, game, url)
    if fetched and type(body) == "string" and body ~= "" then
        return body
    end

    return nil
end

local function tween(instance, duration, properties, style, direction)
    local animation = TweenService:Create(
        instance,
        TweenInfo.new(duration, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out),
        properties
    )
    animation:Play()
    return animation
end

local function getPlayerGui()
    local player = Players.LocalPlayer or Players.PlayerAdded:Wait()
    return player:WaitForChild("PlayerGui")
end

local function getGuiParent()
    local ok, coreGui = pcall(game.GetService, game, "CoreGui")
    if ok and coreGui then
        return coreGui
    end

    return getPlayerGui()
end

local function parentGui(screenGui)
    local preferredParent = getGuiParent()
    local didParent = pcall(function()
        screenGui.Parent = preferredParent
    end)

    if not didParent then
        screenGui.Parent = getPlayerGui()
    end
end

local function destroyExisting()
    local coreGuiOk, coreGui = pcall(game.GetService, game, "CoreGui")
    if coreGuiOk and coreGui then
        local existing = coreGui:FindFirstChild(GUI_NAME)
        if existing then
            existing:Destroy()
        end
    end

    local existing = getPlayerGui():FindFirstChild(GUI_NAME)
    if existing then
        existing:Destroy()
    end
end

-- The intro card: a small dark panel in the middle of the screen with the logo, "Peridot"
-- in green, and one white status line underneath.
local function createCard(parent)
    -- A CanvasGroup fades everything together, but it clips its children, so it is 8px larger
    -- than the panel to leave room for the panel's outline.
    local group = Instance.new("CanvasGroup")
    group.Name = "Card"
    group.AnchorPoint = Vector2.new(0.5, 0.5)
    group.Position = UDim2.fromScale(0.5, 0.5)
    group.Size = UDim2.fromOffset(308, 120)
    group.BackgroundTransparency = 1
    group.BorderSizePixel = 0
    group.GroupTransparency = 1
    group.Parent = parent

    local scale = Instance.new("UIScale")
    scale.Scale = 0.9
    scale.Parent = group

    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.Size = UDim2.new(1, -8, 1, -8)
    panel.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
    panel.BackgroundTransparency = 0.06
    panel.BorderSizePixel = 0
    panel.Parent = group

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = panel

    local outline = Instance.new("UIStroke")
    outline.Color = Color3.fromRGB(205, 210, 196)
    outline.Thickness = 1.5
    outline.Transparency = 0.45
    outline.Parent = panel

    local logo = Instance.new("ImageLabel")
    logo.Name = "Logo"
    logo.BackgroundTransparency = 1
    logo.Image = LOGO_IMAGE
    logo.Position = UDim2.fromOffset(14, 12)
    logo.Size = UDim2.fromOffset(24, 24)
    logo.ScaleType = Enum.ScaleType.Fit
    logo.Parent = panel

    local brand = Instance.new("TextLabel")
    brand.Name = "Brand"
    brand.BackgroundTransparency = 1
    brand.Position = UDim2.fromOffset(46, 10)
    brand.Size = UDim2.new(1, -60, 0, 28)
    brand.Font = Enum.Font.GothamBold
    brand.Text = "Peridot"
    brand.TextColor3 = ACCENT
    brand.TextSize = 18
    brand.TextXAlignment = Enum.TextXAlignment.Left
    brand.Parent = panel

    local status = Instance.new("TextLabel")
    status.Name = "Status"
    status.AnchorPoint = Vector2.new(0.5, 0.5)
    status.BackgroundTransparency = 1
    status.Position = UDim2.new(0.5, 0, 0, 74)
    status.Size = UDim2.new(1, -28, 0, 30)
    status.Font = Enum.Font.GothamBold
    status.Text = "Authenticating"
    status.TextColor3 = Color3.fromRGB(242, 242, 238)
    status.TextSize = 19
    status.TextTruncate = Enum.TextTruncate.AtEnd
    status.Parent = panel

    return { Group = group, Scale = scale, Status = status, StatusPosition = status.Position }
end

-- games.json maps place ids to game names; without it, the built-in list above.
local function fetchGameRegistry()
    local response = fetchText(BASE_URL .. "games.json")
    if not response then
        return DEFAULT_GAMES
    end

    local decodedOk, registry = pcall(HttpService.JSONDecode, HttpService, response)
    if decodedOk and type(registry) == "table" then
        return registry
    end

    return DEFAULT_GAMES
end

-- name to show, script to run, and whether this game has its own script
local function resolveGame(registry)
    local placeId = tostring(game.PlaceId)
    local name = registry[placeId]
    if type(name) == "string" and name ~= "" then
        return { name = name, url = BASE_URL .. "games/" .. placeId .. ".lua", supported = true }
    end
    return { name = "Universal", url = UNIVERSAL_URL, supported = false }
end

local function runSource(url)
    local source = fetchText(url)
    if not source then
        return false
    end

    local compiled = loadstring(source)
    if not compiled then
        return false
    end

    return pcall(compiled)
end

-- onComplete, when given, runs instead of the game script and receives { name, url, supported }.
function Loader.Start(onComplete)
    if Loader._running then
        return nil
    end
    Loader._running = true

    destroyExisting()

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = GUI_NAME
    screenGui.DisplayOrder = 1000000
    screenGui.IgnoreGuiInset = true
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pcall(function()
        screenGui.OnTopOfCoreBlur = true
    end)
    parentGui(screenGui)

    local card = createCard(screenGui)

    local function setStatus(text)
        local base = card.StatusPosition
        local out = tween(card.Status, 0.12, { TextTransparency = 1, Position = base + UDim2.fromOffset(0, -4) },
            Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        out.Completed:Wait()
        card.Status.Text = text
        card.Status.Position = base + UDim2.fromOffset(0, 6)
        local back = tween(card.Status, 0.22, { TextTransparency = 0, Position = base })
        back.Completed:Wait()
    end

    task.spawn(function()
        -- pop in
        tween(card.Scale, 0.38, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        local shown = tween(card.Group, 0.3, { GroupTransparency = 0 })
        shown.Completed:Wait()

        -- "Authenticating" with moving dots while the game list loads (at least three steps)
        local info
        task.spawn(function()
            info = resolveGame(fetchGameRegistry())
        end)
        local step = 0
        while not info or step < 3 do
            step = step + 1
            card.Status.Text = "Authenticating" .. string.rep(".", step % 4)
            task.wait(0.32)
        end

        setStatus("Success !")
        task.wait(0.6)
        setStatus(info.name)
        task.wait(1)

        -- ease out, then hand over to the game script
        tween(card.Scale, 0.3, { Scale = 0.92 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
        local hidden = tween(card.Group, 0.3, { GroupTransparency = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
        hidden.Completed:Wait()
        if screenGui.Parent then
            screenGui:Destroy()
        end

        Loader._running = false
        task.spawn(function()
            local ok, err
            if onComplete then
                ok, err = pcall(onComplete, info)
            else
                ok, err = pcall(runSource, info.url)
            end
            if not ok then
                warn("Peridot loader callback failed:", err)
            end
        end)
    end)

    return screenGui
end

return Loader
