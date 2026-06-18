local function safeGet(name)
    local ok, svc = pcall(function() return game:GetService(name) end)
    if ok and svc then return svc end
    ok, svc = pcall(function() return game[name] end)
    if ok and svc then return svc end
    ok, svc = pcall(function() return game[name:lower()] end)
    if ok and svc then return svc end
    return nil
end

local Players = safeGet("Players")
local RunService = safeGet("RunService")
local Workspace = safeGet("Workspace")
local ReplicatedStorage = safeGet("ReplicatedStorage")

if not Workspace then return end
if not RunService then return end
if not Players then return end
if not ReplicatedStorage then return end

local Camera = nil
local ok_cam, camResult = pcall(function() return Workspace.CurrentCamera end)
if ok_cam and camResult then Camera = camResult else return end

local LocalPlayer = nil
local ok_lp, lp = pcall(function() return Players.LocalPlayer end)
if ok_lp and lp then LocalPlayer = lp end
if not LocalPlayer then return end

local math_floor = math.floor
local math_sqrt = math.sqrt
local math_acos = math.acos
local math_deg = math.deg
local math_abs = math.abs
local math_random = math.random
local math_clamp = math.clamp
local Vector3_new = Vector3.new
local Vector2_new = Vector2.new
local pcall = pcall
local next = next
local tostring = tostring
local tick = tick
local task_wait = task.wait
local task_spawn = task.spawn

local CONFIG = {
    CastigateDelay = 0.45,
    MonarchDelay = 1.5,
    ScanInterval = 0.01,
    CastigateMaxDist = 500,
    MonarchMaxDist = 50,
    ParryCooldown = 0.3,
    CrossMemoryTimeout = 3,
    GlareMemoryTimeout = 3,
    JitterRange = 0.02,
    MaxDistance = 500,
    LineLength = 8,
    LineThickness = 1.5,
    LineTransparency = 0.6,
    TextSize = 13,
    ShowNames = true,
    ShowDistance = true,
    EntitiesFolderName = "Entities",
    HeadName = "Head",
    TorsoName = "HumanoidRootPart",
    SelfName = LocalPlayer and LocalPlayer.Name or nil,
    AngleCloseDist = 20,
    AngleFarDist = 50,
    AngleClose = 20,
    AngleFar = 10,
    CrossEnabled = true,
    GlareEnabled = true,
    AutoParryEnabled = true,
    DEBUG = false,
    
    Human = {
        MissChance = 0.08,
        MissDelay = 0.12,
        ReactionMin = 0.04,
        ReactionMax = 0.11,
        PanicChance = 0.03,
        PanicDelay = 0.25,
        PanicDoubleTap = 0.08,
        LateParryChance = 0.06,
        LateParryDelay = 0.18,
        EarlyParryChance = 0.05,
        EarlyParryDelay = 0.06,
        StaggerMin = 0.5,
        StaggerMax = 1.8,
        StaggerCooldown = 4,
        FumbleChance = 0.04,
        FumbleDuration = 0.35,
        ConfidenceBuild = 0.02,
        ConfidenceDecay = 0.015,
        MaxConfidence = 1.0,
        MinConfidence = 0.3,
        ReadDelayMin = 0.02,
        ReadDelayMax = 0.07,
        HesitateChance = 0.07,
        HesitateDuration = 0.15,
    },
}

local VK_F = 0x46
local VK_T = 0x54
local lastPressTick = 0
local seenCastigates = {}
local parriedCrosses = {}
local seenGlares = {}
local parriedGlares = {}
local currentCrossAddr = nil
local currentGlareAddr = nil
local running = true
local toggleDebounce = false

local Pool = {lines = {}, texts = {}, dots = {}, active = {}}
local Targets = {}

local STATIC_GLARE_ADDR = nil

