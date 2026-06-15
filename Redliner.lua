local pcall = pcall
local tick = tick
local task_wait = task.wait
local task_spawn = task.spawn
local ipairs = ipairs
local pairs = pairs
local next = next
local tostring = tostring
local math_floor = math.floor
local math_sqrt = math.sqrt
local math_huge = math.huge
local table_insert = table.insert
local string_lower = string.lower
local string_find = string.find
local Vector3_new = Vector3.new
local Vector2_new = Vector2.new
local Color3_fromRGB = Color3.fromRGB
local Drawing_new = Drawing.new

local CONFIG = {
    AURA_RANGE = 22.5,
    AURA_ANGLE = 180,
    AUTO_ATTACK = true,
    ATTACK_COOLDOWN = 0.15,
    TARGET_MODE = "closest",
    ESP_INTERVAL = 0.016,
    AURA_INTERVAL = 0.033,
}

local STATE = {
    enabled = false,
    lastAttack = 0,
    currentTarget = nil,
    targetsInRange = {},
    lastAuraUpdate = 0,
    lastESPUpdate = 0,
}

local BLOCKED_PATTERNS = {
    "emptydummy",
    "emptymodel",
    "dummy",
    "placeholder",
}

local function isBlockedName(name)
    if not name then return true end
    local lower = string_lower(name)
    for _, pattern in next, BLOCKED_PATTERNS do
        if string_find(lower, pattern, 1, true) then
            return true
        end
    end
    return false
end

local LocalPlayer = nil
local myChar = nil
local myRoot = nil
local myPos = nil
local CONFIG_SelfName = nil

local function fetchLocalPlayer()
    if LocalPlayer then return true end
    local ok, svc = pcall(function() return game:GetService("Players") end)
    if not ok or not svc then return false end
    local ok2, lp = pcall(function() return svc.LocalPlayer end)
    if ok2 and lp then
        LocalPlayer = lp
        CONFIG_SelfName = lp.Name
        return true
    end
    return false
end

local function updateLocalPlayerCache()
    if not fetchLocalPlayer() then return false end
    myChar = LocalPlayer.Character
    if not myChar then return false end
    myRoot = myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return false end
    local ok, pos = pcall(function() return myRoot.Position end)
    if ok and pos then
        myPos = pos
        return true
    end
    return false
end

local function getMyPosition()
    if updateLocalPlayerCache() then
        return myPos
    end
    return nil
end

local function isSelf(target)
    if not CONFIG_SelfName then return false end
    if not target then return false end
    local ok, name = pcall(function() return target.Name end)
    return ok and name == CONFIG_SelfName
end

local function safeFindFirstChild(parent, name)
    if not parent then return nil end
    local ok, child = pcall(function() return parent:FindFirstChild(name) end)
    if ok and child then return child end
    return nil
end

local function safeGetChildren(parent)
    if not parent then return {} end
    local ok, children = pcall(function() return parent:GetChildren() end)
    if ok and children then return children end
    return {}
end

local function safeGetPosition(part)
    if not part then return nil end
    local ok, pos = pcall(function() return part.Position end)
    if ok and pos then return pos end
    return nil
end

local function safeGetName(instance)
    if not instance then return "?" end
    local ok, name = pcall(function() return instance.Name end)
    if ok and name then return tostring(name) end
    return "?"
end

local healthCache = {}

local function buildHealthCache(player)
    local cache = { readOnly = nil, healthVal = nil, maxVal = nil, impactVal = nil, lastBuild = tick() }
    local ok, ro = pcall(function() return player:FindFirstChild("ReadOnly") end)
    if ok and ro then
        cache.readOnly = ro
        local ok2, hv = pcall(function() return ro:FindFirstChild("health") end)
        if ok2 and hv then cache.healthVal = hv end
        local maxNames = {"maxhealth", "maxHealth", "MaxHealth", "HealthMax"}
        for _, n in ipairs(maxNames) do
            local ok3, mv = pcall(function() return ro:FindFirstChild(n) end)
            if ok3 and mv then cache.maxVal = mv break end
        end
        local ok4, iv = pcall(function() return ro:FindFirstChild("impact") end)
        if ok4 and iv then cache.impactVal = iv end
        if not cache.impactVal then
            local altNames = {"Impact", "posture", "Posture", "stun", "Stun"}
            for _, n in ipairs(altNames) do
                local ok5, av = pcall(function() return ro:FindFirstChild(n) end)
                if ok5 and av then cache.impactVal = av break end
            end
        end
    end
    healthCache[player] = cache
    return cache
