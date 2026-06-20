local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

while true do
	task.wait(1)
	
	for _, player in pairs(Players:GetPlayers()) do
		if player ~= localPlayer then
			pcall(function()
				local hurtbox = game.Workspace.Entities[player.Name].Hurtboxes.Torso_Hurtbox
				if hurtbox then
					hurtbox.Size = Vector3.new(30, 30, 30)
				end
			end)
		end
	end
end
