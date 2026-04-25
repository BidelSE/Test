script_name('dangis_vr')
script_version('5.2')
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
local freezeChatSent = false
local samp = 0

-- ==========================================
-- HUMANIZATION STATE
-- ==========================================
local speedVariance = 0.0       -- re-rolled ±7% each lap
local lastSteerValue = 0        -- tracks what turning_mechanism last set
local steerNoiseValue = 0       -- current noise offset being applied
local steerNoiseDuration = 0    -- frames remaining for active noise
local steerNoiseCooldown = 0    -- frames until next noise is allowed
local collisionCooldown = 0     -- frames remaining in collision-avoid mode
local overrideActive = false    -- true while player is holding any drive key

local freezeChatResponses = { "?", "lag?", "wtf", "bruh", "??" }

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
-- lastSteerValue tracking added so humanization layer can read what was set
-- ==========================================

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

-- ==========================================
-- HUMANIZATION FUNCTIONS
-- ==========================================

-- Applies a brief random steering perturbation after turning_mechanism has set
-- its value. Noise lasts 2–6 frames then cools down 8–30 frames before repeating.
-- Mimics the micro-corrections a human makes constantly while driving.
local function applySteerNoise()
    if steerNoiseDuration > 0 then
        steerNoiseDuration = steerNoiseDuration - 1
        local clamped = math.max(-128, math.min(128, lastSteerValue + steerNoiseValue))
        setGameKeyState(0, clamped)
    elseif steerNoiseCooldown > 0 then
        steerNoiseCooldown = steerNoiseCooldown - 1
    elseif math.random(100) <= 10 then
        -- Larger noise on straights (±25), gentler noise mid-turn (±12)
        local range = (lastSteerValue == 0) and 25 or 12
        steerNoiseValue = math.random(-range, range)
        steerNoiseDuration = math.random(2, 6)
        steerNoiseCooldown = math.random(8, 30)
        local clamped = math.max(-128, math.min(128, lastSteerValue + steerNoiseValue))
        setGameKeyState(0, clamped)
    end
end

-- Checks for a vehicle within 5 units of a point 12 units ahead in the
-- direction of the next waypoint. Uses pcall so a missing getClosestCar
-- implementation degrades gracefully to no collision avoidance.
local function hasObstacleAhead(car, targetX, targetY)
    local carX, carY, carZ = getCarCoordinates(car)
    local dx = targetX - carX
    local dy = targetY - carY
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 0.1 then return false end
    local nx, ny = dx / dist, dy / dist
    local aheadX = carX + nx * 12
    local aheadY = carY + ny * 12
    local ok, nearest = pcall(getClosestCar, aheadX, aheadY, carZ, 5.0, {}, 0)
    return ok and nearest and nearest ~= 0 and nearest ~= car
end

-- ==========================================
-- SAFETY FUNCTIONS
-- ==========================================

-- Uses raw Windows key state (isKeyDown) so detection is independent of what
-- the bot writes to game memory via setGameKeyState/writeMemory each frame.
-- getPadState reads the processed game pad buffer which the bot pollutes.
local function isPlayerControlling()
    return isKeyDown(0x57) or  -- W
           isKeyDown(0x53) or  -- S
           isKeyDown(0x41) or  -- A
           isKeyDown(0x44) or  -- D
           isKeyDown(0x20)     -- Space
end

-- Detects the "Ar žmogus" list dialog and auto-selects the blank line after a
-- human-realistic reading delay (2.5–7 s).
-- All SAMP dialog calls are wrapped in pcall to survive the race window where
-- sampIsDialogActive() returns true but the internal struct isn't fully written
-- yet — dereferencing it caused the null-pointer crash in samp.dll.
-- Fallback is a clean /q disconnect instead of a memory write to 0x0, which
-- was the other likely crash source.
local function handleArbotas()
    local ok, active = pcall(sampIsDialogActive)
    if not ok or not active then
        arbotasHandled = false
        return
    end
    if arbotasHandled then return end

    -- Guard every samp dialog getter — the struct may not be ready yet
    local ok1, style   = pcall(sampGetCurrentDialogType)
    local ok2, title   = pcall(sampGetCurrentDialogCaption)
    if not ok1 or not ok2 then return end
    if style ~= 2 then return end

    local lowerTitle = (title or ""):lower()
    if not (lowerTitle:find("mogus") or lowerTitle:find("bot") or lowerTitle:find("human")) then return end

    arbotasHandled = true
    printStringNow("~y~SAFETY: Arbotas detected, scanning items...", 2000)

    -- Find blank line. Prefer per-item iteration; fall back to splitting full text.
    local blankIndex = -1
    if sampGetCurrentDialogListItemCount and sampGetCurrentDialogListItem then
        local ok3, count = pcall(sampGetCurrentDialogListItemCount)
        if ok3 and count then
            for i = 0, count - 1 do
                local ok4, item = pcall(sampGetCurrentDialogListItem, i)
                if ok4 and (item or ""):match("^%s*$") then
                    blankIndex = i
                    break
                end
            end
        end
    end
    if blankIndex < 0 then
        local ok5, items = pcall(sampGetCurrentDialogText)
        if ok5 then
            local idx = 0
            for line in ((items or "") .. "\n"):gmatch("([^\n]*)\n") do
                if line:match("^%s*$") then
                    blankIndex = idx
                    break
                end
                idx = idx + 1
            end
        end
    end

    if blankIndex >= 0 then
        local ok6, capturedId = pcall(sampGetCurrentDialogId)
        if not ok6 then return end
        local capturedIdx = blankIndex
        lua_thread.create(function()
            local delay = math.random(2500, 7000)
            printStringNow("~y~SAFETY: Answering arbotas in ~" .. math.floor(delay / 1000) .. "s", 3000)
            wait(delay)
            local stillActive = pcall(sampIsDialogActive)
            if stillActive then
                pcall(sampSendDialogResponse, capturedId, 1, capturedIdx, "")
                printStringNow("~g~SAFETY: Arbotas answered (blank line " .. capturedIdx .. ")", 2000)
            end
        end)
    else
        -- No blank line found: disconnect cleanly via /q rather than crashing
        printStringNow("~r~SAFETY: No blank line found — disconnecting...", 2000)
        lua_thread.create(function()
            wait(1500)
            sampSendChat("/q")
        end)
    end
