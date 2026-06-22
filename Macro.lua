local keybind_macrospeed = MacroKeybind or "R"

local keys = {}
keys.leftshift = 0x10
keys.s = 0x53
keys.spacebar = 0x20
keys.w = 0x57

local macrodb = false

local function performSpeedMacro()
	if macrodb then return end
	macrodb = true
	
	keyrelease(keys.w)
	keypress(keys.s)
	task.wait(0.02)

	keypress(keys.leftshift)
	task.wait(0.01)
	keypress(keys.spacebar)
	mouse2press()
	keyrelease(keys.s)
	task.wait(0.05)

	keyrelease(keys.leftshift)
	mouse2press()

	task.wait(0.05)
	task.wait(0.05)
	mouse2release()
	keypress(keys.w)
	task.wait(0.1)

	macrodb = false
end

game:GetService("UserInputService").InputBegan:Connect(function(inp, gps)
	if gps then return end
	if inp.KeyCode == Enum.KeyCode[keybind_macrospeed] then
		performSpeedMacro()
	end
end)
