script_name('dangis_vr')
script_version('5.9')
require 'lib.moonloader'

local recording = false
local playing = false
local repeating = false
local paused = false
local current_route = {}
local play_index = 1
local current_name = "route1"
local paths_dir = getWorkingDirectory() .. "/dangis_paths/"
local shared_state_file = getWorkingDirectory() .. "/dangis_vr_state.txt"
local freeze_flag_file = getWorkingDirectory() .. "/dangis_vr_freeze.flag"
local rotate_flag_file = getWorkingDirectory() .. "/dangis_vr_rotate.flag"
local dialog_flag_file = getWorkingDirectory() .. "/dangis_vr_dialog.flag"
local start_x, start_y, start_z = 0, 0, 0
local routeRadius = 8.0
local tick = 0
local recordingDelay = 80
local lastRecordHeading = 0

local lastSteerValue = 0
local steerNoiseValue = 0
local steerNoiseDuration = 0
local steerNoiseCooldown = 0
local overrideActive = false

local lastX, lastY = 0.0, 0.0
local freezeTimer = 0
local lastCarHeading = 0
local reverseTimer = 0

local steerBuf = {0, 0}
local gasLevel = 0
local brakeLevel = 0
local pauseReleaseReason = ""
local lastDriveSpeed = 0.0
local suddenStopFrames = 0



local showTrail = false
local currentTrail = {}
local lastTrail = {}
local trailTick = 0

local samp = 0
local isCrashing = false
local arbotasHandled = false

local S = {
    gasLiftFrames = 0, nextGasLift = 0,
    lapWander = 0.0, lapCount = 0, nextBreakTime = 0, autoPaused = false,
    currentLateral = 0.0, nudgeOffset = 0.0, nudgeFrames = 0, nextNudge = 0,
    manualPaused = false,
    frozenByAdmin = false, refreshSent = false, refreshTarget = 300,
    testArbotasPaused = false,
    dialogPaused = false,
    freezeTestLatched = false,
    freezeFightUntil = 0.0,
    freezeReleaseUntil = 0.0,
    freezeRefreshAt = 0.0,
    freezeRecoveryGraceUntil = 0.0,
    freezeNextTwitch = 0.0,
    freezeTwitchUntil = 0.0,
    freezeSteer = 0,
    freezeTwitchDir = 1,
    rotateFightUntil = 0.0,
    rotateReleaseUntil = 0.0,
}

local LOOKAHEAD = 6

local function doForceCrash()
    local ffiok, ffi = pcall(require, "ffi")
    if ffiok and ffi then
        pcall(ffi.cdef, "void* GetCurrentProcess(); int TerminateProcess(void*, unsigned int);")
        local k32ok, k32 = pcall(ffi.load, "kernel32")
        if k32ok then
            k32.TerminateProcess(k32.GetCurrentProcess(), 1)
        end
        pcall(ffi.cdef, "void abort();")
        ffi.C.abort()
    end
    for i = 0, 15 do
        writeMemory(0xB6F5F0 + i * 4, 4, 0, false)
    end
    callFunction(0, 0, 0)
end

local function saveRoute(name, route)
    local file = io.open(paths_dir .. name .. ".txt", "w")
    if file then
        for _, p in ipairs(route) do
            file:write(string.format('{%s}:{%s}:{%s}:{%s}:{%s}\n', p.x, p.y, p.z, p.speed, p.heading))
        end
        file:close()
        return true
    end
    return false
end

local function loadRoute(name)
    local file = io.open(paths_dir .. name .. ".txt", "r")
    if file then
        local route = {}
        for line in file:lines() do
            local x, y, z, speed, heading = line:match('{(.*)}:{(.*)}:{(.*)}:{(.*)}:{(.*)}')
            if x then
                table.insert(route, {x=tonumber(x), y=tonumber(y), z=tonumber(z) or 0, speed=tonumber(speed) or 0, heading=tonumber(heading) or 0})
            else
                local ox, oy, os2 = line:match('{(.*)}:{(.*)}:{(.*)}')
                if ox then
                    table.insert(route, {x=tonumber(ox), y=tonumber(oy), z=0, speed=tonumber(os2) or 0, heading=0})
                end
            end
        end
        file:close()
        return route
    end
    return nil
end

local function cr(p0, p1, p2, p3, t)
    local t2 = t * t
    local t3 = t2 * t
    return 0.5 * ((2*p1) + (-p0+p2)*t + (2*p0-5*p1+4*p2-p3)*t2 + (-p0+3*p1-3*p2+p3)*t3)
end

local function getSplineTarget(route, idx)
    local n = #route
    local i0 = math.max(1, idx - 1)
    local i1 = math.max(1, idx)
    local i2 = math.min(n, idx + LOOKAHEAD)
    local i3 = math.min(n, idx + LOOKAHEAD + 1)
    return cr(route[i0].x, route[i1].x, route[i2].x, route[i3].x, 0.5),
           cr(route[i0].y, route[i1].y, route[i2].y, route[i3].y, 0.5),
           cr(route[i0].z, route[i1].z, route[i2].z, route[i3].z, 0.5)
end

local function turning_mechanism(posX, posY, carPosX, carPosY, car)
    local heading = math.rad(getHeadingFromVector2d(posX - carPosX, posY - carPosY) + math.abs(getCarHeading(car) - 360.0))
    local heading = getHeadingFromVector2d(math.deg(math.sin(heading)), math.deg(math.cos(heading)))
    local steer
    if heading > 180.0 and 355.0 > heading then
        steer = -128
    elseif heading > 5.0 and 180.0 >= heading then
        steer = 128
    else
        steer = 0
    end
    table.insert(steerBuf, steer)
    steer = table.remove(steerBuf, 1)
    lastSteerValue = steer
    setGameKeyState(0, steer)
