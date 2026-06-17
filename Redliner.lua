local pcall = pcall
local tick = tick
local task_wait = task.wait
local task_spawn = task.spawn
local ipairs = ipairs
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
    AURA_RANGE = 30,
    AURA_ANGLE = 180,
    AUTO_ATTACK = true,
    ATTACK_COOLDOWN = 0.15,
    AURA_INTERVAL = 0.033,
    PARRY_USE_PRESS_RELEASE = true,
    PARRY_DOUBLE_TAP = false,
    PARRY_DOUBLE_TAP_DELAY = 0.05,
    PARRY_REQUIRE_FOCUS = true,
    PARRY_VERIFY_TARGET = true,
    TOGGLE_KEY = "r",
    ESP_TOGGLE_KEY = "p",
    ESP = {
        Weapon = true,
    },
    ESP_RANGE = 300,
    HURTBOX_TARGET_SIZE = Vector3_new(13, 13, 13),
    HURTBOX_SCAN_INTERVAL = 5,
}

local KNOWN_WEAPONS = {"Castigate", "Phoenix", "Siege", "Monarch"}

local STATE = {
    enabled = true,
    lastAttack = 0,
    currentTarget = nil,
    targetsInRange = {},
    lastAuraUpdate = 0,
    espEnabled = true,
    hurtboxSeen = {},
    entitiesFolder = nil,
}

local BLOCKED_PATTERNS = {
    "emptydummy",
    "emptymodel",
    "dummy",
    "placeholder",
}

local UserInputService = game:GetService("UserInputService")
local toggleDebounce = false
local espToggleDebounce = false

