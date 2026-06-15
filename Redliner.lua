local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
local math_acos = math.acos
local math_deg = math.deg
local math_huge = math.huge
local math_abs = math.abs
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

    LookAngleThreshold = 35,
    MinTriggerDistance = 8,
    MaxTriggerDistance = 250,
    ParryDelay = 1.5,
    ParryCooldown = 0.5,
    EntitiesFolderName = "Entities",
    HeadName = "Head",

    ESP_INTERVAL = 0.05,
    AURA_INTERVAL = 0.033,
    PARRY_INTERVAL = 0.05,
}

local STATE = {
    enabled = false,
    lastAttack = 0,
    currentTarget = nil,
    targetsInRange = {},
    lastAuraUpdate = 0,

    parryEnabled = true,
    parryCooldownUntil = 0,
    parryPending = false,
    monarchWasPresent = false,
    lastParryUpdate = 0,

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

local function safeGetCFrame(part)
    if not part then return nil end
    local ok, cf = pcall(function() return part.CFrame end)
    if ok and cf then return cf end
    return nil
end

local function safeGetLookVector(cf)
    if not cf then return nil end
    local ok, look = pcall(function() return cf.LookVector end)
    if ok and look then return look end
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

local function angleBetween(v1, v2)
    local dot = v1.X * v2.X + v1.Y * v2.Y + v1.Z * v2.Z
    local mag1 = math_sqrt(v1.X*v1.X + v1.Y*v1.Y + v1.Z*v1.Z)
    local mag2 = math_sqrt(v2.X*v2.X + v2.Y*v2.Y + v2.Z*v2.Z)
    if mag1 == 0 or mag2 == 0 then return 180 end
    local cosAngle = dot / (mag1 * mag2)
    if cosAngle > 1 then cosAngle = 1 end
    if cosAngle < -1 then cosAngle = -1 end
    local rad = math_acos(cosAngle)
    return math_deg(rad)
end

local cachedTargets = {}
local lastTargetScan = 0
local TARGET_SCAN_INTERVAL = 0.1

local function scanTargets()
    local targets = {}
    if not updateLocalPlayerCache() then return targets end

    local rangeSq = CONFIG.AURA_RANGE * CONFIG.AURA_RANGE
    local allPlayers = Players:GetPlayers()

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
        refs = {
            head = nil,
            humanoid = nil,
            root = nil,
        },
    }
end

local function removeESP(player)
    local data = espObjects[player]
    if data then
        data.hpText:Remove()
        data.postureText:Remove()
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

local ParryTargets = {}

local function getParryKey(target)
    local name = safeGetName(target)
    local ok, addr = pcall(function() return target.Address end)
    return name .. "_" .. tostring(ok and addr or "0")
end

local function findValidHead(model)
    if not model then return nil, nil, nil end

    local head = safeFindFirstChild(model, CONFIG.HeadName)
    if head then
        local pos = safeGetPosition(head)
        local cf = safeGetCFrame(head)
        local look = cf and safeGetLookVector(cf)
        if pos and look then
            return head, pos, look
        end
    end

    local nestedPaths = {
        {"Mesh", "Head"},
        {"Model", "Head"},
        {"Character", "Head"},
        {"Body", "Head"},
        {"UpperTorso", "Head"},
        {"Torso", "Head"},
    }
    for _, path in next, nestedPaths do
        local current = model
        local found = true
        for _, name in next, path do
            current = safeFindFirstChild(current, name)
            if not current then found = false break end
        end
        if found and current then
            local pos = safeGetPosition(current)
            local cf = safeGetCFrame(current)
            local look = cf and safeGetLookVector(cf)
            if pos and look then
                return current, pos, look
            end
        end
    end

    return nil, nil, nil
end

local cachedParryEntities = {}
local lastParryEntityScan = 0
local PARRY_ENTITY_SCAN_INTERVAL = 0.05

local function scanParryEntities()
    local current = {}
    local entitiesFolder = safeFindFirstChild(Workspace, CONFIG.EntitiesFolderName)
    if entitiesFolder then
        local entities = safeGetChildren(entitiesFolder)
        for _, entity in next, entities do
            if not isSelf(entity) then
                local name = safeGetName(entity)
                if not isBlockedName(name) then
                    local head, pos, look = findValidHead(entity)
                    if head and pos and look then
                        local key = getParryKey(entity)
                        current[key] = true
                        if not ParryTargets[key] then
                            ParryTargets[key] = {target = entity, lastPos = pos, lookVec = look}
                        else
                            ParryTargets[key].lastPos = pos
                            ParryTargets[key].lookVec = look
                        end
                    end
                end
            end
        end
    end

    for key in next, ParryTargets do
        if not current[key] then
            ParryTargets[key] = nil
        end
    end
    cachedParryEntities = current
end

local function updateParryTargets()
    local now = tick()
    if now - lastParryEntityScan >= PARRY_ENTITY_SCAN_INTERVAL then
        scanParryEntities()
        lastParryEntityScan = now
    end
end

local function isAnyoneLookingAtMe()
    local myPos = getMyPosition()
    if not myPos then return false, nil end

    for key, data in next, ParryTargets do
        if not data.lastPos or not data.lookVec then continue end

        local dx = data.lastPos.X - myPos.X
        local dy = data.lastPos.Y - myPos.Y
        local dz = data.lastPos.Z - myPos.Z
        local dist = math_sqrt(dx*dx + dy*dy + dz*dz)
        if dist < CONFIG.MinTriggerDistance or dist > CONFIG.MaxTriggerDistance then continue end

        local toMe = Vector3_new(myPos.X - data.lastPos.X, myPos.Y - data.lastPos.Y, myPos.Z - data.lastPos.Z)
        local angle = angleBetween(data.lookVec, toMe)

        if angle <= CONFIG.LookAngleThreshold then
            return true, safeGetName(data.target)
        end
    end
    return false, nil
