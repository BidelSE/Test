script_name('test_freeze')
script_version('1.4')
require 'lib.moonloader'

-- F8: toggle freeze test
-- Locks the car in place while active so the bot can't move.
-- Sets _G.VR_TEST_FREEZE which the main bot reads in handleFreeze.
-- The bot then stops all inputs and enters frozen-state handling naturally.
-- Auto-unfreezes when bot writes FREEZE_REFRESH to shared state.

local frozenX, frozenY, frozenZ = 0, 0, 0
local freeze_flag_file = getWorkingDirectory() .. "/dangis_vr_freeze.flag"
local shared_state_file = getWorkingDirectory() .. "/dangis_vr_state.txt"
local pendingUnfreezeAt = 0

local function setFreezeFlag(active)
    if active then
        local file = io.open(freeze_flag_file, "w")
        if file then
            file:write("1\n")
            file:close()
        end
    else
        os.remove(freeze_flag_file)
    end
end

local function readBotState()
    local file = io.open(shared_state_file, "r")
    if not file then return nil end
    local state = file:read("*l")
    file:close()
    return state
end

function main()
    wait(0)
    _G.VR_TEST_FREEZE = false
    pendingUnfreezeAt = 0
    setFreezeFlag(false)
    while true do
        wait(0)

        if isKeyJustPressed(VK_F8) then
            if isCharInAnyCar(PLAYER_PED) then
                _G.VR_TEST_FREEZE = not _G.VR_TEST_FREEZE
                if _G.VR_TEST_FREEZE then
                    local car = storeCarCharIsInNoSave(PLAYER_PED)
                    frozenX, frozenY, frozenZ = getCarCoordinates(car)
                    pendingUnfreezeAt = 0
                    setFreezeFlag(true)
                    printStringNow("~y~TEST: Frizinamas... (F8 - isfrizinti)", 2000)
                else
                    pendingUnfreezeAt = 0
                    setFreezeFlag(false)
                    printStringNow("~g~TEST: Isfrizinta!", 2000)
                end
            else
                printStringNow("~r~TEST: Turi buti masinos viduje!", 2000)
            end
        end

        if _G.VR_TEST_FREEZE and isCharInAnyCar(PLAYER_PED) then
            local car = storeCarCharIsInNoSave(PLAYER_PED)
            setCarCoordinates(car, frozenX, frozenY, frozenZ)
            if pendingUnfreezeAt == 0 and readBotState() == "FREEZE_REFRESH" then
                pendingUnfreezeAt = os.clock() + 1.0
            end
            if pendingUnfreezeAt > 0 and os.clock() >= pendingUnfreezeAt then
                _G.VR_TEST_FREEZE = false
                pendingUnfreezeAt = 0
                setFreezeFlag(false)
                printStringNow("~g~TEST: Refresh aptiktas, frizas paleistas!", 2000)
            end
        end
    end
end