local humanState = {
    confidence = 0.6,
    lastStagger = 0,
    lastFumble = 0,
    consecutiveParries = 0,
    lastParryTime = 0,
    inHesitation = false,
    hesitationEnd = 0,
    panicMode = false,
    panicEnd = 0,
    reading = false,
    readEnd = 0,
}

local function initStaticGlareAddr()
    local ok, assets = pcall(function() return ReplicatedStorage:FindFirstChild("Assets", true) end)
    if not ok or not assets then return end
    local ok2, effectAssets = pcall(function() return assets:FindFirstChild("EffectAssets", true) end)
    if not ok2 or not effectAssets then return end
    local ok3, monarchGlare = pcall(function() return effectAssets:FindFirstChild("MonarchGlare") end)
    if ok3 and monarchGlare then
        local ok4, addr = pcall(function() return monarchGlare.Address end)
        if ok4 and addr then
            STATIC_GLARE_ADDR = addr
        end
    end
end

local function safeFindFirstChild(parent, name)
    if not parent then return nil end
    local ok, child = pcall(function() return parent:FindFirstChild(name) end)
    if ok and child then return child end
    return nil
end

local function safeFindFirstChildTrue(parent, name)
    if not parent then return nil end
    local ok, child = pcall(function() return parent:FindFirstChild(name, true) end)
    if ok and child then return child end
    return nil
end

local function safeGetChildren(parent)
    if not parent then return {} end
    local ok, children = pcall(function() return parent:GetChildren() end)
    if ok and children then return children end
    return {}
end

local function safeGetDescendants(parent)
    if not parent then return {} end
    local ok, desc = pcall(function() return parent:GetDescendants() end)
    if ok and desc then return desc end
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

local function isSelf(target)
    if not CONFIG.SelfName then return false end
    if not target then return false end
    return safeGetName(target) == CONFIG.SelfName
end

local function findPart(model, name)
    if not model then return nil end
    local part = safeFindFirstChild(model, name)
    if part then return part end
    return nil
end

local function getLivePartData(model, partName)
    if not model then return nil, nil end
    local part = findPart(model, partName)
    if not part then return nil, nil end
    local pos = safeGetPosition(part)
    local cf = safeGetCFrame(part)
    if not pos or not cf then return nil, nil end
    local lookVec = safeGetLookVector(cf)
    if not lookVec then return nil, nil end
    return pos, lookVec
end

local function getLiveHeadData(model)
    return getLivePartData(model, CONFIG.HeadName)
end

local function getLiveTorsoData(model)
    local pos, lookVec = getLivePartData(model, CONFIG.TorsoName)
    if pos and lookVec then return pos, lookVec end
    local fallbackNames = {"UpperTorso", "Torso", "LowerTorso", "Body"}
    for _, name in next, fallbackNames do
        pos, lookVec = getLivePartData(model, name)
        if pos and lookVec then return pos, lookVec end
    end
    return nil, nil
end

local function getBestAttackData(model)
    local headPos, headLook = getLiveHeadData(model)
    if headPos and headLook then
        return headPos, headLook
    end
    return getLiveTorsoData(model)
end

local function dist3D(a, b)
    local dx = b.X - a.X
    local dy = b.Y - a.Y
    local dz = b.Z - a.Z
    return math_sqrt(dx*dx + dy*dy + dz*dz)
end

local function getKey(target)
    local name = safeGetName(target)
    local ok, addr = pcall(function() return target.Address end)
    return name .. "_" .. tostring(ok and addr or "0")
end

local function updateTargets()
    local current = {}
    local entitiesFolder = safeFindFirstChild(Workspace, CONFIG.EntitiesFolderName)
    if entitiesFolder then
        local entities = safeGetChildren(entitiesFolder)
        for _, entity in next, entities do
            if not isSelf(entity) then
                local key = getKey(entity)
                current[key] = true
                if not Targets[key] then
                    Targets[key] = {target = entity}
                end
            end
        end
    end
    for key in next, Targets do
        if not current[key] then
            Targets[key] = nil
            if Pool.lines[key] then pcall(function() Pool.lines[key].Visible = false end) end
            if Pool.texts[key] then pcall(function() Pool.texts[key].Visible = false end) end
            if Pool.dots[key] then pcall(function() Pool.dots[key].Visible = false end) end
            Pool.active[key] = nil
        end
    end
