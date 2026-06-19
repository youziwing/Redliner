local tick = tick
local task_wait = task.wait
local task_spawn = task.spawn
local ipairs = ipairs
local next = next
local tostring = tostring
local math_floor = math.floor
local math_sqrt = math.sqrt
local math_huge = math.huge
local math_max = math.max
local math_min = math.min
local math_abs = math.abs
local math_acos = math.acos
local math_deg = math.deg
local table_insert = table.insert
local table_sort = table.sort
local string_lower = string.lower
local string_find = string.find
local string_sub = string.sub
local string_byte = string.byte
local Vector3_new = Vector3.new
local Vector2_new = Vector2.new
local Color3_fromRGB = Color3.fromRGB
local Drawing_new = Drawing.new
local pcall = pcall
local CONFIG = {
    AURA_RANGE = 30,
    AURA_ANGLE = 180,
    AUTO_ATTACK = true,
    ATTACK_COOLDOWN = 0.15,
    AURA_INTERVAL = 0.05,
    ESP_UPDATE_RATE = 0.008,
    ESP_RENDER_RATE = 0.008,
    PLAYER_SCAN_RATE = 0.3,
    HURTBOX_SCAN_INTERVAL = 8,
    HURTBOX_TARGET_SIZE = Vector3_new(13, 13, 13),
    HURTBOX_NORMAL_SIZE = Vector3_new(2.1, 2.1, 1.05),
    TOGGLE_KEY = "r",
    ESP_TOGGLE_KEY = "p",
    HITBOX_TOGGLE_KEY = "h",
    ESP = { Weapon = true },
    BLOCKED_PATTERNS = {
        "emptydummy", "emptymodel", "dummy", "placeholder",
        "testdummy", "training", "bot", "npc", "mob",
    },
}
local KNOWN_WEAPONS = {"Castigate", "Phoenix", "Siege", "Monarch"}
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local STATE = {
    enabled = true,
    lastAttack = 0,
    currentTarget = nil,
    targetsInRange = {},
    lastAuraUpdate = 0,
    espEnabled = true,
    hurtboxLarge = true,
    entitiesFolder = nil,
    myPos = nil,
    myLook = nil,
    lastPosUpdate = 0,
}
local function getMyData()
    local now = tick()
    if now - STATE.lastPosUpdate < 0.05 then
        return STATE.myPos, STATE.myLook
    end
    local lp = Players.LocalPlayer
    if not lp then return nil, nil end
    local char = lp.Character
    if not char then return nil, nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil, nil end
    local pos = root.Position
    local look = root.CFrame.LookVector
    STATE.myPos = pos
    STATE.myLook = look
    STATE.lastPosUpdate = now
    return pos, look
end
local function angleBetween(vecA, vecB)
    local dot = vecA.X * vecB.X + vecA.Y * vecB.Y + vecA.Z * vecB.Z
    dot = math_max(-1, math_min(1, dot))
    return math_deg(math_acos(dot))
end
local function isSelf(target)
    local lp = Players.LocalPlayer
    if not lp or not target then return false end
    if target == lp then return true end
    return target.Name == lp.Name
end
local function isBlockedName(name)
    if not name or name == "" then return true end
    local lower = string_lower(name)
    for i = 1, #CONFIG.BLOCKED_PATTERNS do
        if string_find(lower, CONFIG.BLOCKED_PATTERNS[i], 1, true) then
            return true
        end
    end
    return false
end
local function isBlockedPlayer(player)
    if isSelf(player) then return true end
    if isBlockedName(player.Name) then return true end
    local char = player.Character
    if char and isBlockedName(char.Name) then return true end
    return false
end
local function isRealPlayer(player)
    if isBlockedPlayer(player) then return false end
    local ro = player:FindFirstChild("ReadOnly")
    if ro then
        local hv = ro:FindFirstChild("health")
        if hv and hv.Value ~= nil then return true end
    end
    local char = player.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then return true end
    end
    return false
