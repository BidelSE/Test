script_name('hud_aswd')
script_version('1.2')
require 'lib.moonloader'

-- Draws a live WASD input overlay showing what the bot is pressing.
-- Reads state exported by dangis_vr via shared state file + globals.
-- Position: left side, adaptive vertical position.

local font = nil
local BX, BY = 30, 300
local SZ = 30
local shared_state_file = getWorkingDirectory() .. "/dangis_vr_state.txt"
local freeze_flag_file = getWorkingDirectory() .. "/dangis_vr_freeze.flag"

local state, gas, brake, steer, lastUpdate = "IDLE", 0, 0, 0, 0

local function fileExists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

local function readSharedState()
    local file = io.open(shared_state_file, "r")
    if not file then return end
    state = file:read("*l") or "IDLE"
    gas = tonumber(file:read("*l")) or 0
    brake = tonumber(file:read("*l")) or 0
    steer = tonumber(file:read("*l")) or 0
    lastUpdate = tonumber(file:read("*l")) or 0
    file:close()
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

        readSharedState()
        if font then
            local bx, by = hudPosition()
            local textCol = (lastUpdate > 0 and os.clock() - lastUpdate < 2.0) and 0xFFFFFFFF or 0xFF999999

            local wCol = gas   > 50  and 0xFF33DD33 or 0xFF2A2A2A
            local sCol = brake > 50  and 0xFFDD3333 or 0xFF2A2A2A
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

            if fileExists(freeze_flag_file) then
                renderFontDrawText(font, "FREEZE TEST", bx, by + SZ * 2 + 18, 0xFFFFFF00)
            end
        end
    end
end