end

local function getHealthCache(player)
    local cache = healthCache[player]
    local now = tick()
    if not cache or (now - cache.lastBuild > 2) then
        cache = buildHealthCache(player)
    end
    return cache
end

local function getHealth(player)
    local cache = getHealthCache(player)
    if cache.healthVal then
        local ok, val = pcall(function() return cache.healthVal.Value end)
        if ok and val ~= nil then return val end
    end
    local ok, char = pcall(function() return player.Character end)
    if ok and char then
        local ok2, hum = pcall(function() return char:FindFirstChildOfClass("Humanoid") end)
        if ok2 and hum then
            local ok3, h = pcall(function() return hum.Health end)
            if ok3 and h ~= nil then return h end
        end
    end
    return nil
end

local function getMaxHealth(player)
    local cache = getHealthCache(player)
    if cache.maxVal then
        local ok, val = pcall(function() return cache.maxVal.Value end)
        if ok and val ~= nil then return val end
    end
    local ok, char = pcall(function() return player.Character end)
    if ok and char then
        local ok2, hum = pcall(function() return char:FindFirstChildOfClass("Humanoid") end)
        if ok2 and hum then
            local ok3, m = pcall(function() return hum.MaxHealth end)
            if ok3 and m ~= nil then return m end
        end
    end
    return nil
end

local function getPosture(player)
    local cache = getHealthCache(player)
    if cache.impactVal then
        local ok, val = pcall(function() return cache.impactVal.Value end)
        if ok and val ~= nil then return val end
    end
    local ok, readOnly = pcall(function() return player:FindFirstChild("ReadOnly") end)
    if not ok or not readOnly then return nil end
    local altNames = {"impact", "Impact", "posture", "Posture", "stun", "Stun"}
    for _, name in ipairs(altNames) do
        local ok3, val = pcall(function()
            local v = readOnly:FindFirstChild(name)
            return v and v.Value
        end)
        if ok3 and val ~= nil then return val end
    end
    return nil
end

local function distanceSq(posA, posB)
    if not posA or not posB then return math_huge end
    local dx = posB.X - posA.X
    local dy = posB.Y - posA.Y
    local dz = posB.Z - posA.Z
    return dx*dx + dy*dy + dz*dz
end

local cachedTargets = {}
local lastTargetScan = 0
local TARGET_SCAN_INTERVAL = 0.1

local function scanTargets()
    local targets = {}
    if not updateLocalPlayerCache() then return targets end
    local rangeSq = CONFIG.AURA_RANGE * CONFIG.AURA_RANGE
    local allPlayers = game:GetService("Players"):GetPlayers()
    for i = 1, #allPlayers do
        local player = allPlayers[i]
        if player ~= LocalPlayer and player.Name ~= LocalPlayer.Name and not isBlockedName(player.Name) then
            local health = getHealth(player)
            if health and health > 0 then
                local ok, char = pcall(function() return player.Character end)
                if ok and char then
                    local ok2, root = pcall(function() return char:FindFirstChild("HumanoidRootPart") end)
                    if ok2 and root then
                        local ok3, head = pcall(function() return char:FindFirstChild("Head") end)
                        local ok4, rootPos = pcall(function() return root.Position end)
                        if ok4 and rootPos then
                            local distSq = distanceSq(myPos, rootPos)
                            if distSq <= rangeSq then
                                local headPos = nil
                                if head then
                                    local ok5, hPos = pcall(function() return head.Position end)
                                    if ok5 then headPos = hPos end
                                end
                                local maxHealth = getMaxHealth(player)
                                table_insert(targets, {
                                    player = player,
                                    character = char,
                                    head = head,
                                    root = root,
                                    health = health,
                                    maxHealth = maxHealth or health,
                                    distance = math_sqrt(distSq),
                                    position = headPos or rootPos,
                                })
                            end
                        end
                    end
                end
            end
        end
    end
    return targets
end

local function getAllTargets()
    local now = tick()
    if now - lastTargetScan >= TARGET_SCAN_INTERVAL then
        cachedTargets = scanTargets()
        lastTargetScan = now
    end
    return cachedTargets
end

local function performAttack()
    local currentTime = tick()
    if currentTime - STATE.lastAttack < CONFIG.ATTACK_COOLDOWN then
        return false
    end
    STATE.lastAttack = currentTime
    pcall(mouse1click)
    return true
end