end

local function roundVec2(v)
    if not v then return Vector2_new(0, 0) end
    return Vector2_new(math_floor(v.X + 0.5), math_floor(v.Y + 0.5))
end

local function safeWTS(pos)
    local ok, screenPos, onScreen = pcall(function() return Camera:WorldToViewportPoint(pos) end)
    if ok and screenPos then return roundVec2(Vector2_new(screenPos.X, screenPos.Y)), onScreen end
    return nil, false
end

local function getDraw(drawingType, pool, key)
    if not pool[key] then
        local ok, obj = pcall(function() return Drawing.new(drawingType) end)
        if ok and obj then
            pool[key] = obj
            if drawingType == "Line" then
                obj.Color = Color3.new(1, 0.2, 0.2)
            elseif drawingType == "Circle" then
                obj.Color = Color3.new(1, 0.8, 0.2)
                obj.Filled = true
            elseif drawingType == "Text" then
                obj.Color = Color3.new(1, 1, 1)
                obj.Outline = true
                obj.Center = false
            end
        else
            return nil
        end
    end
    return pool[key]
end

local function hide(key)
    if Pool.lines[key] then pcall(function() Pool.lines[key].Visible = false end) end
    if Pool.texts[key] then pcall(function() Pool.texts[key].Visible = false end) end
    if Pool.dots[key] then pcall(function() Pool.dots[key].Visible = false end) end
    Pool.active[key] = nil
end

local function renderVisualizer()
    local camPos = safeGetPosition(Camera)
    if not camPos then return end

    for key, data in next, Targets do
        local target = data.target
        local shouldDraw = true

        if not target then
            shouldDraw = false
        else
            local pos, lookVec = getLiveHeadData(target)
            if not pos or not lookVec then
                shouldDraw = false
            else
                local dist = dist3D(camPos, pos)
                if dist > CONFIG.MaxDistance then
                    shouldDraw = false
                else
                    local endPos = pos + (lookVec * CONFIG.LineLength)
                    local ss, onScreen1 = safeWTS(pos)
                    local se, onScreen2 = safeWTS(endPos)

                    if not ss or not se or not onScreen1 or not onScreen2 then
                        shouldDraw = false
                    else
                        local alpha = 1
                        local thick = CONFIG.LineThickness
                        if CONFIG.FadeWithDistance and dist > 100 then
                            local fade = 1 - ((dist - 100) / (CONFIG.MaxDistance - 100))
                            alpha = fade < 0.2 and 0.2 or fade
                            thick = CONFIG.LineThickness * alpha
                            if thick < 0.5 then thick = 0.5 end
                        end

                        local line = getDraw("Line", Pool.lines, key)
                        if line then
                            line.From = ss
                            line.To = se
                            line.Thickness = thick
                            line.Transparency = alpha * CONFIG.LineTransparency
                            line.Visible = true
                        end

                        local dot = getDraw("Circle", Pool.dots, key)
                        if dot then
                            dot.Position = se
                            dot.Radius = math_floor(thick * 2 + 1)
                            dot.Transparency = alpha * 0.8
                            dot.Visible = true
                        end

                        if CONFIG.ShowNames or CONFIG.ShowDistance then
                            local text = getDraw("Text", Pool.texts, key)
                            if text then
                                local str = ""
                                if CONFIG.ShowNames then str = safeGetName(target) end
                                if CONFIG.ShowDistance then
                                    if str ~= "" then str = str .. " " end
                                    str = str .. "[" .. math_floor(dist) .. "m]"
                                end
                                text.Text = str
                                text.Size = CONFIG.TextSize
                                text.Position = Vector2_new(ss.X + 8, ss.Y - 8)
                                text.Transparency = alpha
                                text.Visible = true
                            end
                        end

                        Pool.active[key] = true
                    end
                end
            end
        end

        if not shouldDraw then
            hide(key)
        end
    end

    for key in next, Pool.lines do
        if not Pool.active[key] then
            hide(key)
        end
    end
    for key in next, Pool.active do
        Pool.active[key] = nil
    end
