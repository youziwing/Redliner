local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local VK_F = 0x46
local VK_T = 0x54
local CONFIG = {
    CastigateDelay = 0.35,
    MonarchDelay = 1.25,
    ScanInterval = 0.01,
    CastigateMaxDist = 150,
    MonarchMaxDist = 50,
    PhoenixDelay = 1.5,
    PhoenixMaxDist = 50,
    ParryCooldown = 0.3,
    AngleCloseDist = 20,
    AngleFarDist = 50,
    AngleClose = 15,
    AngleFar = 17,
    CrossEnabled = true,
    GlareEnabled = true,
    PhoenixEnabled = true,
    AutoParryEnabled = true,
    BlockedPatterns = {"emptydummy", "emptymodel", "dummy", "placeholder", "testdummy", "training", "bot", "npc", "mob"},
}
local lastPressTick = 0
local seenCastigates = {}
local parriedCrosses = {}
local running = true
local toggleDebounce = false
local wasTDown = false
local lastToggleTime = 0
local STATIC_GLARE_ADDR = nil
local STATIC_PHOENIX_ADDR = nil
local glareActive = false
local function clamp(v, lo, hi)
    return v < lo and lo or (v > hi and hi or v)
end
local function safeGet(inst, prop)
    local ok, val = pcall(function() return inst[prop] end)
    return ok and val or nil
end
local function safeFind(parent, name, deep)
    if not parent then return nil end
    local ok, child = pcall(function()
        return deep and parent:FindFirstChild(name, true) or parent:FindFirstChild(name)
    end)
    return ok and child or nil
end
local function safeChildren(parent)
    if not parent then return {} end
    local ok, kids = pcall(function() return parent:GetChildren() end)
    return ok and kids or {}
end
local function dist3D(a, b)
    local ok, result = pcall(function()
        local dx = b.X - a.X
        local dy = b.Y - a.Y
        local dz = b.Z - a.Z
        return math.sqrt(dx*dx + dy*dy + dz*dz)
    end)
    return ok and result or math.huge
end
local function isBlocked(name)
    if not name then return true end
    local lower = string.lower(name)
    for _, p in ipairs(CONFIG.BlockedPatterns) do
        if string.find(lower, p, 1, true) then return true end
    end
    return false
end
local function isValidTarget(model)
    if not model or model == LocalPlayer.Character then return false end
    if isBlocked(safeGet(model, "Name")) then return false end
    return safeFind(model, "Head") or safeFind(model, "HumanoidRootPart")
end
local function getAngleThreshold(dist)
    local t = clamp((dist - CONFIG.AngleCloseDist) / (CONFIG.AngleFarDist - CONFIG.AngleCloseDist), 0, 1)
    return CONFIG.AngleClose + (CONFIG.AngleFar - CONFIG.AngleClose) * t
end
local function isLookingAtMe(enemyPos, enemyLook)
    local ok, facing, angle, dist = pcall(function()
        local char = LocalPlayer.Character
        if not char then return false, 180, 0 end
        local head = safeFind(char, "Head")
        if not head then return false, 180, 0 end
        local myPos = safeGet(head, "Position")
        if not myPos then return false, 180, 0 end
        local d = dist3D(enemyPos, myPos)
        if d > CONFIG.CastigateMaxDist then return false, 180, d end
        local toMe = (myPos - enemyPos).Unit
        local dot = enemyLook.X * toMe.X + enemyLook.Y * toMe.Y + enemyLook.Z * toMe.Z
        dot = math.max(-1, math.min(1, dot))
        if dot <= 0 then return false, 90, d end
        local a = math.deg(math.acos(dot))
        return a < getAngleThreshold(d), a, d
    end)
    if ok then return facing, angle, dist end
    return false, 180, 0
end
local function getAttackData(model)
    for _, name in ipairs({"Head", "HumanoidRootPart", "UpperTorso", "Torso", "LowerTorso"}) do
        local part = safeFind(model, name)
        if part then
            local pos = safeGet(part, "Position")
            local cf = safeGet(part, "CFrame")
            if pos and cf then
                local ok, look = pcall(function() return cf.LookVector end)
                if ok and look then return pos, look end
            end
        end
    end
    return nil, nil
end
local function findThreat()
    if not LocalPlayer then return nil end
    local char = LocalPlayer.Character
    if not char then return nil end
    local myHead = safeFind(char, "Head")
    if not myHead then return nil end
    local myPos = safeGet(myHead, "Position")
    if not myPos then return nil end
    local closest, closestDist, closestFacing = nil, math.huge, false
    local entities = safeFind(Workspace, "Entities")
    if entities then
        for _, e in ipairs(safeChildren(entities)) do
            if isValidTarget(e) then
                local pos, look = getAttackData(e)
                if pos then
                    local dist = dist3D(myPos, pos)
                    if dist < closestDist then
                        local facing, _, _ = isLookingAtMe(pos, look)
                        if facing then
                            closestDist = dist
                            closest = e
                            closestFacing = true
                        end
                    end
                end
            end
        end
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local pc = p.Character
            if pc and isValidTarget(pc) then
                local pos, look = getAttackData(pc)
                if pos then
                    local dist = dist3D(myPos, pos)
                    if dist < closestDist then
                        local facing, _, _ = isLookingAtMe(pos, look)
                        if facing then
                            closestDist = dist
                            closest = pc
                            closestFacing = true
                        end
                    end
                end
            end
        end
    end
    return closest, closestDist, closestFacing
