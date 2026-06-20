local pcall, tick, wait, spawn = pcall, tick, task.wait, task.spawn
local ipairs, next, tostring, floor, sqrt, huge, insert, lower, find, min, max = ipairs, next, tostring, math.floor, math.sqrt, math.huge, table.insert, string.lower, string.find, math.min, math.max
local V3, V2, C3, Draw = Vector3.new, Vector2.new, Color3.fromRGB, Drawing.new
local CONFIG = {
    AURA_RANGE = 38, AURA_ANGLE = 180, AUTO_ATTACK = true, ATTACK_COOLDOWN = 0.15,
    AURA_INTERVAL = 0.020, PARRY_USE_PRESS_RELEASE = true, PARRY_DOUBLE_TAP = false,
    PARRY_DOUBLE_TAP_DELAY = 0.05, PARRY_REQUIRE_FOCUS = true, PARRY_VERIFY_TARGET = true,
    TOGGLE_KEY = "r", ESP_TOGGLE_KEY = "p", HITBOX_TOGGLE_KEY = "h",
    ESP = { Weapon = true }, ESP_RANGE = 300,
    HURTBOX_TARGET_SIZE = V3(25, 25, 25), HURTBOX_SCAN_INTERVAL = 5,
    KNOWN_WEAPONS = {"Castigate","Phoenix","Siege","Monarch"},
    BLOCKED = {"emptydummy","emptymodel","dummy","placeholder"}
}
local STATE = {
    enabled = true, lastAttack = 0, target = nil, targets = {}, lastAura = 0,
    espOn = true, hurtboxSeen = {}, entities = nil, hitboxLarge = true,
    debounce = {}, espObjs = {}, healthCache = {}, cachedTargets = {}, lastScan = 0,
    players = {}, running = true
}
local function safe(f, ...) local ok, r = pcall(f, ...) return ok and r or nil end
local function notify(t, m, d) safe(function() (_G.notify or notify)(t, m, d) end) end
local function getSvc(n) return safe(function() return game:GetService(n) end) end
local Players = getSvc("Players")
local UIS = getSvc("UserInputService")
local function getLP() return safe(function() return Players.LocalPlayer end) end
local function getChar(p) return safe(function() return (p or getLP()).Character end) end
local function getPart(c, n) return safe(function() return c:FindFirstChild(n) end) end
local function getPos(p) return safe(function() return p.Position end) end
local function getMyPos() local c = getChar() return c and getPos(getPart(c, "HumanoidRootPart")) end
local function isSelf(t) local lp = getLP() return t == lp or (lp and t and safe(function() return t.Name == lp.Name end)) end
local function blocked(n) if not n then return true end local l = lower(n) for _, p in ipairs(CONFIG.BLOCKED) do if find(l, p, 1, true) then return true end end return false end
local function dist2(a, b) if not a or not b then return huge end local dx, dy, dz = b.X-a.X, b.Y-a.Y, b.Z-a.Z return dx*dx+dy*dy+dz*dz end
local function hColor(pct)
    pct = min(1, max(0, pct))
    if pct >= 0.7 then
        local t = (pct - 0.7) / 0.3
        return C3(floor(255 * (1 - t)), 255, 0)
    elseif pct >= 0.3 then
        local t = (pct - 0.3) / 0.4
        return C3(255, 255, floor(255 * (1 - t)))
    else
        local t = pct / 0.3
        return C3(255, floor(255 * t), 0)
    end
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
local function getWeapon(p, c)
    local function search(f) if not f then return nil end for _, ch in ipairs(safe(function() return f:GetChildren() end) or {}) do local n = safe(function() return ch.Name end) if n then local l = lower(n) for _, w in ipairs(CONFIG.KNOWN_WEAPONS) do if find(l, lower(w), 1, true) then return w end end end end return nil end
    return search(c) or search(safe(function() return p:FindFirstChild("Backpack") end)) or "None"
