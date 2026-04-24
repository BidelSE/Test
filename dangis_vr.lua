script_name('dangis_vr')
script_version('5.1')
require 'lib.moonloader'

-- ==========================================
-- BOT STATE
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
-- SAFETY STATE
-- ==========================================
local isCrashing = false
local arbotasHandled = false
local lastX, lastY = 0.0, 0.0
local freezeTimer = 0
local samp = 0

-- ==========================================
-- ROUTE FUNCTIONS (v4.0 unchanged)
-- ==========================================

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

-- ==========================================
-- DRIVING FUNCTIONS (v4.0 unchanged)
-- ==========================================

local function turning_mechanism(posX, posY, carPosX, carPosY, car)
    local heading = math.rad(getHeadingFromVector2d(posX - carPosX, posY - carPosY) + math.abs(getCarHeading(car) - 360.0))
    local heading = getHeadingFromVector2d(math.deg(math.sin(heading)), math.deg(math.cos(heading)))
    if heading > 180.0 and 355.0 > heading then
        setGameKeyState(0, -128)
    else
        if heading > 5.0 and 180.0 >= heading then
            setGameKeyState(0, 128)
        else
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

-- ==========================================
-- SAFETY FUNCTIONS
-- ==========================================

-- Returns true if the real player is touching any driving input.
local function isPlayerControlling()
    return getPadState(PLAYER_PED, 16) > 0 or  -- W  / accelerate
           getPadState(PLAYER_PED, 14) > 0 or  -- S  / reverse
           getPadState(PLAYER_PED, 0)  ~= 0 or -- A/D / steer
           getPadState(PLAYER_PED, 15) > 0     -- Space / handbrake
end

-- Detects the "Ar žmogus" bot-check list dialog and auto-selects the blank line.
-- The blank line is the correct answer — if the bot can find and click it reliably,
-- the server owners know this CAPTCHA approach is insufficient and must be rethought.
-- Falls back to a crash disconnect only if no blank line can be found.
local function handleArbotas()
    if not sampIsDialogActive() then
        arbotasHandled = false
        isCrashing = false
        return
    end
    if arbotasHandled then return end

    local dialogId, style, title, btn1, btn2, items = sampGetCurrentDialogInfo()

    -- Only act on LIST-type dialogs (style 2) with a bot-check title
    if style ~= 2 then return end
    local lowerTitle = title:lower()
    if not (lowerTitle:find("mogus") or lowerTitle:find("bot") or lowerTitle:find("human")) then return end

    arbotasHandled = true
    printStringNow("~y~SAFETY: Arbotas detected, scanning for blank line...", 2000)

    -- Items are newline-separated; find the first blank/whitespace-only entry
    local blankIndex = -1
    local idx = 0
    for line in (items .. "\n"):gmatch("([^\n]*)\n") do
        if line:match("^%s*$") then
            blankIndex = idx
            break
        end
        idx = idx + 1
    end

    if blankIndex >= 0 then
        printStringNow("~g~SAFETY: Blank line at index " .. blankIndex .. " — auto-answering!", 3000)
        sampSendDialogResponse(dialogId, 1, blankIndex, "")
    else
        -- Blank line not found: crash as fallback to avoid wrong answer ban
        if not isCrashing then
            isCrashing = true
            printStringNow("~r~SAFETY: No blank line found — crashing as fallback...", 2000)
            lua_thread.create(function()
                wait(1500)
                writeMemory(0x0, 4, 0, true) -- null-pointer write → hardware fault crash
            end)
        end
    end
end

-- When an admin freeze is detected (~1 s stationary), zeroes throttle memory
-- so the bot appears idle rather than revving against the freeze.
local function handleFreeze(car)
    local cx, cy = getCarCoordinates(car)
    local speed  = getCarSpeed(car)
    if getDistanceBetweenCoords2d(cx, cy, lastX, lastY) < 0.1 and speed < 0.1 then
        freezeTimer = freezeTimer + 1
        if freezeTimer > 30 then
            writeMemory(0xB73458 + 0x20, 1, 0, false)
            writeMemory(0xB73458 + 0xC,  1, 0, false)
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

    samp = getModuleHandle("samp.dll")
    if samp == 0 then
        printStringNow("~r~SAMP not found! Safety systems disabled.", 3000)
    else
        printStringNow("~g~Safety Systems: ~w~ACTIVE", 3000)
    end

    printStringNow("~g~Dangis VR v5.1 ikelta!", 3000)
    printStringNow("~w~F2-Irasyti F10-Paleisti F11-Kartoti F6-Pauze F7-Sustabdyti", 5000)

    -- Arbotas thread: runs independently of bot state so it catches checks
    -- during recording, pause, or idle — not just during playback.
    lua_thread.create(function()
        while true do
            wait(50)
            if samp ~= 0 then
                handleArbotas()
            end
        end
    end)

    -- Recording loop (v4.0 unchanged)
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

    -- Playback loop (v4.0 driving logic, freeze + override safety layered on top)
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

                    -- Safety: freeze detection
                    handleFreeze(car)

                    -- Safety: manual override — player input wins, bot yields
                    if isPlayerControlling() then
                        writeMemory(0xB73458 + 0x20, 1, 0, false)
                        writeMemory(0xB73458 + 0xC,  1, 0, false)
                        setGameKeyState(0, 0)
                        printStringNow("~y~OVERRIDE ACTIVE", 100)
                    else
                        -- v4.0 driving logic (unchanged)
                        local point = current_route[play_index]
                        local carX, carY, carZ = getCarCoordinates(car)

                        draw_line(point.x, point.y)
                        turning_mechanism(point.x, point.y, carX, carY, car)

                        local currentSpeed = getCarSpeed(car)
                        if currentSpeed < point.speed + 0.2 then
                            press_gas()
                        else
                            press_brake()
                        end

                        printStringNow('~g~VR Bot ~w~' .. play_index .. '/' .. #current_route .. ' ~y~' .. math.floor(currentSpeed) .. 'km/h', 100)

                        -- Waypoint check with closest point skip logic
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

                        -- Auto repair if health low
                        if getCarHealth(car) < 500 then
                            repairCar(car)
                        end

                        -- Check end of route
                        if play_index > #current_route then
                            if repeating then
                                play_index = 1
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

        -- F2: Start/stop recording
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

        -- F10: Start/stop playback
        if isKeyJustPressed(VK_F10) then
            if not playing then
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

        -- F11: Toggle repeat
        if isKeyJustPressed(VK_F11) then
            repeating = not repeating
            if repeating then
                showMsg("~g~Kartojimas IJUNGTAS!")
            else
                showMsg("~r~Kartojimas ISJUNGTAS!")
            end
        end

        -- F6: Pause/resume
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

        -- F7: Stop everything
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
