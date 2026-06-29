local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local STAFF_USERNAMES = {
    ["cubxfy"] = true,
    ["smiibs"] = true,
    ["rematchin"] = true,
    ["xxlightfox420xx"] = true,
    ["jarnemans"] = true,
    ["expert_zerby"] = true,
    ["pear4357"] = true,
    ["sshanzyo"] = true,
    ["misakinzx"] = true,
    ["fwswtr"] = true,
    ["scaredofscaryclowns"] = true,
    ["asciimynetzach"] = true,
    ["luy45"] = true,
    ["luckymstr"] = true,
    ["dere1235"] = true,
}

local alerted = {}

local function alertStaff(player)
    local name = player.Name or "Unknown"
    local display = player.DisplayName or name
    local msg = string.format("%s (@%s)", display, name)
    warn("[Mod] " .. msg)
    notify("Staff Detected", msg, 7)
end

local function isStaff(player)
    if not player then return false end
    local name = player.Name
    if not name then return false end
    return STAFF_USERNAMES[string.lower(name)] == true
end

local function processPlayer(player)
    if not player or not player.Name then return end
    local key = string.lower(player.Name)
    if alerted[key] then return end
    alerted[key] = true
    if isStaff(player) then
        alertStaff(player)
    end
end

local function scanAllPlayers()
    local list = Players:GetPlayers()
    if not list then return end
    for _, player in ipairs(list) do
        processPlayer(player)
    end
end

RunService.Heartbeat:Connect(function()
    local list = Players:GetPlayers()
    if not list then return end
    for _, player in ipairs(list) do
        processPlayer(player)
    end
end)

pcall(function()
    if Players.PlayerAdded then
        Players.PlayerAdded:Connect(processPlayer)
    end
end)

print("Slayyyy")
scanAllPlayers()