local function onKeyPress(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode[CONFIG.TOGGLE_KEY:upper()] then
        if toggleDebounce then return end
        toggleDebounce = true
        CONFIG.AUTO_ATTACK = not CONFIG.AUTO_ATTACK
        notify("Vault", "Auto Attack: " .. (CONFIG.AUTO_ATTACK and "ON" or "OFF"), 3)
        task_wait(0.3)
        toggleDebounce = false
    end
    if input.KeyCode == Enum.KeyCode[CONFIG.ESP_TOGGLE_KEY:upper()] then
        if espToggleDebounce then return end
        espToggleDebounce = true
        STATE.espEnabled = not STATE.espEnabled
        if not STATE.espEnabled then
            if espObjects then
                for p, d in next, espObjects do
                    if d then
                        if d.hpText then
                            pcall(function() d.hpText.Visible = false end)
                            pcall(function() d.hpText:Remove() end)
                        end
                        if d.postureText then
                            pcall(function() d.postureText.Visible = false end)
                            pcall(function() d.postureText:Remove() end)
                        end
                        if d.weaponText then
                            pcall(function() d.weaponText.Visible = false end)
                            pcall(function() d.weaponText:Remove() end)
                        end
                    end
                end
            end
            espObjects = {}
            healthCache = {}
            cachedTargets = {}
            lastPlayerList = {}
            notify("Vault", "ESP: REMOVED", 3)
        else
            notify("Vault", "ESP: ON", 3)
        end
        task_wait(0.3)
        espToggleDebounce = false
    end
end

UserInputService.InputBegan:Connect(onKeyPress)

local function getLocalPlayer()
    local ok, svc = pcall(function() return game:GetService("Players") end)
    if not ok or not svc then return nil end
    local ok2, lp = pcall(function() return svc.LocalPlayer end)
    return ok2 and lp or nil
end

local function getMyPosition()
    local lp = getLocalPlayer()
    if not lp then return nil end
    local ok, char = pcall(function() return lp.Character end)
    if not ok or not char then return nil end
    local ok2, root = pcall(function() return char:FindFirstChild("HumanoidRootPart") end)
    if not ok2 or not root then return nil end
    local ok3, pos = pcall(function() return root.Position end)
    return ok3 and pos or nil
end

local function isSelf(target)
    local lp = getLocalPlayer()
    if not lp or not target then return false end
    if target == lp then return true end
    local ok, tName = pcall(function() return target.Name end)
    local ok2, mName = pcall(function() return lp.Name end)
    return ok and ok2 and tName == mName
end

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

local function searchFolder(folder)
    if not folder then return nil end
    local ok, children = pcall(function() return folder:GetChildren() end)
    if not ok or not children then return nil end
    for _, child in ipairs(children) do
        local okN, cName = pcall(function() return child.Name end)
        if okN and cName then
            local name = string_lower(cName)
            for _, wName in ipairs(KNOWN_WEAPONS) do
                if string_find(name, string_lower(wName), 1, true) then
                    return wName
                end
            end
        end
    end
    return nil
end

local function getWeaponName(player, character)
    local result = searchFolder(character)
    if result then return result end
    local ok, backpack = pcall(function() return player:FindFirstChild("Backpack") end)
    if ok and backpack then
        result = searchFolder(backpack)
        if result then return result end
    end
    return "None"
end

local healthCache = {}

local function buildHealthCache(player)
    local cache = { healthVal = nil, maxVal = nil, impactVal = nil, lastBuild = tick() }
    local ok, ro = pcall(function() return player:FindFirstChild("ReadOnly") end)
    if ok and ro then
        local ok2, hv = pcall(function() return ro:FindFirstChild("health") end)
        if ok2 and hv then cache.healthVal = hv end
        local maxNames = {"maxhealth", "maxHealth", "MaxHealth", "HealthMax"}
        for _, n in ipairs(maxNames) do
            local ok3, mv = pcall(function() return ro:FindFirstChild(n) end)
            if ok3 and mv then cache.maxVal = mv break end
        end
        local altNames = {"impact", "Impact", "posture", "Posture", "stun", "Stun"}
        for _, n in ipairs(altNames) do
            local ok4, iv = pcall(function() return ro:FindFirstChild(n) end)
            if ok4 and iv then cache.impactVal = iv break end
        end
    end
    healthCache[player] = cache
    return cache
end

local function getHealthCache(player)
    local cache = healthCache[player]
    if not cache or (tick() - cache.lastBuild > 2) then
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
    local ok, ro = pcall(function() return player:FindFirstChild("ReadOnly") end)
    if not ok or not ro then return nil end
    local altNames = {"impact", "Impact", "posture", "Posture", "stun", "Stun"}
    for _, n in ipairs(altNames) do
        local ok2, val = pcall(function()
            local v = ro:FindFirstChild(n)
            return v and v.Value
        end)
        if ok2 and val ~= nil then return val end
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

local function scanTargets()
    local targets = {}
    local myPos = getMyPosition()
    if not myPos then return targets end
    local lp = getLocalPlayer()
    if not lp then return targets end
    local rangeSq = CONFIG.AURA_RANGE * CONFIG.AURA_RANGE
    local ok, all = pcall(function() return game:GetService("Players"):GetPlayers() end)
    if not ok or not all then return targets end
    for i = 1, #all do
        local p = all[i]
        if p ~= lp and not isSelf(p) then
            local okN, name = pcall(function() return p.Name end)
            if okN and name and not isBlockedName(name) then
                local health = getHealth(p)
                if health and health > 0 then
                    local okC, char = pcall(function() return p.Character end)
                    if okC and char then
                        local okR, root = pcall(function() return char:FindFirstChild("HumanoidRootPart") end)
                        if okR and root then
                            local okH, head = pcall(function() return char:FindFirstChild("Head") end)
                            local okP, rootPos = pcall(function() return root.Position end)
                            if okP and rootPos then
                                local distSq = distanceSq(myPos, rootPos)
                                if distSq <= rangeSq then
                                    local headPos = nil
                                    if head then
                                        local okHP, hPos = pcall(function() return head.Position end)
                                        if okHP then headPos = hPos end
                                    end
                                    table_insert(targets, {
                                        player = p,
                                        root = root,
                                        health = health,
                                        maxHealth = getMaxHealth(p) or health,
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
    end
    return targets
end

local function getAllTargets()
    local now = tick()
    if now - lastTargetScan >= 0.1 then
        cachedTargets = scanTargets()
        lastTargetScan = now
    end
    return cachedTargets
end

local function performAttack()
    local now = tick()
    if now - STATE.lastAttack < (CONFIG.ATTACK_COOLDOWN - 0.02) then
        return false
    end
    if CONFIG.PARRY_REQUIRE_FOCUS then
        local okF, focused = pcall(isrbxactive)
        if okF and not focused then return false end
    end
    STATE.lastAttack = now
    if CONFIG.PARRY_USE_PRESS_RELEASE then
        if pcall(mouse1press) then
            if CONFIG.PARRY_DOUBLE_TAP then
                task_wait(CONFIG.PARRY_DOUBLE_TAP_DELAY)
                pcall(mouse1release)
                task_wait(CONFIG.PARRY_DOUBLE_TAP_DELAY)
                pcall(mouse1press)
                task_wait(CONFIG.PARRY_DOUBLE_TAP_DELAY)
                pcall(mouse1release)
            else
                task_wait(0.016)
                pcall(mouse1release)
            end
            return true
        end
        return pcall(mouse1click)
    end
    return pcall(mouse1click)
end

local function updateAura()
    if not STATE.enabled then return end
    local now = tick()
    if now - STATE.lastAuraUpdate < CONFIG.AURA_INTERVAL then return end
    STATE.lastAuraUpdate = now
    local targets = getAllTargets()
    STATE.targetsInRange = targets
    if #targets > 0 then
        local target = targets[1]
        STATE.currentTarget = target
        if CONFIG.AUTO_ATTACK then
            if CONFIG.PARRY_VERIFY_TARGET and target.root then
                local ok, curPos = pcall(function() return target.root.Position end)
                local myPos = getMyPosition()
                if ok and curPos and myPos then
                    if distanceSq(myPos, curPos) <= CONFIG.AURA_RANGE * CONFIG.AURA_RANGE then
                        performAttack()
                    end
                else
                    performAttack()
                end
            else
                performAttack()
            end
        end
    else
        STATE.currentTarget = nil
    end
end

local function processHurtbox(obj)
    if not obj or not obj:IsA("BasePart") then return end
    if obj.Name ~= "Torso_Hurtbox" then return end
    if STATE.hurtboxSeen[obj] then return end
    STATE.hurtboxSeen[obj] = true
    pcall(function() obj.Size = CONFIG.HURTBOX_TARGET_SIZE end)
end

local function scanHurtboxes()
    local entities = STATE.entitiesFolder
    if not entities then
        local ok, ent = pcall(function() return workspace:FindFirstChild("Entities") end)
        if ok and ent then
            entities = ent
            STATE.entitiesFolder = ent
        else
            return
        end
    end
    local ok, parent = pcall(function() return entities.Parent end)
    if not ok or not parent then
        STATE.entitiesFolder = nil
        STATE.hurtboxSeen = {}
        return
    end
    local ok2, descendants = pcall(function() return entities:GetDescendants() end)
    if not ok2 or not descendants then return end
    for _, obj in ipairs(descendants) do
        processHurtbox(obj)
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
    local lp = getLocalPlayer()
    if not lp then return end
    if player == lp or isSelf(player) then return end
    local okN, name = pcall(function() return player.Name end)
    if not okN or not name or isBlockedName(name) then return end
    if espObjects[player] then return end
    local hp = Drawing_new("Text")
    hp.Size = 13
    hp.Font = Drawing.Fonts.System
    hp.Outline = true
    hp.Center = true
    hp.Visible = false
    hp.ZIndex = 3
    local posture = Drawing_new("Text")
    posture.Size = 13
    posture.Font = Drawing.Fonts.System
    posture.Outline = true
    posture.Center = true
    posture.Color = Color3_fromRGB(80, 150, 255)
    posture.Visible = false
    posture.ZIndex = 3
    local weapon = Drawing_new("Text")
    weapon.Size = 13
    weapon.Font = Drawing.Fonts.System
    weapon.Outline = true
    weapon.Center = true
    weapon.Color = Color3_fromRGB(255, 180, 100)
    weapon.Visible = false
    weapon.ZIndex = 3
    espObjects[player] = {
        hpText = hp,
        postureText = posture,
        weaponText = weapon,
        lastChar = nil,
        cachedMax = nil,
        cachedWeapon = nil,
        lastWeaponUpdate = 0,
        refs = { head = nil, root = nil },
    }
end

local function removeESP(player)
    local data = espObjects[player]
    if data then
        if data.hpText then
            pcall(function() data.hpText.Visible = false end)
            pcall(function() data.hpText:Remove() end)
        end
        if data.postureText then
            pcall(function() data.postureText.Visible = false end)
            pcall(function() data.postureText:Remove() end)
        end
        if data.weaponText then
            pcall(function() data.weaponText.Visible = false end)
            pcall(function() data.weaponText:Remove() end)
        end
        espObjects[player] = nil
        healthCache[player] = nil
    end
end

local function updateESP()
    if not STATE.espEnabled then return end
    local lp = getLocalPlayer()
    if not lp then return end
    if not espObjects then return end
    local myPos = getMyPosition()
    local espRangeSq = CONFIG.ESP_RANGE * CONFIG.ESP_RANGE
    local now = tick()
    for player, data in next, espObjects do
        if player == lp or isSelf(player) then
            data.hpText.Visible = false
            data.postureText.Visible = false
            data.weaponText.Visible = false
            continue
        end
        local char = nil
        local okC, c = pcall(function() return player.Character end)
        if okC then char = c end
        if char ~= data.lastChar then
            data.lastChar = char
            data.cachedMax = nil
            data.cachedWeapon = nil
            data.lastWeaponUpdate = 0
            if char then
                local okH, head = pcall(function() return char:FindFirstChild("Head") end)
                local okR, root = pcall(function() return char:FindFirstChild("HumanoidRootPart") end)
                data.refs.head = okH and head or nil
                data.refs.root = okR and root or nil
            else
                data.refs.head = nil
                data.refs.root = nil
            end
        end
        local head = data.refs.head
        if not head then
            data.hpText.Visible = false
            data.postureText.Visible = false
            data.weaponText.Visible = false
            continue
        end
        if myPos and data.refs.root and CONFIG.ESP_RANGE > 0 then
            local okRP, rootPos = pcall(function() return data.refs.root.Position end)
            if okRP and rootPos and distanceSq(myPos, rootPos) > espRangeSq then
                data.hpText.Visible = false
                data.postureText.Visible = false
                data.weaponText.Visible = false
                continue
            end
        end
        local ok, pos, onScreen = pcall(WorldToScreen, head.Position)
        if not ok or not onScreen or not pos then
            data.hpText.Visible = false
            data.postureText.Visible = false
            data.weaponText.Visible = false
            continue
        end
        local health = getHealth(player)
        local maxHealth = data.cachedMax or getMaxHealth(player)
        if maxHealth and not data.cachedMax then data.cachedMax = maxHealth end
        local posture = getPosture(player)
        local hpPos = Vector2_new(pos.X, pos.Y - 28)
        local ppPos = Vector2_new(pos.X, pos.Y - 16)
        local wpPos = Vector2_new(pos.X, pos.Y - 4)
        if health and maxHealth and maxHealth > 0 and health > 0 then
            local pct = health / maxHealth
            if pct > 1 then pct = 1 elseif pct < 0 then pct = 0 end
            data.hpText.Text = tostring(math_floor(health))
            data.hpText.Position = hpPos
            data.hpText.Color = healthColor(pct)
            data.hpText.Visible = true
        else
            data.hpText.Visible = false
        end
        if posture ~= nil then
            data.postureText.Text = tostring(math_floor(posture))
            data.postureText.Position = ppPos
            data.postureText.Visible = true
        else
            data.postureText.Visible = false
        end
        if CONFIG.ESP.Weapon then
            if not data.cachedWeapon or (now - data.lastWeaponUpdate > 1) then
                data.cachedWeapon = getWeaponName(player, char)
                data.lastWeaponUpdate = now
            end
            data.weaponText.Text = data.cachedWeapon
            data.weaponText.Position = wpPos
            data.weaponText.Visible = true
        else
            data.weaponText.Visible = false
        end
    end
end

local lastPlayerList = {}

local function updatePlayerList()
    if not STATE.espEnabled then return end
    local lp = getLocalPlayer()
    if not lp then return end
    local ok, all = pcall(function() return game:GetService("Players"):GetPlayers() end)
    if not ok or not all then return end
    for _, p in ipairs(all) do
        if p ~= lp and not isSelf(p) and not lastPlayerList[p] then
            lastPlayerList[p] = true
            createESP(p)
        end
    end
    for p in next, lastPlayerList do
        local here = false
        for _, v in ipairs(all) do if v == p then here = true break end end
        if not here then
            lastPlayerList[p] = nil
            removeESP(p)
        end
    end
end

local running = true

local function doCleanup()
    running = false
    STATE.enabled = false
    STATE.currentTarget = nil
    if espObjects then
        for p, d in next, espObjects do
            if d then
                if d.hpText then
                    pcall(function() d.hpText.Visible = false end)
                    pcall(function() d.hpText:Remove() end)
                end
                if d.postureText then
                    pcall(function() d.postureText.Visible = false end)
                    pcall(function() d.postureText:Remove() end)
                end
                if d.weaponText then
                    pcall(function() d.weaponText.Visible = false end)
                    pcall(function() d.weaponText:Remove() end)
                end
            end
        end
    end
    espObjects = {}
    healthCache = {}
    cachedTargets = {}
    lastPlayerList = {}
    STATE.hurtboxSeen = {}
    STATE.entitiesFolder = nil
end

_G.VaultCleanup = doCleanup

local function isGameValid()
    local ok, svc = pcall(function() return game:GetService("Players") end)
    if not ok or not svc then return false end
    local ok2, lp = pcall(function() return svc.LocalPlayer end)
    if not ok2 or not lp then return false end
    local ok3, pid = pcall(function() return game.PlaceId end)
    return ok3 and pid ~= nil
end

local function onFrame()
    if not running then return end
    if not isGameValid() then doCleanup() return end
    updateESP()
end

local function auraLoop()
    while running do
        if STATE.enabled then pcall(updateAura) end
        task_wait(0.01)
    end
end

local function playerPollLoop()
    while running do
        pcall(updatePlayerList)
        task_wait(0.5)
    end
end

local function hurtboxLoop()
    task_wait(1)
    while running do
        pcall(scanHurtboxes)
        task_wait(CONFIG.HURTBOX_SCAN_INTERVAL)
    end
end

local function espFrameLoop()
    while running do
        local start = tick()
        pcall(onFrame)
        local elapsed = tick() - start
        local sleep = 0.016 - elapsed
        if sleep > 0 then task_wait(sleep) end

        local okP, curId = pcall(function() return game.PlaceId end)
        local ok_pid, pid = pcall(function() return game.PlaceId end)
        local lastPlaceId = ok_pid and pid or 0
        if not okP or curId ~= lastPlaceId then doCleanup() break end
        local okL, exists = pcall(function() return game:GetService("Players").LocalPlayer ~= nil end)
        if not okL or not exists then doCleanup() break end
    end
end

local function mainLoop()
    STATE.enabled = true
    STATE.currentTarget = nil
    local lp = nil
    for _ = 1, 100 do
        lp = getLocalPlayer()
        if lp then break end
        task_wait(0.1)
    end
    if not lp then return end
    local Players = game:GetService("Players")
    local ok, all = pcall(function() return Players:GetPlayers() end)
    if ok and all then
        for _, p in ipairs(all) do
            if p ~= lp and not isSelf(p) then
                if STATE.espEnabled then
                    createESP(p)
                    lastPlayerList[p] = true
                end
            end
        end
    end
    if espObjects[lp] then removeESP(lp) end
    local ok_pid, pid = pcall(function() return game.PlaceId end)
    local lastPlaceId = ok_pid and pid or 0

    task_spawn(espFrameLoop)
    task_spawn(auraLoop)
    task_spawn(playerPollLoop)
    task_spawn(hurtboxLoop)

    for _ = 1, 50 do
        local char = getMyPosition()
        if char then break end
        task_wait(0.1)
    end
end

pcall(mainLoop)

notify("Vault", "Cutie Patootie", 7)