end

-- When frozen (~1 s stationary): zeroes throttle memory, sends occasional
-- input twitches every ~3 s and one natural chat message after 3 s to mimic
-- a confused human realising they cannot move.
local function handleFreeze(car)
    local cx, cy = getCarCoordinates(car)
    local speed  = getCarSpeed(car)
    if getDistanceBetweenCoords2d(cx, cy, lastX, lastY) < 0.1 and speed < 0.1 then
        freezeTimer = freezeTimer + 1
        if freezeTimer > 30 then
            writeMemory(0xB73458 + 0x20, 1, 0, false)
            writeMemory(0xB73458 + 0xC,  1, 0, false)

            -- Send one chat message ~3 s into the freeze
            if freezeTimer == 90 and not freezeChatSent then
                freezeChatSent = true
                local msg = freezeChatResponses[math.random(#freezeChatResponses)]
                sampSendChat(msg)
            end

            -- Random input twitch roughly every 3 s (180 frames) with ±20% jitter
            local twitchInterval = math.random(150, 210)
            if freezeTimer % twitchInterval == 0 then
                local kind = math.random(3)
                if kind == 1 then
                    -- Brief gas tap
                    writeMemory(0xB73458 + 0x20, 1, math.random(80, 160), false)
                elseif kind == 2 then
                    -- Brief steer twitch
                    local dir = math.random(2) == 1 and math.random(30, 60) or math.random(-60, -30)
                    setGameKeyState(0, dir)
                end
                -- Input resets naturally next frame from the zero-writes above
            end
        end
    else
        freezeTimer = 0
        freezeChatSent = false
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
        printStringNow("~g~Safety Systems + Humanization: ~w~ACTIVE", 3000)
    end

    printStringNow("~g~Dangis VR v5.2 ikelta!", 3000)
    printStringNow("~w~F2-Irasyti F10-Paleisti F11-Kartoti F6-Pauze F7-Sustabdyti", 5000)

    -- Arbotas thread (independent — fires during recording, pause, idle, playback)
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

    -- Playback loop
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

                    -- Safety: freeze detection + humanization
                    handleFreeze(car)

                    -- Pause driving while chat input or any dialog is open.
                    -- A real driver would lift off the gas when they open chat.
                    -- Also prevents W/A/S/D typed into the chat box from being
                    -- misread as driving input by isPlayerControlling below.
                    local _, chatOpen   = pcall(sampIsChatInputActive)
                    local _, dialogOpen = pcall(sampIsDialogActive)
                    if chatOpen or dialogOpen then
                        writeMemory(0xB73458 + 0x20, 1, 0,   false) -- release gas
                        writeMemory(0xB73458 + 0xC,  1, 100, false) -- gentle brake
                        setGameKeyState(0, 0)                        -- straighten
                    -- Safety: manual override — player input wins, bot yields.
                    -- Bot values are cleared once on the transition frame only.
                    -- Writing zeros every frame cancels the player's W/A/S/D.
                    elseif isPlayerControlling() then
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

                        -- v4.0 driving: steering and line draw
                        draw_line(point.x, point.y)
                        turning_mechanism(point.x, point.y, carX, carY, car)

                        -- Humanization: micro steering noise applied after base steering
                        applySteerNoise()

                        -- Humanization: speed variance
                        -- speedVariance is a per-lap offset (±7%) rolled on loop restart.
                        -- Small per-frame noise (±2 units) added on top.
                        local frameNoise = math.random(-2, 2)
                        local targetSpeed = point.speed * (1.0 + speedVariance) + frameNoise
                        local currentSpeed = getCarSpeed(car)

                        -- Anti-collision: if a vehicle is ahead, brake and ease right
                        if collisionCooldown > 0 then
                            collisionCooldown = collisionCooldown - 1
                            press_brake()
                            if collisionCooldown > 30 then
                                setGameKeyState(0, 55) -- mild right steer to go around
                            end
                        else
                            if hasObstacleAhead(car, point.x, point.y) then
                                collisionCooldown = 80
                            end
                            -- v4.0 speed control (now against humanized targetSpeed)
                            if currentSpeed < targetSpeed + 0.2 then
                                press_gas()
                            else
                                press_brake()
                            end
                        end

                        printStringNow('~g~VR Bot ~w~' .. play_index .. '/' .. #current_route .. ' ~y~' .. math.floor(currentSpeed) .. 'km/h', 100)

                        -- v4.0 waypoint advancement
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
                                -- Humanization: re-roll per-lap speed variance each loop
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
                -- Roll speed variance fresh each playback start
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
