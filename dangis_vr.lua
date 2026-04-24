script_name('dangis_vr')
script_version('5.0')
require 'lib.moonloader'

-- ==========================================
-- BOT SETTINGS
-- ==========================================
local recording = false
local playing = false
local repeating = false
local paused = false
local current_route = {}
local play_index = 1
local current_name = "route1"
local paths_dir = getWorkingDirectory() .. "/dangis_paths/"
local start_x, start_y, start_z = 0, 0, 0
local routeRadius = 8.0
local tick = 0
local recordingDelay = 80

-- ==========================================
-- SAFETY SETTINGS
-- ==========================================
local crashDelay = 3500
local isCrashing = false
local lastX, lastY = 0.0, 0.0
local freezeTimer = 0
local samp = 0

local OFFSETS = {
    R1 = { dialog = 0x21A0B8, chat = 0x21A0E4 },
    R4 = { dialog = 0x269830, chat = 0x269954 }
}
local activeOffset = OFFSETS.R1

-- ==========================================
-- ROUTE FUNCTIONS
-- ==========================================

local function saveRoute(name, route)
    local file = io.open(paths_dir .. name .. ".txt", "w")
    if file then
        for _, point in ipairs(route) do
            file:write('{' .. point.x .. '}:{' .. point.y .. '}:{' .. point.z .. '}:{' .. point.speed .. '}\n')
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
            local x, y, z, speed = line:match('{([^}]*)}:{([^}]*)}:{([^}]*)}:{([^}]*)}')
            if x and y and z and speed then
                table.insert(route, {
                    x = tonumber(x),
                    y = tonumber(y),
                    z = tonumber(z),
                    speed = tonumber(speed) or 0
                })
            else
                -- backward-compat: old format had no z field
                local x2, y2, speed2 = line:match('{([^}]*)}:{([^}]*)}:{([^}]*)}')
                if x2 and y2 and speed2 then
                    table.insert(route, {
                        x = tonumber(x2),
                        y = tonumber(y2),
                        z = 0,
                        speed = tonumber(speed2) or 0
                    })
                end
            end
        end
        file:close()
        return route
    end
    return nil
end

-- ==========================================
-- DRIVING FUNCTIONS
-- ==========================================

local function turning_mechanism(posX, posY, carPosX, carPosY, car)
    local targetHeading = getHeadingFromVector2d(posX - carPosX, posY - carPosY)
    local carHeading = getCarHeading(car)
    local diff = (targetHeading - carHeading + 360) % 360
    if diff > 180 and diff < 355 then
        setGameKeyState(0, -128)
    elseif diff > 5 and diff <= 180 then
        setGameKeyState(0, 128)
    else
        setGameKeyState(0, 0)
    end
end

local function press_gas()
    writeMemory(0xB73458 + 0x20, 1, 255, false)
    writeMemory(0xB73458 + 0xC,  1, 0,   false)
end

local function press_brake()
    writeMemory(0xB73458 + 0xC,  1, 255, false)
    writeMemory(0xB73458 + 0x20, 1, 0,   false)
end

local function release_throttle()
    writeMemory(0xB73458 + 0x20, 1, 0, false)
    writeMemory(0xB73458 + 0xC,  1, 0, false)
end

local function draw_line(posX, posY, posZ)
    local chPosX, chPosY, chPosZ = getCharCoordinates(PLAYER_PED)
    if isPointOnScreen(posX, posY, posZ, 0.0) then
        local wPosX,  wPosY  = convert3DCoordsToScreen(posX,   posY,   posZ)
        local wPosX1, wPosY1 = convert3DCoordsToScreen(chPosX, chPosY, chPosZ)
        renderDrawLine(wPosX1, wPosY1, wPosX, wPosY, 2, 0xFFFF0000)
        renderDrawPolygon(wPosX,  wPosY,  10, 10, 14, 0.0, 0xFF000000)
        renderDrawPolygon(wPosX1, wPosY1, 10, 10, 14, 0.0, 0xFF000000)
    end
end

local function showMsg(text)
    printStringNow(text, 2000)
end

local function stopAll()
    recording = false
    playing   = false
    repeating = false
    paused    = false
    play_index = 1
    setGameKeyState(0, 0)
    release_throttle()
end

-- ==========================================
-- SAFETY FUNCTIONS
-- ==========================================