end

local function getDynamicAngleThreshold(dist)
    local t = (dist - CONFIG.AngleCloseDist) / (CONFIG.AngleFarDist - CONFIG.AngleCloseDist)
    t = math_clamp(t, 0, 1)
    local angle = CONFIG.AngleClose + (CONFIG.AngleFar - CONFIG.AngleClose) * t
    return angle
end

local function isEnemyLookingAtMe(enemyPos, enemyLookVec, maxDist)
    if not enemyPos or not enemyLookVec then return false, 180, 0 end
    local myChar = LocalPlayer.Character
    if not myChar then return false, 180, 0 end
    local myHead = safeFindFirstChild(myChar, CONFIG.HeadName)
    if not myHead then return false, 180, 0 end
    local myPos = safeGetPosition(myHead)
    if not myPos then return false, 180, 0 end

    local dist = dist3D(enemyPos, myPos)
    if dist > maxDist then return false, 180, dist end

    local toMe = (myPos - enemyPos).Unit
    local dot = enemyLookVec.X * toMe.X + enemyLookVec.Y * toMe.Y + enemyLookVec.Z * toMe.Z
    
    if dot > 1 then dot = 1 end
    if dot < -1 then dot = -1 end

    if dot <= 0 then 
        if CONFIG.DEBUG then print("[Vault] AngleCheck | dot=" .. string.format("%.3f", dot) .. " | FACING AWAY") end
        return false, 90, dist 
    end

    local angle = math_deg(math_acos(dot))
    local threshold = getDynamicAngleThreshold(dist)

    if CONFIG.DEBUG then
        print("[Vault] AngleCheck | dot=" .. string.format("%.3f", dot) .. " | angle=" .. string.format("%.1f", angle) .. " | threshold=" .. string.format("%.1f", threshold) .. " | result=" .. tostring(angle < threshold))
    end

    return angle < threshold, angle, dist
end

local function findClosestEnemy(maxDist)
    local myChar = LocalPlayer.Character
    if not myChar then return nil, math.huge, false end
    local myHead = safeFindFirstChild(myChar, CONFIG.HeadName)
    if not myHead then return nil, math.huge, false end
    local myPos = safeGetPosition(myHead)
    if not myPos then return nil, math.huge, false end

    local closestDist = math.huge
    local closestKey = nil
    local closestIsFacing = false

    for key, data in next, Targets do
        if not data.target then continue end

        local pos, lookVec = getBestAttackData(data.target)
        if pos then
            local dist = dist3D(myPos, pos)
            if dist < closestDist and dist <= maxDist then
                closestDist = dist
                closestKey = key

                if lookVec then
                    local isFacing, _, _ = isEnemyLookingAtMe(pos, lookVec, maxDist)
                    closestIsFacing = isFacing
                end
            end
        end
    end

    return closestKey, closestDist, closestIsFacing
end

local function updateHumanState(didParry)
    local now = tick()
    local h = CONFIG.Human
    
    if didParry then
        humanState.consecutiveParries = humanState.consecutiveParries + 1
        humanState.lastParryTime = now
        humanState.confidence = math_clamp(humanState.confidence + h.ConfidenceBuild, h.MinConfidence, h.MaxConfidence)
    else
        humanState.consecutiveParries = 0
        humanState.confidence = math_clamp(humanState.confidence - h.ConfidenceDecay, h.MinConfidence, h.MaxConfidence)
    end
    
    if humanState.panicMode and now > humanState.panicEnd then
        humanState.panicMode = false
    end
    
    if humanState.inHesitation and now > humanState.hesitationEnd then
        humanState.inHesitation = false
    end
    
    if humanState.reading and now > humanState.readEnd then
        humanState.reading = false
    end
