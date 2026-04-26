script_name('test_freeze')
script_version('1.0')
require 'lib.moonloader'

-- F8: toggle freeze test
-- Locks the car in place while active so the bot can't move.
-- Sets _G.VR_TEST_FREEZE which the main bot reads in handleFreeze.
-- The bot then stops all inputs and enters frozen-state handling naturally.

local frozenX, frozenY, frozenZ = 0, 0, 0

function main()
    wait(0)
    _G.VR_TEST_FREEZE = false
    while true do
        wait(0)

        if isKeyJustPressed(VK_F8) then
            if isCharInAnyCar(PLAYER_PED) then
                _G.VR_TEST_FREEZE = not _G.VR_TEST_FREEZE
                if _G.VR_TEST_FREEZE then
                    local car = storeCarCharIsInNoSave(PLAYER_PED)
                    frozenX, frozenY, frozenZ = getCarCoordinates(car)
                    printStringNow("~y~TEST: Frizinamas... (F8 - isfrizinti)", 2000)
                else
                    printStringNow("~g~TEST: Isfrizinta!", 2000)
                end
            else
                printStringNow("~r~TEST: Turi buti masinos viduje!", 2000)
            end
        end

        if _G.VR_TEST_FREEZE and isCharInAnyCar(PLAYER_PED) then
            local car = storeCarCharIsInNoSave(PLAYER_PED)
            setCarCoordinates(car, frozenX, frozenY, frozenZ)
        end
    end
end
