script_name('dangis_vr')
script_version('5.5')
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
local lastRecordHeading = 0

local lastSteerValue = 0
local steerNoiseValue = 0
local steerNoiseDuration = 0
local steerNoiseCooldown = 0
local collisionCooldown = 0
local avoidSteerDir = 0
local overrideActive = false

local lastX, lastY = 0.0, 0.0
local freezeTimer = 0
local lastCarHeading = 0
local reverseTimer = 0

local steerBuf = {0, 0}
local gasLevel = 0
local brakeLevel = 0



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
    routeObstacleDist = math.huge, routeAvoidDir = 0, routeObstacleTimer = 0,
    currentLateral = 0.0, nudgeOffset = 0.0, nudgeFrames = 0, nextNudge = 0,
    frozenByAdmin = false, refreshSent = false,
    testFreezeActive = false, testArbotasActive = false,
    testArbotasLines = {}, testArbotasEmptyIdx = 0, testArbotasCursor = 1,
    testArbotasBotResult = nil, testArbotasBotRunning = false,
    hudFont = nil,
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
        local range = (lastSteerValue == 0) and 25 or 40
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
    local checkX = carX + nx * 12
    local checkY = carY + ny * 12
    local ok1, nearest = pcall(getClosestCar, checkX, checkY, carZ, 5.0, {}, 0)
    if ok1 and nearest and nearest ~= 0 and nearest ~= car then
        local ox, oy = getCarCoordinates(nearest)
        return ox, oy
    end
    local ok2, nearObj = pcall(getClosestObject, checkX, checkY, carZ, 4.0, false, false)
    if ok2 and nearObj and nearObj ~= 0 then
        local ok3, ox, oy = pcall(getObjectCoordinates, nearObj)
        if ok3 and ox then return ox, oy end
    end
    return nil
end

local function avoidDir(car, obsX, obsY, targetX, targetY)
    local carX, carY = getCarCoordinates(car)
    local dx = targetX - carX
    local dy = targetY - carY
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.1 then return 128 end
    local nx, ny = dx / d, dy / d
    local dot = (obsX - carX) * ny + (obsY - carY) * (-nx)
    return dot > 0 and -128 or 128
end

local function sharpTurnAhead(route, idx)
    local n = #route
    for i = idx, math.min(idx + LOOKAHEAD, n - 1) do
        local ax = route[i].x - route[math.max(1, i-1)].x
        local ay = route[i].y - route[math.max(1, i-1)].y
        local bx = route[math.min(n, i+1)].x - route[i].x
        local by = route[math.min(n, i+1)].y - route[i].y
        local da = math.sqrt(ax*ax + ay*ay)
        local db = math.sqrt(bx*bx + by*by)
        if da > 0.1 and db > 0.1 then
            local dot = (ax/da)*(bx/db) + (ay/da)*(by/db)
            if dot < -0.3 then return true end
        end
    end
    return false
end

local function findNearestWaypoint(route, carX, carY)
    local best, bestDist = 1, math.huge
    for i = 1, #route do
        local d = getDistanceBetweenCoords2d(carX, carY, route[i].x, route[i].y)
        if d < bestDist then bestDist = d; best = i end
    end
    return best
end

