script_name('dangis_vr')
script_version('5.3')
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

local speedVariance = 0.0
local lastSteerValue = 0
local steerNoiseValue = 0
local steerNoiseDuration = 0
local steerNoiseCooldown = 0
local collisionCooldown = 0
local avoidSteerDir = 0
local overrideActive = false

local lastX, lastY = 0.0, 0.0
local freezeTimer = 0

local function saveRoute(name, route)
    local file = io.open(paths_dir .. name .. ".txt", "w")
    if file then
        for _, point in ipairs(route) do
            file:write('{' .. point.x .. '}:{' .. point.y .. '}:{' .. point.speed .. '}\n')
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
            local x, y, speed = line:match('{(.*)}:{(.*)}:{(.*)}')
            if x and y and speed then
                table.insert(route, {
                    x = tonumber(x),
                    y = tonumber(y),
                    speed = tonumber(speed) or 0
                })
            end
        end
        file:close()
        return route
    end
    return nil
end

local function turning_mechanism(posX, posY, carPosX, carPosY, car)
    local heading = math.rad(getHeadingFromVector2d(posX - carPosX, posY - carPosY) + math.abs(getCarHeading(car) - 360.0))
    local heading = getHeadingFromVector2d(math.deg(math.sin(heading)), math.deg(math.cos(heading)))
    if heading > 180.0 and 355.0 > heading then
        lastSteerValue = -128
        setGameKeyState(0, -128)
    else
        if heading > 5.0 and 180.0 >= heading then
            lastSteerValue = 128
            setGameKeyState(0, 128)
        else
            lastSteerValue = 0
            setGameKeyState(0, 0)
        end
    end
end

local function press_gas()
    writeMemory(0xB73458 + 0x20, 1, 255, false)
end

local function press_brake()
    writeMemory(0xB73458 + 0xC, 1, 255, false)
end

local function draw_line(posX, posY)
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
    if steerNoiseDuration > 0 then
        steerNoiseDuration = steerNoiseDuration - 1
        setGameKeyState(0, math.max(-128, math.min(128, lastSteerValue + steerNoiseValue)))
    elseif steerNoiseCooldown > 0 then
        steerNoiseCooldown = steerNoiseCooldown - 1
    elseif math.random(100) <= 10 then
        local range = (lastSteerValue == 0) and 25 or 12
        steerNoiseValue = math.random(-range, range)
        steerNoiseDuration = math.random(2, 6)
        steerNoiseCooldown = math.random(8, 30)
        setGameKeyState(0, math.max(-128, math.min(128, lastSteerValue + steerNoiseValue)))
    end
end

local function getObstacleAhead(car, targetX, targetY)
    local carX, carY, carZ = getCarCoordinates(car)
    local dx = targetX - carX
    local dy = targetY - carY
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.1 then return nil end
    local nx, ny = dx / d, dy / d
    local ok, nearest = pcall(getClosestCar, carX + nx * 12, carY + ny * 12, carZ, 5.0, {}, 0)
    if ok and nearest and nearest ~= 0 and nearest ~= car then return nearest end
    return nil
end

local function avoidDirection(car, obstacle, targetX, targetY)
    local carX, carY = getCarCoordinates(car)
    local obsX, obsY = getCarCoordinates(obstacle)
    local dx = targetX - carX
    local dy = targetY - carY
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.1 then return 128 end
    local nx, ny = dx / d, dy / d
    local dot = (obsX - carX) * ny + (obsY - carY) * (-nx)
    return dot > 0 and -128 or 128
end

local function isPlayerControlling()
    return isKeyDown(0x57) or
           isKeyDown(0x53) or
           isKeyDown(0x41) or
           isKeyDown(0x44) or
           isKeyDown(0x20)
end

local function handleFreeze(car)
    local cx, cy = getCarCoordinates(car)
    local speed = getCarSpeed(car)
    if getDistanceBetweenCoords2d(cx, cy, lastX, lastY) < 0.1 and speed < 0.1 then
        freezeTimer = freezeTimer + 1
        if freezeTimer > 30 then
            writeMemory(0xB73458 + 0x20, 1, 0, false)
            writeMemory(0xB73458 + 0xC,  1, 0, false)
            local twitchInterval = math.random(150, 210)
            if freezeTimer % twitchInterval == 0 then
                local kind = math.random(2)
                if kind == 1 then
                    writeMemory(0xB73458 + 0x20, 1, math.random(80, 160), false)
                else
                    local dir = math.random(2) == 1 and math.random(30, 60) or math.random(-60, -30)
                    setGameKeyState(0, dir)
                end
            end
        end
    else
        freezeTimer = 0
    end
    lastX, lastY = cx, cy
end

