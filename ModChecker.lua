local Players = game:GetService("Players")

-- redliner mods
local STAFF_IDS = {
    [833111475]  = true,
    [465617580]  = true,
    [12946313]   = true,
    [423972562]  = true,
    [86930434]   = true,
    [919857618]  = true,
    [907424331]  = true,
    [3554368424] = true,
    [3901099809] = true,
    [151047265]  = true,
    [10414427598]= true,
    [34772947]   = true,
    [75119385]   = true,
    [1527191625] = true,
    [199337439]  = true,
    [72929869]   = true,
}

local function alertStaffDetected(player)
    local userId = player.UserId
    local name = player.Name
    local displayName = player.DisplayName

    warn(string.format(
        "Mod In Game | %s (@%s) | UserId: %d",
        displayName,
        name,
        userId
    ))
end

local function checkPlayer(player)
    if STAFF_IDS[player.UserId] then
        alertStaffDetected(player)
    end
end

Players.PlayerAdded:Connect(checkPlayer)

for _, player in ipairs(Players:GetPlayers()) do
    checkPlayer(player)
end

print("Slayyy" .. tostring(#STAFF_IDS) .. " IDs.")