local function scanRouteAhead(route, idx, car)
    local n = #route
    local best = math.huge
    local bestDir = 0
    for i = idx + 10, math.min(idx + 200, n), 5 do
        local p = route[i]
        local obX, obY = nil, nil
        local ok1, nearCar = pcall(getClosestCar, p.x, p.y, p.z, 6.0, {}, 0)
        if ok1 and nearCar and nearCar ~= 0 and nearCar ~= car then
            local cx, cy = getCarCoordinates(nearCar)
            obX, obY = cx, cy
        end
        if not obX then
            local ok2, nearObj = pcall(getClosestObject, p.x, p.y, p.z, 3.0, false, false)
            if ok2 and nearObj and nearObj ~= 0 then
                local ok3, ox, oy = pcall(getObjectCoordinates, nearObj)
                if ok3 and ox then obX, obY = ox, oy end
            end
        end
        if obX then
            local prev = route[math.max(1, i - 1)]
            local rx = p.x - prev.x
            local ry = p.y - prev.y
            local rLen = math.sqrt(rx*rx + ry*ry)
            local cross = rx * (obY - p.y) - ry * (obX - p.x)
            local lateralDist = rLen > 0.1 and math.abs(cross) / rLen or 99
            if lateralDist < 2.5 then
                local d = i - idx
                if d < best then
                    best = d
                    bestDir = cross > 0 and 1 or -1
                end
            end
        end
    end
    return best, bestDir
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
    if S.testFreezeActive then
        freezeTimer = freezeTimer + 1
        if freezeTimer > 3 then S.frozenByAdmin = true end
        lastX, lastY = cx, cy
        return
    end
    if getDistanceBetweenCoords2d(cx, cy, lastX, lastY) < 0.1 and speed < 0.1 then
        freezeTimer = freezeTimer + 1
        if freezeTimer > 3 then S.frozenByAdmin = true end
        if freezeTimer > 150 and reverseTimer == 0 then
            local point = route[pidx]
            local th = getHeadingFromVector2d(point.x - cx, point.y - cy)
            local diff = math.abs(getCarHeading(car) - th)
            if diff > 180 then diff = 360 - diff end
            if diff > 100 then reverseTimer = 80 end
        end
    else
        freezeTimer = 0
        S.frozenByAdmin = false
        S.refreshSent = false
    end
    lastX, lastY = cx, cy
end

local function handleAdminRotate(car)
    if not playing or isCrashing then return end
    local heading = getCarHeading(car)
    local diff = math.abs(heading - lastCarHeading)
    if diff > 180 then diff = 360 - diff end
    if diff > 150 then
        isCrashing = true
        paused = true
        setGameKeyState(0, 0)
        gasLevel = 0; brakeLevel = 0
        writeMemory(0xB73458 + 0x20, 1, 0, false)
        writeMemory(0xB73458 + 0xC,  1, 0, false)
        lua_thread.create(function()
            wait(math.random(1500, 6000))
            doForceCrash()
        end)
    end
    lastCarHeading = heading
end

local function readCString(addr, maxLen)
    if not addr or addr < 0x10000 then return "" end
    local s = ""
    pcall(function()
        for i = 0, (maxLen or 512) - 1 do
            local b = readMemory(addr + i, 1, false)
            if b == 0 then break end
            if b == 10 then s = s .. "\n"
            elseif b >= 32 and b <= 126 then s = s .. string.char(b)
            elseif b > 126 then s = s .. " "  -- extended ASCII (e.g. Lithuanian ž) → space
            end
        end
    end)
    return s
end

local function tryAnswerAntibotDialog(dPtr)
    local ffiok, ffi = pcall(require, "ffi")
    if not ffiok then return false end

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
end

