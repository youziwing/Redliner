-- Matcha LuaVM — Look-Aware Auto Parry System v3
-- FEATURE: Dynamic LookAngleThreshold based on distance
-- Far enemies = tighter angle (harder to trigger), Close enemies = wider angle (easier to trigger)

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

if not Workspace then print("[ERROR] Workspace nil") return end
if not RunService then print("[ERROR] RunService nil") return end
if not Players then print("[ERROR] Players nil") return end

local Camera = nil
local ok_cam, camResult = pcall(function() return Workspace.CurrentCamera end)
if ok_cam and camResult then Camera = camResult else print("[ERROR] Camera nil") return end

local LocalPlayer = nil
local ok_lp, lp = pcall(function() return Players.LocalPlayer end)
if ok_lp and lp then LocalPlayer = lp end
if not LocalPlayer then print("[ERROR] LocalPlayer nil") return end

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
    ScanInterval = 0.01,
    MaxParryDistance = 500,
    ParryCooldown = 0.3,
    CrossMemoryTimeout = 3,
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
    SelfName = LocalPlayer and LocalPlayer.Name or nil,
    
    -- Dynamic Angle Config
    AngleCloseDist = 20,
    AngleFarDist = 50,
    AngleClose = 19,
    AngleFar = 10,
}

local VK_F = 0x46
local lastPressTick = 0
local seenCastigates = {}
local parriedCrosses = {}
local currentCrossAddr = nil
local running = true

local Pool = {lines = {}, texts = {}, dots = {}, active = {}}
local Targets = {}

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

local function findHead(model)
    if not model then return nil, nil end
    local head = safeFindFirstChild(model, CONFIG.HeadName)
    if head then
        local pos = safeGetPosition(head)
        if pos then return head, pos end
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
            if pos then return current, pos end
        end
    end
    local descendants = safeGetDescendants(model)
    for _, child in next, descendants do
        local name = safeGetName(child)
        if name:find("Head") or name:find("head") then
            local pos = safeGetPosition(child)
            if pos then return child, pos end
        end
    end
    return nil, nil
end

local function getLook(model)
    local head, _ = findHead(model)
    if not head then return nil end
    local cf = safeGetCFrame(head)
    if not cf then return nil end
    return safeGetLookVector(cf)
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
                    Targets[key] = {target = entity, lastPos = nil, head = nil, lookVec = nil}
                end
                local data = Targets[key]
                local head, pos = findHead(entity)
                if pos then
                    data.lastPos = pos
                    data.head = head
                    data.lookVec = getLook(entity)
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
        
        if not target or not data.lastPos then
            shouldDraw = false
        else
            local pos = data.lastPos
            local lookVec = data.lookVec
            
            if not lookVec then
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

local function isEnemyLookingAtMe(enemyPos, enemyLookVec)
    if not enemyPos or not enemyLookVec then return false, 180, 0, 0 end
    local myChar = LocalPlayer.Character
    if not myChar then return false, 180, 0, 0 end
    local myHead = safeFindFirstChild(myChar, CONFIG.HeadName)
    if not myHead then return false, 180, 0, 0 end
    local myPos = safeGetPosition(myHead)
    if not myPos then return false, 180, 0, 0 end
    
    local dist = dist3D(enemyPos, myPos)
    if dist > CONFIG.MaxParryDistance then return false, 180, dist, 0 end
    
    local toMe = (myPos - enemyPos).Unit
    local dot = enemyLookVec.X * toMe.X + enemyLookVec.Y * toMe.Y + enemyLookVec.Z * toMe.Z
    dot = math_abs(dot)
    if dot > 1 then dot = 1 end
    if dot < -1 then dot = -1 end
    
    local angle = math_deg(math_acos(dot))
    local threshold = getDynamicAngleThreshold(dist)
    
    return angle < threshold, angle, dist, threshold
end

local function findClosestThreat()
    local closestDist = math.huge
    local closestKey = nil
    local closestAngle = 180
    local closestThreshold = 0
    
    for key, data in next, Targets do
        if data.lastPos and data.lookVec then
            local isLooking, angle, dist, threshold = isEnemyLookingAtMe(data.lastPos, data.lookVec)
            if isLooking and dist < closestDist then
                closestDist = dist
                closestKey = key
                closestAngle = angle
                closestThreshold = threshold
            end
        end
    end
    
    return closestKey, closestDist, closestAngle, closestThreshold
end

local function pressF(delay)
    local now = tick()
    if now - lastPressTick < CONFIG.ParryCooldown then return false end
    lastPressTick = now
    
    local jitter = (math_random() * CONFIG.JitterRange * 2) - CONFIG.JitterRange
    local actualDelay = delay + jitter
    if actualDelay < 0 then actualDelay = 0 end
    
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
    
    local visualEffects = lp.PlayerGui:FindFirstChild("VisualEffects")
    if not visualEffects then return nil end
    
    local castigate = visualEffects:FindFirstChild("Cross")
    if not castigate then return nil end
    
    return tostring(castigate.Address)
end

local function cleanupOldEntries()
    local now = tick()
    for addr, time in next, seenCastigates do
        if now - time > CONFIG.CrossMemoryTimeout then
            seenCastigates[addr] = nil
            parriedCrosses[addr] = nil
        end
    end
end

local function parryLoop()
    while running do
        local crossAddr = getCurrentCross()
        
        if crossAddr then
            local now = tick()
            
            if not seenCastigates[crossAddr] then
                seenCastigates[crossAddr] = now
            end
            
            if not parriedCrosses[crossAddr] then
                updateTargets()
                local threatKey, threatDist, threatAngle, threatThreshold = findClosestThreat()
                
                if threatKey then
                    local didParry = pressF(CONFIG.CastigateDelay)
                    if didParry then
                        parriedCrosses[crossAddr] = true
                    end
                end
            end
            
            currentCrossAddr = crossAddr
        else
            currentCrossAddr = nil
        end
        
        cleanupOldEntries()
        task_wait(CONFIG.ScanInterval)
    end
end

local function visualLoop()
    while running do
        updateTargets()
        renderVisualizer()
        task_wait(0.016)
    end
end

task_spawn(parryLoop)
task_spawn(visualLoop)

_G.LookParryCleanup = function()
    running = false
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
    currentCrossAddr = nil
    lastPressTick = 0
end

print("[Look Parry v3] Loaded — Dynamic angle scaling active")
print("[Look Parry v3] Close (" .. CONFIG.AngleCloseDist .. "m): " .. CONFIG.AngleClose .. "°")
print("[Look Parry v3] Far (" .. CONFIG.AngleFarDist .. "m): " .. CONFIG.AngleFar .. "°")
print("[Look Parry v3] Call _G.LookParryCleanup() to stop")
