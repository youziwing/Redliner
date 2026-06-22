local _ENV = getfenv()

local Players = _ENV.game:GetService("Players")
local UIS = _ENV.game:GetService("UserInputService")
local RunSvc = _ENV.game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

local Settings = {
    Enabled = false,
    Keybind = _ENV.MacroKeybind or _ENV.Enum.KeyCode.X,
    Cooldown = 0.12,
    DebounceTime = 0.15
}

local States = {
    OnCooldown = false,
    IsRunning = false
}

UIS.InputBegan:Connect(function(Input, Chatting)
    if Chatting then return end
    if Input.KeyCode ~= Settings.Keybind then return end
    
    Settings.Enabled = not Settings.Enabled
    
    local Status = Settings.Enabled and "ACTIVE" or "DISABLED"
    print(string.format("[Macro] Speed boost %s", Status))
end)

local function Press(Key)
    _ENV.keypress(Key)
end

local function Release(Key)
    _ENV.keyrelease(Key)
end

local function Hold(Duration, ...)
    local Keys = {...}
    for _, K in ipairs(Keys) do
        Press(K)
    end
    task.wait(Duration)
    for _, K in ipairs(Keys) do
        Release(K)
    end
end

local function Click()
    _ENV.mouse2press()
    task.wait()
    _ENV.mouse2release()
end

local function ExecuteSequence()
    if States.OnCooldown or States.IsRunning then return end
    if not Settings.Enabled then return end
    
    States.IsRunning = true
    States.OnCooldown = true
    
    Release(_ENV.keys.w)
    Hold(0.02, _ENV.keys.s)
    
    Press(_ENV.keys.leftshift)
    task.wait(0.01)
    
    Press(_ENV.keys.spacebar)
    Click()
    Release(_ENV.keys.s)
    task.wait(0.05)
    
    Release(_ENV.keys.leftshift)
    Click()
    task.wait(0.1)
    
    Press(_ENV.keys.w)
    task.wait(Settings.Cooldown)
    
    States.IsRunning = false
    
    task.delay(Settings.DebounceTime, function()
        States.OnCooldown = false
    end)
end

RunSvc.Heartbeat:Connect(function()
    if not Settings.Enabled then return end
    ExecuteSequence()
end)

LocalPlayer.CharacterAdded:Connect(function(NewChar)
    Character = NewChar
    States.OnCooldown = false
    States.IsRunning = false
    Settings.Enabled = false
end)