local function handleArbotas()
    if not playing or isCrashing or samp == 0 then return end
    local dPtr = readMemory(samp + 0x21A0B8, 4, true)
    if dPtr == 0 then arbotasHandled = false; return end
    if readMemory(dPtr + 0x28, 4, true) ~= 1 then arbotasHandled = false; return end
    if arbotasHandled then return end
    -- Skip non-arbotas dialogs (prevents crash when F1, server info dialogs, etc. open)
    local foundMogus = false
    for off = 0, 0x60, 4 do
        local ptr = readMemory(dPtr + off, 4, false)
        if ptr and ptr > 0x10000 and ptr < 0x7FFFFFFF then
            local ok, s = pcall(readCString, ptr, 512)
            if ok and s:lower():find("mogus") then foundMogus = true; break end
        end
    end
    if not foundMogus then
        for off = 0x2C, 0x200, 4 do
            local ok, s = pcall(readCString, dPtr + off, 256)
            if ok and s:lower():find("mogus") then foundMogus = true; break end
        end
    end
    if not foundMogus then return end
    arbotasHandled = true
    paused = true
    setGameKeyState(0, 0)
    gasLevel = 0; brakeLevel = 0
    writeMemory(0xB73458 + 0x20, 1, 0, false)
    writeMemory(0xB73458 + 0xC,  1, 0, false)

    if tryAnswerAntibotDialog(dPtr) then
        lua_thread.create(function()
            -- Wait up to 15s for the answer + dialog close
            for _ = 1, 150 do
                wait(100)
                local dp = readMemory(samp + 0x21A0B8, 4, true)
                if dp == 0 or readMemory(dp + 0x28, 4, true) ~= 1 then
                    arbotasHandled = false
                    paused = false
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
end

function main()
    printStringNow("~y~Dangis VR: ~w~Laukiama...", 5000)
    wait(8000)
    if not doesDirectoryExist(paths_dir) then createDirectory(paths_dir) end
    samp = getModuleHandle("samp.dll")
    printStringNow("~g~Dangis VR v5.5 ikelta!", 3000)
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
                    playing = false; repeating = false; paused = false
                    setGameKeyState(0, 0)
                    gasLevel = 0; brakeLevel = 0
                    showMsg("~r~Vaziavimas sustabdytas - islejei masina!")
                else
                    local car = storeCarCharIsInNoSave(PLAYER_PED)
                    local carX, carY, carZ = getCarCoordinates(car)

                    if S.nextBreakTime > 0 and os.clock() >= S.nextBreakTime then
                        S.autoPaused = true
                        paused = true
                        setGameKeyState(0, 0)
                        gasLevel = 0; brakeLevel = 0
                        writeMemory(0xB73458 + 0x20, 1, 0, false)
                        writeMemory(0xB73458 + 0xC,  1, 0, false)
                        S.nextBreakTime = 0
                        local breakDuration = math.random(3, 12) * 60 * 1000
                        lua_thread.create(function()
                            wait(breakDuration)
                            if S.autoPaused then
                                S.autoPaused = false
                                paused = false
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

                    S.routeObstacleTimer = S.routeObstacleTimer + 1
                    if S.routeObstacleTimer >= 30 then
                        S.routeObstacleTimer = 0
                        S.routeObstacleDist, S.routeAvoidDir = scanRouteAhead(current_route, play_index, car)
                    end

                    handleFreeze(car, current_route, play_index)
                    handleAdminRotate(car)

                    if isPlayerControlling() then
                        if not overrideActive then
                            overrideActive = true
                            writeMemory(0xB73458 + 0x20, 1, 0, false)
                            writeMemory(0xB73458 + 0xC,  1, 0, false)
                            setGameKeyState(0, 0)
                            gasLevel = 0; brakeLevel = 0
                        end
                        printStringNow("~y~OVERRIDE ACTIVE", 100)
                    else
                        overrideActive = false

                        if reverseTimer > 0 then
                            reverseTimer = reverseTimer - 1
                            press_brake()
                            setGameKeyState(0, 0)
                            gasLevel = 0
                        elseif S.frozenByAdmin then
                            setGameKeyState(0, 0)
                            gasLevel = 0; brakeLevel = 0
                            writeMemory(0xB73458 + 0x20, 1, 0, false)
                            writeMemory(0xB73458 + 0xC,  1, 0, false)
                            if freezeTimer > 150 then
                                local iv = 180
                                if freezeTimer % iv == 0 then
                                    if math.random(2) == 1 then
                                        writeMemory(0xB73458 + 0x20, 1, math.random(60, 120), false)
                                    else
                                        setGameKeyState(0, math.random(2) == 1 and math.random(30, 60) or math.random(-60, -30))
                                    end
                                end
                            end
                            if freezeTimer >= 480 and not S.refreshSent then
                                S.refreshSent = true
                                typeSAMPCommand("/refresh")
                            end
                        else
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
                                    if S.routeObstacleDist < 60 and S.routeAvoidDir ~= 0 then
                                        local strength = (1.0 - S.routeObstacleDist / 60.0) * 2.0
                                        targetLateral = targetLateral + S.routeAvoidDir * strength
                                    end
                                    S.currentLateral = S.currentLateral + (targetLateral - S.currentLateral) * 0.04
                                    tX = tX + (-ndy / nd) * S.currentLateral
                                    tY = tY + (ndx / nd) * S.currentLateral
                                end
                            end

                            draw_line(tX, tY)

                            local point = current_route[play_index]
                            local speedMult = 1.0
                            if S.routeObstacleDist < 100 then
                                speedMult = S.routeObstacleDist >= 20
                                    and (0.5 + (S.routeObstacleDist - 20) / 80 * 0.5)
                                    or 0.4
                            end
                            local targetSpeed = point.speed * speedMult
                            local currentSpeed = getCarSpeed(car)

                            local obsX, obsY = getObstacleAhead(car, tX, tY)
                            if obsX and collisionCooldown == 0 then
                                collisionCooldown = 51
                                avoidSteerDir = avoidDir(car, obsX, obsY, tX, tY)
                            end

                            if collisionCooldown > 0 then
                                collisionCooldown = collisionCooldown - 1
                                setGameKeyState(0, avoidSteerDir)
                                gasLevel = 0
                                brakeLevel = currentSpeed > 10 and 255 or 0
                                writeMemory(0xB73458 + 0x20, 1, 0, false)
                                writeMemory(0xB73458 + 0xC, 1, brakeLevel, false)
                            elseif sharpTurnAhead(current_route, play_index) and currentSpeed > targetSpeed * 0.7 then
                                turning_mechanism(tX, tY, carX, carY, car)
                                applySteerNoise()
                                local excess = math.max(0, currentSpeed - targetSpeed * 0.7)
                                brakeLevel = math.min(255, math.floor(excess * 30))
                                gasLevel = math.max(0, gasLevel - 25)
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
                                        gasLevel = math.min(255, gasLevel + 18)
                                        brakeLevel = math.max(0, brakeLevel - 50)
                                    elseif currentSpeed < targetSpeed + 1.5 then
                                        brakeLevel = math.max(0, brakeLevel - 50)
                                    else
                                        local excess = currentSpeed - (targetSpeed + 1.5)
                                        brakeLevel = math.min(255, math.floor(excess * 30))
                                        gasLevel = math.max(0, gasLevel - 25)
                                    end
                                end
                                writeMemory(0xB73458 + 0x20, 1, gasLevel, false)
                                writeMemory(0xB73458 + 0xC, 1, brakeLevel, false)
                            end

                            printStringNow('~g~VR Bot ~w~' .. play_index .. '/' .. #current_route .. ' ~y~' .. math.floor(currentSpeed) .. 'km/h', 100)

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
                                    setGameKeyState(0, 0)
                                    gasLevel = 0; brakeLevel = 0
                                    showMsg("~g~Kelias baigtas!")
                                end
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
                S.autoPaused = false
                steerBuf = {0, 0}
                S.nextBreakTime = os.clock() + math.random(45, 90) * 60
                if isCharInAnyCar(PLAYER_PED) then
                    lastCarHeading = getCarHeading(storeCarCharIsInNoSave(PLAYER_PED))
                end
                if #current_route > 5 then
                    play_index = 1; playing = true; paused = false
                    showMsg("~g~Vaziavimas pradetas!")
                else
                    local route = loadRoute(current_name)
                    if route and #route > 0 then
                        current_route = route; play_index = 1; playing = true; paused = false
                        showMsg("~g~Kelias ikrautas ir paleistas: " .. current_name)
                    else
                        showMsg("~r~Nera irasyto kelio!")
                    end
                end
            else
                playing = false
                setGameKeyState(0, 0)
                gasLevel = 0; brakeLevel = 0
                writeMemory(0xB73458 + 0x20, 1, 0, false)
                writeMemory(0xB73458 + 0xC,  1, 0, false)
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
                    paused = false
                    S.nextBreakTime = os.clock() + math.random(45, 90) * 60
                    showMsg("~g~Tesiama!")
                else
                    paused = not paused
                    if paused then
                        setGameKeyState(0, 0)
                        gasLevel = 0; brakeLevel = 0
                        writeMemory(0xB73458 + 0x20, 1, 0, false)
                        writeMemory(0xB73458 + 0xC,  1, 0, false)
                        showMsg("~y~Pristabdyta!")
                    else
                        S.nextBreakTime = os.clock() + math.random(45, 90) * 60
                        showMsg("~g~Tesiama!")
                    end
                end
            end
        end

        if isKeyJustPressed(VK_F7) then
            recording = false; playing = false; repeating = false; paused = false
            S.autoPaused = false; play_index = 1
            setGameKeyState(0, 0)
            gasLevel = 0; brakeLevel = 0
            writeMemory(0xB73458 + 0x20, 1, 0, false)
            writeMemory(0xB73458 + 0xC,  1, 0, false)
            showMsg("~r~Viskas sustabdyta!")
        end

        if isKeyJustPressed(VK_F3) then
            local dp = readMemory(samp + 0x21A0B8, 4, true)
            if dp ~= 0 and readMemory(dp + 0x28, 4, true) == 1 then
                local ok = tryAnswerAntibotDialog(dp)
                showMsg(ok and "~g~TEST: Atsakymas vykdomas..." or "~r~TEST: Tuscia eilute nerasta!")
            elseif playing and not paused then
                paused = true
                setGameKeyState(0, 0)
                gasLevel = 0; brakeLevel = 0
                writeMemory(0xB73458 + 0x20, 1, 0, false)
                writeMemory(0xB73458 + 0xC,  1, 0, false)
                showMsg("~y~TEST: Sustojimas simuliuojamas...")
                lua_thread.create(function()
                    wait(math.random(3000, 8000))
                    paused = false
                    showMsg("~g~TEST: Tesiama!")
                end)
            else
                showMsg("~r~TEST: Botas nestartavo arba nera dialogo!")
            end
        end

        if isKeyJustPressed(VK_F4) then
            if isCharInAnyCar(PLAYER_PED) then
                local car = storeCarCharIsInNoSave(PLAYER_PED)
                local h = getCarHeading(car)
                local newH = (h + 180.0) % 360.0
                lastCarHeading = newH  -- update baseline so handleAdminRotate won't crash-trigger
                setCarHeading(car, newH)
                showMsg("~y~TEST: Masina pasukta 180 laipsniu!")
            else
                showMsg("~r~TEST: Turi buti masinos viduje!")
            end
        end

        if isKeyJustPressed(VK_F5) then
            if S.testArbotasActive then
                S.testArbotasActive = false
                S.testArbotasBotResult = nil
                S.testArbotasBotRunning = false
            else
                local function fakeLine()
                    local r = math.random(5)
                    if r == 1 then
                        return string.format("O(x %s y) = z^%d", math.random(2)==1 and "^" or "*", math.random(100, 9999))
                    elseif r == 2 then
                        return string.format("%d %d %05d", math.random(100,9999), math.random(1000,9999), math.random(10000,99999))
                    elseif r == 3 then
                        return string.format("%d + %05d", math.random(1000,9999), math.random(1000,99999))
                    elseif r == 4 then
                        return string.format("* %d %05d", math.random(1000,9999), math.random(10000,99999))
                    else
                        return string.format("|%s ; * %s%s%s", string.char(math.random(65,90)),
                            string.char(math.random(97,122)), string.char(math.random(97,122)), string.char(math.random(97,122)))
                    end
                end
                local nItems = math.random(8, 13)
                local emptyPos = math.random(3, nItems)
                S.testArbotasLines = {}
                for i = 1, nItems do
                    S.testArbotasLines[i] = (i == emptyPos) and "" or fakeLine()
                end
                S.testArbotasEmptyIdx = emptyPos
                S.testArbotasCursor = 1
                S.testArbotasBotResult = nil
                S.testArbotasBotRunning = true
                S.testArbotasActive = true
                lua_thread.create(function()
                    wait(math.random(3000, 7000))
                    local presses = S.testArbotasEmptyIdx - 1
                    for _ = 1, presses do
                        S.testArbotasCursor = math.min(S.testArbotasCursor + 1, #S.testArbotasLines)
                        wait(math.random(40, 90))
                    end
                    wait(math.random(300, 800))
                    S.testArbotasBotResult = S.testArbotasLines[S.testArbotasCursor] == ""
                    S.testArbotasBotRunning = false
                    wait(3000)
                    S.testArbotasActive = false
                    S.testArbotasBotResult = nil
                end)
            end
        end

        if isKeyJustPressed(VK_F8) then
            if S.testFreezeActive then
                S.testFreezeActive = false
                freezeTimer = 0
                S.frozenByAdmin = false
                S.refreshSent = false
                showMsg("~g~TEST: Isfrizinta!")
            else
                if playing then
                    S.testFreezeActive = true
                    freezeTimer = 0
                    showMsg("~y~TEST: Frizinamas... (F8 - isfrizinti)")
                else
                    showMsg("~r~TEST: Botas nestartavo!")
                end
            end
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

        -- Lazy font creation
        if not S.hudFont then
            S.hudFont = renderFontCreate("Arial", 11, 1)
        end

        -- Live ASWD bot input display
        if playing and S.hudFont then
            local bx, by = 12, 12
            local sz = 20
            local wCol = gasLevel > 50   and 0xFF33DD33 or 0xFF333333
            local sCol = brakeLevel > 50 and 0xFFDD3333 or 0xFF333333
            local aCol = lastSteerValue < -60 and 0xFFFF9900 or 0xFF333333
            local dCol = lastSteerValue >  60 and 0xFFFF9900 or 0xFF333333
            renderDrawBox(bx + sz,      by,      sz, sz, wCol)
            renderDrawBox(bx,           by + sz, sz, sz, aCol)
            renderDrawBox(bx + sz,      by + sz, sz, sz, sCol)
            renderDrawBox(bx + sz*2,    by + sz, sz, sz, dCol)
            renderFontDrawText(S.hudFont, "W", bx + sz + 6,   by + 4,      0xFF000000)
            renderFontDrawText(S.hudFont, "A", bx + 6,        by + sz + 4, 0xFF000000)
            renderFontDrawText(S.hudFont, "S", bx + sz + 6,   by + sz + 4, 0xFF000000)
            renderFontDrawText(S.hudFont, "D", bx + sz*2 + 6, by + sz + 4, 0xFF000000)
            if S.testFreezeActive then
                renderFontDrawText(S.hudFont, "FREEZE TEST", bx, by + sz*2 + 4, 0xFFFFFF00)
            end
        end

        -- Arbotas test dialog
        if S.testArbotasActive and S.hudFont then
            local dw = 310
            local lineH = 17
            local headerH = 54
            local dh = headerH + #S.testArbotasLines * lineH + 28
            local dx = 485
            local dy = 110
            -- outer border
            renderDrawBox(dx - 2, dy - 2, dw + 4, dh + 4, 0xFF888888)
            -- body background
            renderDrawBox(dx, dy, dw, dh, 0xFF111111)
            -- title bar
            renderDrawBox(dx, dy, dw, 18, 0xFF880000)
            renderFontDrawText(S.hudFont, "Ar zmogus", dx + 4, dy + 2, 0xFFFFFFFF)
            -- header lines
            renderDrawBox(dx, dy + 18, dw, 18, 0xFF661111)
            renderFontDrawText(S.hudFont, "Pasirinkite tuscia eilute", dx + 4, dy + 20, 0xFFFF6666)
            renderFontDrawText(S.hudFont, "Pasirinkus blogai galima gauti Ban", dx + 4, dy + 36, 0xFFFF4444)
            -- items
            for i, line in ipairs(S.testArbotasLines) do
                local ly = dy + headerH + (i - 1) * lineH
                if i == S.testArbotasCursor then
                    renderDrawBox(dx, ly, dw, lineH, 0xFF223366)
                end
                if line ~= "" then
                    renderFontDrawText(S.hudFont, line, dx + 4, ly + 2, 0xFF44AAFF)
                end
            end
            -- button bar
            local btnY = dy + headerH + #S.testArbotasLines * lineH + 4
            renderDrawBox(dx, btnY, dw, 20, 0xFF222222)
            renderFontDrawText(S.hudFont, "[ Gerai ]", dx + dw/2 - 25, btnY + 2, 0xFFAAAAAA)
            -- bot status
            if S.testArbotasBotResult == true then
                renderFontDrawText(S.hudFont, "BOT: Teisingai! (tuscia eilute surasta)", dx + 4, btnY + 4, 0xFF22FF22)
            elseif S.testArbotasBotResult == false then
                renderFontDrawText(S.hudFont, "BOT: Neteisingai!", dx + 4, btnY + 4, 0xFFFF2222)
            elseif S.testArbotasBotRunning then
                renderFontDrawText(S.hudFont, "BOT galvoja...", dx + 4, btnY + 4, 0xFFFFFF00)
            end
        end
    end
end
