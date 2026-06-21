local pcall, tick, wait, spawn = pcall, tick, task.wait, task.spawn
local ipairs, next, tostring, floor, sqrt, huge, insert, lower, find, min, max = ipairs, next, tostring, math.floor, math.sqrt, math.huge, table.insert, string.lower, string.find, math.min, math.max
local V3, V2, C3, Draw = Vector3.new, Vector2.new, Color3.fromRGB, Drawing.new
local CONFIG = {
    AURA_RANGE = 30, AURA_ANGLE = 180, AUTO_ATTACK = true, ATTACK_COOLDOWN = 0.15,
    AURA_INTERVAL = 0.020, PARRY_USE_PRESS_RELEASE = true, PARRY_DOUBLE_TAP = false,
    PARRY_DOUBLE_TAP_DELAY = 0.05, PARRY_REQUIRE_FOCUS = true, PARRY_VERIFY_TARGET = true,
    TOGGLE_KEY = "r", ESP_TOGGLE_KEY = "p",
    ESP = { Weapon = true, Bullets = true }, ESP_RANGE = 300,
    KNOWN_WEAPONS = {"Castigate","Phoenix","Siege","Monarch"},
    BLOCKED = {"emptydummy","emptymodel","dummy","placeholder"},
    TEAM_CHECK = true
}
local STATE = {
    enabled = true, lastAttack = 0, target = nil, targets = {}, lastAura = 0,
    espOn = true, debounce = {}, espObjs = {}, healthCache = {}, cachedTargets = {}, lastScan = 0,
    players = {}, running = true
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local cachedUserIds, cachedFolderIds = {}, {}

local function toUnsigned(s) return s >= 0 and s or s + 4294967296 end

local function getRealUserId(p)
    if not p then return -1 end
    if cachedUserIds[p.Name] then return cachedUserIds[p.Name] end
    local id = -1
    pcall(function() if memory_read and p.Address then id = toUnsigned(memory_read("int", p.Address + 760)) end end)
    cachedUserIds[p.Name] = id
    return id
end

local function getTeamId(uid)
    if uid == -1 then return -1 end
    local md = ReplicatedStorage:FindFirstChild("ReadOnly") and ReplicatedStorage.ReadOnly:FindFirstChild("Match")
    if not md then return -1 end
    local pf = md:FindFirstChild("Players")
    if not pf then return -1 end
    local f = pf:FindFirstChild(tostring(uid))
    return f and tonumber(f:GetAttribute("team_id")) or -1
end

local function refreshFolders()
    cachedFolderIds = {}
    local md = ReplicatedStorage:FindFirstChild("ReadOnly") and ReplicatedStorage.ReadOnly:FindFirstChild("Match")
    local pf = md and md:FindFirstChild("Players")
    if not pf then return end
    for _, f in ipairs(pf:GetChildren()) do
        local uid = tonumber(f.Name)
        if uid then cachedFolderIds[uid] = tonumber(f:GetAttribute("team_id")) or -1 end
    end
end

local function isEnemy(p)
    if p == LocalPlayer then return false end
    local myId, theirId = getRealUserId(LocalPlayer), getRealUserId(p)
    if myId == -1 or theirId == -1 then return true end
    local myTeam, theirTeam = getTeamId(myId), getTeamId(theirId)
    if theirTeam == -1 then theirTeam = cachedFolderIds[theirId] or -1 end
    if myTeam == -1 or theirTeam == -1 then return true end
    return myTeam ~= theirTeam
end

local function isTeammate(p) return p == LocalPlayer or not isEnemy(p) end

_G.TeamCheck = { isEnemy = isEnemy, isTeammate = isTeammate, getTeamId = function(p) return getTeamId(getRealUserId(p)) end, getRealUserId = getRealUserId }

local function safe(f, ...) local ok, r = pcall(f, ...) return ok and r or nil end
local function notify(t, m, d) safe(function() (_G.notify or notify)(t, m, d) end) end
local UIS = safe(function() return game:GetService("UserInputService") end)
local function getLP() return LocalPlayer end
local function getChar(p) return safe(function() return (p or LocalPlayer).Character end) end
local function getPart(c, n) return safe(function() return c:FindFirstChild(n) end) end
local function getPos(p) return safe(function() return p.Position end) end
local function getMyPos() local c = getChar() return c and getPos(getPart(c, "HumanoidRootPart")) end
local function isSelf(t) return t == LocalPlayer or (LocalPlayer and t and safe(function() return t.Name == LocalPlayer.Name end)) end
local function blocked(n) if not n then return true end local l = lower(n) for _, p in ipairs(CONFIG.BLOCKED) do if find(l, p, 1, true) then return true end end return false end
local function dist2(a, b) if not a or not b then return huge end local dx, dy, dz = b.X-a.X, b.Y-a.Y, b.Z-a.Z return dx*dx+dy*dy+dz*dz end
local function hColor(pct)
    pct = min(1, max(0, pct))
    if pct >= 0.7 then local t = (pct - 0.7) / 0.3 return C3(floor(255 * (1 - t)), 255, 0)
    elseif pct >= 0.3 then local t = (pct - 0.3) / 0.4 return C3(255, 255, floor(255 * (1 - t)))
    else local t = pct / 0.3 return C3(255, floor(255 * t), 0) end
end
local function getHealth(p)
    local c = STATE.healthCache[p]
    if not c or tick()-c.t > 2 then
        c = {t = tick()}
        local ro = safe(function() return p:FindFirstChild("ReadOnly") end)
        if ro then c.h = safe(function() return ro:FindFirstChild("health") end) c.m = safe(function() for _, n in ipairs({"maxhealth","maxHealth","MaxHealth","HealthMax"}) do local v = ro:FindFirstChild(n) if v then return v end end end) c.i = safe(function() for _, n in ipairs({"impact","Impact","posture","Posture","stun","Stun"}) do local v = ro:FindFirstChild(n) if v then return v end end end) end
        STATE.healthCache[p] = c
    end
    if c.h then local v = safe(function() return c.h.Value end) if v ~= nil then return v end end
    local hum = safe(function() return getChar(p):FindFirstChildOfClass("Humanoid") end)
    return hum and safe(function() return hum.Health end)
end
local function getMaxHealth(p)
    local c = STATE.healthCache[p]
    if c and c.m then local v = safe(function() return c.m.Value end) if v ~= nil then return v end end
    local hum = safe(function() return getChar(p):FindFirstChildOfClass("Humanoid") end)
    return hum and safe(function() return hum.MaxHealth end)
end
local function getPosture(p)
    local c = STATE.healthCache[p]
    if c and c.i then local v = safe(function() return c.i.Value end) if v ~= nil then return v end end
    local ro = safe(function() return p:FindFirstChild("ReadOnly") end)
    if not ro then return nil end
    for _, n in ipairs({"impact","Impact","posture","Posture","stun","Stun"}) do local v = safe(function() local o = ro:FindFirstChild(n) return o and o.Value end) if v ~= nil then return v end end
    return nil
end

local WEAPON_BY_MAX_HEAT = {
    [300] = "Castigate",
    [280] = "Siege",
    [170] = "Phoenix",
    [200] = "Monarch",
}

local WEAPON_BY_HEAT_PER = {
    [100] = "Castigate",
    [140] = "Siege",
    [170] = "Phoenix",
    [200] = "Monarch",
}

local WEAPON_BULLET_DATA = {
    Castigate = {max = 3, heatPer = 100},
    Siege = {max = 2, heatPer = 140},
    Phoenix = {max = 1, heatPer = 170},
    Monarch = {max = 1, heatPer = 200},
}

local function getWeaponFromStats(p)
    local ro = safe(function() return p:FindFirstChild("ReadOnly") end)
    if not ro then return nil end
    local maxHeat = safe(function() 
        local h = ro:FindFirstChild("max_heat")
        return h and h.Value
    end)
    if maxHeat and WEAPON_BY_MAX_HEAT[maxHeat] then
        return WEAPON_BY_MAX_HEAT[maxHeat]
    end
    local heatPer = safe(function() 
        local h = ro:FindFirstChild("heat_per_bullet")
        return h and h.Value
    end)
    if heatPer and WEAPON_BY_HEAT_PER[heatPer] then
        return WEAPON_BY_HEAT_PER[heatPer]
    end
    return nil
end

local function getWeaponFromModel(p)
    local c = getChar(p)
    local function search(f) 
        if not f then return nil end 
        for _, ch in ipairs(safe(function() return f:GetChildren() end) or {}) do 
            local n = safe(function() return ch.Name end) 
            if n then 
                local l = lower(n)
                for _, w in ipairs(CONFIG.KNOWN_WEAPONS) do 
                    if find(l, lower(w), 1, true) then return w end 
                end 
            end 
        end 
        return nil 
    end
    return search(c) or search(safe(function() return p:FindFirstChild("Backpack") end))
end

local function getWeaponFromHeat(p)
    local fromStats = getWeaponFromStats(p)
    if fromStats then return fromStats end
    local fromModel = getWeaponFromModel(p)
    if fromModel then return fromModel end
    return "None"
end

local function getBullets(p)
    local ro = safe(function() return p:FindFirstChild("ReadOnly") end)
    if not ro then return nil end
    local heat = safe(function() local h = ro:FindFirstChild("heat") return h and h.Value end)
    local heatPer = safe(function() local h = ro:FindFirstChild("heat_per_bullet") return h and h.Value end)
    if not heat or not heatPer or heatPer <= 0 then return nil end
    local current = floor(heat / heatPer)
    local wep = getWeaponFromHeat(p)
    local data = WEAPON_BULLET_DATA[wep]
    if data then
        return min(current, data.max), data.max
    end
    return min(current, 3), 3
end

local function scanTargets()
    local t, myPos = {}, getMyPos() if not myPos then return t end
    local lp, rsq = LocalPlayer, CONFIG.AURA_RANGE*CONFIG.AURA_RANGE
    for _, p in ipairs(safe(function() return Players:GetPlayers() end) or {}) do
        if p ~= lp and not isSelf(p) then
            if CONFIG.TEAM_CHECK and not isEnemy(p) then continue end
            local n = safe(function() return p.Name end)
            if n and not blocked(n) then
                local h = getHealth(p)
                if h and h > 0 then
                    local c = getChar(p)
                    local r = c and getPart(c, "HumanoidRootPart")
                    local rp = r and getPos(r)
                    if rp and dist2(myPos, rp) <= rsq then
                        local head = getPart(c, "Head")
                        insert(t, {player = p, root = r, health = h, maxHealth = getMaxHealth(p) or h, dist = sqrt(dist2(myPos, rp)), pos = (head and getPos(head)) or rp})
                    end
                end
            end
        end
    end
    return t
end
local function getTargets() local now = tick() if now - STATE.lastScan >= 0.1 then STATE.cachedTargets = scanTargets() STATE.lastScan = now end return STATE.cachedTargets end
local function attack()
    local now = tick()
    if now - STATE.lastAttack < CONFIG.ATTACK_COOLDOWN - 0.02 then return false end
    if CONFIG.PARRY_REQUIRE_FOCUS then local f = safe(isrbxactive) if f == false then return false end end
    STATE.lastAttack = now
    if CONFIG.PARRY_USE_PRESS_RELEASE then
        if safe(mouse1press) then
            if CONFIG.PARRY_DOUBLE_TAP then wait(CONFIG.PARRY_DOUBLE_TAP_DELAY) safe(mouse1release) wait(CONFIG.PARRY_DOUBLE_TAP_DELAY) safe(mouse1press) wait(CONFIG.PARRY_DOUBLE_TAP_DELAY) safe(mouse1release) else wait(0.016) safe(mouse1release) end
            return true
        end
        return safe(mouse1click) ~= nil
    end
    return safe(mouse1click) ~= nil
end
local function updateAura()
    if not STATE.enabled then return end
    local now = tick()
    if now - STATE.lastAura < CONFIG.AURA_INTERVAL then return end
    STATE.lastAura = now
    local t = getTargets()
    STATE.targets = t
    if #t == 0 then STATE.target = nil return end
    STATE.target = t[1]
    if not CONFIG.AUTO_ATTACK then return end
    if CONFIG.PARRY_VERIFY_TARGET and STATE.target.root then
        local cp, mp = getPos(STATE.target.root), getMyPos()
        if cp and mp and dist2(mp, cp) <= CONFIG.AURA_RANGE*CONFIG.AURA_RANGE then attack() else attack() end
    else attack() end
end
local function makeESP(p)
    local lp = LocalPlayer if not lp or p == lp or isSelf(p) then return end
    if CONFIG.TEAM_CHECK and not isEnemy(p) then return end
    local n = safe(function() return p.Name end) if not n or blocked(n) or STATE.espObjs[p] then return end
    local function txt() local t = Draw("Text") t.Size = 13 t.Font = Drawing.Fonts.System t.Outline = true t.Center = true t.Visible = false t.ZIndex = 3 return t end
    local hp, pp, wp, bp = txt(), txt(), txt(), txt()
    pp.Color = C3(80, 150, 255) wp.Color = C3(255, 180, 100) bp.Color = C3(255, 80, 80)
    STATE.espObjs[p] = {hp = hp, pp = pp, wp = wp, bp = bp, lastChar = nil, maxCache = nil, wepCache = nil, wepTime = 0, bulletCache = nil, bulletTime = 0, head = nil, root = nil}
end
local function removeESP(p)
    local d = STATE.espObjs[p] if not d then return end
    for _, k in ipairs({"hp","pp","wp","bp"}) do if d[k] then safe(function() d[k].Visible = false end) safe(function() d[k]:Remove() end) end end
    STATE.espObjs[p] = nil STATE.healthCache[p] = nil
end
local function updateESP()
    if not STATE.espOn then return end
    local lp, myPos = LocalPlayer, getMyPos() if not lp then return end
    local rsq = CONFIG.ESP_RANGE * CONFIG.ESP_RANGE
    local now = tick()
    for p, d in next, STATE.espObjs do
        if p == lp or isSelf(p) then for _, k in ipairs({"hp","pp","wp","bp"}) do if d[k] then d[k].Visible = false end end continue end
        if CONFIG.TEAM_CHECK and not isEnemy(p) then for _, k in ipairs({"hp","pp","wp","bp"}) do if d[k] then d[k].Visible = false end end continue end
        local c = getChar(p)
        if c ~= d.lastChar then
            d.lastChar = c d.maxCache = nil d.wepCache = nil d.wepTime = 0 d.bulletCache = nil d.bulletTime = 0
            d.head = c and getPart(c, "Head") d.root = c and getPart(c, "HumanoidRootPart")
        end
        if not d.head then for _, k in ipairs({"hp","pp","wp","bp"}) do if d[k] then d[k].Visible = false end end continue end
        if myPos and d.root and CONFIG.ESP_RANGE > 0 then local rp = getPos(d.root) if rp and dist2(myPos, rp) > rsq then for _, k in ipairs({"hp","pp","wp","bp"}) do if d[k] then d[k].Visible = false end end continue end end
        local hp = getPos(d.head) if not hp then for _, k in ipairs({"hp","pp","wp","bp"}) do if d[k] then d[k].Visible = false end end continue end
        local ok, pos, onScreen = pcall(WorldToScreen, hp) if not ok or not onScreen or not pos then for _, k in ipairs({"hp","pp","wp","bp"}) do if d[k] then d[k].Visible = false end end continue end
        local h, mh = getHealth(p), d.maxCache or getMaxHealth(p) if mh and not d.maxCache then d.maxCache = mh end
        local post = getPosture(p)
        if h and mh and mh > 0 and h > 0 then
            local pct = h / mh
            pct = pct > 1 and 1 or pct < 0 and 0 or pct
            d.hp.Text = tostring(floor(h))
            d.hp.Position = V2(pos.X, pos.Y-28)
            d.hp.Color = hColor(pct)
            d.hp.Visible = true
        else
            d.hp.Visible = false
        end
        if post ~= nil then d.pp.Text = tostring(floor(post)) d.pp.Position = V2(pos.X, pos.Y-16) d.pp.Visible = true else d.pp.Visible = false end
        if CONFIG.ESP.Weapon then if not d.wepCache or now - d.wepTime > 1 then d.wepCache = getWeaponFromHeat(p) d.wepTime = now end d.wp.Text = d.wepCache d.wp.Position = V2(pos.X, pos.Y+20) d.wp.Visible = true else d.wp.Visible = false end
        if CONFIG.ESP.Bullets then
            if not d.bulletCache or now - d.bulletTime > 0.5 then
                local b, m = getBullets(p)
                d.bulletCache = {b, m}
                d.bulletTime = now
            end
            if d.bulletCache[1] ~= nil then
                d.bp.Text = tostring(d.bulletCache[1]) .. "/" .. tostring(d.bulletCache[2] or "?") .. " B"
                d.bp.Position = V2(pos.X+35, pos.Y-4)
                d.bp.Visible = true
            else
                d.bp.Visible = false
            end
        else
            d.bp.Visible = false
        end
    end
end
local function updatePlayers()
    if not STATE.espOn then return end
    local lp = LocalPlayer if not lp then return end
    local all = safe(function() return Players:GetPlayers() end) or {}
    for _, p in ipairs(all) do if p ~= lp and not isSelf(p) and not STATE.players[p] then if CONFIG.TEAM_CHECK and not isEnemy(p) then continue end STATE.players[p] = true makeESP(p) end end
    for p in next, STATE.players do local here = false for _, v in ipairs(all) do if v == p then here = true break end end if not here then STATE.players[p] = nil removeESP(p) end end
end
local function doCleanup()
    STATE.running = false STATE.enabled = false STATE.target = nil
    for p, d in next, STATE.espObjs do if d then for _, k in ipairs({"hp","pp","wp","bp"}) do if d[k] then safe(function() d[k].Visible = false end) safe(function() d[k]:Remove() end) end end end end
    STATE.espObjs = {} STATE.healthCache = {} STATE.cachedTargets = {} STATE.players = {}
    cachedUserIds = {} cachedFolderIds = {}
end
_G.VaultCleanup = doCleanup
local function isValid() return Players and LocalPlayer and safe(function() return game.PlaceId end) ~= nil end
local function onKey(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode[CONFIG.TOGGLE_KEY:upper()] then
        if STATE.debounce.toggle then return end STATE.debounce.toggle = true CONFIG.AUTO_ATTACK = not CONFIG.AUTO_ATTACK notify("Vault", "Auto Attack: " .. (CONFIG.AUTO_ATTACK and "ON" or "OFF"), 3) wait(0.3) STATE.debounce.toggle = false
    end
    if input.KeyCode == Enum.KeyCode[CONFIG.ESP_TOGGLE_KEY:upper()] then
        if STATE.debounce.esp then return end STATE.debounce.esp = true STATE.espOn = not STATE.espOn
        if not STATE.espOn then
            for p, d in next, STATE.espObjs do if d then for _, k in ipairs({"hp","pp","wp","bp"}) do if d[k] then safe(function() d[k].Visible = false end) safe(function() d[k]:Remove() end) end end end end
            STATE.espObjs = {} STATE.healthCache = {} STATE.cachedTargets = {} STATE.players = {} notify("Vault", "ESP: REMOVED", 3)
        else notify("Vault", "ESP: ON", 3) end
        wait(0.3) STATE.debounce.esp = false
    end
    if input.KeyCode == Enum.KeyCode.J then
        if STATE.debounce.team then return end STATE.debounce.team = true CONFIG.TEAM_CHECK = not CONFIG.TEAM_CHECK notify("Vault", "Team Check: " .. (CONFIG.TEAM_CHECK and "ON" or "OFF"), 3) STATE.cachedTargets = {} wait(0.3) STATE.debounce.team = false
    end
end
if UIS then safe(function() UIS.InputBegan:Connect(onKey) end) end
local function main()
    STATE.enabled = true STATE.target = nil
    if not LocalPlayer then for _ = 1, 100 do if Players and Players.LocalPlayer then LocalPlayer = Players.LocalPlayer break end wait(0.1) end end
    if not LocalPlayer then return end
    for _, p in ipairs(safe(function() return Players:GetPlayers() end) or {}) do if p ~= LocalPlayer then getRealUserId(p) end end
    refreshFolders()
    for _, p in ipairs(safe(function() return Players:GetPlayers() end) or {}) do if p ~= LocalPlayer and not isSelf(p) and STATE.espOn then if CONFIG.TEAM_CHECK and not isEnemy(p) then continue end makeESP(p) STATE.players[p] = true end end
    if STATE.espObjs[LocalPlayer] then removeESP(LocalPlayer) end
    local lastId = safe(function() return game.PlaceId end) or 0
    spawn(function() while STATE.running do safe(refreshFolders) wait(3) end end)
    spawn(function() while STATE.running do safe(function() for _, p in ipairs(safe(function() return Players:GetPlayers() end) or {}) do if p ~= LocalPlayer then getRealUserId(p) end end end) wait(2) end end)
    spawn(function() while STATE.running do safe(updateESP) local s = tick() wait(0.008) if tick()-s > 0.05 then wait(0.001) end local cid = safe(function() return game.PlaceId end) if not cid or cid ~= lastId then doCleanup() break end if not safe(function() return Players.LocalPlayer end) then doCleanup() break end end end)
    spawn(function() while STATE.running do if STATE.enabled then safe(updateAura) end wait(0.01) end end)
    spawn(function() while STATE.running do safe(updatePlayers) wait(0.5) end end)
    for _ = 1, 50 do if getMyPos() then break end wait(0.1) end
end
if isValid() then safe(main) notify("Vault", "Cutie Patootie", 7) end