end
local function distanceSq(posA, posB)
    if not posA or not posB then return math_huge end
    local dx = posB.X - posA.X
    local dy = posB.Y - posA.Y
    local dz = posB.Z - posA.Z
    return dx*dx + dy*dy + dz*dz
end
local function searchFolder(folder)
    if not folder then return nil end
    local children = folder:GetChildren()
    for i = 1, #children do
        local child = children[i]
        if child then
            local cName = child.Name
            if cName then
                local name = string_lower(cName)
                for j = 1, #KNOWN_WEAPONS do
                    if string_find(name, string_lower(KNOWN_WEAPONS[j]), 1, true) then
                        return KNOWN_WEAPONS[j]
                    end
                end
            end
        end
    end
    return nil
end
local function getWeaponName(player, character)
    if character then
        local result = searchFolder(character)
        if result then return result end
    end
    if player then
        local backpack = player:FindFirstChild("Backpack")
        if backpack then
            local result = searchFolder(backpack)
            if result then return result end
        end
    end
    return "None"
end
local healthCache = {}
local function buildHealthCache(player)
    local cache = { healthVal = nil, maxVal = nil, impactVal = nil, lastBuild = tick() }
    local ro = player:FindFirstChild("ReadOnly")
    if ro then
        local hv = ro:FindFirstChild("health")
        if hv then cache.healthVal = hv end
        local maxNames = {"maxhealth", "maxHealth", "MaxHealth", "HealthMax"}
        for i = 1, #maxNames do
            local mv = ro:FindFirstChild(maxNames[i])
            if mv then cache.maxVal = mv break end
        end
        local altNames = {"impact", "Impact", "posture", "Posture", "stun", "Stun"}
        for i = 1, #altNames do
            local iv = ro:FindFirstChild(altNames[i])
            if iv then cache.impactVal = iv break end
        end
    end
    healthCache[player] = cache
    return cache
end
local function getHealthCache(player)
    local cache = healthCache[player]
    if not cache or (tick() - cache.lastBuild > 3) then
        cache = buildHealthCache(player)
    end
    return cache
end
local function getHealth(player)
    local cache = getHealthCache(player)
    if cache.healthVal then
        local val = cache.healthVal.Value
        if val ~= nil then return val end
    end
    local char = player.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            local h = hum.Health
            if h ~= nil then return h end
        end
    end
    return nil
end
local function getMaxHealth(player)
    local cache = getHealthCache(player)
    if cache.maxVal then
        local val = cache.maxVal.Value
        if val ~= nil then return val end
    end
    local char = player.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            local m = hum.MaxHealth
            if m ~= nil then return m end
        end
    end
    return nil
end
local function getPosture(player)
    local cache = getHealthCache(player)
    if cache.impactVal then
        local val = cache.impactVal.Value
        if val ~= nil then return val end
    end
    return nil
end
local function isLocalPlayerHurtbox(obj)
    local lp = Players.LocalPlayer
    if not lp then return false end
    local myName = lp.Name
    if not myName or myName == "" then return false end
    local parent = obj.Parent
    local depth = 0
    while parent and depth < 10 do
        if parent.Name == myName then
            return true
        end
        parent = parent.Parent
        depth = depth + 1
    end
    return false
end
local function processHurtbox(obj)
    if not obj then return end
    if not obj:IsA("BasePart") then return end
    if obj.Name ~= "Torso_Hurtbox" then return end
    if isLocalPlayerHurtbox(obj) then return end
    obj.Size = CONFIG.HURTBOX_TARGET_SIZE
end
local function scanHurtboxes()
    local entities = STATE.entitiesFolder
    if not entities then
        entities = Workspace:FindFirstChild("Entities")
        if entities then
            STATE.entitiesFolder = entities
        else
            return
        end
    end
    if not entities.Parent then
        STATE.entitiesFolder = nil
        return
    end
    local descendants = entities:GetDescendants()
    for i = 1, #descendants do
        processHurtbox(descendants[i])
    end