local function updateAura()
    if not STATE.enabled then return end
    local now = tick()
    if now - STATE.lastAuraUpdate < CONFIG.AURA_INTERVAL then return end
    STATE.lastAuraUpdate = now
    local targets = getAllTargets()
    STATE.targetsInRange = targets
    if #targets > 0 then
        STATE.currentTarget = targets[1]
        if CONFIG.AUTO_ATTACK then
            performAttack()
        end
    else
        STATE.currentTarget = nil
    end
end

local espObjects = {}

local function healthColor(pct)
    if pct > 0.5 then
        local t = (pct - 0.5) * 2
        return Color3_fromRGB(math_floor(255 * (1 - t)), 255, 0)
    else
        local t = pct * 2
        return Color3_fromRGB(255, math_floor(255 * t), 0)
    end
end

local function createESP(player)
    if player == LocalPlayer or player.Name == LocalPlayer.Name or isBlockedName(player.Name) then return end
    if espObjects[player] then return end
    local hpText = Drawing_new("Text")
    hpText.Size = 13
    hpText.Font = Drawing.Fonts.System
    hpText.Outline = true
    hpText.Center = true
    hpText.Visible = false
    hpText.ZIndex = 3
    local postureText = Drawing_new("Text")
    postureText.Size = 13
    postureText.Font = Drawing.Fonts.System
    postureText.Outline = true
    postureText.Center = true
    postureText.Color = Color3_fromRGB(80, 150, 255)
    postureText.Visible = false
    postureText.ZIndex = 3
    espObjects[player] = {
        player = player,
        hpText = hpText,
        postureText = postureText,
        char = nil,
        lastChar = nil,
        cachedMax = nil,
        lastHealth = nil,
        lastPosture = nil,
        lastPos = nil,
        lastPosturePos = nil,
        refs = { head = nil, humanoid = nil, root = nil },
    }
end

local function removeESP(player)
    local data = espObjects[player]
    if data then
        pcall(function() if data.hpText then data.hpText:Remove() end end)
        pcall(function() if data.postureText then data.postureText:Remove() end end)
        espObjects[player] = nil
        healthCache[player] = nil
    end
end

local function updateESPRefs(data, char)
    if not char then
        data.refs.head = nil
        data.refs.humanoid = nil
        data.refs.root = nil
        return
    end
    local ok1, head = pcall(function() return char:FindFirstChild("Head") end)
    data.refs.head = (ok1 and head) or nil
    local ok2, hum = pcall(function() return char:FindFirstChildOfClass("Humanoid") end)
    data.refs.humanoid = (ok2 and hum) or nil
    local ok3, root = pcall(function() return char:FindFirstChild("HumanoidRootPart") end)
    data.refs.root = (ok3 and root) or nil
end

local running = true
local lastPlayerList = {}

local function doCleanup()
    running = false
    for player, data in next, espObjects do
        pcall(function() if data and data.hpText then data.hpText:Remove() end end)
        pcall(function() if data and data.postureText then data.postureText:Remove() end end)
    end
    espObjects = {}
    healthCache = {}
    cachedTargets = {}
    lastPlayerList = {}
    STATE.enabled = false
    STATE.currentTarget = nil
    LocalPlayer = nil
    myChar = nil
    myRoot = nil
    myPos = nil
    CONFIG_SelfName = nil
    print("[Vault] Cleanup done")
end

_G.VaultCleanup = doCleanup

local function isGameValid()
    local ok, svc = pcall(function() return game:GetService("Players") end)
    if not ok or not svc then return false end
    local ok2, lp = pcall(function() return svc.LocalPlayer end)
    if not ok2 or not lp then return false end
    local ok3, pid = pcall(function() return game.PlaceId end)
    if not ok3 or not pid then return false end
    return true
end

local function updatePlayerList()
    local ok, allPlayers = pcall(function() return game:GetService("Players"):GetPlayers() end)
    if not ok or not allPlayers then return end
    for _, player in ipairs(allPlayers) do
        if player ~= LocalPlayer and player.Name ~= LocalPlayer.Name then
            if not lastPlayerList[player] then
                lastPlayerList[player] = true
                createESP(player)
            end
        end
    end
    for player in next, lastPlayerList do
        local stillHere = false
        for _, p in ipairs(allPlayers) do
            if p == player then
                stillHere = true
                break
            end
        end
        if not stillHere then
            lastPlayerList[player] = nil
            removeESP(player)
        end
    end
end

