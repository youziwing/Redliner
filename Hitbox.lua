local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local localPlayer = Players.LocalPlayer

local isBigSize = true
local bigSize = Vector3.new(30, 30, 30)
local normalSize = Vector3.new(1.05, 2.1, 1.05)

local function getTargetSize()
    if isBigSize then
        return bigSize
    else
        return normalSize
    end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.H then
        isBigSize = not isBigSize
        
        if isBigSize then
            notify("Hitbox", "Big", 3)
        else
            notify("Hitbox", "Normal", 3)
        end
    end
end)

while true do
    task.wait(1)
    
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= localPlayer then
            pcall(function()
                local hurtbox = game.Workspace.Entities[player.Name].Hurtboxes.Torso_Hurtbox
                if hurtbox then
                    hurtbox.Size = getTargetSize()
                end
            end)
        end
    end
end
