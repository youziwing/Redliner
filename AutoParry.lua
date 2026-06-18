local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local plr = Players.LocalPlayer
local cam = Workspace.CurrentCamera

if not plr or not cam then 
    warn("bruh where's the player/camera")
    return 
end

local SETTINGS = {
    AutoParry = true,
    ParryKey = "F",
    ToggleKey = "T",

    CastigateDelay = 0.45,
    CastigateRange = 500,

    GlareDelay = 1.5,
    GlareRange = 50,

    Cooldown = 0.3,
    ScanRate = 0.01,

    MaxDist = 500,
    LineLength = 8,
    LineThick = 1.5,
    LineAlpha = 0.6,
    ShowNames = true,
    ShowDist = true,

    AngleClose = 23,
    AngleFar = 10,
    AngleCloseDist = 20,
    AngleFarDist = 50,
}

local VK_F = 0x46
local VK_T = 0x54
local lastParry = 0
local running = true

local crosses = {}     
parriedCrosses = {}     
local glares = {}       
parriedGlares = {}      

local lines = {}
local texts = {}
local dots = {}
local activeKeys = {}
local targets = {}

local glareStaticAddr = nil

local function getDist(a, b)
    return (a - b).Magnitude
end

local function getAngle(fromPos, fromLook, toPos)
    local toTarget = (toPos - fromPos).Unit
    local dot = fromLook:Dot(toTarget)
    dot = math.clamp(dot, -1, 1)
    return math.deg(math.acos(dot))
end

local function getDynAngle(dist)
    local t = math.clamp((dist - SETTINGS.AngleCloseDist) / (SETTINGS.AngleFarDist - SETTINGS.AngleCloseDist), 0, 1)
    return SETTINGS.AngleClose + (SETTINGS.AngleFar - SETTINGS.AngleClose) * t
end

local function initGlareAddr()
    local assets = ReplicatedStorage:FindFirstChild("Assets", true)
    if not assets then return end
    local effectAssets = assets:FindFirstChild("EffectAssets", true)
    if not effectAssets then return end
    local monarchGlare = effectAssets:FindFirstChild("MonarchGlare")
    if monarchGlare then
        local ok, addr = pcall(function() return monarchGlare.Address end)
        if ok then glareStaticAddr = addr end
    end
end

local function getTargets()
    local current = {}
    local folder = Workspace:FindFirstChild("Entities")
    if folder then
        for _, e in ipairs(folder:GetChildren()) do
            if e.Name ~= plr.Name then
                local key = e.Name .. "_" .. tostring(e.Address or "0")
                current[key] = true
                if not targets[key] then
                    targets[key] = e
                end
            end
        end
    end

    -- cleanup dead targets
    for key in pairs(targets) do
        if not current[key] then
            targets[key] = nil
            if lines[key] then lines[key].Visible = false end
            if texts[key] then texts[key].Visible = false end
            if dots[key] then dots[key].Visible = false end
            activeKeys[key] = nil
        end
    end
end

local function getAttackData(model)
    if not model then return nil, nil end

    local head = model:FindFirstChild("Head")
    if head then
        return head.Position, head.CFrame.LookVector
    end

    for _, name in ipairs({"HumanoidRootPart", "UpperTorso", "Torso", "LowerTorso"}) do
        local part = model:FindFirstChild(name)
        if part then
            return part.Position, part.CFrame.LookVector
        end
    end

    return nil, nil
end

local function getLine(key)
    if not lines[key] then
        lines[key] = Drawing.new("Line")
        lines[key].Color = Color3.new(1, 0.2, 0.2)
    end
    return lines[key]
end

local function getDot(key)
    if not dots[key] then
        dots[key] = Drawing.new("Circle")
        dots[key].Color = Color3.new(1, 0.8, 0.2)
        dots[key].Filled = true
    end
    return dots[key]
end

local function getText(key)
    if not texts[key] then
        texts[key] = Drawing.new("Text")
        texts[key].Color = Color3.new(1, 1, 1)
        texts[key].Outline = true
        texts[key].Center = false
    end
    return texts[key]
end

