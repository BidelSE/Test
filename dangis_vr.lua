script_name('dangis_vr')
script_version('4.1')
require 'lib.moonloader'

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

-- FIX: save z coordinate alongside x, y, speed
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

-- FIX: load z coordinate; fall back gracefully for old routes without z
-- FIX: use [^}]* instead of .* to prevent greedy mis-parsing of malformed lines
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

-- FIX: correct heading math — compute signed angular difference directly,
-- no double-declaration of 'heading' and no meaningless deg(sin(x)) conversion
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

-- FIX: press_gas and press_brake now also release the opposing input
-- so the previous state never bleeds through
local function press_gas()
    writeMemory(0xB73458 + 0x20, 1, 255, false)
    writeMemory(0xB73458 + 0xC,  1, 0,   false)
end

local function press_brake()
    writeMemory(0xB73458 + 0xC,  1, 255, false)
    writeMemory(0xB73458 + 0x20, 1, 0,   false)
end

-- FIX: new helper to zero both throttle bytes on pause/stop
local function release_throttle()
    writeMemory(0xB73458 + 0x20, 1, 0, false)
    writeMemory(0xB73458 + 0xC,  1, 0, false)
end

-- FIX: accept and use the waypoint's own z for correct 3-D screen projection
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

-- FIX: single helper so every stop path resets all state identically,
-- including throttle memory bytes
local function stopAll()
    recording = false
    playing   = false
    repeating = false
    paused    = false
    play_index = 1
    setGameKeyState(0, 0)
    release_throttle()
end

function main()
    printStringNow("~y~Dangis VR: ~w~Laukiama...", 5000)
    wait(8000)

    if not doesDirectoryExist(paths_dir) then
        createDirectory(paths_dir)
    end

    printStringNow("~g~Dangis VR v4.1 ikelta!", 3000)
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
                        -- FIX: store z in each recorded point
                        table.insert(current_route, {x = posX, y = posY, z = posZ, speed = speed})
                        -- FIX: reuse the already-sampled timestamp instead of calling os.clock() again
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
        while true do
            wait(0)
            if playing and not paused and #current_route > 0 then
                -- FIX: check bounds FIRST so current_route[play_index] is never nil
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
                    local point = current_route[play_index]
                    local carX, carY, carZ = getCarCoordinates(car)

                    -- Lookahead steering — 3 waypoints ahead
                    local lookAheadIdx   = math.min(play_index + 3, #current_route)
                    local lookAheadPoint = current_route[lookAheadIdx]
                    -- FIX: pass the waypoint's z to draw_line
                    draw_line(lookAheadPoint.x, lookAheadPoint.y, lookAheadPoint.z)
                    turning_mechanism(lookAheadPoint.x, lookAheadPoint.y, carX, carY, car)

                    -- FIX: dead-band ±3 km/h prevents gas/brake oscillation;
                    -- coast zone explicitly releases both to avoid state bleed
                    local currentSpeed = getCarSpeed(car)
                    if currentSpeed < point.speed - 3 then
                        press_gas()
                    elseif currentSpeed > point.speed + 3 then
                        press_brake()
                    else
                        release_throttle()
                    end

                    printStringNow('~g~VR Bot ~w~' .. play_index .. '/' .. #current_route .. ' ~y~' .. math.floor(currentSpeed) .. 'km/h', 100)

                    -- Waypoint check with closest-point skip logic
                    if locateCharInCar2d(PLAYER_PED, point.x, point.y, routeRadius, routeRadius, false) then
                        play_index = play_index + 1
                    else
                        local closestIdx  = play_index
                        local closestDist = getDistanceBetweenCoords2d(carX, carY, point.x, point.y)
                        for i = play_index, math.min(play_index + 10, #current_route) do
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
                    -- FIX: use getCarCoordinates so start position matches the
                    -- coordinates recorded in the loop (was getCharCoordinates)
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
                -- FIX: release throttle memory on manual stop
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
                    -- FIX: release throttle memory on pause (was only clearing steering)
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