function main()
    printStringNow("~y~Dangis VR: ~w~Laukiama...", 5000)
    wait(8000)

    if not doesDirectoryExist(paths_dir) then
        createDirectory(paths_dir)
    end

    printStringNow("~g~Dangis VR v5.3 ikelta!", 3000)
    printStringNow("~w~F2-Irasyti F10-Paleisti F11-Kartoti F6-Pauze F7-Sustabdyti", 5000)

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
                        table.insert(current_route, {x = posX, y = posY, speed = speed})
                        tick = os.clock() * 1000
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

    lua_thread.create(function()
        while true do
            wait(0)
            if playing and not paused and #current_route > 0 then
                if not isCharInAnyCar(PLAYER_PED) then
                    playing = false
                    repeating = false
                    paused = false
                    setGameKeyState(0, 0)
                    showMsg("~r~Vaziavimas sustabdytas - islejei masina!")
                else
                    local car = storeCarCharIsInNoSave(PLAYER_PED)

                    handleFreeze(car)

                    if isPlayerControlling() then
                        if not overrideActive then
                            overrideActive = true
                            writeMemory(0xB73458 + 0x20, 1, 0, false)
                            writeMemory(0xB73458 + 0xC,  1, 0, false)
                            setGameKeyState(0, 0)
                        end
                        printStringNow("~y~OVERRIDE ACTIVE", 100)
                    else
                        overrideActive = false
                        local point = current_route[play_index]
                        local carX, carY, carZ = getCarCoordinates(car)

                        draw_line(point.x, point.y)
                        turning_mechanism(point.x, point.y, carX, carY, car)
                        applySteerNoise()

                        local targetSpeed = point.speed * (1.0 + speedVariance) + math.random(-2, 2)
                        local currentSpeed = getCarSpeed(car)

                        local obstacle = getObstacleAhead(car, point.x, point.y)
                        if obstacle and collisionCooldown == 0 then
                            collisionCooldown = 50
                            avoidSteerDir = avoidDirection(car, obstacle, point.x, point.y)
                        end

                        if collisionCooldown > 0 then
                            collisionCooldown = collisionCooldown - 1
                            setGameKeyState(0, avoidSteerDir)
                            if currentSpeed > 10 then press_brake() end
                        else
                            if currentSpeed < targetSpeed + 0.2 then
                                press_gas()
                            else
                                press_brake()
                            end
                        end

                        printStringNow('~g~VR Bot ~w~' .. play_index .. '/' .. #current_route .. ' ~y~' .. math.floor(currentSpeed) .. 'km/h', 100)

                        if locateCharInCar2d(PLAYER_PED, point.x, point.y, routeRadius, routeRadius, false) then
                            play_index = play_index + 1
                        else
                            local closestIdx = play_index
                            local closestDist = getDistanceBetweenCoords2d(carX, carY, point.x, point.y)
                            for i = play_index, math.min(play_index + 10, #current_route) do
                                local p = current_route[i]
                                local d = getDistanceBetweenCoords2d(carX, carY, p.x, p.y)
                                if d < closestDist then
                                    closestDist = d
                                    closestIdx = i
                                end
                            end
                            play_index = closestIdx
                        end

                        if getCarHealth(car) < 500 then
                            repairCar(car)
                        end

                        if play_index > #current_route then
                            if repeating then
                                play_index = 1
                                speedVariance = (math.random() * 0.14) - 0.07
                                showMsg("~g~Kilpa baigta! Kartojama!")
                            else
                                playing = false
                                play_index = 1
                                setGameKeyState(0, 0)
                                showMsg("~g~Kelias baigtas!")
                            end
                        end
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
                    playing = false
                    current_route = {}
                    start_x, start_y, start_z = getCharCoordinates(PLAYER_PED)
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
                speedVariance = (math.random() * 0.14) - 0.07
                if #current_route > 5 then
                    play_index = 1
                    playing = true
                    paused = false
                    showMsg("~g~Vaziavimas pradetas!")
                else
                    local route = loadRoute(current_name)
                    if route and #route > 0 then
                        current_route = route
                        play_index = 1
                        playing = true
                        paused = false
                        showMsg("~g~Kelias ikrautas ir paleistas: " .. current_name)
                    else
                        showMsg("~r~Nera irasyto kelio!")
                    end
                end
            else
                playing = false
                setGameKeyState(0, 0)
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
                    showMsg("~y~Pristabdyta!")
                else
                    showMsg("~g~Tesiama!")
                end
            end
        end

        if isKeyJustPressed(VK_F7) then
            recording = false
            playing = false
            repeating = false
            paused = false
            play_index = 1
            setGameKeyState(0, 0)
            showMsg("~r~Viskas sustabdyta!")
        end
    end
end