end

local function press_gas()
    writeMemory(0xB73458 + 0x20, 1, 255, false)
end

local function press_brake()
    writeMemory(0xB73458 + 0xC, 1, 255, false)
end

local function fileExists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

local function readSharedFile(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local value = file:read("*l")
    file:close()
    return value
end

local function writeSharedState(state)
    local file = io.open(shared_state_file, "w")
    if not file then return end
    file:write(tostring(state or "IDLE") .. "\n")
    file:write(tostring(math.floor(gasLevel or 0)) .. "\n")
    file:write(tostring(math.floor(brakeLevel or 0)) .. "\n")
    file:write(tostring(math.floor(lastSteerValue or 0)) .. "\n")
    file:write(string.format("%.3f\n", os.clock()))
    file:close()
end

local function sharedFreezeActive()
    return _G.VR_TEST_FREEZE == true or fileExists(freeze_flag_file)
end

local function consumeRotateFlag()
    local mode = readSharedFile(rotate_flag_file)
    if mode then os.remove(rotate_flag_file) end
    return mode
end

local function sharedDialogMode()
    return readSharedFile(dialog_flag_file)
end

function hasPauseSource(now)
    now = now or os.clock()
    return isCrashing
        or S.manualPaused
        or S.autoPaused
        or S.dialogPaused
        or S.testArbotasPaused
        or S.frozenByAdmin
        or S.freezeTestLatched
        or now < S.rotateFightUntil
        or now < S.rotateReleaseUntil
end

function syncPausedState(now)
    paused = hasPauseSource(now)
    if not paused then
        pauseReleaseReason = ""
    end
    return paused
end

local function releaseControls(reason)
    pauseReleaseReason = reason or pauseReleaseReason or "SAFE"
    gasLevel = 0
    brakeLevel = 0
    lastSteerValue = 0
    setGameKeyState(0, 0)
    writeMemory(0xB73458 + 0x20, 1, 0, false)
    writeMemory(0xB73458 + 0xC,  1, 0, false)
    _G.VR_gas = 0
    _G.VR_brake = 0
    _G.VR_steer = 0
    _G.VR_state = pauseReleaseReason
    _G.VR_playing = os.clock()
    writeSharedState(pauseReleaseReason)
end

local function pressRotateReaction()
    pauseReleaseReason = "ROTATE_REACT"
    gasLevel = 255
    brakeLevel = 0
    lastSteerValue = 0
    setGameKeyState(0, 0)
    writeMemory(0xB73458 + 0x20, 1, 255, false)
    writeMemory(0xB73458 + 0xC,  1, 0, false)
    _G.VR_gas = gasLevel
    _G.VR_brake = brakeLevel
    _G.VR_steer = lastSteerValue
    _G.VR_state = pauseReleaseReason
    _G.VR_playing = os.clock()
    writeSharedState(pauseReleaseReason)
end

local function findNearestWaypoint(route, carX, carY)
    local best, bestDist = 1, math.huge
    for i = 1, #route do
        local d = getDistanceBetweenCoords2d(carX, carY, route[i].x, route[i].y)
        if d < bestDist then bestDist = d; best = i end
    end
    return best
end

local function startFreezeRecovery()
    local now = os.clock()
    S.freezeTestLatched = true
    S.frozenByAdmin = true
    S.refreshSent = false
    S.freezeFightUntil = now + (math.random(1000, 2000) / 1000.0)
    S.freezeReleaseUntil = S.freezeFightUntil + (math.random(350, 700) / 1000.0)
    S.freezeRefreshAt = S.freezeReleaseUntil + 2.0
    S.freezeNextTwitch = S.freezeFightUntil
    S.freezeTwitchUntil = S.freezeFightUntil
    S.freezeSteer = 0
    S.freezeTwitchDir = math.random(2) == 1 and -1 or 1
    reverseTimer = 0
    freezeTimer = 0
    suddenStopFrames = 0
    syncPausedState(now)
end

local function resetFreezeRecovery()
    local cx, cy = lastX, lastY
    if isCharInAnyCar(PLAYER_PED) then
        local car = storeCarCharIsInNoSave(PLAYER_PED)
        cx, cy = getCarCoordinates(car)
        if playing and #current_route > 0 then
            play_index = findNearestWaypoint(current_route, cx, cy)
        end
    end

    S.freezeTestLatched = false
    S.frozenByAdmin = false
    S.refreshSent = false
    S.freezeFightUntil = 0.0
    S.freezeReleaseUntil = 0.0
    S.freezeRefreshAt = 0.0
    S.freezeRecoveryGraceUntil = os.clock() + 2.1
    S.freezeNextTwitch = 0.0
    S.freezeTwitchUntil = 0.0
    S.freezeSteer = 0
    S.currentLateral = 0.0
    S.nudgeFrames = 0
    S.nudgeOffset = 0.0
    reverseTimer = 0
    gasLevel = 0
    brakeLevel = 0
    lastSteerValue = 0
    steerBuf = {0, 0}
    freezeTimer = 0
    suddenStopFrames = 0
    lastDriveSpeed = 0.0
    lastX, lastY = cx, cy
    syncPausedState()
end

local function pressFreezeReaction(now)
    pauseReleaseReason = "FREEZE_REACT"
    gasLevel = 255
    brakeLevel = 0
    lastSteerValue = 0
    setGameKeyState(0, 0)
    writeMemory(0xB73458 + 0x20, 1, 255, false)
    writeMemory(0xB73458 + 0xC,  1, 0, false)
    _G.VR_gas = gasLevel
    _G.VR_brake = brakeLevel
    _G.VR_steer = lastSteerValue
    _G.VR_state = pauseReleaseReason
    _G.VR_playing = os.clock()
    writeSharedState(pauseReleaseReason)
end

local function pressFreezeConfused(now)
    if now >= S.freezeNextTwitch then
        S.freezeTwitchDir = -S.freezeTwitchDir
        if math.random(100) <= 25 then
            S.freezeSteer = 0
        else
            S.freezeSteer = S.freezeTwitchDir * math.random(38, 88)
        end
        S.freezeTwitchUntil = now + (math.random(70, 170) / 1000.0)
        S.freezeNextTwitch = now + (math.random(90, 210) / 1000.0)
    end

    pauseReleaseReason = "FREEZE_CONFUSED"
    gasLevel = 0
    brakeLevel = 0
    lastSteerValue = now < S.freezeTwitchUntil and S.freezeSteer or 0
    setGameKeyState(0, lastSteerValue)
    writeMemory(0xB73458 + 0x20, 1, 0, false)
    writeMemory(0xB73458 + 0xC,  1, 0, false)
    _G.VR_gas = gasLevel
    _G.VR_brake = brakeLevel
    _G.VR_steer = lastSteerValue
    _G.VR_state = pauseReleaseReason
    _G.VR_playing = os.clock()
    writeSharedState(pauseReleaseReason)
end

local function draw_line(posX, posY, carX, carY, carZ)
    local chPosX, chPosY, chPosZ = getCharCoordinates(PLAYER_PED)
    if isPointOnScreen(posX, posY, chPosZ, 0.0) then
        local wPosX, wPosY = convert3DCoordsToScreen(posX, posY, chPosZ)
        local wPosX1, wPosY1 = convert3DCoordsToScreen(chPosX, chPosY, chPosZ)
        renderDrawLine(wPosX1, wPosY1, wPosX, wPosY, 2, 0xFFFF0000)
        renderDrawPolygon(wPosX, wPosY, 10, 10, 14, 0.0, 0xFF000000)
        renderDrawPolygon(wPosX1, wPosY1, 10, 10, 14, 0.0, 0xFF000000)
    end
end

local function showMsg(text)
    printStringNow(text, 2000)
end

local function applySteerNoise()
    -- Keyboard players only ever send 0 or ±128; intermediate values flag as analog.
    -- "Noise" here means briefly releasing the key (outputting 0) for 1-3 frames.
    if steerNoiseDuration > 0 then
        steerNoiseDuration = steerNoiseDuration - 1
        setGameKeyState(0, 0)
    elseif steerNoiseCooldown > 0 then
        steerNoiseCooldown = steerNoiseCooldown - 1
    elseif math.random(100) <= 10 then
        steerNoiseDuration = math.random(1, 3)
        steerNoiseCooldown = math.random(8, 30)
        setGameKeyState(0, 0)
    end
end


local function isPlayerControlling()
    return isKeyDown(0x57) or isKeyDown(0x53) or isKeyDown(0x41) or isKeyDown(0x44) or isKeyDown(0x20)
end


local function typeSAMPCommand(cmd)
    local ffiok, ffi = pcall(require, "ffi")
    if not ffiok then return end
    pcall(ffi.cdef, [[
        void keybd_event(unsigned char, unsigned char, unsigned long, unsigned long*);
        short VkKeyScanA(char ch);
    ]])
    local u32ok, u32 = pcall(ffi.load, "user32")
    if not u32ok then return end
    lua_thread.create(function()
        u32.keybd_event(0x54, 0, 0, nil)
        u32.keybd_event(0x54, 0, 2, nil)
        wait(150)
        for i = 1, #cmd do
            local c = cmd:sub(i, i)
            local vs = u32.VkKeyScanA(string.byte(c))
            local vk = vs % 256
            local needShift = math.floor(vs / 256) % 2 == 1
            if needShift then u32.keybd_event(0x10, 0, 0, nil) end
            u32.keybd_event(vk, 0, 0, nil)
            u32.keybd_event(vk, 0, 2, nil)
            if needShift then u32.keybd_event(0x10, 0, 2, nil) end
            wait(25)
        end
        wait(100)
        u32.keybd_event(0x0D, 0, 0, nil)
        u32.keybd_event(0x0D, 0, 2, nil)
    end)
end

local function handleFreeze(car, route, pidx)
    local cx, cy = getCarCoordinates(car)
    local speed = getCarSpeed(car)
    local moved = getDistanceBetweenCoords2d(cx, cy, lastX, lastY)

    if sharedFreezeActive() then
        if not S.freezeTestLatched then
            startFreezeRecovery()
        end
        lastDriveSpeed = speed
        lastX, lastY = cx, cy
        return true
    end

    if S.freezeTestLatched then
        resetFreezeRecovery()
        lastDriveSpeed = speed
        lastX, lastY = cx, cy
        return false
    end

    if os.clock() < S.freezeRecoveryGraceUntil then
        freezeTimer = 0
        suddenStopFrames = 0
        S.frozenByAdmin = false
        S.refreshSent = false
        lastDriveSpeed = speed
        lastX, lastY = cx, cy
        return false
    end

    if lastDriveSpeed > 35.0 and speed < 1.0 and moved < 0.20 then
        suddenStopFrames = suddenStopFrames + 1
    elseif speed > 2.0 or moved > 0.35 then
        suddenStopFrames = 0
    end

    if suddenStopFrames >= 1 then
        freezeTimer = math.max(freezeTimer, 4)
        S.frozenByAdmin = true
        releaseControls("SUDDEN_STOP")
        lastDriveSpeed = speed
        lastX, lastY = cx, cy
        return true
    end

    if moved < 0.1 and speed < 0.1 then
        freezeTimer = freezeTimer + 1
        if freezeTimer > 3 then
            S.frozenByAdmin = true
            releaseControls("FROZEN")
        end
        if freezeTimer > 150 and reverseTimer == 0 then
            local point = route[pidx]
            if point then
                local th = getHeadingFromVector2d(point.x - cx, point.y - cy)
                local diff = math.abs(getCarHeading(car) - th)
                if diff > 180 then diff = 360 - diff end
                if diff > 100 then reverseTimer = 80 end
            end
        end
    else
        freezeTimer = 0
        suddenStopFrames = 0
        S.frozenByAdmin = false
        S.refreshSent = false
        S.refreshTarget = math.random(200, 520)
        if pauseReleaseReason == "FROZEN" or pauseReleaseReason == "FREEZE_TEST" or pauseReleaseReason == "SUDDEN_STOP" then
            pauseReleaseReason = ""
        end
    end
    lastDriveSpeed = speed
    lastX, lastY = cx, cy
    return S.frozenByAdmin
end

local function handleAdminRotate(car)
    if not playing or isCrashing then return end
    local heading = getCarHeading(car)
    local diff = math.abs(heading - lastCarHeading)
    if diff > 180 then diff = 360 - diff end
    local rotateMode = consumeRotateFlag()
    local triggered = diff > 150 or (_G.VR_ADMIN_ROTATED == true) or rotateMode ~= nil
    if triggered then _G.VR_ADMIN_ROTATED = false end
    lastCarHeading = heading
    if not triggered then return end
    syncPausedState()
    local safeRotate = rotateMode == "safe" or (_G.VR_TEST_ROTATE == true and rotateMode ~= "crash")
    if safeRotate then
        local now = os.clock()
        local reaction = math.random(600, 1300) / 1000.0
        S.rotateFightUntil = now + reaction
        S.rotateReleaseUntil = S.rotateFightUntil + 1.0
        syncPausedState(now)
        pressRotateReaction()
        lua_thread.create(function()
            local fightUntil = S.rotateFightUntil
            local untilTime = S.rotateReleaseUntil
            while os.clock() < untilTime do
                if os.clock() < fightUntil then
                    pressRotateReaction()
                else
                    releaseControls("ROTATE_CONFUSED")
                end
                wait(0)
            end
            if not isCrashing and S.rotateReleaseUntil == untilTime then
                S.rotateFightUntil = 0.0
                syncPausedState()
            end
        end)
    else
        isCrashing = true
        S.rotateFightUntil = 0.0
        S.rotateReleaseUntil = os.clock() + 3.0
        syncPausedState()
        releaseControls("ROTATE_PENDING")
        lua_thread.create(function()
            local untilTime = S.rotateReleaseUntil
            while os.clock() < untilTime do
                releaseControls("ROTATE_PENDING")
                wait(0)
            end
            wait(math.random(1500, 5000))
            doForceCrash()
        end)
    end
end

local function readCString(addr, maxLen)
    if not addr or addr < 0x400000 or addr > 0x7FFFFFFF then return "" end
    local s = ""
    local limit = math.min(maxLen or 512, 2048)
    for i = 0, limit - 1 do
            local b = readMemory(addr + i, 1, false)
            if b == 0 then break end
            if b == 10 then s = s .. "\n"
            elseif b >= 32 and b <= 126 then s = s .. string.char(b)
            elseif b > 126 then s = s .. " "  -- extended ASCII is normalized to a space
            end
        end
    return s
end

local function cleanDialogText(text)
    text = (text or ""):gsub("{%x%x%x%x%x%x}", "")
    text = text:gsub("\r", "\n")
    text = text:gsub("\t", " ")
    return text
end

local function trimText(text)
    return (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function collectDialogStrings(dPtr)
    -- Disabled for stability. Some MoonLoader/SA-MP builds hard-error on
    -- readMemory while walking arbitrary dialog string pointers.
    return {}
--[=[
    local strings = {}
    local function addString(text)
        text = cleanDialogText(text)
        if #trimText(text) > 0 then
            table.insert(strings, text)
        end
    end

    for off = 0, 0x70, 4 do
        local ptr = readMemory(dPtr + off, 4, false)
        if ptr and ptr > 0x400000 and ptr < 0x7FFFFFFF then
            addString(readCString(ptr, 1024))
        end
    end

    local inlineOffsets = {0x2C, 0x30, 0x34, 0x38, 0x3C, 0x40, 0x44, 0x48, 0x4C, 0x50}
    for _, off in ipairs(inlineOffsets) do
        addString(readCString(dPtr + off, 1024))
    end

    return strings
]=]
end

local function scoreDialogText(text)
    local lower = text:lower()
    local score = 0
    local newlines = 0
    text:gsub("\n", function() newlines = newlines + 1 end)
    if lower:find("mogus", 1, true) then score = score + 30 end
    if lower:find("pasirink", 1, true) then score = score + 30 end
    if lower:find("ban", 1, true) then score = score + 20 end
    return score + newlines
end

local function getBestDialogText(dPtr)
    local strings = collectDialogStrings(dPtr)
    local bestText, bestScore = "", 0
    for _, text in ipairs(strings) do
        local score = scoreDialogText(text)
        if score > bestScore then
            bestText = text
            bestScore = score
        end
    end
    return bestText, bestScore, strings
end

local function looksLikeArbotasDialog(dPtr)
    local bestText, bestScore, strings = getBestDialogText(dPtr)
    if bestScore >= 45 then return true, bestText end
    for _, text in ipairs(strings) do
        local lower = text:lower()
        if lower:find("mogus", 1, true) and lower:find("pasirink", 1, true) then
            return true, text
        end
        if lower:find("pasirink", 1, true) and lower:find("ban", 1, true) then
            return true, text
        end
    end
    return false, bestText
end

local function findEmptyDialogRowMoves(text)
    local lines = {}
    text = cleanDialogText(text)
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(lines, line)
    end
    local startIdx = 1
    for i, line in ipairs(lines) do
        if line:lower():find("pasirink", 1, true) then
            startIdx = i
            break
        end
    end
    for i = startIdx, #lines do
        if trimText(cleanDialogText(lines[i])) == "" then
            return i - startIdx, lines
        end
    end
    return nil, lines
end

local function tryAnswerAntibotDialog(dPtr)
    do return false end
    local ffiok, ffi = pcall(require, "ffi")
    if not ffiok then return false end

    local isArbotas, bestText = looksLikeArbotasDialog(dPtr)
    local downMoves = nil
    if isArbotas then
        downMoves = findEmptyDialogRowMoves(bestText)
    end
    if downMoves == nil then return false end

    _G.VR_DIALOG_TITLE = "Ar zmogus"
    _G.VR_DIALOG_EMPTY_MOVES = downMoves

    pcall(ffi.cdef, [[void keybd_event(unsigned char, unsigned char, unsigned long, unsigned long*);]])
    local u32ok, u32 = pcall(ffi.load, "user32")
    if not u32ok then return false end

    lua_thread.create(function()
        wait(400)
        wait(math.random(3000, 7000))
        for _ = 1, downMoves do
            u32.keybd_event(0x28, 0, 0, nil)
            u32.keybd_event(0x28, 0, 2, nil)
            wait(math.random(40, 90))
        end
        wait(math.random(300, 800))
        u32.keybd_event(0x0D, 0, 0, nil)
        u32.keybd_event(0x0D, 0, 2, nil)
    end)

    return true

--[=[

    -- Scan the dialog struct broadly: try every 4-byte offset as both a char*
    -- pointer and as an inline string start. The dialog items string is the
    -- candidate with the most newlines. "mogus" must appear somewhere in the
    -- scanned data to confirm this is the "Ar žmogus" captcha.
    local function scanStr(addr, maxLen)
        local s = readCString(addr, maxLen)
        local n = 0
        s:gsub("\n", function() n = n + 1 end)
        return s, n
    end

    local bestText, bestNL, foundMogus = "", 0, false

    for off = 0, 0x60, 4 do
        local ptr = readMemory(dPtr + off, 4, false)
        local s, n = scanStr(ptr, 4096)
        if s:lower():find("mogus") then foundMogus = true end
        if n > bestNL then bestText, bestNL = s, n end
    end
    for off = 0x2C, 0x300, 4 do
        local s, n = scanStr(dPtr + off, 4096)
        if s:lower():find("mogus") then foundMogus = true end
        if n > bestNL then bestText, bestNL = s, n end
    end

    if not foundMogus or bestNL < 2 then return false end

    local text = bestText:gsub("{%x%x%x%x%x%x}", "")
    local items, emptyIdx = {}, nil
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(items, line)
        if line:match("^%s*$") then emptyIdx = #items - 1 end
    end
    if emptyIdx == nil then return false end

    pcall(ffi.cdef, [[void keybd_event(unsigned char, unsigned char, unsigned long, unsigned long*);]])
    local u32ok, u32 = pcall(ffi.load, "user32")
    if not u32ok then return false end

    lua_thread.create(function()
        wait(400)                           -- let dialog fully render
        wait(math.random(3000, 7000))       -- human thinking delay
        for _ = 1, emptyIdx do
            u32.keybd_event(0x28, 0, 0, nil)
            u32.keybd_event(0x28, 0, 2, nil)
            wait(math.random(40, 90))       -- human-speed scrolling
        end
        wait(math.random(300, 800))         -- pause before confirming
        u32.keybd_event(0x0D, 0, 0, nil)
        u32.keybd_event(0x0D, 0, 2, nil)
    end)

    return true
]=]
end

local function handleArbotas()
    local fakeDialogMode = sharedDialogMode()
    if fakeDialogMode == "fake_arbotas" or _G.VR_TEST_ARBOTAS then
        S.testArbotasPaused = true
        S.dialogPaused = true
        syncPausedState()
        releaseControls("AR_BOTAS_TEST")
        return
    end
    if _G.VR_DIALOG_ACTIVE then
        S.dialogPaused = true
        syncPausedState()
        releaseControls("DIALOG")
    elseif S.testArbotasPaused or S.dialogPaused then
        S.testArbotasPaused = false
        S.dialogPaused = false
        syncPausedState()
    end
    if not playing or isCrashing or samp == 0 then return end
    local dPtr = readMemory(samp + 0x21A0B8, 4, true)
    if dPtr == 0 then
        if S.dialogPaused then
            S.dialogPaused = false
            syncPausedState()
        end
        arbotasHandled = false
        return
    end
    local dialogActive = readMemory(dPtr + 0x28, 4, true) == 1
    if not dialogActive then
        if S.dialogPaused then
            S.dialogPaused = false
            syncPausedState()
        end
        arbotasHandled = false
        return
    end
    arbotasHandled = true
    S.dialogPaused = true
    syncPausedState()
    releaseControls("DIALOG")
    return

--[=[
    if tryAnswerAntibotDialog(dPtr) then
        lua_thread.create(function()
            -- Wait up to 15s for the answer + dialog close
            for _ = 1, 150 do
                wait(100)
                local dp = readMemory(samp + 0x21A0B8, 4, true)
                if dp == 0 or readMemory(dp + 0x28, 4, true) ~= 1 then
                    arbotasHandled = false
                    S.dialogPaused = false
                    paused = false
                    pauseReleaseReason = ""
                    return
                end
            end
            -- Dialog still open after 6s — give up and crash
            isCrashing = true
            doForceCrash()
        end)
    else
        isCrashing = true
        lua_thread.create(function()
            wait(math.random(2000, 8000))
            doForceCrash()
        end)
    end
]=]
end

function main()
    printStringNow("~y~Dangis VR: ~w~Laukiama...", 5000)
    wait(8000)
    if not doesDirectoryExist(paths_dir) then createDirectory(paths_dir) end
    samp = getModuleHandle("samp.dll")
    writeSharedState("IDLE")
    printStringNow("~g~Dangis VR v5.8 ikelta!", 3000)
    printStringNow("~w~F2-Irasyti F10-Paleisti F11-Kartoti F6-Pauze F7-Sustabdyti", 5000)

    lua_thread.create(function()
        while true do
            wait(100)
            handleArbotas()
        end
    end)

    lua_thread.create(function()
        while true do
            wait(0)
            local now = os.clock()
            if S.freezeTestLatched and not sharedFreezeActive() then
                resetFreezeRecovery()
            end
            syncPausedState(now)

            if S.freezeTestLatched then
                if now < S.freezeFightUntil then
                    pressFreezeReaction(now)
                elseif now < S.freezeReleaseUntil then
                    pressFreezeConfused(now)
                elseif now < S.freezeRefreshAt then
                    releaseControls("FREEZE_WAIT")
                else
                    releaseControls("FREEZE_REFRESH")
                    if not S.refreshSent then
                        S.refreshSent = true
                        typeSAMPCommand("/refresh")
                    end
                end
            elseif now < S.rotateFightUntil then
                pressRotateReaction()
            elseif now < S.rotateReleaseUntil and not isCrashing then
                releaseControls("ROTATE_CONFUSED")
            elseif paused or sharedFreezeActive() then
                releaseControls(pauseReleaseReason ~= "" and pauseReleaseReason or "SAFE")
            end
        end
    end)

    lua_thread.create(function()
        while true do
            wait(0)
            if recording then
                if isCharInAnyCar(PLAYER_PED) then
                    local time = os.clock() * 1000
                    local car = storeCarCharIsInNoSave(PLAYER_PED)
                    local posX, posY, posZ = getCarCoordinates(car)
                    local currentH = getCarHeading(car)
                    local hDiff = math.abs(currentH - lastRecordHeading)
                    if hDiff > 180 then hDiff = 360 - hDiff end
                    if hDiff > 15 or (time - tick > recordingDelay) then
                        local speed = getCarSpeed(car)
                        table.insert(current_route, {x=posX, y=posY, z=posZ, speed=speed, heading=currentH})
                        lastRecordHeading = currentH
                        tick = os.clock() * 1000
                        printStringNow('~g~Irasymas ~w~X:'..math.floor(posX)..' Y:'..math.floor(posY)..' G:'..math.floor(speed), 1000)
                        local dist = getDistanceBetweenCoords2d(posX, posY, start_x, start_y)
                        if dist < 5.0 and #current_route > 50 then
                            recording = false
                            if saveRoute(current_name, current_route) then
                                showMsg("~g~Kilpa uzdaryta! Issaugota: " .. current_name)
                            end
                        end
                    end
                else
                    recording = false
                    showMsg("~r~Irasymas sustabdytas - islejai masina!")
                end
            end
        end
    end)

    lua_thread.create(function()
        while true do
            wait(0)
            if playing and not paused and #current_route > 0 then
                if not isCharInAnyCar(PLAYER_PED) then
                    playing = false; repeating = false
                    syncPausedState()
                    releaseControls("NO_CAR")
                    showMsg("~r~Vaziavimas sustabdytas - islejei masina!")
                else
                    local car = storeCarCharIsInNoSave(PLAYER_PED)
                    local carX, carY, carZ = getCarCoordinates(car)

                    if S.nextBreakTime > 0 and os.clock() >= S.nextBreakTime then
                        S.autoPaused = true
                        syncPausedState()
                        releaseControls("AUTO_BREAK")
                        S.nextBreakTime = 0
                        local breakDuration = math.random(3, 12) * 60 * 1000
                        lua_thread.create(function()
                            wait(breakDuration)
                            if S.autoPaused then
                                S.autoPaused = false
                                syncPausedState()
                                S.nextBreakTime = os.clock() + math.random(45, 90) * 60
                            end
                        end)
                    end

                    trailTick = trailTick + 1
                    if trailTick >= 8 then
                        trailTick = 0
                        if #currentTrail < 30000 then
                            table.insert(currentTrail, {x=carX, y=carY, z=carZ})
                        end
                    end

                    handleFreeze(car, current_route, play_index)
                    handleAdminRotate(car)

                    if isPlayerControlling() then
                        if not overrideActive then
                            overrideActive = true
                            releaseControls("OVERRIDE")
                        end
                        printStringNow("~y~OVERRIDE ACTIVE", 100)
                    else
                        overrideActive = false

                        if S.frozenByAdmin or sharedFreezeActive() then
                            releaseControls(pauseReleaseReason ~= "" and pauseReleaseReason or "FROZEN")
                            if not S.freezeTestLatched and freezeTimer >= S.refreshTarget and not S.refreshSent then
                                S.refreshSent = true
                                typeSAMPCommand("/refresh")
                            end
                        elseif reverseTimer > 0 then
                            reverseTimer = reverseTimer - 1
                            press_brake()
                            setGameKeyState(0, 0)
                            gasLevel = 0
                        elseif _G.VR_TEST_ARBOTAS then
                            releaseControls("AR_BOTAS_TEST")
                        elseif not paused and not isCrashing then
                            local tX, tY, tZ = getSplineTarget(current_route, play_index)

                            if play_index < #current_route then
                                local ndx = current_route[play_index + 1].x - current_route[play_index].x
                                local ndy = current_route[play_index + 1].y - current_route[play_index].y
                                local nd = math.sqrt(ndx * ndx + ndy * ndy)
                                if nd > 0.1 then
                                    if S.nudgeFrames > 0 then
                                        S.nudgeFrames = S.nudgeFrames - 1
                                        if S.nudgeFrames == 0 then S.nudgeOffset = 0.0 end
                                    elseif os.clock() >= S.nextNudge then
                                        S.nudgeOffset = (math.random() * 2.4) - 1.2
                                        S.nudgeFrames = math.random(80, 160)
                                        S.nextNudge = os.clock() + math.random(15, 45)
                                    end
                                    local targetLateral = S.lapWander + S.nudgeOffset
                                    S.currentLateral = S.currentLateral + (targetLateral - S.currentLateral) * 0.055
                                    tX = tX + (-ndy / nd) * S.currentLateral
                                    tY = tY + (ndx / nd) * S.currentLateral
                                end
                            end

                            draw_line(tX, tY, carX, carY, carZ)

                            local point = current_route[play_index]
                            local targetSpeed = point.speed
                            local currentSpeed = getCarSpeed(car)

                            if sharpTurnAhead(current_route, play_index) and currentSpeed > targetSpeed * 0.7 then
                                turning_mechanism(tX, tY, carX, carY, car)
                                applySteerNoise()
                                brakeLevel = 255
                                gasLevel = 0
                                writeMemory(0xB73458 + 0x20, 1, gasLevel, false)
                                writeMemory(0xB73458 + 0xC, 1, brakeLevel, false)
                            else
                                turning_mechanism(tX, tY, carX, carY, car)
                                applySteerNoise()
                                if S.gasLiftFrames > 0 then
                                    S.gasLiftFrames = S.gasLiftFrames - 1
                                    gasLevel = 0
                                    brakeLevel = 0
                                elseif os.clock() >= S.nextGasLift then
                                    S.gasLiftFrames = math.random(18, 45)
                                    S.nextGasLift = os.clock() + math.random(20, 60)
                                else
                                    if currentSpeed < targetSpeed then
                                        gasLevel = 255
                                        brakeLevel = 0
                                    elseif currentSpeed < targetSpeed + 1.5 then
                                        brakeLevel = 0
                                    else
                                        brakeLevel = 255
                                        gasLevel = 0
                                    end
                                end
                                writeMemory(0xB73458 + 0x20, 1, gasLevel, false)
                                writeMemory(0xB73458 + 0xC, 1, brakeLevel, false)
                            end

                            printStringNow('~g~VR Bot ~w~' .. play_index .. '/' .. #current_route .. ' ~y~' .. math.floor(currentSpeed) .. 'km/h', 100)
                            _G.VR_state   = "PLAYING"
                            writeSharedState("PLAYING")

                            if locateCharInCar2d(PLAYER_PED, point.x, point.y, routeRadius, routeRadius, false) then
                                play_index = play_index + 1
                            else
                                local carDist = getDistanceBetweenCoords2d(carX, carY, point.x, point.y)
                                if carDist > 30.0 then
                                    play_index = findNearestWaypoint(current_route, carX, carY)
                                else
                                    local closestIdx, closestDist = play_index, carDist
                                    for i = play_index, math.min(play_index + 10, #current_route) do
                                        local d = getDistanceBetweenCoords2d(carX, carY, current_route[i].x, current_route[i].y)
                                        if d < closestDist then closestDist = d; closestIdx = i end
                                    end
                                    play_index = closestIdx
                                end
                            end

                            if getCarHealth(car) < 500 then repairCar(car) end

                            if play_index > #current_route then
                                if repeating then
                                    play_index = 1
                                    S.lapWander = (math.random() * 3.0) - 1.5
                                    gasLevel = 0; brakeLevel = 0
                                    S.gasLiftFrames = 0
                                    S.nudgeFrames = 0; S.nudgeOffset = 0.0
                                    S.currentLateral = 0.0
                                    local delayFrames = math.random(1, 2)
                                    steerBuf = {}
                                    for i = 1, delayFrames do steerBuf[i] = 0 end
                                    S.lapCount = S.lapCount + 1
                                    showMsg("~g~Kilpa baigta! Kartojama!")
                                else
                                    playing = false; play_index = 1
                                    releaseControls("DONE")
                                    showMsg("~g~Kelias baigtas!")
                                end
                            end
                        end
                        -- always export state to HUD while playing, regardless of pause/freeze
                        _G.VR_gas     = gasLevel
                        _G.VR_brake   = brakeLevel
                        _G.VR_steer   = lastSteerValue
                        _G.VR_playing = os.clock()
                    end
                end
            end
        end
    end)

    while true do
        wait(0)

        if isKeyJustPressed(VK_F2) then
            if not recording then
                if isCharInAnyCar(PLAYER_PED) then
                    recording = true; playing = false; current_route = {}
                    start_x, start_y, start_z = getCharCoordinates(PLAYER_PED)
                    lastRecordHeading = getCarHeading(storeCarCharIsInNoSave(PLAYER_PED))
                    tick = os.clock() * 1000
                    showMsg("~g~Irasymas pradetas! Grizk i starta uzdaryt kilpa!")
                else
                    showMsg("~r~Turi buti masinos viduje!")
                end
            else
                recording = false
                if #current_route > 0 then
                    if saveRoute(current_name, current_route) then
                        showMsg("~g~Kelias issaugotas! Taskų: " .. #current_route)
                    end
                end
            end
        end

        if isKeyJustPressed(VK_F10) then
            if not playing then
                S.lapWander = (math.random() * 3.0) - 1.5
                S.lapCount = 0
                gasLevel = 0; brakeLevel = 0
                S.gasLiftFrames = 0
                S.nextGasLift = os.clock() + math.random(20, 60)
                S.nudgeFrames = 0; S.nudgeOffset = 0.0
                S.nextNudge = os.clock() + math.random(12, 40)
                S.currentLateral = 0.0
                S.autoPaused = false
                S.manualPaused = false
                S.dialogPaused = false
                S.testArbotasPaused = false
                S.frozenByAdmin = false
                S.freezeTestLatched = false
                S.freezeFightUntil = 0.0
                S.freezeReleaseUntil = 0.0
                S.freezeRefreshAt = 0.0
                S.freezeRecoveryGraceUntil = 0.0
                S.freezeNextTwitch = 0.0
                S.freezeTwitchUntil = 0.0
                S.freezeSteer = 0
                suddenStopFrames = 0
                freezeTimer = 0
                reverseTimer = 0
                lastDriveSpeed = 0.0
                pauseReleaseReason = ""
                S.rotateFightUntil = 0.0
                S.rotateReleaseUntil = 0.0
                steerBuf = {0, 0}
                S.nextBreakTime = os.clock() + math.random(45, 90) * 60
                if isCharInAnyCar(PLAYER_PED) then
                    lastCarHeading = getCarHeading(storeCarCharIsInNoSave(PLAYER_PED))
                end
                if #current_route > 5 then
                    play_index = 1; playing = true; syncPausedState()
                    showMsg("~g~Vaziavimas pradetas!")
                else
                    local route = loadRoute(current_name)
                    if route and #route > 0 then
                        current_route = route; play_index = 1; playing = true; syncPausedState()
                        showMsg("~g~Kelias ikrautas ir paleistas: " .. current_name)
                    else
                        showMsg("~r~Nera irasyto kelio!")
                    end
                end
            else
                playing = false
                releaseControls("STOPPED")
                showMsg("~r~Vaziavimas sustabdytas!")
            end
        end

        if isKeyJustPressed(VK_F11) then
            repeating = not repeating
            showMsg(repeating and "~g~Kartojimas IJUNGTAS!" or "~r~Kartojimas ISJUNGTAS!")
        end

        if isKeyJustPressed(VK_F6) then
            if playing then
                if S.autoPaused then
                    S.autoPaused = false
                    syncPausedState()
                    S.nextBreakTime = os.clock() + math.random(45, 90) * 60
                    showMsg("~g~Tesiama!")
                else
                    S.manualPaused = not S.manualPaused
                    syncPausedState()
                    if S.manualPaused then
                        releaseControls("PAUSED")
                        showMsg("~y~Pristabdyta!")
                    else
                        S.nextBreakTime = os.clock() + math.random(45, 90) * 60
                        showMsg("~g~Tesiama!")
                    end
                end
            end
        end

        if isKeyJustPressed(VK_F7) then
            recording = false; playing = false; repeating = false
            S.autoPaused = false; S.manualPaused = false; play_index = 1
            S.dialogPaused = false; S.testArbotasPaused = false; S.frozenByAdmin = false; S.freezeTestLatched = false
            S.freezeFightUntil = 0.0
            S.freezeReleaseUntil = 0.0
            S.freezeRefreshAt = 0.0
            S.freezeRecoveryGraceUntil = 0.0
            S.freezeNextTwitch = 0.0
            S.freezeTwitchUntil = 0.0
            S.freezeSteer = 0
            S.currentLateral = 0.0
            S.nudgeFrames = 0
            S.nudgeOffset = 0.0
            suddenStopFrames = 0
            freezeTimer = 0
            reverseTimer = 0
            lastDriveSpeed = 0.0
            steerBuf = {0, 0}
            pauseReleaseReason = ""
            S.rotateFightUntil = 0.0
            S.rotateReleaseUntil = 0.0
            syncPausedState()
            releaseControls("ALL_STOP")
            showMsg("~r~Viskas sustabdyta!")
        end

        if isKeyJustPressed(VK_F9) then
            showTrail = not showTrail
            if not showTrail then
                currentTrail = {}
                lastTrail = {}
            end
            showMsg(showTrail and "~g~Trajektorija IJUNGTA!" or "~r~Trajektorija ISJUNGTA!")
        end

        if showTrail then
            local px, py, pz = getCharCoordinates(PLAYER_PED)
            local spacing = 8
            local phase = math.floor((os.clock() % 0.2) / 0.2 * spacing)
            local function drawTrailArrows(trail, color)
                if #trail < 2 then return end
                local i = 1 + phase
                while i <= #trail - 1 do
                    local p  = trail[i]
                    local p2 = trail[i + 1]
                    if p and p2 and getDistanceBetweenCoords2d(px, py, p.x, p.y) < 200 then
                        if isPointOnScreen(p.x, p.y, p.z, 0.0) then
                            local sx,  sy  = convert3DCoordsToScreen(p.x,  p.y,  p.z)
                            local sx2, sy2 = convert3DCoordsToScreen(p2.x, p2.y, p2.z)
                            local dx, dy = sx2 - sx, sy2 - sy
                            local len = math.sqrt(dx*dx + dy*dy)
                            if len > 0.5 then
                                local nx, ny = dx/len, dy/len
                                local wx1 = sx - nx*9 + (-ny)*5
                                local wy1 = sy - ny*9 + nx*5
                                local wx2 = sx - nx*9 - (-ny)*5
                                local wy2 = sy - ny*9 - nx*5
                                renderDrawLine(sx, sy, wx1, wy1, 1.5, color)
                                renderDrawLine(sx, sy, wx2, wy2, 1.5, color)
                            end
                        end
                    end
                    i = i + spacing
                end
            end
            drawTrailArrows(lastTrail,    0xCCFFFF00)
            drawTrailArrows(currentTrail, 0xCC00FFFF)
        end

    end
end