end

local function getHumanizedDelay(baseDelay)
    local h = CONFIG.Human
    local now = tick()
    local adjustedDelay = baseDelay
    
    if humanState.inHesitation then
        return nil
    end
    
    if humanState.reading then
        return nil
    end
    
    if humanState.panicMode then
        if math_random() < 0.5 then
            adjustedDelay = adjustedDelay + h.PanicDelay
        end
    end
    
    local reactionVar = h.ReactionMin + math_random() * (h.ReactionMax - h.ReactionMin)
    adjustedDelay = adjustedDelay + reactionVar
    
    if math_random() < h.MissChance * (1.5 - humanState.confidence) then
        adjustedDelay = adjustedDelay + h.MissDelay
        if CONFIG.DEBUG then print("[Vault] Human: Missed timing") end
    end
    
    if math_random() < h.LateParryChance then
        adjustedDelay = adjustedDelay + h.LateParryDelay
        if CONFIG.DEBUG then print("[Vault] Human: Late parry") end
    end
    
    if math_random() < h.EarlyParryChance then
        adjustedDelay = math_max(0.01, adjustedDelay - h.EarlyParryDelay)
        if CONFIG.DEBUG then print("[Vault] Human: Early parry") end
    end
    
    if math_random() < h.HesitateChance * (1.3 - humanState.confidence) then
        humanState.inHesitation = true
        humanState.hesitationEnd = now + h.HesitateDuration
        if CONFIG.DEBUG then print("[Vault] Human: Hesitation") end
        return nil
    end
    
    local timeSinceLast = now - humanState.lastParryTime
    if humanState.consecutiveParries >= 3 and timeSinceLast < h.StaggerCooldown then
        if math_random() < 0.4 then
            local stagger = h.StaggerMin + math_random() * (h.StaggerMax - h.StaggerMin)
            humanState.lastStagger = now
            adjustedDelay = adjustedDelay + stagger
            humanState.consecutiveParries = 0
            if CONFIG.DEBUG then print("[Vault] Human: Staggered") end
        end
    end
    
    if now - humanState.lastFumble > 8 and math_random() < h.FumbleChance then
        humanState.lastFumble = now
        adjustedDelay = adjustedDelay + h.FumbleDuration
        if CONFIG.DEBUG then print("[Vault] Human: Fumbled") end
    end
    
    if math_random() < h.PanicChance and timeSinceLast < 1.5 then
        humanState.panicMode = true
        humanState.panicEnd = now + 1.2
        if CONFIG.DEBUG then print("[Vault] Human: Panic mode") end
    end
    
    return adjustedDelay
end

local function pressF(delay)
    if not CONFIG.AutoParryEnabled then return false end

    local now = tick()
    if now - lastPressTick < CONFIG.ParryCooldown then return false end
    
    local humanDelay = getHumanizedDelay(delay)
    if not humanDelay then return false end
    
    lastPressTick = now
    updateHumanState(true)

    local jitter = (math_random() * CONFIG.JitterRange * 2) - CONFIG.JitterRange
    local actualDelay = humanDelay + jitter
    if actualDelay < 0 then actualDelay = 0 end

    if CONFIG.DEBUG then
        print("[Vault] Parry in " .. string.format("%.3f", actualDelay) .. "s")
    end

    task_spawn(function()
        task_wait(actualDelay)
        pcall(function()
            keypress(VK_F)
            task_wait(0.05)
            keyrelease(VK_F)
        end)
    end)

    return true
end

