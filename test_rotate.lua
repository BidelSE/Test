script_name('test_rotate')
script_version('1.0')
require 'lib.moonloader'

-- F4  : rotate car 180 degrees
--       _G.VR_TEST_ROTATE = true  → main bot stops inputs but does NOT crash (resumes after ~3-8s)
--       _G.VR_TEST_ROTATE = false → main bot reacts with real crash (default, for full test)
-- F4 + hold Shift: enable safe mode (no crash) before rotating

local safeMode = false

function main()
    wait(0)
    _G.VR_TEST_ROTATE = false
    while true do
        wait(0)

        safeMode = isKeyDown(0x10)  -- Left/Right Shift held = safe mode

        if isKeyJustPressed(VK_F4) then
            if isCharInAnyCar(PLAYER_PED) then
                local car = storeCarCharIsInNoSave(PLAYER_PED)
                local h = getCarHeading(car)
                _G.VR_TEST_ROTATE = safeMode
                setCarHeading(car, (h + 180.0) % 360.0)
                if safeMode then
                    printStringNow("~y~TEST: Pasukta 180 (saugus - atsipirks)!", 2000)
                else
                    printStringNow("~r~TEST: Pasukta 180 (tikras - suges)!", 2000)
                end
                lua_thread.create(function()
                    wait(10000)
                    _G.VR_TEST_ROTATE = false
                end)
            else
                printStringNow("~r~TEST: Turi buti masinos viduje!", 2000)
            end
        end
    end
end