local function hide(key)
    if lines[key] then lines[key].Visible = false end
    if texts[key] then texts[key].Visible = false end
    if dots[key] then dots[key].Visible = false end
    activeKeys[key] = nil
end

local function updateVisuals()
    local camPos = cam.CFrame.Position

    for key, target in pairs(targets) do
        local pos, look = getAttackData(target)
        if not pos or not look then
            hide(key)
            continue
        end

        local dist = getDist(camPos, pos)
        if dist > SETTINGS.MaxDist then
            hide(key)
            continue
        end

        local endPos = pos + look * SETTINGS.LineLength
        local sp1, on1 = cam:WorldToViewportPoint(pos)
        local sp2, on2 = cam:WorldToViewportPoint(endPos)

        if not on1 or not on2 then
            hide(key)
            continue
        end

        local s1 = Vector2.new(math.floor(sp1.X + 0.5), math.floor(sp1.Y + 0.5))
        local s2 = Vector2.new(math.floor(sp2.X + 0.5), math.floor(sp2.Y + 0.5))

        local alpha = 1
        local thick = SETTINGS.LineThick
        if dist > 100 then
            alpha = math.clamp(1 - (dist - 100) / (SETTINGS.MaxDist - 100), 0.2, 1)
            thick = math.max(0.5, SETTINGS.LineThick * alpha)
        end

        local line = getLine(key)
        line.From = s1
        line.To = s2
        line.Thickness = thick
        line.Transparency = alpha * SETTINGS.LineAlpha
        line.Visible = true

        local dot = getDot(key)
        dot.Position = s2
        dot.Radius = math.floor(thick * 2 + 1)
        dot.Transparency = alpha * 0.8
        dot.Visible = true

        if SETTINGS.ShowNames or SETTINGS.ShowDist then
            local text = getText(key)
            local str = ""
            if SETTINGS.ShowNames then str = target.Name end
            if SETTINGS.ShowDist then
                if str ~= "" then str = str .. " " end
                str = str .. "[" .. math.floor(dist) .. "m]"
            end
            text.Text = str
            text.Size = 13
            text.Position = Vector2.new(s1.X + 8, s1.Y - 8)
            text.Transparency = alpha
            text.Visible = true
        end

        activeKeys[key] = true
    end

    for key in pairs(lines) do
        if not activeKeys[key] then
            hide(key)
        end
    end
    for key in pairs(activeKeys) do
        activeKeys[key] = nil
    end
end

local function isFacingMe(enemyPos, enemyLook, maxDist)
    local char = plr.Character
    if not char then return false, 180, 0 end
    local head = char:FindFirstChild("Head")
    if not head then return false, 180, 0 end

    local myPos = head.Position
    local dist = getDist(enemyPos, myPos)
    if dist > maxDist then return false, 180, dist end

    local angle = getAngle(enemyPos, enemyLook, myPos)
    local threshold = getDynAngle(dist)

    return angle < threshold, angle, dist
end

local function getClosestThreat(maxDist)
    local char = plr.Character
    if not char then return nil, math.huge, false end
    local head = char:FindFirstChild("Head")
    if not head then return nil, math.huge, false end

    local myPos = head.Position
    local closestKey, closestDist = nil, math.huge
    local isFacing = false

    for key, target in pairs(targets) do
        local pos, look = getAttackData(target)
        if pos then
            local dist = getDist(myPos, pos)
            if dist < closestDist and dist <= maxDist then
                closestDist = dist
                closestKey = key
                if look then
                    isFacing = select(1, isFacingMe(pos, look, maxDist))
                end
            end
        end
    end

    return closestKey, closestDist, isFacing
end

local function doParry(delay)
    if not SETTINGS.AutoParry then return false end

    local now = tick()
    if now - lastParry < SETTINGS.Cooldown then return false end
    lastParry = now

    local jitter = (math.random() * 0.04) - 0.02  -- +/- 0.02s jitter
    local actualDelay = math.max(0, delay + jitter)

    task.spawn(function()
        task.wait(actualDelay)
        pcall(function()
            keypress(VK_F)
            task.wait(0.05)
            keyrelease(VK_F)
        end)
    end)

    return true
