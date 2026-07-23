local keybind_macrospeed = MacroKeybind or "R"

local VK = {
    LSHIFT = 0x10,
    S = 0x53,
    SPACE = 0x20,
    W = 0x57,
    R = 0x52,
}

local function getVK(key)
    return VK[key:upper()] or VK.R
end

local macroBindVK = getVK(keybind_macrospeed)

local macrodb = false
local wasKeyDown = false

setrobloxinput(true)

local function performSpeedMacro()
    if macrodb then return end
    macrodb = true

    keyrelease(VK.W)
    keypress(VK.S)
    wait(0.02)

    keypress(VK.LSHIFT)
    wait(0.01)
    keypress(VK.SPACE)
    mouse2press()
    keyrelease(VK.S)
    wait(0.05)

    keyrelease(VK.LSHIFT)
    mouse2press()

    wait(0.10)
    mouse2release()

    keypress(VK.W)
    wait(0.1)

    macrodb = false
end

while true do
    if isrbxactive() then
        local isDown = iskeypressed(macroBindVK)
        
        if isDown and not wasKeyDown and not macrodb then
            performSpeedMacro()
        end
        
        wasKeyDown = isDown
    end
    
    wait(0.05)
end