end
local function pressF(delay)
    if not CONFIG.AutoParryEnabled then return false end
    local now = tick()
    if now - lastPressTick < CONFIG.ParryCooldown then return false end
    lastPressTick = now
    local jitter = (math.random() * 0.04) - 0.02
    local actual = math.max(0, delay + jitter)
    task.spawn(function()
        task.wait(actual)
        pcall(function()
            keypress(VK_F)
            task.wait(0.05)
            keyrelease(VK_F)
        end)
    end)
    return true
end
local function getCurrentCross()
    if not LocalPlayer or not LocalPlayer.PlayerGui then return nil end
    local vis = safeFind(LocalPlayer.PlayerGui, "VisualEffects")
    if not vis then return nil end
    local cross = safeFind(vis, "Cross")
    if cross then
        local ok, addr = pcall(function() return cross.Address end)
        return ok and addr or nil
    end
    return nil
end
local function getCurrentGlare()
    if not LocalPlayer or not LocalPlayer.PlayerGui then return nil end
    local vis = safeFind(LocalPlayer.PlayerGui, "VisualEffects", true)
    if not vis then return nil end
    local glare = safeFind(vis, "MonarchGlare")
    if glare then
        local ok, addr = pcall(function() return glare.Address end)
        if ok and addr and addr ~= STATIC_GLARE_ADDR then
            return addr
        end
    end
    return nil
end
local function getCurrentPhoenix()
    if not LocalPlayer or not LocalPlayer.PlayerGui then return nil end
    local vis = safeFind(LocalPlayer.PlayerGui, "VisualEffects", true)
    if not vis then return nil end
    local phoenix = safeFind(vis, "PhoenixGlare")
    if phoenix then
        local ok, addr = pcall(function() return phoenix.Address end)
        if ok and addr and addr ~= STATIC_PHOENIX_ADDR then
            return addr
        end
    end
    return nil
end
local function initStaticGlareAddr()
    local static = ReplicatedStorage:FindFirstChild("Assets", true)
        and ReplicatedStorage.Assets:FindFirstChild("EffectAssets", true)
        and ReplicatedStorage.Assets.EffectAssets:FindFirstChild("MonarchGlare")
    if static then
        STATIC_GLARE_ADDR = static.Address
    end
end
local function initStaticPhoenixAddr()
    local static = ReplicatedStorage:FindFirstChild("Assets", true)
        and ReplicatedStorage.Assets:FindFirstChild("EffectAssets", true)
        and ReplicatedStorage.Assets.EffectAssets:FindFirstChild("PhoenixGlare")
    if static then
        STATIC_PHOENIX_ADDR = static.Address
    end
end
local function cleanupOld(t, timeout)
    local now = tick()
    for addr, time in next, t do
        if type(time) == "number" and now - time > timeout then
            t[addr] = nil
        end
    end
end
local function doToggle()
    local now = tick()
    if toggleDebounce then return end
    if now - lastToggleTime < 0.5 then return end
    toggleDebounce = true
    lastToggleTime = now
    CONFIG.AutoParryEnabled = not CONFIG.AutoParryEnabled
    local msg = "Auto Parry: " .. (CONFIG.AutoParryEnabled and "ON" or "OFF")
    pcall(function() notify("Auto Parry", msg, 3) end)
    task.spawn(function()
        task.wait(0.5)
        toggleDebounce = false
    end)
end
local function checkTToggle()
    local isDown = false
    pcall(function() if iskeypressed then isDown = iskeypressed(VK_T) end end)
    if isDown and not wasTDown then
        doToggle()
        wasTDown = true
    elseif not isDown then
        wasTDown = false
    end
end
local function parryLoop()
    while running do
        checkTToggle()
        if CONFIG.AutoParryEnabled then
            local crossAddr = CONFIG.CrossEnabled and getCurrentCross() or nil
            local glareAddr = CONFIG.GlareEnabled and getCurrentGlare() or nil
            local now = tick()
            if crossAddr then
                if not seenCastigates[crossAddr] then
                    seenCastigates[crossAddr] = now
                end
                if not parriedCrosses[crossAddr] then
                    local _, dist, facing = findThreat()
                    if facing and dist and dist <= CONFIG.CastigateMaxDist then
                        if pressF(CONFIG.CastigateDelay) then
                            parriedCrosses[crossAddr] = true
                        end
                    end
                end
            end
            if glareAddr then
                if not seenCastigates[glareAddr] then
                    seenCastigates[glareAddr] = now
                end
                if not parriedCrosses[glareAddr] then
                    local _, dist, facing = findThreat()
                    if facing and dist and dist <= CONFIG.MonarchMaxDist then
                        if pressF(CONFIG.MonarchDelay) then
                            parriedCrosses[glareAddr] = true
                        end
                    end
                end
            end
        end
        cleanupOld(seenCastigates, 3)
        cleanupOld(parriedCrosses, 3)
        task.wait(CONFIG.ScanInterval)
    end
end
_G.LookParryCleanup = function()
    running = false
    seenCastigates = {}
    parriedCrosses = {}
    lastPressTick = 0
    CONFIG.AutoParryEnabled = true
end
initStaticGlareAddr()
task.spawn(parryLoop)
