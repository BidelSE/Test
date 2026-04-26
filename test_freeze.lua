script_name('test_freeze')
script_version('1.0')
require 'lib.moonloader'

-- F8: toggle freeze test
-- Sets _G.VR_TEST_FREEZE which the main bot reads in handleFreeze.
-- The bot then stops all inputs and enters frozen-state handling naturally.

function main()
    wait(0)
    _G.VR_TEST_FREEZE = false
    while true do
        wait(0)

        if isKeyJustPressed(VK_F8) then
            if isCharInAnyCar(PLAYER_PED) then
                _G.VR_TEST_FREEZE = not _G.VR_TEST_FREEZE
                if _G.VR_TEST_FREEZE then
                    printStringNow("~y~TEST: Frizinamas... (F8 - isfrizinti)", 2000)
                else
                    printStringNow("~g~TEST: Isfrizinta!", 2000)
                end
            else
                printStringNow("~r~TEST: Turi buti masinos viduje!", 2000)
            end
        end
    end
end