end
local cachedTargets = {}
local lastTargetScan = 0
local function scanTargets()
    local targets = {}
    local myPos, myLook = getMyData()
    if not myPos then return targets end
    local lp = Players.LocalPlayer
    if not lp then return targets end
    local rangeSq = CONFIG.AURA_RANGE * CONFIG.AURA_RANGE
    local all = Players:GetPlayers()
    for i = 1, #all do
        local p = all[i]
        if not isRealPlayer(p) then continue end
        local health = getHealth(p)
        if health and health > 0 then
            local char = p.Character
            if char then
                local root = char:FindFirstChild("HumanoidRootPart")
                if root then
                    local head = char:FindFirstChild("Head")
                    local rootPos = root.Position
                    if rootPos then
                        local distSq = distanceSq(myPos, rootPos)
                        if distSq <= rangeSq then
                            local toTarget = (rootPos - myPos).Unit
                            local angle = angleBetween(myLook, toTarget)
                            local inAngle = angle <= (CONFIG.AURA_ANGLE / 2)
                            local headPos = nil
                            if head then headPos = head.Position end
                            table_insert(targets, {
                                player = p,
                                root = root,
                                health = health,
                                maxHealth = getMaxHealth(p) or health,
                                distance = math_sqrt(distSq),
                                position = headPos or rootPos,
                                angle = angle,
                                inAngle = inAngle,
                            })
                        end
                    end
                end
            end
        end
    end
    table_sort(targets, function(a, b) return a.distance < b.distance end)
    return targets
end
local function getAllTargets()
    local now = tick()
    if now - lastTargetScan >= 0.12 then
        cachedTargets = scanTargets()
        lastTargetScan = now
    end
    return cachedTargets
end
local function performAttack()
    local now = tick()
    if now - STATE.lastAttack < CONFIG.ATTACK_COOLDOWN then
        return false
    end
    STATE.lastAttack = now
    mouse1press()
    task_wait(0.016)
    mouse1release()
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
        local target = nil
        for i = 1, #targets do
            if targets[i].inAngle then
                target = targets[i]
                break
            end
        end
        STATE.currentTarget = target
        if target and CONFIG.AUTO_ATTACK then
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
    local lp = Players.LocalPlayer
    if not lp then return end
    if player == lp or isSelf(player) then return end
    if not isRealPlayer(player) then return end
    if espObjects[player] then return end
    local hp = Drawing_new("Text")
    hp.Size = 13
    hp.Font = Drawing.Fonts.System
    hp.Outline = true
    hp.Center = true
    hp.Visible = false
    hp.ZIndex = 3
    hp.Color = Color3_fromRGB(255, 255, 255)
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
        lastScreenPos = nil,
        lastOnScreen = false,
        lastVisible = false,
    }
end
local function removeESP(player)
    local data = espObjects[player]
    if data then
        if data.hpText then data.hpText.Visible = false data.hpText:Remove() end
        if data.postureText then data.postureText.Visible = false data.postureText:Remove() end
        if data.weaponText then data.weaponText.Visible = false data.weaponText:Remove() end
        espObjects[player] = nil
        healthCache[player] = nil
    end
end
local _myPosCache = nil
local _myPosCacheTime = 0
local function getMyPosCached()
    local now = tick()
    if now - _myPosCacheTime < 0.05 then
        return _myPosCache
    end
    _myPosCache = getMyData()
    _myPosCacheTime = now
    return _myPosCache
