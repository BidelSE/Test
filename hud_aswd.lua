script_name('hud_aswd')
script_version('1.3')
require 'lib.moonloader'

-- Draws a live WASD input overlay showing what the bot is pressing.
-- Reads the state dangis_vr writes to dangis_vr_state.txt. MoonLoader scripts
-- cannot see each other's globals, so that file is the only channel.
-- Position: left side, adaptive vertical position.

local font = nil
local BX, BY = 30, 300
local SZ = 30
local READ_INTERVAL = 0.1
local shared_state_file = getWorkingDirectory() .. "/dangis_vr_state.txt"
local freeze_flag_file = getWorkingDirectory() .. "/dangis_vr_freeze.flag"

local state, gas, brake, steer, lastUpdate, reversing = "IDLE", 0, 0, 0, 0, false
local freezeTest = false
local lastReadAt = -1

local function fileExists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

-- Keeps the previous values when the file is missing or caught half-written.
-- Lines: state, gas, brake, steer, timestamp, reversing (1/0, optional).
local function readSharedState()
    local file = io.open(shared_state_file, "r")
    if not file then return end
    local newState = file:read("*l")
    local newGas = tonumber(file:read("*l"))
    local newBrake = tonumber(file:read("*l"))
    local newSteer = tonumber(file:read("*l"))
    local newUpdate = tonumber(file:read("*l"))
    local newReverse = file:read("*l")
    file:close()
    if not newState or newState == "" or not newGas or not newBrake or not newSteer or not newUpdate then
        return
    end
    state, gas, brake, steer, lastUpdate = newState, newGas, newBrake, newSteer, newUpdate
    reversing = newReverse == "1"
end

local function hudPosition()
    local x, y = BX, BY
    if getScreenResolution then
        local _, sh = getScreenResolution()
        if sh and sh > 0 then
            y = math.max(220, math.floor(sh * 0.42))
        end
    end
    return x, y
end

function main()
    wait(0)
    while true do
        wait(0)

        if not font then
            font = renderCreateFont("Arial", 12, 1)
        end

        -- The bot writes at most every 50 ms; reading every frame only costs I/O.
        local now = os.clock()
        if now - lastReadAt >= READ_INTERVAL then
            lastReadAt = now
            readSharedState()
            freezeTest = fileExists(freeze_flag_file)
        end
        if font then
            local bx, by = hudPosition()
            local textCol = (lastUpdate > 0 and now - lastUpdate < 2.0) and 0xFFFFFFFF or 0xFF999999

            local wCol = gas   > 50  and 0xFF33DD33 or 0xFF2A2A2A
            local sCol = (brake > 50 or reversing) and 0xFFDD3333 or 0xFF2A2A2A
            local aCol = steer < -60 and 0xFFFF9900 or 0xFF2A2A2A
            local dCol = steer >  60 and 0xFFFF9900 or 0xFF2A2A2A

            renderDrawBox(bx - 5, by - 20, SZ * 3 + 10, SZ * 2 + 44, 0xAA000000)
            renderFontDrawText(font, "VR INPUT", bx, by - 17, 0xFFFFFF00)
            --   [ W ]
            -- [A][S][D]
            renderDrawBox(bx + SZ,     by,      SZ, SZ, wCol)
            renderDrawBox(bx,          by + SZ, SZ, SZ, aCol)
            renderDrawBox(bx + SZ,     by + SZ, SZ, SZ, sCol)
            renderDrawBox(bx + SZ * 2, by + SZ, SZ, SZ, dCol)

            renderFontDrawText(font, "W", bx + SZ + 10,     by + 7,      0xFF000000)
            renderFontDrawText(font, "A", bx + 10,          by + SZ + 7, 0xFF000000)
            renderFontDrawText(font, "S", bx + SZ + 10,     by + SZ + 7, 0xFF000000)
            renderFontDrawText(font, "D", bx + SZ * 2 + 10, by + SZ + 7, 0xFF000000)
            renderFontDrawText(font, state, bx, by + SZ * 2 + 4, textCol)

            if freezeTest then
                renderFontDrawText(font, "FREEZE TEST", bx, by + SZ * 2 + 18, 0xFFFFFF00)
            end
        end
    end
end
