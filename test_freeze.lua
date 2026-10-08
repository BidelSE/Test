script_name('test_freeze')
script_version('1.5')
require 'lib.moonloader'

-- F8: toggle freeze test
-- Locks the car in place while active so the bot can't move.
-- Signals the bot through dangis_vr_freeze.flag (MoonLoader scripts cannot
-- see each other's globals); the bot then runs its normal freeze recovery.
-- Auto-unfreezes 1 s after the bot writes FREEZE_REFRESH to the shared state.

local frozenX, frozenY, frozenZ = 0, 0, 0
local freezeActive = false
local freeze_flag_file = getWorkingDirectory() .. "/dangis_vr_freeze.flag"
local shared_state_file = getWorkingDirectory() .. "/dangis_vr_state.txt"
local pendingUnfreezeAt = 0
local lastStateReadAt = -1
local lastBotState = nil

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

-- Read at most every 50 ms; a half-written file keeps the last known state.
local function readBotState()
    local now = os.clock()
    if now - lastStateReadAt < 0.05 then return lastBotState end
    lastStateReadAt = now
    local file = io.open(shared_state_file, "r")
    if not file then return lastBotState end
    local state = file:read("*l")
    file:close()
    if state and state ~= "" then
        lastBotState = state
    end
    return lastBotState
end

local function stopFreeze(message)
    freezeActive = false
    pendingUnfreezeAt = 0
    setFreezeFlag(false)
    printStringNow(message, 2000)
end

-- A flag left behind by a reload would keep the bot holding the car still.
function onScriptTerminate(scr)
    if scr == thisScript() then
        os.remove(freeze_flag_file)
    end
end

function main()
    wait(0)
    freezeActive = false
    pendingUnfreezeAt = 0
    setFreezeFlag(false)
    while true do
        wait(0)

        if isKeyJustPressed(VK_F8) then
            if freezeActive then
                stopFreeze("~g~TEST: Isfrizinta!")
            elseif isCharInAnyCar(PLAYER_PED) then
                local car = storeCarCharIsInNoSave(PLAYER_PED)
                frozenX, frozenY, frozenZ = getCarCoordinates(car)
                freezeActive = true
                pendingUnfreezeAt = 0
                setFreezeFlag(true)
                printStringNow("~y~TEST: Frizinamas... (F8 - isfrizinti)", 2000)
            else
                printStringNow("~r~TEST: Turi buti masinos viduje!", 2000)
            end
        end

        if freezeActive and isCharInAnyCar(PLAYER_PED) then
            local car = storeCarCharIsInNoSave(PLAYER_PED)
            setCarCoordinates(car, frozenX, frozenY, frozenZ)
            if pendingUnfreezeAt == 0 and readBotState() == "FREEZE_REFRESH" then
                pendingUnfreezeAt = os.clock() + 1.0
            end
            if pendingUnfreezeAt > 0 and os.clock() >= pendingUnfreezeAt then
                stopFreeze("~g~TEST: Refresh aptiktas, frizas paleistas!")
            end
        end
    end
end
