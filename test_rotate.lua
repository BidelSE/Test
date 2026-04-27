script_name('test_rotate')
script_version('1.3')
require 'lib.moonloader'

-- F4        : rotate car 180 degrees (safe mode — bot stops inputs, resumes after 3-8s)
-- Ctrl+F4   : rotate car 180 degrees (real crash mode — bot detects and kills SAMP)

function main()
    wait(0)
    _G.VR_TEST_ROTATE = true
    local rotate_flag_file = getWorkingDirectory() .. "/dangis_vr_rotate.flag"
    os.remove(rotate_flag_file)
    while true do
        wait(0)

        if isKeyJustPressed(VK_F4) then
            if isCharInAnyCar(PLAYER_PED) then
                local car = storeCarCharIsInNoSave(PLAYER_PED)
                local h = getCarHeading(car)
                local realCrash = isKeyDown(0x11)  -- Ctrl held = real crash
                _G.VR_TEST_ROTATE = not realCrash
                local file = io.open(rotate_flag_file, "w")
                if file then
                    file:write(realCrash and "crash\n" or "safe\n")
                    file:close()
                end
                setCarHeading(car, (h + 180.0) % 360.0)
                _G.VR_ADMIN_ROTATED = true
                if not realCrash then
                    printStringNow("~y~TEST: Pasukta 180 (reakcija + pauze)!", 2000)
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