end
local function scanTargets()
    local t, myPos = {}, getMyPos() if not myPos then return t end
    local lp, rsq = getLP(), CONFIG.AURA_RANGE*CONFIG.AURA_RANGE
    for _, p in ipairs(safe(function() return Players:GetPlayers() end) or {}) do
        if p ~= lp and not isSelf(p) then
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
local function processHurtbox(o) if not o or not o:IsA("BasePart") or o.Name ~= "Torso_Hurtbox" or STATE.hurtboxSeen[o] then return end STATE.hurtboxSeen[o] = true safe(function() o.Size = CONFIG.HURTBOX_TARGET_SIZE end) end
local function scanHurtboxes()
    local e = STATE.entities
    if not e then e = safe(function() return workspace:FindFirstChild("Entities") end) if e then STATE.entities = e else return end end
    if not safe(function() return e.Parent end) then STATE.entities = nil STATE.hurtboxSeen = {} return end
    for _, o in ipairs(safe(function() return e:GetDescendants() end) or {}) do processHurtbox(o) end
end
local function makeESP(p)
    local lp = getLP() if not lp or p == lp or isSelf(p) then return end
    local n = safe(function() return p.Name end) if not n or blocked(n) or STATE.espObjs[p] then return end
    local function txt() local t = Draw("Text") t.Size = 13 t.Font = Drawing.Fonts.System t.Outline = true t.Center = true t.Visible = false t.ZIndex = 3 return t end
    local hp, pp, wp = txt(), txt(), txt()
    pp.Color = C3(80, 150, 255) wp.Color = C3(255, 180, 100)
    STATE.espObjs[p] = {hp = hp, pp = pp, wp = wp, lastChar = nil, maxCache = nil, wepCache = nil, wepTime = 0, head = nil, root = nil}
end
local function removeESP(p)
    local d = STATE.espObjs[p] if not d then return end
    for _, k in ipairs({"hp","pp","wp"}) do if d[k] then safe(function() d[k].Visible = false end) safe(function() d[k]:Remove() end) end end
    STATE.espObjs[p] = nil STATE.healthCache[p] = nil
end
local function updateESP()
    if not STATE.espOn then return end
    local lp, myPos = getLP(), getMyPos() if not lp then return end
    local rsq = CONFIG.ESP_RANGE * CONFIG.ESP_RANGE
    local now = tick()
    for p, d in next, STATE.espObjs do
        if p == lp or isSelf(p) then for _, k in ipairs({"hp","pp","wp"}) do if d[k] then d[k].Visible = false end end continue end
        local c = getChar(p)
        if c ~= d.lastChar then
            d.lastChar = c d.maxCache = nil d.wepCache = nil d.wepTime = 0
            d.head = c and getPart(c, "Head") d.root = c and getPart(c, "HumanoidRootPart")
        end
        if not d.head then for _, k in ipairs({"hp","pp","wp"}) do if d[k] then d[k].Visible = false end end continue end
        if myPos and d.root and CONFIG.ESP_RANGE > 0 then local rp = getPos(d.root) if rp and dist2(myPos, rp) > rsq then for _, k in ipairs({"hp","pp","wp"}) do if d[k] then d[k].Visible = false end end continue end end
        local hp = getPos(d.head) if not hp then for _, k in ipairs({"hp","pp","wp"}) do if d[k] then d[k].Visible = false end end continue end
        local ok, pos, onScreen = pcall(WorldToScreen, hp) if not ok or not onScreen or not pos then for _, k in ipairs({"hp","pp","wp"}) do if d[k] then d[k].Visible = false end end continue end
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
        if CONFIG.ESP.Weapon then if not d.wepCache or now - d.wepTime > 1 then d.wepCache = getWeapon(p, c) d.wepTime = now end d.wp.Text = d.wepCache d.wp.Position = V2(pos.X, pos.Y-4) d.wp.Visible = true else d.wp.Visible = false end
    end
end
local function updatePlayers()
    if not STATE.espOn then return end
    local lp = getLP() if not lp then return end
    local all = safe(function() return Players:GetPlayers() end) or {}
    for _, p in ipairs(all) do if p ~= lp and not isSelf(p) and not STATE.players[p] then STATE.players[p] = true makeESP(p) end end
    for p in next, STATE.players do local here = false for _, v in ipairs(all) do if v == p then here = true break end end if not here then STATE.players[p] = nil removeESP(p) end end