end
local function updateESP_60FPS()
    if not STATE.espEnabled then return end
    local lp = Players.LocalPlayer
    if not lp then return end
    local myPos = getMyPosCached()
    local showWeapon = CONFIG.ESP.Weapon
    local now = tick()
    for player, data in next, espObjects do
        if player == lp then
            data.hpText.Visible = false
            data.postureText.Visible = false
            data.weaponText.Visible = false
            continue
        end
        local char = player.Character
        if char ~= data.lastChar then
            data.lastChar = char
            data.cachedMax = nil
            data.cachedWeapon = nil
            data.lastWeaponUpdate = 0
            if char then
                data.refs.head = char:FindFirstChild("Head")
                data.refs.root = char:FindFirstChild("HumanoidRootPart")
            else
                data.refs.head = nil
                data.refs.root = nil
            end
        end
        local head = data.refs.head
        if not head then
            if data.lastVisible then
                data.hpText.Visible = false
                data.postureText.Visible = false
                data.weaponText.Visible = false
                data.lastVisible = false
            end
            continue
        end
        local inRange = true
        if myPos and data.refs.root then
            local rootPos = data.refs.root.Position
            if rootPos then
                if distanceSq(myPos, rootPos) > 90000 then
                    inRange = false
                end
            end
        end
        if not inRange then
            if data.lastVisible then
                data.hpText.Visible = false
                data.postureText.Visible = false
                data.weaponText.Visible = false
                data.lastVisible = false
            end
            continue
        end
        local pos, onScreen = WorldToScreen(head.Position)
        if not onScreen or not pos then
            if data.lastVisible then
                data.hpText.Visible = false
                data.postureText.Visible = false
                data.weaponText.Visible = false
                data.lastVisible = false
            end
            continue
        end
        data.lastScreenPos = pos
        data.lastOnScreen = true
        local px = math_floor(pos.X + 0.5)
        local py = math_floor(pos.Y + 0.5)
        local health = getHealth(player)
        local maxHealth = data.cachedMax or getMaxHealth(player)
        if maxHealth and not data.cachedMax then data.cachedMax = maxHealth end
        if health and maxHealth and maxHealth > 0 and health > 0 then
            local pct = health / maxHealth
            if pct > 1 then pct = 1 elseif pct < 0 then pct = 0 end
            data.hpText.Text = tostring(math_floor(health))
            data.hpText.Position = Vector2_new(px, py - 28)
            data.hpText.Color = healthColor(pct)
            data.hpText.Visible = true
        else
            data.hpText.Visible = false
        end
        local posture = getPosture(player)
        if posture ~= nil then
            data.postureText.Text = tostring(math_floor(posture))
            data.postureText.Position = Vector2_new(px, py - 16)
            data.postureText.Visible = true
        else
            data.postureText.Visible = false
        end
        if showWeapon then
            if not data.cachedWeapon or (now - data.lastWeaponUpdate > 2) then
                data.cachedWeapon = getWeaponName(player, char)
                data.lastWeaponUpdate = now
            end
            data.weaponText.Text = data.cachedWeapon or "None"
            data.weaponText.Position = Vector2_new(px, py - 4)
            data.weaponText.Visible = true
        else
            data.weaponText.Visible = false
        end
        data.lastVisible = data.hpText.Visible or data.postureText.Visible or data.weaponText.Visible
    end
end
local lastPlayerList = {}
local function updatePlayerList()
    if not STATE.espEnabled then return end
    local lp = Players.LocalPlayer
    if not lp then return end
    local all = Players:GetPlayers()
    for i = 1, #all do
        local p = all[i]
        if p ~= lp and not lastPlayerList[p] then
            lastPlayerList[p] = true
            createESP(p)
        end
    end
    for p in next, lastPlayerList do
        local here = false
        for i = 1, #all do
            if all[i] == p then here = true break end
        end
        if not here then
            lastPlayerList[p] = nil
            removeESP(p)
        end
    end
end
local debounceToggle = false
local debounceEsp = false
local debounceHitbox = false
local function charToVK(char)
    return string_byte(string_lower(char)) - 96
