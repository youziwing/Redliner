local _ENV = getfenv()

local keybind_macrospeed = _ENV.MacroKeybind or "R"

local keys = {}
keys.leftshift = 0x10
keys.s = 0x53
keys.spacebar = 0x20
keys.w = 0x57

local macrodb = false

local function performSpeedMacro()
	if macrodb then return end
	macrodb = true
	
	_ENV.keyrelease(keys.w)
	_ENV.keypress(keys.s)
	task.wait(0.02)

	_ENV.keypress(keys.leftshift)
	task.wait(0.01)
	_ENV.keypress(keys.spacebar)
	_ENV.mouse2press()
	_ENV.keyrelease(keys.s)
	task.wait(0.05)

	_ENV.keyrelease(keys.leftshift)
	_ENV.mouse2press()

	task.wait(0.05)
	task.wait(0.05)
	_ENV.mouse2release()
	_ENV.keypress(keys.w)
	task.wait(0.1)

	macrodb = false
end

game:GetService("UserInputService").InputBegan:Connect(function(inp, gps)
	if gps then return end
	if inp.KeyCode == Enum.KeyCode[keybind_macrospeed] then
		performSpeedMacro()
	end
end)