end

local function getMonarchDraw()
    local temp = safeFindFirstChild(ReplicatedStorage, "Temp")
    if not temp then return nil end
    return safeFindFirstChild(temp, "MONARCH_DRAW")
end

local VK_F = 0x46

local function pressFDelayed()
    task_spawn(function()
        task_wait(CONFIG.ParryDelay)
        pcall(function()
            keypress(VK_F)
            task_wait(0.05)
            keyrelease(VK_F)
        end)
        print("[PARRY] F pressed (Monarch + Look confirmed)")
    end)
end

local function triggerParry(entityName)
    local now = tick()
    if now < STATE.parryCooldownUntil then return end
    if STATE.parryPending then return end

    print(string.format("[PARRY TRIGGER] Monarch active + %s looking at you! Delay: %.1fs", entityName, CONFIG.ParryDelay))
    pressFDelayed()
    STATE.parryCooldownUntil = now + CONFIG.ParryCooldown
    STATE.parryPending = true
    task_spawn(function()
        task_wait(CONFIG.ParryDelay + 0.1)
        STATE.parryPending = false
    end)
end

local function createUI()
    pcall(function()
        UI.AddTab("Vault", function(tab)
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

            local sec2 = tab:Section("Parry", "Right")
            sec2:Toggle("parry_enabled", "Enable Parry", true, function(val)
                STATE.parryEnabled = val
            end)
            sec2:SliderFloat("parry_delay", "Parry Delay", 0, 3, CONFIG.ParryDelay, "%.1f", function(val)
                CONFIG.ParryDelay = val
            end)
            sec2:SliderFloat("parry_cooldown", "Parry Cooldown", 0.1, 2, CONFIG.ParryCooldown, "%.2f", function(val)
                CONFIG.ParryCooldown = val
            end)
        end)
    end)
end

local running = true
local lastPlaceId = nil

local function doCleanup()
    running = false
    for player, data in next, espObjects do
        data.hpText:Remove()
        data.postureText:Remove()
    end
    espObjects = {}
    ParryTargets = {}
    healthCache = {}
    cachedTargets = {}
    STATE.enabled = false
    STATE.currentTarget = nil
    print("[Vault] Auto-cleanup triggered")
end

_G.VaultCleanup = doCleanup

local function mainLoop()
    local ok_lp, lp = pcall(function() return Players.LocalPlayer end)
    if not ok_lp or not lp then
        task_wait(0.5)
        return mainLoop()
    end
    LocalPlayer = lp
    CONFIG_SelfName = lp.Name

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            createESP(player)
        end
    end

    Players.PlayerAdded:Connect(function(player)
        if player ~= LocalPlayer and player.Name ~= LocalPlayer.Name then
            createESP(player)
        end
    end)

    Players.PlayerRemoving:Connect(removeESP)

    if espObjects[LocalPlayer] then
        removeESP(LocalPlayer)
    end

    local ok_pid, pid = pcall(function() return game.PlaceId end)
    lastPlaceId = (ok_pid and pid) or 0

    RunService.RenderStepped:Connect(function()
        if not running then return end
        local now = tick()

        local ok_place, currentPlaceId = pcall(function() return game.PlaceId end)
        if not ok_place or currentPlaceId ~= lastPlaceId then
            doCleanup()
            return
        end

        local ok_lpc, lpExists = pcall(function() return Players.LocalPlayer ~= nil end)
        if not ok_lpc or not lpExists then
            doCleanup()
            return
        end

        if now - STATE.lastESPUpdate >= CONFIG.ESP_INTERVAL then
            STATE.lastESPUpdate = now

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

                if health and maxHealth and maxHealth > 0 and health > 0 then
                    local pct = health / maxHealth
                    if pct > 1 then pct = 1 end
                    if pct < 0 then pct = 0 end

                    local hpStr = tostring(math_floor(health))
                    if hpText.Text ~= hpStr then
                        hpText.Text = hpStr
                    end
                    local newPos = Vector2_new(pos.X, pos.Y - 28)
                    if data.lastPos == nil or math_abs(newPos.X - data.lastPos.X) > 1 or math_abs(newPos.Y - data.lastPos.Y) > 1 then
                        hpText.Position = newPos
                        data.lastPos = newPos
                    end
                    hpText.Color = healthColor(pct)
                    hpText.Visible = true
                else
                    hpText.Visible = false
                end

                if posture ~= nil then
                    local postStr = tostring(math_floor(posture))
                    if postureText.Text ~= postStr then
                        postureText.Text = postStr
                    end
                    postureText.Position = Vector2_new(pos.X, pos.Y - 16)
                    postureText.Visible = true
                else
                    postureText.Visible = false
                end
            end
        end

        updateAura()

        if STATE.parryEnabled then
            local ok_parry, err_parry = pcall(function()
                updateParryTargets()

                local monarchDraw = getMonarchDraw()
                local monarchPresent = (monarchDraw ~= nil)

                if monarchPresent then
                    local isLooking, lookerName = isAnyoneLookingAtMe()
                    if isLooking then
                        triggerParry(lookerName)
                    end
                end

                STATE.monarchWasPresent = monarchPresent
            end)

            if not ok_parry then
                print("[PARRY ERROR] " .. tostring(err_parry))
            end
        end
    end)

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

    print("[Vault Combined] Loaded")
end

mainLoop()
