script_name('hud_aswd')
script_version('1.0')
require 'lib.moonloader'

-- Draws a live WASD input overlay showing what the bot is pressing.
-- Reads state exported by dangis_vr via _G.VR_gas / VR_brake / VR_steer / VR_playing.
-- Position: bottom-left, just to the right of the minimap.

local font = nil
local BX, BY = 160, 540   -- screen position (adjust if minimap overlaps)
local SZ = 22              -- box size in pixels

function main()
    wait(0)
    while true do
        wait(0)

        if not font then
            font = renderCreateFont("Arial", 12, 1)
        end

        local isPlaying = _G.VR_playing and (os.clock() - _G.VR_playing) < 0.2
        if isPlaying and font then
            local gas   = _G.VR_gas   or 0
            local brake = _G.VR_brake or 0
            local steer = _G.VR_steer or 0

            local wCol = gas   > 50  and 0xFF33DD33 or 0xFF2A2A2A
            local sCol = brake > 50  and 0xFFDD3333 or 0xFF2A2A2A
            local aCol = steer < -60 and 0xFFFF9900 or 0xFF2A2A2A
            local dCol = steer >  60 and 0xFFFF9900 or 0xFF2A2A2A

            --   [ W ]
            -- [A][S][D]
            renderDrawBox(BX + SZ,     BY,      SZ, SZ, wCol)
            renderDrawBox(BX,          BY + SZ, SZ, SZ, aCol)
            renderDrawBox(BX + SZ,     BY + SZ, SZ, SZ, sCol)
            renderDrawBox(BX + SZ * 2, BY + SZ, SZ, SZ, dCol)

            renderFontDrawText(font, "W", BX + SZ + 7,     BY + 4,      0xFF000000)
            renderFontDrawText(font, "A", BX + 7,          BY + SZ + 4, 0xFF000000)
            renderFontDrawText(font, "S", BX + SZ + 7,     BY + SZ + 4, 0xFF000000)
            renderFontDrawText(font, "D", BX + SZ * 2 + 7, BY + SZ + 4, 0xFF000000)

            if _G.VR_TEST_FREEZE then
                renderFontDrawText(font, "FREEZE TEST", BX, BY + SZ * 2 + 4, 0xFFFFFF00)
            end
        end

    end
end
