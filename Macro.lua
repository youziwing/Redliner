-- Matcha LuaVM Speed Macro
-- Uses polling loop with iskeypressed() since Matcha has no UserInputService

local keybind_macrospeed = MacroKeybind or "R"

-- Windows Virtual Key Codes (Matcha uses these, not strings)
local VK = {
    LSHIFT = 0x10,      -- Left Shift
    S = 0x53,           -- S key
    SPACE = 0x20,       -- Spacebar
    W = 0x57,           -- W key
    R = 0x52,           -- R key (default bind)
}

-- Get the VK code for the keybind
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

print("Speed macro loaded. Press", keybind_macrospeed, "to activate.")

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