end

local function getCurrentCross()
    if not plr.PlayerGui then return nil end
    local vis = plr.PlayerGui:FindFirstChild("VisualEffects")
    if not vis then return nil end
    local cross = vis:FindFirstChild("Cross")
    if cross then
        return tostring(cross.Address)
    end
    return nil
end

local function getCurrentGlare()
    if not plr.PlayerGui then return nil end
    local vis = plr.PlayerGui:FindFirstChild("VisualEffects", true)
    if not vis then return nil end
    local glare = vis:FindFirstChild("MonarchGlare")
    if not glare then return nil end
    local addr = tostring(glare.Address)
    if addr == glareStaticAddr then return nil end
    return addr
end

local function tryParry(delay, maxDist, addr, parriedTable)
    if not SETTINGS.AutoParry then return false end

    local _, threatDist, facing = getClosestThreat(maxDist)

    if facing then
        local didParry = doParry(delay * 0.85)
        if didParry then
            parriedTable[addr] = true
            return true
        end
    end

    return false
end

local toggleText = nil

local function updateToggle()
    if not toggleText then
        toggleText = Drawing.new("Text")
        toggleText.Size = 14
        toggleText.Font = Drawing.Fonts.SystemBold
        toggleText.Outline = true
        toggleText.Position = Vector2.new(20, 60)
        toggleText.ZIndex = 100
    end

    if SETTINGS.AutoParry then
        toggleText.Text = "PARRY: ON [T]"
        toggleText.Color = Color3.new(0.2, 1, 0.2)
    else
        toggleText.Text = "PARRY: OFF [T]"
        toggleText.Color = Color3.new(1, 0.2, 0.2)
    end
    toggleText.Visible = true
end

local function toggle()
    SETTINGS.AutoParry = not SETTINGS.AutoParry
    local msg = "Auto Parry: " .. (SETTINGS.AutoParry and "ON" or "OFF")
    pcall(function() notify("Auto Parry", msg, 3) end)
    updateToggle()
end

local UIS = game:GetService("UserInputService")
UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.T then
        toggle()
    end
end)

local function parryLoop()
    while running do
        getTargets()

        if SETTINGS.AutoParry then
            local now = tick()
            local crossAddr = getCurrentCross()
            local glareAddr = getCurrentGlare()

            if crossAddr then
                if not crosses[crossAddr] then
                    crosses[crossAddr] = now
                end
                if not parriedCrosses[crossAddr] then
                    tryParry(SETTINGS.CastigateDelay, SETTINGS.CastigateRange, crossAddr, parriedCrosses)
                end
            end

            -- monarch glare
            if glareAddr then
                if not glares[glareAddr] then
                    glares[glareAddr] = now
                end
                if not parriedGlares[glareAddr] then
                    tryParry(SETTINGS.GlareDelay, SETTINGS.GlareRange, glareAddr, parriedGlares)
                end
            end
        end

        local now = tick()
        for addr, time in pairs(crosses) do
            if now - time > 3 then
                crosses[addr] = nil
                parriedCrosses[addr] = nil
            end
        end
        for addr, time in pairs(glares) do
            if now - time > 3 then
                glares[addr] = nil
                parriedGlares[addr] = nil
            end
        end

        task.wait(SETTINGS.ScanRate)
    end
end

local function visualLoop()
    while running do
        getTargets()
        updateVisuals()
        updateToggle()
        task.wait(0.016)  
    end
end

_G.ParryCleanup = function()
    running = false
    if toggleText then
        pcall(function() toggleText:Remove() end)
        toggleText = nil
    end
    for _, t in pairs({lines, dots, texts}) do
        for _, obj in pairs(t) do
            pcall(function() obj:Remove() end)
        end
    end
    lines, dots, texts = {}, {}, {}
    activeKeys = {}
    targets = {}
    crosses, parriedCrosses = {}, {}
    glares, parriedGlares = {}, {}
    lastParry = 0
    SETTINGS.AutoParry = true
end

initGlareAddr()
task.spawn(parryLoop)
task.spawn(visualLoop)

print("Auto Parry loaded | Press T to toggle")