-- Returns true if the real player is touching any driving input.
-- Used to hand control back to the player and prevent bot fighting their input.
local function isPlayerControlling()
    return getPadState(PLAYER_PED, 16) > 0 or  -- W  / accelerate
           getPadState(PLAYER_PED, 14) > 0 or  -- S  / reverse
           getPadState(PLAYER_PED, 0)  ~= 0 or -- A/D / steer
           getPadState(PLAYER_PED, 15) > 0     -- Space / handbrake
end

-- Triggers a controlled crash when a SAMP dialog (e.g. /arbotas check) appears.
-- The crash itself is a detectable event: server owners can correlate the
-- disconnect type and timing to build a dialog-triggered disconnect signature.
local function handleArbotas()
    local dInfo = readMemory(samp + activeOffset.dialog, 4, true)
    if dInfo ~= 0 and readMemory(dInfo + 0x28, 4, true) == 1 then
        if not isCrashing then
            isCrashing = true
            printStringNow("~r~SAFETY: Dialog detected. Crashing in 3.5s...", 3000)
            lua_thread.create(function()
                wait(crashDelay)
                writeMemory(0x0, 4, 0, true) -- null-pointer write → hardware fault crash
            end)
        end
    end
end

-- When an admin freeze is detected (car stationary despite engine running),
-- zeroes the throttle memory bytes so the bot looks idle rather than revving.
-- Exposes the gap: freeze + zero-throttle pattern is still distinguishable
-- from a real driver who would steer or attempt to move.
local function handleFreeze(car)
    local cx, cy = getCarCoordinates(car)
    local speed  = getCarSpeed(car)
    if getDistanceBetweenCoords2d(cx, cy, lastX, lastY) < 0.1 and speed < 0.1 then
        freezeTimer = freezeTimer + 1
        if freezeTimer > 30 then -- ~1 second of being stationary
            release_throttle()
        end
    else
        freezeTimer = 0
    end
    lastX, lastY = cx, cy
end