end
local function doCleanup()
    STATE.running = false STATE.enabled = false STATE.target = nil
    for p, d in next, STATE.espObjs do if d then for _, k in ipairs({"hp","pp","wp"}) do if d[k] then safe(function() d[k].Visible = false end) safe(function() d[k]:Remove() end) end end end end
    STATE.espObjs = {} STATE.healthCache = {} STATE.cachedTargets = {} STATE.players = {} STATE.hurtboxSeen = {} STATE.entities = nil
end
_G.VaultCleanup = doCleanup
local function isValid() return Players and getLP() and safe(function() return game.PlaceId end) ~= nil end
local function onKey(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode[CONFIG.TOGGLE_KEY:upper()] then
        if STATE.debounce.toggle then return end STATE.debounce.toggle = true CONFIG.AUTO_ATTACK = not CONFIG.AUTO_ATTACK notify("Vault", "Auto Attack: " .. (CONFIG.AUTO_ATTACK and "ON" or "OFF"), 3) wait(0.3) STATE.debounce.toggle = false
    end
    if input.KeyCode == Enum.KeyCode[CONFIG.ESP_TOGGLE_KEY:upper()] then
        if STATE.debounce.esp then return end STATE.debounce.esp = true STATE.espOn = not STATE.espOn
        if not STATE.espOn then
            for p, d in next, STATE.espObjs do if d then for _, k in ipairs({"hp","pp","wp"}) do if d[k] then safe(function() d[k].Visible = false end) safe(function() d[k]:Remove() end) end end end end
            STATE.espObjs = {} STATE.healthCache = {} STATE.cachedTargets = {} STATE.players = {} notify("Vault", "ESP: REMOVED", 3)
        else notify("Vault", "ESP: ON", 3) end
        wait(0.3) STATE.debounce.esp = false
    end
    if input.KeyCode == Enum.KeyCode[CONFIG.HITBOX_TOGGLE_KEY:upper()] then
        if STATE.debounce.hitbox then return end STATE.debounce.hitbox = true STATE.hitboxLarge = not STATE.hitboxLarge
        if STATE.hitboxLarge then CONFIG.HURTBOX_TARGET_SIZE = V3(25, 25, 25) notify("Vault", "Hitbox: LARGE", 3) else CONFIG.HURTBOX_TARGET_SIZE = V3(2.1, 2.1, 1.05) notify("Vault", "Hitbox: NORMAL", 3) end
        STATE.hurtboxSeen = {} safe(scanHurtboxes) wait(0.3) STATE.debounce.hitbox = false
    end
end
if UIS then UIS.InputBegan:Connect(onKey) end
local function main()
    STATE.enabled = true STATE.target = nil
    local lp = nil for _ = 1, 100 do lp = getLP() if lp then break end wait(0.1) end if not lp then return end
    for _, p in ipairs(safe(function() return Players:GetPlayers() end) or {}) do if p ~= lp and not isSelf(p) and STATE.espOn then makeESP(p) STATE.players[p] = true end end
    if STATE.espObjs[lp] then removeESP(lp) end
    local lastId = safe(function() return game.PlaceId end) or 0
    spawn(function() while STATE.running do safe(updateESP) local s = tick() wait(0.008) if tick()-s > 0.05 then wait(0.001) end local cid = safe(function() return game.PlaceId end) if not cid or cid ~= lastId then doCleanup() break end if not safe(function() return Players.LocalPlayer end) then doCleanup() break end end end)
    spawn(function() while STATE.running do if STATE.enabled then safe(updateAura) end wait(0.01) end end)
    spawn(function() while STATE.running do safe(updatePlayers) wait(0.5) end end)
    spawn(function() wait(1) while STATE.running do safe(scanHurtboxes) wait(CONFIG.HURTBOX_SCAN_INTERVAL) end end)
    for _ = 1, 50 do if getMyPos() then break end wait(0.1) end
end
if isValid() then safe(main) notify("Vault", "Cutie Patootie", 7) end