local function getCurrentCross()
    local lp = LocalPlayer
    if not lp or not lp.PlayerGui then return nil end

    local visualEffects = safeFindFirstChild(lp.PlayerGui, "VisualEffects")
    if not visualEffects then return nil end

    local castigate = safeFindFirstChild(visualEffects, "Cross")
    if not castigate then return nil end

    return tostring(castigate.Address)
end

local function getCurrentGlare()
    local lp = LocalPlayer
    if not lp or not lp.PlayerGui then return nil end

    local visualEffects = safeFindFirstChildTrue(lp.PlayerGui, "VisualEffects")
    if not visualEffects then return nil end

    local glare = safeFindFirstChild(visualEffects, "MonarchGlare")
    if not glare then return nil end

    local addr = tostring(glare.Address)
    if STATIC_GLARE_ADDR and addr == STATIC_GLARE_ADDR then return nil end

    return addr
end

local function cleanupOldEntries()
    local now = tick()
    for addr, time in next, seenCastigates do
        if now - time > CONFIG.CrossMemoryTimeout then
            seenCastigates[addr] = nil
            parriedCrosses[addr] = nil
        end
    end
    for addr, time in next, seenGlares do
        if now - time > CONFIG.GlareMemoryTimeout then
            seenGlares[addr] = nil
            parriedGlares[addr] = nil
        end
    end
end

local function tryParry(delay, maxDist, addr, parriedTable)
    if not CONFIG.AutoParryEnabled then return false end

    local threatKey, threatDist, isFacing = findClosestEnemy(maxDist)

    if threatKey and isFacing then
        local actualDelay = delay * 0.85

        if CONFIG.DEBUG then
            print("[Vault] tryParry | dist=" .. math_floor(threatDist) .. " | facing=true | delay=" .. string.format("%.3f", actualDelay))
        end

        local didParry = pressF(actualDelay)
        if didParry then
            parriedTable[addr] = true
            return true
        end
    elseif threatKey and not isFacing then
        if CONFIG.DEBUG then
            print("[Vault] tryParry | dist=" .. math_floor(threatDist) .. " | facing=false | SKIPPED")
        end
    elseif CONFIG.DEBUG then
        print("[Vault] tryParry | no threat in range (max=" .. maxDist .. ")")
    end

    return false
end

local toggleStateText = nil

local function updateToggleDisplay()
    if not toggleStateText then
        local ok, obj = pcall(function() return Drawing.new("Text") end)
        if ok and obj then
            toggleStateText = obj
            toggleStateText.Size = 14
            toggleStateText.Font = Drawing.Fonts.SystemBold
            toggleStateText.Outline = true
            toggleStateText.Center = false
            toggleStateText.Position = Vector2_new(20, 60)
            toggleStateText.ZIndex = 100
        end
    end
    if toggleStateText then
        if CONFIG.AutoParryEnabled then
            toggleStateText.Text = "PARRY: ON [T]"
            toggleStateText.Color = Color3.new(0.2, 1, 0.2)
        else
            toggleStateText.Text = "PARRY: OFF [T]"
            toggleStateText.Color = Color3.new(1, 0.2, 0.2)
        end
        toggleStateText.Visible = true
    end
end

local function doToggle()
    if toggleDebounce then
        if CONFIG.DEBUG then print("[Vault] Toggle debounced") end
        return
    end
    toggleDebounce = true
    CONFIG.AutoParryEnabled = not CONFIG.AutoParryEnabled
    local msg = "Auto Parry: " .. (CONFIG.AutoParryEnabled and "ON" or "OFF")
    if CONFIG.AutoParryEnabled then
        if CONFIG.CrossEnabled then msg = msg .. " | Castigate: ON" end
        if CONFIG.GlareEnabled then msg = msg .. " | Monarch: ON" end
    end
    pcall(function() notify("Auto Parry", msg, 3) end)
    if CONFIG.DEBUG then print("[Vault] " .. msg) end
    updateToggleDisplay()
    task_spawn(function()
        task_wait(0.3)
        toggleDebounce = false
    end)