-- ==========================================
-- MAIN
-- ==========================================
function main()
    printStringNow("~y~Dangis VR: ~w~Laukiama...", 5000)
    wait(8000)

    if not doesDirectoryExist(paths_dir) then
        createDirectory(paths_dir)
    end

    -- SAMP safety system init
    samp = getModuleHandle("samp.dll")
    if samp == 0 then
        printStringNow("~r~SAMP not found! Safety systems disabled.", 3000)
    else
        -- Auto-detect R1 vs R4 by checking if the R1 dialog pointer is non-null
        if readMemory(samp + OFFSETS.R1.dialog, 4, true) == 0 then
            activeOffset = OFFSETS.R4
        end
        printStringNow("~g~Safety Systems: ~w~ACTIVE", 3000)
    end

    printStringNow("~g~Dangis VR v5.0 ikelta!", 3000)
    printStringNow("~w~F2-Irasyti F10-Paleisti F11-Kartoti F6-Pauze F7-Sustabdyti", 5000)

    -- Recording loop
    lua_thread.create(function()
        while true do
            wait(0)
            if recording then
                if isCharInAnyCar(PLAYER_PED) then
                    local time = os.clock() * 1000
                    if time - tick > recordingDelay then
                        local car = storeCarCharIsInNoSave(PLAYER_PED)
                        local posX, posY, posZ = getCarCoordinates(car)
                        local speed = getCarSpeed(car)
                        table.insert(current_route, {x = posX, y = posY, z = posZ, speed = speed})
                        tick = time
                        printStringNow('~g~Irasymas ~w~X: ' .. math.floor(posX) .. ' Y: ' .. math.floor(posY) .. ' Greitis: ' .. math.floor(speed), 1000)
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

    -- Playback loop
    lua_thread.create(function()
        local lastFrameTime = os.clock() * 1000
        while true do
            wait(0)

            local now = os.clock() * 1000
            local dt  = now - lastFrameTime
            lastFrameTime = now

            if playing and not paused and #current_route > 0 then
                if play_index > #current_route then
                    if repeating then
                        play_index = 1
                        showMsg("~g~Kilpa baigta! Kartojama!")
                    else
                        stopAll()
                        showMsg("~g~Kelias baigtas!")
                    end
                elseif not isCharInAnyCar(PLAYER_PED) then
                    stopAll()
                    showMsg("~r~Vaziavimas sustabdytas - islejei masina!")
                else
                    local car = storeCarCharIsInNoSave(PLAYER_PED)

                    -- Safety: arbotas / admin dialog check
                    if samp ~= 0 then
                        handleArbotas()
                    end

                    -- Safety: freeze detection
                    handleFreeze(car)

                    -- Safety: manual override — player input wins, bot yields
                    if isPlayerControlling() then
                        release_throttle()
                        setGameKeyState(0, 0)
                        printStringNow("~y~OVERRIDE ACTIVE", 100)
                    else
                        local carX, carY, carZ = getCarCoordinates(car)

                        -- Re-sync after lag spike or large positional drift
                        local distToCurrent = getDistanceBetweenCoords2d(carX, carY,
                            current_route[play_index].x, current_route[play_index].y)
                        if dt > 300 or distToCurrent > 25 then
                            local scanEnd  = math.min(play_index + 200, #current_route)
                            local bestIdx  = play_index
                            local bestDist = distToCurrent
                            for i = play_index, scanEnd do
                                local p = current_route[i]
                                local d = getDistanceBetweenCoords2d(carX, carY, p.x, p.y)
                                if d < bestDist then
                                    bestDist = d
                                    bestIdx  = i
                                end
                            end
                            play_index = bestIdx
                        end

                        local point = current_route[play_index]

                        -- Distance-based lookahead: aim at first waypoint ≥15 m ahead
                        local lookAheadIdx = play_index
                        for i = play_index, math.min(play_index + 30, #current_route) do
                            if getDistanceBetweenCoords2d(carX, carY,
                                    current_route[i].x, current_route[i].y) >= 15.0 then
                                lookAheadIdx = i
                                break
                            end
                        end
                        local lookAheadPoint = current_route[lookAheadIdx]
                        draw_line(lookAheadPoint.x, lookAheadPoint.y, lookAheadPoint.z)
                        turning_mechanism(lookAheadPoint.x, lookAheadPoint.y, carX, carY, car)

                        -- ±3 km/h dead-band prevents gas/brake oscillation
                        local currentSpeed = getCarSpeed(car)
                        if currentSpeed < point.speed - 3 then
                            press_gas()
                        elseif currentSpeed > point.speed + 3 then
                            press_brake()
                        else
                            release_throttle()
                        end

                        printStringNow('~g~VR Bot ~w~' .. play_index .. '/' .. #current_route .. ' ~y~' .. math.floor(currentSpeed) .. 'km/h', 100)

                        -- Waypoint advancement (20-point window)
                        if locateCharInCar2d(PLAYER_PED, point.x, point.y, routeRadius, routeRadius, false) then
                            play_index = play_index + 1
                        else
                            local closestIdx  = play_index
                            local closestDist = getDistanceBetweenCoords2d(carX, carY, point.x, point.y)
                            for i = play_index, math.min(play_index + 20, #current_route) do
                                local p = current_route[i]
                                local d = getDistanceBetweenCoords2d(carX, carY, p.x, p.y)
                                if d < closestDist then
                                    closestDist = d
                                    closestIdx  = i
                                end
                            end
                            play_index = closestIdx
                        end

                        if getCarHealth(car) < 500 then
                            repairCar(car)
                        end
                    end
                end
            else
                lastFrameTime = now
            end
        end
    end)

    while true do
        wait(0)

        if isKeyJustPressed(VK_F2) then
            if not recording then
                if isCharInAnyCar(PLAYER_PED) then
                    recording = true
                    playing   = false
                    current_route = {}
                    local car = storeCarCharIsInNoSave(PLAYER_PED)
                    start_x, start_y, start_z = getCarCoordinates(car)
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
                if #current_route > 5 then
                    play_index = 1
                    playing    = true
                    paused     = false
                    showMsg("~g~Vaziavimas pradetas!")
                else
                    local route = loadRoute(current_name)
                    if route and #route > 0 then
                        current_route = route
                        play_index    = 1
                        playing       = true
                        paused        = false
                        showMsg("~g~Kelias ikrautas ir paleistas: " .. current_name)
                    else
                        showMsg("~r~Nera irasyto kelio!")
                    end
                end
            else
                playing = false
                setGameKeyState(0, 0)
                release_throttle()
                showMsg("~r~Vaziavimas sustabdytas!")
            end
        end

        if isKeyJustPressed(VK_F11) then
            repeating = not repeating
            if repeating then
                showMsg("~g~Kartojimas IJUNGTAS!")
            else
                showMsg("~r~Kartojimas ISJUNGTAS!")
            end
        end

        if isKeyJustPressed(VK_F6) then
            if playing then
                paused = not paused
                if paused then
                    setGameKeyState(0, 0)
                    release_throttle()
                    showMsg("~y~Pristabdyta!")
                else
                    showMsg("~g~Tesiama!")
                end
            end
        end

        if isKeyJustPressed(VK_F7) then
            stopAll()
            showMsg("~r~Viskas sustabdyta!")
        end
    end
end
