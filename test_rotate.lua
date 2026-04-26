script_name('test_rotate')
script_version('1.0')
require 'lib.moonloader'

-- F4        : rotate car 180 degrees (safe mode — bot stops inputs, resumes after 3-8s)
-- Ctrl+F4   : rotate car 180 degrees (real crash mode — bot detects and kills SAMP)

function main()
    wait(0)
    _G.VR_TEST_ROTATE = true
    while true do
        wait(0)

        if isKeyJustPressed(VK_F4) then
            if isCharInAnyCar(PLAYER_PED) then
                local car = storeCarCharIsInNoSave(PLAYER_PED)
                local h = getCarHeading(car)
                local realCrash = isKeyDown(0x11)  -- Ctrl held = real crash
                _G.VR_TEST_ROTATE = not realCrash
                setCarHeading(car, (h + 180.0) % 360.0)
                if not realCrash then
                    printStringNow("~y~TEST: Pasukta 180 (saugus - atsipirks)!", 2000)
                else
                    printStringNow("~r~TEST: Pasukta 180 (tikras - suges)!", 2000)
                end
                lua_thread.create(function()
                    wait(10000)
                    _G.VR_TEST_ROTATE = true
                end)
            else
                printStringNow("~r~TEST: Turi buti masinos viduje!", 2000)
            end
        end
    end
end