local function updateESP()
    for player, data in next, espObjects do
        if player == LocalPlayer or player.Name == LocalPlayer.Name then
            data.hpText.Visible = false
            data.postureText.Visible = false
            continue
        end
        local hpText = data.hpText
        local postureText = data.postureText
        local char = player.Character
        if char ~= data.lastChar then
            data.lastChar = char
            data.cachedMax = nil
            data.lastPos = nil
            data.lastPosturePos = nil
            updateESPRefs(data, char)
        end
        local head = data.refs.head
        local root = data.refs.root
        if not head or not root then
            hpText.Visible = false
            postureText.Visible = false
            continue
        end
        local ok, pos, onScreen = pcall(WorldToScreen, head.Position)
        if not ok or not onScreen then
            hpText.Visible = false
            postureText.Visible = false
            continue
        end
        local health = getHealth(player)
        local maxHealth = data.cachedMax or getMaxHealth(player)
        if maxHealth and not data.cachedMax then
            data.cachedMax = maxHealth
        end
        local posture = getPosture(player)
        local hpPos = Vector2_new(pos.X, pos.Y - 28)
        local posturePos = Vector2_new(pos.X, pos.Y - 16)
        if health and maxHealth and maxHealth > 0 and health > 0 then
            local pct = health / maxHealth
            if pct > 1 then pct = 1 end
            if pct < 0 then pct = 0 end
            hpText.Text = tostring(math_floor(health))
            hpText.Position = hpPos
            hpText.Color = healthColor(pct)
            hpText.Visible = true
        else
            hpText.Visible = false
        end
        if posture ~= nil then
            postureText.Text = tostring(math_floor(posture))
            postureText.Position = posturePos
            postureText.Visible = true
        else
            postureText.Visible = false
        end
    end
end

local function onFrame()
    if not running then return end
    if not isGameValid() then
        doCleanup()
        return
    end
    updateESP()
end

local function auraLoop()
    while running do
        if STATE.enabled then
            updateAura()
        end
        task_wait(0.01)
    end
end

local function playerPollLoop()
    while running do
        updatePlayerList()
        task_wait(0.5)
    end
end

local function createUI()
    pcall(function()
        UI.AddTab("Redliner", function(tab)
            local sec = tab:Section("Aura", "Left")
            sec:Toggle("aura_enabled", "Enable Aura", false, function(val)
                STATE.enabled = val
                if not val then STATE.currentTarget = nil end
            end)
            sec:SliderFloat("aura_range", "Range", 1, 22.5, CONFIG.AURA_RANGE, "%.1f", function(val)
                CONFIG.AURA_RANGE = val
            end)
            sec:SliderFloat("aura_cooldown", "Cooldown", 0.05, 1.0, CONFIG.ATTACK_COOLDOWN, "%.2f", function(val)
                CONFIG.ATTACK_COOLDOWN = val
            end)
        end)
    end)
end

local function mainLoop()
    local ok_lp, lp = pcall(function() return game:GetService("Players").LocalPlayer end)
    if not ok_lp or not lp then
        task_wait(0.5)
        return mainLoop()
    end
    LocalPlayer = lp
    CONFIG_SelfName = lp.Name

    local Players = game:GetService("Players")

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            createESP(player)
            lastPlayerList[player] = true
        end
    end

    if espObjects[LocalPlayer] then
        removeESP(LocalPlayer)
    end

    local ok_pid, pid = pcall(function() return game.PlaceId end)
    local lastPlaceId = (ok_pid and pid) or 0

    task_spawn(function()
        while running do
            local start = tick()
            local ok, err = pcall(onFrame)
            if not ok then
                print("[Vault FRAME ERROR] " .. tostring(err))
            end
            local elapsed = tick() - start
            local sleep = 0.016 - elapsed
            if sleep > 0 then
                task_wait(sleep)
            end
            local ok_place, currentPlaceId = pcall(function() return game.PlaceId end)
            if not ok_place or currentPlaceId ~= lastPlaceId then
                doCleanup()
                break
            end
            local ok_lpc, lpExists = pcall(function() return Players.LocalPlayer ~= nil end)
            if not ok_lpc or not lpExists then
                doCleanup()
                break
            end
        end
    end)

    task_spawn(auraLoop)
    task_spawn(playerPollLoop)

    local function init()
        if not fetchLocalPlayer() then
            task_wait(0.1)
            return init()
        end
        local attempts = 0
        while attempts < 50 do
            local ok, char = pcall(function() return LocalPlayer.Character end)
            if ok and char then
                local ok2, root = pcall(function() return char:FindFirstChild("HumanoidRootPart") end)
                if ok2 and root then
                    break
                end
            end
            task_wait(0.1)
            attempts = attempts + 1
        end
        createUI()
    end

    init()
    notify("Vault", "Cutie")
end

mainLoop()