end

local inputConnected = false
pcall(function()
    local UIS = game:GetService("UserInputService")
    if UIS and UIS.InputBegan then
        local conn = UIS.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            if input.KeyCode == VK_T then
                if CONFIG.DEBUG then print("[Vault] Event toggle triggered (VK " .. tostring(input.KeyCode) .. ")") end
                doToggle()
            end
        end)
        if conn then
            inputConnected = true
            if CONFIG.DEBUG then print("[Vault] InputBegan connected for toggle") end
        end
    end
end)

local wasTDown = false

local function checkTToggle()
    local isDown = false
    pcall(function()
        if iskeypressed then
            isDown = iskeypressed(VK_T)
        end
    end)
    
    if isDown and not wasTDown then
        if CONFIG.DEBUG then print("[Vault] Poll toggle triggered") end
        doToggle()
        wasTDown = true
    elseif not isDown then
        wasTDown = false
    end
end

local function parryLoop()
    while running do
        checkTToggle()
        updateTargets()

        if CONFIG.AutoParryEnabled then
            local crossAddr = getCurrentCross()
            local glareAddr = getCurrentGlare()
            local now = tick()

            if crossAddr and CONFIG.CrossEnabled then
                if not seenCastigates[crossAddr] then
                    seenCastigates[crossAddr] = now
                    if CONFIG.DEBUG then print("[Vault] Cross detected: " .. crossAddr:sub(-4)) end
                end

                if not parriedCrosses[crossAddr] then
                    tryParry(CONFIG.CastigateDelay, CONFIG.CastigateMaxDist, crossAddr, parriedCrosses)
                end

                currentCrossAddr = crossAddr
            else
                currentCrossAddr = nil
            end

            if glareAddr and CONFIG.GlareEnabled then
                if not seenGlares[glareAddr] then
                    seenGlares[glareAddr] = now
                    if CONFIG.DEBUG then print("[Vault] Glare detected: " .. glareAddr:sub(-4)) end
                end

                if not parriedGlares[glareAddr] then
                    tryParry(CONFIG.MonarchDelay, CONFIG.MonarchMaxDist, glareAddr, parriedGlares)
                end

                currentGlareAddr = glareAddr
            else
                currentGlareAddr = nil
            end
        end

        cleanupOldEntries()
        task_wait(CONFIG.ScanInterval)
    end
end

local function visualLoop()
    while running do
        updateTargets()
        renderVisualizer()
        updateToggleDisplay()
        task_wait(0.016)
    end
end


initStaticGlareAddr()
task_spawn(parryLoop)
task_spawn(visualLoop)

_G.LookParryCleanup = function()
    running = false
    if toggleStateText then
        pcall(function() toggleStateText.Visible = false end)
        pcall(function() toggleStateText:Remove() end)
        toggleStateText = nil
    end
    for key in next, Pool.lines do
        if Pool.lines[key] then pcall(function() Pool.lines[key]:Remove() end) end
        if Pool.dots[key] then pcall(function() Pool.dots[key]:Remove() end) end
        if Pool.texts[key] then pcall(function() Pool.texts[key]:Remove() end) end
    end
    Pool.lines = {}
    Pool.dots = {}
    Pool.texts = {}
    Pool.active = {}
    Targets = {}
    seenCastigates = {}
    parriedCrosses = {}
    seenGlares = {}
    parriedGlares = {}
    currentCrossAddr = nil
    currentGlareAddr = nil
    lastPressTick = 0
    CONFIG.AutoParryEnabled = true
    humanState = {
        confidence = 0.6,
        lastStagger = 0,
        lastFumble = 0,
        consecutiveParries = 0,
        lastParryTime = 0,
        inHesitation = false,
        hesitationEnd = 0,
        panicMode = false,
        panicEnd = 0,
        reading = false,
        readEnd = 0,
    }
end

print("Auto Parry Loaded")