end
local toggleVK = charToVK(CONFIG.TOGGLE_KEY)
local espToggleVK = charToVK(CONFIG.ESP_TOGGLE_KEY)
local hitboxToggleVK = charToVK(CONFIG.HITBOX_TOGGLE_KEY)
local function onKeyPress(input, gameProcessed)
    if gameProcessed then return end
    if not input then return end
    local keyCode = input.KeyCode
    if not keyCode then return end
    if keyCode == toggleVK then
        if debounceToggle then return end
        debounceToggle = true
        CONFIG.AUTO_ATTACK = not CONFIG.AUTO_ATTACK
        notify("Vault", "Auto Attack: " .. (CONFIG.AUTO_ATTACK and "ON" or "OFF"), 3)
        task_wait(0.3)
        debounceToggle = false
    elseif keyCode == espToggleVK then
        if debounceEsp then return end
        debounceEsp = true
        STATE.espEnabled = not STATE.espEnabled
        if not STATE.espEnabled then
            for p, d in next, espObjects do
                if d and d.hpText then d.hpText.Visible = false d.hpText:Remove() end
                if d and d.postureText then d.postureText.Visible = false d.postureText:Remove() end
                if d and d.weaponText then d.weaponText.Visible = false d.weaponText:Remove() end
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
        debounceEsp = false
    elseif keyCode == hitboxToggleVK then
        if debounceHitbox then return end
        debounceHitbox = true
        STATE.hurtboxLarge = not STATE.hurtboxLarge
        if STATE.hurtboxLarge then
            CONFIG.HURTBOX_TARGET_SIZE = Vector3_new(13, 13, 13)
            notify("Vault", "Hitbox: LARGE", 3)
        else
            CONFIG.HURTBOX_TARGET_SIZE = Vector3_new(2.1, 2.1, 1.05)
            notify("Vault", "Hitbox: NORMAL", 3)
        end
        STATE.entitiesFolder = nil
        pcall(scanHurtboxes)
        task_wait(0.3)
        debounceHitbox = false
    end
end
UserInputService.InputBegan:Connect(onKeyPress)
local running = true
local function doCleanup()
    running = false
    STATE.enabled = false
    STATE.currentTarget = nil
    for p, d in next, espObjects do
        if d then
            if d.hpText then d.hpText.Visible = false d.hpText:Remove() end
            if d.postureText then d.postureText.Visible = false d.postureText:Remove() end
            if d.weaponText then d.weaponText.Visible = false d.weaponText:Remove() end
        end
    end
    espObjects = {}
    healthCache = {}
    cachedTargets = {}
    lastPlayerList = {}
    STATE.entitiesFolder = nil
end
_G.VaultCleanup = doCleanup
local function isGameValid()
    return Players.LocalPlayer ~= nil and game.PlaceId ~= nil
end
local function auraLoop()
    while running do
        if STATE.enabled then updateAura() end
        task_wait(0.05)
    end
end
local function playerPollLoop()
    while running do
        updatePlayerList()
        task_wait(CONFIG.PLAYER_SCAN_RATE)
    end
end
local function hurtboxLoop()
    task_wait(2)
    while running do
        scanHurtboxes()
        task_wait(CONFIG.HURTBOX_SCAN_INTERVAL)
    end
end
local function espRenderLoop()
    while running do
        if not isGameValid() then doCleanup() break end
        updateESP_60FPS()
        task_wait(CONFIG.ESP_RENDER_RATE)
    end
end
local function espUpdateLoop()
    while running do
        if not isGameValid() then doCleanup() break end
        for player, data in next, espObjects do
            if player == Players.LocalPlayer then continue end
            local char = player.Character
            if char ~= data.lastChar then
                data.lastChar = char
                data.cachedMax = nil
                data.cachedWeapon = nil
                data.lastWeaponUpdate = 0
                if char then
                    data.refs.head = char:FindFirstChild("Head")
                    data.refs.root = char:FindFirstChild("HumanoidRootPart")
                else
                    data.refs.head = nil
                    data.refs.root = nil
                end
            end
        end
        task_wait(CONFIG.ESP_UPDATE_RATE)
    end
end
local function mainLoop()
    STATE.enabled = true
    STATE.currentTarget = nil
    local lp = nil
    for i = 1, 100 do
        lp = Players.LocalPlayer
        if lp then break end
        task_wait(0.1)
    end
    if not lp then return end
    local all = Players:GetPlayers()
    for i = 1, #all do
        local p = all[i]
        if p ~= lp then
            createESP(p)
            lastPlayerList[p] = true
        end
    end
    if espObjects[lp] then removeESP(lp) end
    task_spawn(espRenderLoop)
    task_spawn(espUpdateLoop)
    task_spawn(auraLoop)
    task_spawn(playerPollLoop)
    task_spawn(hurtboxLoop)
end
mainLoop()
notify("Vault", "Cutie Patootie", 5)
