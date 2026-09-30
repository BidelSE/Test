script_name('dangis_vr')
script_version('5.48')
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
local debug_log_file = getWorkingDirectory() .. "/dangis_vr_debug.log"
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

local steerBuf = {0, 0}
local gasLevel = 0
local brakeLevel = 0
local pauseReleaseReason = ""
local lastDriveSpeed = 0.0
local suddenStopFrames = 0
local recordReverseFrames = 0
local recordForwardBrakeFrames = 0
local DRIVE_FORWARD = "FWD"
local DRIVE_BACK = "BACK"
local COLOR_ROUTE_FORWARD = 0xFFFF0000
local COLOR_ROUTE_BACK = 0xFF000000
local COLOR_ROUTE_BACK_OUTLINE = 0xFFFFFFFF
local recordDriveMode = DRIVE_FORWARD
local playbackDriveMode = DRIVE_FORWARD
local syntheticReverseKeyDown = false
local reverseKeyFfi, reverseKeyUser32 = nil, nil
local commandInputFfiReady = false



local showTrail = false
local currentTrail = {}
local lastTrail = {}
local trailTick = 0

local samp = 0

local S = {
    gasLiftFrames = 0, nextGasLift = 0,
    lapWander = 0.0, lapCount = 0,
    routeObstacleDist = math.huge, routeAvoidDir = 0, routeObstacleTimer = 0,
    routeObstacleUrgency = 0.0,
    avoidRouteDir = 0, avoidSideHit = false,
    avoidLateralTarget = 0.0, avoidHoldUntil = 0.0,
    bypassActive = false, bypassDir = 0, bypassOffset = 0.0,
    bypassHoldUntil = 0.0, bypassLastSeen = 0.0,
    bypassReturning = false,
    avoidClusterCount = 0,
    showObstacleDots = true, obstacleDebugMode = 2, obstacleFont = nil, obstacleHits = {}, obstacleProbes = {},
    currentLateral = 0.0, nudgeOffset = 0.0, nudgeFrames = 0, nextNudge = 0,
    manualPaused = false,
    -- Legacy name: this means freeze/recovery owns controls, not only admin state.
    frozenByAdmin = false, refreshSent = false, refreshTarget = 300,
    recentDriveSpeed = 0.0, recentDriveUntil = 0.0,
    testArbotasPaused = false,
    dialogPaused = false,
    dialogReleaseUntil = 0.0,
    freezeTestLatched = false,
    freezeRecoveryMode = "",
    freezeRefreshSentAt = 0.0,
    freezeFightUntil = 0.0,
    freezeReleaseUntil = 0.0,
    freezeRefreshAt = 0.0,
    freezeResumeDelay = 0.0,
    freezeRecoveryGraceUntil = 0.0,
    rotateFightUntil = 0.0,
    rotateReleaseUntil = 0.0,
    rotateIgnoreUntil = 0.0,
    reversePlaybackGraceUntil = 0.0,
    backToForwardUntil = 0.0,
    bumpActive = false,
    bumpPhase = "",
    bumpReason = "",
    bumpUntil = 0.0,
    bumpStartedAt = 0.0,
    bumpCooldownUntil = 0.0,
    bumpGraceUntil = 0.0,
    bumpStartX = 0.0,
    bumpStartY = 0.0,
    bumpMinDistance = 0.0,
    bumpMaxDistance = 0.0,
    bumpSteer = 0,
    forwardNoProgressFrames = 0,
    forwardNoProgressDist = 0.0,
    forwardNoProgressIndex = 0,
    rejoinFrames = 0,
    rejoinSteer = 0,
    rejoinCooldownUntil = 0.0,
    rejoinDisableUntil = 0.0,
}

local LOOKAHEAD = 6
local AVOID_OBJECT_MODELS = {
    [1238] = true, -- cone
    [1459] = true, -- road barrier
    [1423] = true, -- road barrier
    [19951] = true, -- road sign
    [19952] = true, -- road sign
    [19974] = true, -- road sign
    [19961] = true, -- road sign
    [19960] = true, -- road sign
}

-- Architecture map:
-- Utils/Debug: small shared helpers and optional debug output.
-- RouteStorage/RouteRecorder/RouteFollower: route files, recording, playback.
-- ObstacleAvoidance: existing probe scanner and bypass state.
-- RecoverySystem/AdminProtection/DialogBridge: pause and safety gates.
-- InputHandler/MainLoop: hotkeys, threads, and frame order.
local CONFIG = {
    route = {
        radius = routeRadius,
        recordingDelay = recordingDelay,
        lookahead = LOOKAHEAD,
        pathsDir = paths_dir,
        defaultName = current_name,
    },
    controls = {
        steerKey = 0,
        gasAddress = 0xB73458 + 0x20,
        brakeAddress = 0xB73458 + 0xC,
    },
    obstacle = {
        models = AVOID_OBJECT_MODELS,
        scanEveryFrames = 6,
        maxTrailPoints = 30000,
    },
    recovery = {
        rotateStartIgnoreSeconds = 0.8,
        freezeRecoveryGraceSeconds = 2.1,
        freezeWaitBeforeRefreshMinSeconds = 2.0,
        freezeWaitBeforeRefreshMaxSeconds = 3.0,
        freezeResumeDelayMinSeconds = 0.5,
        freezeResumeDelayMaxSeconds = 1.0,
        reverseTransitionGraceSeconds = 2.4,
        backToForwardCoastSeconds = 0.85,
        reverseLookaheadPoints = 90,
        reverseLookaheadRadius = 16.0,
        bumpEnabled = true,
        bumpCooldownSeconds = 3.4,
        bumpCoastSeconds = 0.32,
        bumpFreezeGraceSeconds = 1.8,
        bumpReverseMinSeconds = 0.85,
        bumpReverseMaxSeconds = 1.65,
        bumpReverseHardMaxSeconds = 2.6,
        bumpReverseDistanceMin = 2.0,
        bumpReverseDistanceMax = 6.0,
        bumpSteerMax = 72,
        bumpMinRecentSpeed = 2.0,
        bumpResyncBackPoints = 10,
        bumpResyncAheadPoints = 45,
        bumpResyncMaxDistance = 28.0,
        bumpFreezeEscalateSeconds = 0.85,
        bumpFreezeEscalateDistance = 0.25,
        forwardNoProgressFrames = 44,
        forwardNoProgressGas = 80,
        forwardNoProgressSpeed = 8.0,
        forwardProgressEpsilon = 0.06,
    },
    dialog = {
        sharedFile = dialog_flag_file,
    },
    debug = {
        enabled = false,
        logToFile = true,
        logFile = debug_log_file,
        maxLogBytes = 65536,
        categories = {
            route = true,
            obstacle = false,
            recovery = true,
            dialog = true,
            admin = true,
            input = true,
        },
    },
}

-- STATE is a debug/read-only mirror of legacy globals for now.
-- Do not use it as the source of truth until the old globals are fully migrated.
local STATE = {
    route = {
        points = current_route,
        name = current_name,
    },
    playback = {
        playing = playing,
        repeating = repeating,
        paused = paused,
        index = play_index,
        pauseReason = pauseReleaseReason,
    },
    obstacle = S,
    recovery = S,
    admin = S,
    dialog = S,
    input = {
        overrideActive = overrideActive,
        steerBuffer = steerBuf,
    },
    vehicle = {
        lastX = lastX,
        lastY = lastY,
        gas = gasLevel,
        brake = brakeLevel,
        steer = lastSteerValue,
    },
    pauseReasons = {
        manual = false,
        dialog = false,
        admin = false,
        obstacle = false,
        recovery = false,
    },
}

local Utils = {}
local Debug = {}
local RouteStorage = {}
local RouteRecorder = {}
local RouteFollower = {}
local ObstacleAvoidance = {}
local RecoverySystem = {}
local AdminProtection = {}
local DialogBridge = {}
local InputHandler = {}
local MainLoop = {}

local lastLoggedSharedState = nil

local function trimDebugLogFile()
    if not CONFIG.debug.logToFile then return end
    local path = CONFIG.debug.logFile or debug_log_file
    local file = io.open(path, "r")
    if not file then return end
    local size = file:seek("end") or 0
    file:close()
    if size > (CONFIG.debug.maxLogBytes or 65536) then
        local reset = io.open(path, "w")
        if reset then
            reset:write(string.format("[%.3f] [LOG] truncated old debug log\n", os.clock()))
            reset:close()
        end
    end
end

local function logEvent(category, message)
    if not CONFIG.debug.logToFile then return end
    local file = io.open(CONFIG.debug.logFile or debug_log_file, "a")
    if not file then return end
    file:write(string.format("[%.3f] [%s] %s\n", os.clock(), tostring(category or "INFO"), tostring(message or "")))
    file:close()
end

local function writeDriveControls(gas, brake)
    if S and (S.freezeTestLatched or S.frozenByAdmin) then
        gas = 0
        brake = 0
    end
    writeMemory(CONFIG.controls.gasAddress, 1, gas or 0, false)
    writeMemory(CONFIG.controls.brakeAddress, 1, brake or 0, false)
end

local function refreshStateView()
    local now = os.clock()
    STATE.route.points = current_route
    STATE.route.name = current_name
    STATE.playback.playing = playing
    STATE.playback.repeating = repeating
    STATE.playback.paused = paused
    STATE.playback.index = play_index
    STATE.playback.pauseReason = pauseReleaseReason
    STATE.input.overrideActive = overrideActive
    STATE.input.steerBuffer = steerBuf
    STATE.vehicle.lastX = lastX
    STATE.vehicle.lastY = lastY
    STATE.vehicle.gas = gasLevel
    STATE.vehicle.brake = brakeLevel
    STATE.vehicle.steer = lastSteerValue
    STATE.pauseReasons.manual = S.manualPaused
    STATE.pauseReasons.dialog = S.dialogPaused or S.testArbotasPaused
    STATE.pauseReasons.obstacle = S.bypassActive or collisionCooldown > 0
    STATE.pauseReasons.admin = now < (S.rotateFightUntil or 0.0) or now < (S.rotateReleaseUntil or 0.0)
    STATE.pauseReasons.recovery = S.freezeTestLatched
        or S.frozenByAdmin
        or S.bumpActive
        or now < (S.backToForwardUntil or 0.0)
end

function dbg(category, message)
    logEvent(category, message)
    if not CONFIG.debug.enabled then return end
    if not CONFIG.debug.categories[category] then return end
    printStringNow(string.format("~w~[%s] %s", tostring(category), tostring(message)), 1000)
end

Debug.log = dbg

function resetObstacleBypass()
    S.avoidLateralTarget = 0.0
    S.avoidHoldUntil = 0.0
    S.bypassActive = false
    S.bypassDir = 0
    S.bypassOffset = 0.0
    S.bypassHoldUntil = 0.0
    S.bypassLastSeen = 0.0
    S.bypassReturning = false
end

local function shouldAvoidObjectModel(modelId)
    modelId = tonumber(modelId)
    return modelId ~= nil and AVOID_OBJECT_MODELS[modelId] == true
end

local function callObjectModelGetter(name, obj)
    local fn = _G and _G[name] or nil
    if type(fn) ~= "function" then return nil end
    local ok, modelId = pcall(fn, obj)
    modelId = ok and tonumber(modelId) or nil
    if modelId and modelId > 0 then return modelId end
    return nil
end

local function getAvoidObjectModel(obj)
    if not obj or obj == 0 then return nil end
    return callObjectModelGetter("getObjectModel", obj)
        or callObjectModelGetter("getObjectModelId", obj)
        or callObjectModelGetter("getObjectModelID", obj)
        or callObjectModelGetter("getObjectModelIndex", obj)
end

local function isAvoidableObject(obj)
    local modelId = getAvoidObjectModel(obj)
    return shouldAvoidObjectModel(modelId), modelId
end

local function readObjectCoordinates(obj)
    local ok, a, b, c, d = pcall(getObjectCoordinates, obj)
    if not ok then return false end
    if type(a) == "boolean" then
        if not a then return false end
        return true, b, c, d
    end
    if a == nil then return false end
    return true, a, b, c
end

local function collisionObjectModelId(colPoint)
    if not colPoint then return nil end
    local ok, modelId = pcall(function()
        return tonumber(colPoint.modelId or colPoint.modelID or colPoint.model or colPoint.modelIndex)
    end)
    modelId = ok and modelId or nil
    if modelId then return modelId end
    local entityOk, entity = pcall(function()
        return colPoint.entity or colPoint.object or colPoint.handle or colPoint.entityHandle
    end)
    if not entityOk then return nil end
    return getAvoidObjectModel(entity)
end

local function normalizeDriveMode(value)
    if value == true or value == 1 then return DRIVE_BACK end
    local text = tostring(value or ""):upper()
    if text == "1" or text == "TRUE" or text == "R" or text == "REV" or text == "REVERSE" or text == "BACK" or text == "B" then
        return DRIVE_BACK
    end
    return DRIVE_FORWARD
end

local function applyDriveModeToPoint(point, mode)
    if type(point) ~= "table" then return point end
    point.drive = normalizeDriveMode(mode or point.drive or point.mode or point.reverse)
    point.reverse = point.drive == DRIVE_BACK
    return point
end

local function isRoutePointReverse(point)
    if type(point) ~= "table" then return false end
    return normalizeDriveMode(point.drive or point.mode or point.reverse) == DRIVE_BACK
end

local function routeDriveModeAt(route, idx)
    local p = type(route) == "table" and route[idx] or nil
    return normalizeDriveMode(p and (p.drive or p.mode or p.reverse) or DRIVE_FORWARD)
end

local function hasDriveModeRun(route, idx, mode, needed)
    if type(route) ~= "table" then return false end
    needed = needed or 3
    local last = math.min(#route, idx + needed - 1)
    if last - idx + 1 < needed then return false end
    for i = idx, last do
        if routeDriveModeAt(route, i) ~= mode then return false end
    end
    return true
end

local function getPlaybackDriveMode(route, idx)
    -- Playback must obey the recorded route mode exactly. Smoothing this caused
    -- BACK to leak into FWD sections and made reverse paths unpredictable.
    playbackDriveMode = routeDriveModeAt(route, idx)
    return playbackDriveMode
end

local function storageFileExists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

local function copyStorageFile(src, dst)
    local input = io.open(src, "r")
    if not input then return false end
    local data = input:read("*a") or ""
    input:close()

    local output = io.open(dst, "w")
    if not output then return false end
    output:write(data)
    output:close()
    return true
end

local function getRecordingForwardAxes(heading)
    local h = math.rad(heading or 0.0)
    local fx = -math.sin(h)
    local fy = -math.cos(h)
    local len = math.sqrt(fx * fx + fy * fy)
    if len < 0.1 then return 0.0, 1.0 end
    return fx / len, fy / len
end

local function normalizeRouteReverseFlags(route)
    -- Reverse is now an explicit recorded drive mode. Normalize only the
    -- string/legacy boolean representation; never infer it from geometry.
    if type(route) == "table" then
        for _, p in ipairs(route) do
            applyDriveModeToPoint(p)
        end
    end
    return route
end

local function saveRoute(name, route)
    route = normalizeRouteReverseFlags(route)
    if RouteStorage.validateRoute and not RouteStorage.validateRoute(route) then return false end
    local path = paths_dir .. name .. ".txt"
    local tmpPath = path .. ".tmp"
    local bakPath = path .. ".bak"
    local file = io.open(tmpPath, "w")
    if file then
        for _, p in ipairs(route) do
            local drive = normalizeDriveMode(p.drive or p.reverse)
            file:write(string.format('{%s}:{%s}:{%s}:{%s}:{%s}:{%s}\n',
                p.x, p.y, p.z, p.speed, p.heading, drive))
        end
        file:close()
        os.remove(bakPath)
        if storageFileExists(path) then
            if not os.rename(path, bakPath) then
                os.remove(path)
            end
        end
        if os.rename(tmpPath, path) then
            os.remove(bakPath)
            return true
        end
        if copyStorageFile(tmpPath, path) then
            os.remove(tmpPath)
            os.remove(bakPath)
            return true
        end
        if storageFileExists(bakPath) then
            os.rename(bakPath, path)
        end
        os.remove(tmpPath)
    end
    return false
end

local function loadRoute(name)
    local path = paths_dir .. name .. ".txt"
    local function readRouteFile(filePath)
        local file = io.open(filePath, "r")
        if not file then return nil end
        local route = {}
        for line in file:lines() do
            local x, y, z, speed, heading, drive = line:match('^{([^}]*)}:{([^}]*)}:{([^}]*)}:{([^}]*)}:{([^}]*)}:{([^}]*)}$')
            if x then
                local mode = normalizeDriveMode(drive)
                table.insert(route, {x=tonumber(x), y=tonumber(y), z=tonumber(z) or 0, speed=tonumber(speed) or 0, heading=tonumber(heading) or 0, drive=mode, reverse=mode == DRIVE_BACK})
            else
                x, y, z, speed, heading = line:match('^{([^}]*)}:{([^}]*)}:{([^}]*)}:{([^}]*)}:{([^}]*)}$')
                if x then
                    table.insert(route, {x=tonumber(x), y=tonumber(y), z=tonumber(z) or 0, speed=tonumber(speed) or 0, heading=tonumber(heading) or 0, drive=DRIVE_FORWARD, reverse=false})
                else
                    local ox, oy, os2 = line:match('^{([^}]*)}:{([^}]*)}:{([^}]*)}$')
                    if ox then
                        table.insert(route, {x=tonumber(ox), y=tonumber(oy), z=0, speed=tonumber(os2) or 0, heading=0, drive=DRIVE_FORWARD, reverse=false})
                    end
                end
            end
        end
        file:close()
        return route
    end

    local route = normalizeRouteReverseFlags(readRouteFile(path))
    local tmpRoute = normalizeRouteReverseFlags(readRouteFile(path .. ".tmp"))
    local bakRoute = normalizeRouteReverseFlags(readRouteFile(path .. ".bak"))
    local routeOk = RouteStorage.validateRoute == nil or RouteStorage.validateRoute(route)
    local tmpOk = RouteStorage.validateRoute ~= nil and RouteStorage.validateRoute(tmpRoute)

    if tmpOk and not routeOk then
        return tmpRoute
    end
    if routeOk then return route end
    if RouteStorage.validateRoute == nil or RouteStorage.validateRoute(bakRoute) then return bakRoute end
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

local function ensureReverseKeyApi()
    if reverseKeyFfi == false then return nil end
    if reverseKeyFfi and reverseKeyUser32 then return reverseKeyUser32 end
    local ok, ffi = pcall(require, "ffi")
    if not ok then
        reverseKeyFfi = false
        return nil
    end
    pcall(ffi.cdef, [[
        void keybd_event(unsigned char, unsigned char, unsigned long, unsigned long*);
        short GetAsyncKeyState(int vKey);
    ]])
    local u32ok, u32 = pcall(ffi.load, "user32")
    if not u32ok then
        reverseKeyFfi = false
        return nil
    end
    reverseKeyFfi, reverseKeyUser32 = ffi, u32
    return reverseKeyUser32
end

local function isPhysicalKeyDown(vk)
    if isKeyDown(vk) then return true end
    local u32 = ensureReverseKeyApi()
    if not u32 or not u32.GetAsyncKeyState then return false end
    local ok, state = pcall(u32.GetAsyncKeyState, vk)
    state = ok and tonumber(state) or 0
    return state < 0 or state >= 0x8000
end

local function setSyntheticReverseKey(active, force)
    active = active == true
    local u32 = ensureReverseKeyApi()
    if not u32 then return end
    if not force and syntheticReverseKeyDown == active then return end
    if active then
        u32.keybd_event(0x53, 0, 0, nil)
        syntheticReverseKeyDown = true
    else
        u32.keybd_event(0x53, 0, 2, nil)
        syntheticReverseKeyDown = false
    end
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
    state = tostring(state or "IDLE")
    local file = io.open(shared_state_file, "w")
    if not file then return end
    file:write(state .. "\n")
    file:write(tostring(math.floor(gasLevel or 0)) .. "\n")
    file:write(tostring(math.floor(brakeLevel or 0)) .. "\n")
    file:write(tostring(math.floor(lastSteerValue or 0)) .. "\n")
    file:write(string.format("%.3f\n", os.clock()))
    file:close()
    if state ~= lastLoggedSharedState then
        logEvent("STATE", tostring(lastLoggedSharedState or "nil") .. " -> " .. state)
        lastLoggedSharedState = state
    end
end

local function sharedFreezeActive()
    return _G.VR_TEST_FREEZE == true or fileExists(freeze_flag_file)
end

local function freezeRecoveryOwnsControls()
    return S.freezeTestLatched == true
        or S.frozenByAdmin == true
        or sharedFreezeActive()
end

local function consumeRotateFlag()
    local file = io.open(rotate_flag_file, "r")
    if not file then return nil end
    local mode = file:read("*l")
    local stamp = tonumber(file:read("*l") or "")
    file:close()
    os.remove(rotate_flag_file)
    if mode ~= "safe" and mode ~= "rotate" then return nil end
    if stamp and os.clock() - stamp > 3.0 then return nil end
    return mode
end

function clearRotateTrigger()
    os.remove(rotate_flag_file)
    _G.VR_ADMIN_ROTATED = false
end

local function sharedDialogMode()
    return readSharedFile(dialog_flag_file)
end

local safeFfi, safeK32 = nil, nil
local function safeReadDword(addr)
    if not addr or addr < 0x10000 or addr > 0x7FFFFFFF then return nil end
    if safeFfi == nil then
        local ok, ffi = pcall(require, "ffi")
        if not ok then safeFfi = false; return nil end
        pcall(ffi.cdef, "int IsBadReadPtr(const void* lp, unsigned int ucb);")
        local k32ok, k32 = pcall(ffi.load, "kernel32")
        if not k32ok then safeFfi = false; return nil end
        safeFfi, safeK32 = ffi, k32
    end
    if not safeFfi or not safeK32 then return nil end
    if safeK32.IsBadReadPtr(safeFfi.cast("void*", addr), 4) ~= 0 then return nil end
    return tonumber(safeFfi.cast("uint32_t*", addr)[0])
end

local function isSampDialogActive()
    if samp == 0 then return false end
    local dPtr = safeReadDword(samp + 0x21A0B8)
    if not dPtr or dPtr == 0 then return false end
    if dPtr < 0x01000000 or dPtr > 0x7FFFFFFF then return false end
    return safeReadDword(dPtr + 0x28) == 1
end

function hasPauseSource(now)
    now = now or os.clock()
    -- Bump recovery and R >> FWD are not pause sources: the playback thread
    -- must keep ticking so those recovery mini-states can finish cleanly.
    return S.manualPaused
        or S.dialogPaused
        or S.testArbotasPaused
        or now < S.dialogReleaseUntil
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
    setSyntheticReverseKey(false, true)
    pauseReleaseReason = reason or pauseReleaseReason or "SAFE"
    gasLevel = 0
    brakeLevel = 0
    lastSteerValue = 0
    setGameKeyState(0, 0)
    writeDriveControls(0, 0)
    _G.VR_gas = 0
    _G.VR_brake = 0
    _G.VR_steer = 0
    _G.VR_state = pauseReleaseReason
    _G.VR_playing = os.clock()
    writeSharedState(pauseReleaseReason)
end

local function pressRotateReaction()
    if freezeRecoveryOwnsControls() then
        releaseControls(pauseReleaseReason ~= "" and pauseReleaseReason or "FREEZE_WAIT")
        return
    end
    pauseReleaseReason = "ROTATE_REACT"
    gasLevel = 255
    brakeLevel = 0
    lastSteerValue = 0
    setSyntheticReverseKey(false, true)
    setGameKeyState(0, 0)
    writeDriveControls(255, 0)
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

local function resetForwardNoProgress()
    S.forwardNoProgressFrames = 0
    S.forwardNoProgressDist = 0.0
    S.forwardNoProgressIndex = 0
end

local function resetBumpState(clearCooldown)
    S.bumpActive = false
    S.bumpPhase = ""
    S.bumpReason = ""
    S.bumpUntil = 0.0
    S.bumpStartedAt = 0.0
    S.bumpStartX = 0.0
    S.bumpStartY = 0.0
    S.bumpMinDistance = 0.0
    S.bumpMaxDistance = 0.0
    S.bumpSteer = 0
    if clearCooldown then
        S.bumpCooldownUntil = 0.0
        S.bumpGraceUntil = 0.0
    end
    resetForwardNoProgress()
end

local function startFreezeRecovery(mode)
    local now = os.clock()
    if S.freezeTestLatched then
        releaseControls(pauseReleaseReason ~= "" and pauseReleaseReason or "FREEZE_WAIT")
        return true
    end
    local waitBeforeRefresh = math.random(
        math.floor((CONFIG.recovery.freezeWaitBeforeRefreshMinSeconds or 2.0) * 1000),
        math.floor((CONFIG.recovery.freezeWaitBeforeRefreshMaxSeconds or 3.0) * 1000)
    ) / 1000.0
    local resumeDelay = math.random(
        math.floor((CONFIG.recovery.freezeResumeDelayMinSeconds or 0.5) * 1000),
        math.floor((CONFIG.recovery.freezeResumeDelayMaxSeconds or 1.0) * 1000)
    ) / 1000.0
    setSyntheticReverseKey(false, true)
    resetBumpState(false)
    S.backToForwardUntil = 0.0
    S.freezeTestLatched = true
    S.freezeRecoveryMode = mode or "real"
    S.frozenByAdmin = true
    S.refreshSent = false
    S.freezeRefreshSentAt = 0.0
    S.freezeFightUntil = 0.0
    S.freezeRefreshAt = now + waitBeforeRefresh
    S.freezeReleaseUntil = 0.0
    S.freezeResumeDelay = resumeDelay
    releaseControls("FREEZE_WAIT")
    freezeTimer = 0
    suddenStopFrames = 0
    syncPausedState(now)
    logEvent("RECOVERY", string.format("freeze recovery wait %.2fs resume %.2fs mode=%s",
        waitBeforeRefresh, resumeDelay, tostring(S.freezeRecoveryMode)))
    return true
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
    S.freezeRecoveryMode = ""
    S.frozenByAdmin = false
    S.refreshSent = false
    S.freezeRefreshSentAt = 0.0
    S.freezeFightUntil = 0.0
    S.freezeReleaseUntil = 0.0
    S.freezeRefreshAt = 0.0
    S.freezeResumeDelay = 0.0
    S.freezeRecoveryGraceUntil = os.clock() + 2.1
    S.reversePlaybackGraceUntil = 0.0
    S.backToForwardUntil = 0.0
    resetBumpState(true)
    S.currentLateral = 0.0
    S.nudgeFrames = 0
    S.nudgeOffset = 0.0
    S.routeObstacleDist = math.huge
    S.routeAvoidDir = 0
    S.routeObstacleUrgency = 0.0
    S.routeObstacleTimer = 0
    S.obstacleHits = {}
    S.obstacleProbes = {}
    S.rejoinFrames = 0
    S.rejoinSteer = 0
    S.rejoinCooldownUntil = 0.0
    S.rejoinDisableUntil = os.clock() + 2.5
    resetObstacleBypass()
    S.avoidClusterCount = 0
    collisionCooldown = 0
    avoidSteerDir = 0
    S.avoidRouteDir = 0
    S.avoidSideHit = false
    gasLevel = 0
    brakeLevel = 0
    lastSteerValue = 0
    steerBuf = {0, 0}
    freezeTimer = 0
    suddenStopFrames = 0
    lastDriveSpeed = 0.0
    S.recentDriveSpeed = 0.0
    S.recentDriveUntil = 0.0
    lastX, lastY = cx, cy
    syncPausedState()
end

local function obstacleColor(kind, urgent, sideScan)
    if urgent then return 0xFFFF4444 end
    if kind == "car" then return sideScan and 0xFFFFCC55 or 0xFFFFAA33 end
    if kind == "solid" then return sideScan and 0xFFFFFF99 or 0xFFFFFF55 end
    if kind == "ped" then return 0xFFFF66FF end
    return sideScan and 0xFF66FFFF or 0xFF33DDFF
end

local function obstacleTag(kind)
    if kind == "car" then return "C" end
    if kind == "solid" then return "W" end
    if kind == "ped" then return "P" end
    if kind == "obj" then return "O" end
    return "?"
end

local function obstacleLabel(hit)
    if hit and hit.modelId then return "O" .. tostring(hit.modelId) end
    if not hit then return "?" end
    return obstacleTag(hit.kind)
end

local function clamp01(value)
    if value < 0.0 then return 0.0 end
    if value > 1.0 then return 1.0 end
    return value
end

function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function obstacleUrgency(hit)
    if not hit then return 0.0 end
    local worldDist = hit.worldDist or 999.0
    local lateral = hit.lateral or 99.0
    if hit.sideScan then
        local clearance = hit.clearance or lateral
        local near = clamp01((18.0 - worldDist) / 13.0)
        local scrape = clamp01((3.4 - clearance) / 3.4)
        return clamp01(near * (0.20 + scrape * 0.80))
    end

    local near = clamp01((42.0 - worldDist) / 36.0)
    local center = clamp01((2.8 - lateral) / 2.8)
    return clamp01(near * (0.25 + center * 0.75))
end

function computeObstacleClusterPlan()
    local bestDist = math.huge
    local weightedSide = 0.0
    local weightSum = 0.0
    local leftThreat = 0.0
    local rightThreat = 0.0
    local centerThreat = 0.0
    local count = 0

    for i = 1, math.min(#S.obstacleHits, 28) do
        local hit = S.obstacleHits[i]
        local modelOk = hit.kind == "car" or (hit.kind == "obj" and shouldAvoidObjectModel(hit.modelId))
        local d = hit.worldDist or 999.0
        local forward = hit.forward or d
        local lateral = hit.carLateral or 0.0
        local clearance = math.abs(lateral)
        if modelOk and d > 2.0 and d < 62.0 and forward > -1.0 and clearance < 5.4 then
            local corridor = clamp01((5.4 - clearance) / 5.4)
            local approach = clamp01((62.0 - d) / 56.0)
            local weight = (0.35 + corridor * 1.45) * (0.35 + approach)
            if clearance < 2.8 then weight = weight + 0.65 end
            if clearance < 1.4 then centerThreat = centerThreat + weight end
            if lateral >= 0.0 then
                leftThreat = leftThreat + weight
            else
                rightThreat = rightThreat + weight
            end
            weightedSide = weightedSide + lateral * weight
            weightSum = weightSum + weight
            count = count + 1
            if d < bestDist then bestDist = d end
        end
    end

    if count == 0 then return math.huge, 0, 0.0, 0 end

    local dir = 0
    if math.abs(weightedSide) < 0.35 or centerThreat > 0.75 then
        dir = leftThreat <= rightThreat and 1 or -1
    elseif weightedSide > 0.0 then
        dir = -1
    else
        dir = 1
    end

    local urgency = clamp01((62.0 - bestDist) / 56.0 + math.min(0.45, weightSum * 0.055))
    if bestDist < 36.0 then urgency = math.max(urgency, 0.38) end
    if bestDist < 18.0 then urgency = math.max(urgency, 0.62) end
    return bestDist, dir, urgency, count
end

function updateObstacleBypass(now)
    local seen = S.routeObstacleDist < 62.0
        and S.routeAvoidDir ~= 0
        and (S.routeObstacleUrgency or 0.0) > 0.04

    if seen then
        local dir = S.routeAvoidDir > 0 and 1 or -1
        if not S.bypassActive or now > (S.bypassHoldUntil or 0.0) + 0.8 or S.bypassDir == 0 then
            S.bypassDir = dir
            S.bypassOffset = math.max(math.abs(S.currentLateral or 0.0), 2.15)
        elseif dir ~= S.bypassDir then
            -- A cone line can produce alternating side hits; keep the committed
            -- lane choice instead of zig-zagging through the divider.
            dir = S.bypassDir
        end

        S.bypassActive = true
        S.bypassReturning = false
        S.bypassLastSeen = now

        local urgency = clamp01(S.routeObstacleUrgency or 0.0)
        local distFactor = clamp01((58.0 - S.routeObstacleDist) / 52.0)
        local countFactor = clamp01(((S.avoidClusterCount or 0) - 1) / 7.0)
        local wantedOffset = 2.30 + urgency * 0.35 + distFactor * 0.25 + countFactor * 0.35
        if S.routeObstacleDist < 28.0 then wantedOffset = math.max(wantedOffset, 2.65) end
        if S.routeObstacleDist < 14.0 then wantedOffset = math.max(wantedOffset, 2.90) end
        wantedOffset = clamp(wantedOffset, 2.20, 3.25)

        S.bypassOffset = S.bypassOffset + (wantedOffset - S.bypassOffset) * 0.16
        S.bypassOffset = clamp(S.bypassOffset, 0.0, 3.25)
        local hold = math.max(2.6, math.min(5.4, 1.9 + S.routeObstacleDist * 0.05 + (S.avoidClusterCount or 0) * 0.22))
        S.bypassHoldUntil = math.max(S.bypassHoldUntil or 0.0, now + hold)
        S.avoidHoldUntil = S.bypassHoldUntil
        S.avoidLateralTarget = S.bypassDir * S.bypassOffset
        return true
    end

    if S.bypassActive then
        if now <= (S.bypassHoldUntil or 0.0) then
            S.avoidLateralTarget = (S.bypassDir or 0) * (S.bypassOffset or 0.0)
            return true
        end

        S.bypassReturning = true
        S.avoidLateralTarget = (S.avoidLateralTarget or 0.0) * 0.985
        S.bypassOffset = math.abs(S.avoidLateralTarget)
        if math.abs(S.avoidLateralTarget) < 0.08 and math.abs(S.currentLateral or 0.0) < 0.18 then
            resetObstacleBypass()
            return false
        end
        return true
    end

    return false
end

local function draw_line(posX, posY, carX, carY, carZ, color)
    color = color or COLOR_ROUTE_FORWARD
    local chPosX, chPosY, chPosZ = getCharCoordinates(PLAYER_PED)
    if isPointOnScreen(posX, posY, chPosZ, 0.0) then
        local wPosX, wPosY = convert3DCoordsToScreen(posX, posY, chPosZ)
        local wPosX1, wPosY1 = convert3DCoordsToScreen(chPosX, chPosY, chPosZ)
        if color == COLOR_ROUTE_BACK then
            renderDrawLine(wPosX1, wPosY1, wPosX, wPosY, 4, COLOR_ROUTE_BACK_OUTLINE)
        end
        renderDrawLine(wPosX1, wPosY1, wPosX, wPosY, 2, color)
        renderDrawPolygon(wPosX, wPosY, 10, 10, 14, 0.0, 0xFF000000)
        renderDrawPolygon(wPosX1, wPosY1, 10, 10, 14, 0.0, 0xFF000000)
    end
    if not S.showObstacleDots or (S.obstacleDebugMode or 0) <= 0 then return end
    if not S.obstacleFont then
        S.obstacleFont = renderCreateFont("Arial", 9, 1)
    end

    carX = carX or chPosX
    carY = carY or chPosY
    carZ = carZ or chPosZ

    local debugMode = S.obstacleDebugMode or 1
    for i = 1, math.min(#S.obstacleProbes, debugMode >= 2 and 140 or 60) do
        local probe = S.obstacleProbes[i]
        local pz = probe.z or carZ
        if getDistanceBetweenCoords2d(carX, carY, probe.x, probe.y) < 160 and isPointOnScreen(probe.x, probe.y, pz, 0.0) then
            local psx, psy = convert3DCoordsToScreen(probe.x, probe.y, pz)
            if debugMode >= 2 and probe.fromX and isPointOnScreen(probe.fromX, probe.fromY, probe.fromZ or pz, 0.0) then
                local fsx, fsy = convert3DCoordsToScreen(probe.fromX, probe.fromY, probe.fromZ or pz)
                local probeColor = probe.hit
                    and obstacleColor(probe.kind or "obj", false, probe.sideScan == true)
                    or (probe.sideScan and 0x8855DDFF or 0x8855FF55)
                renderDrawLine(fsx, fsy, psx, psy, probe.hit and 1.2 or 0.8, probeColor)
            end
            local dotColor = probe.hit
                and obstacleColor(probe.kind or "obj", false, probe.sideScan == true)
                or (probe.sideScan and 0xAA55DDFF or 0xAA55FF55)
            renderDrawPolygon(psx, psy, probe.hit and 5 or 3, probe.hit and 5 or 3, 10, 0.0, dotColor)
        end
    end

    if #S.obstacleHits == 0 then return end

    local best = S.obstacleHits[1]
    local csx, csy = convert3DCoordsToScreen(chPosX, chPosY, chPosZ)
    for i = 1, math.min(#S.obstacleHits, 6) do
        local hit = S.obstacleHits[i]
        if getDistanceBetweenCoords2d(carX, carY, hit.x, hit.y) < 140 and isPointOnScreen(hit.x, hit.y, hit.z or carZ, 0.0) then
            local sx, sy = convert3DCoordsToScreen(hit.x, hit.y, hit.z or chPosZ)
            renderDrawLine(csx, csy, sx, sy, i == 1 and 1.8 or 1.0, i == 1 and 0xFFFF66FF or 0xAAFF66FF)
            if i == 1 and S.obstacleFont then
                renderFontDrawText(S.obstacleFont, "OBS", sx + 6, sy + 8, 0xFFFFAAFF)
            end
        end
    end

    for i = 1, math.min(#S.obstacleHits, 18) do
        local hit = S.obstacleHits[i]
        local hz = hit.z or carZ
        if getDistanceBetweenCoords2d(carX, carY, hit.x, hit.y) < 140 and isPointOnScreen(hit.x, hit.y, hz, 0.0) then
            local sx, sy = convert3DCoordsToScreen(hit.x, hit.y, hz)
            local urgent = hit.worldDist < 18 or hit.lateral < 2.2
            local color = obstacleColor(hit.kind, urgent, hit.sideScan == true)
            local size = urgent and 9 or 6
            renderDrawPolygon(sx, sy, size, size, 14, 0.0, color)
            local sideText = hit.cross > 0 and "L" or "R"
            local tag = hit.lowBlockScan and (hit.modelId and ("O" .. tostring(hit.modelId)) or "B") or obstacleLabel(hit)
            renderFontDrawText(S.obstacleFont, string.format("%s %d %s", tag, math.floor(hit.worldDist), sideText), sx + 8, sy - 6, color)
        end
    end

    if debugMode >= 2 and best then
        local bx, by = 230, 420
        local sideText = best.cross > 0 and "LEFT" or "RIGHT"
        local sourceText = best.sideScan and "SIDE" or "PATH"
        local tag = best.lowBlockScan and (best.modelId and ("O" .. tostring(best.modelId)) or "B") or obstacleLabel(best)
        local latText = best.sideScan and (best.clearance or best.lateral or 0.0) or (best.lateral or 0.0)
        local latName = best.sideScan and "clr" or "lat"
        local showAvoid = math.abs(S.avoidLateralTarget or 0.0) > 0.05
        renderDrawBox(bx, by, 190, showAvoid and 52 or 36, 0xAA000000)
        renderFontDrawText(S.obstacleFont, string.format("OBS %s %dm %s", tag, math.floor(best.worldDist), sideText), bx + 6, by + 4, 0xFFFFFFFF)
        renderFontDrawText(S.obstacleFont, string.format("%s u%.2f %s %.1f n%d", sourceText, best.urgency or obstacleUrgency(best), latName, latText, S.avoidClusterCount or 0), bx + 6, by + 18, 0xFFCCCCCC)
        if showAvoid then
            local hold = math.max(0.0, (S.avoidHoldUntil or 0.0) - os.clock())
            local mode = S.bypassActive and "BYPASS" or "AVOID"
            renderFontDrawText(S.obstacleFont, string.format("%s %.1fm hold %.1fs", mode, S.avoidLateralTarget or 0.0, hold), bx + 6, by + 32, 0xFF66FF66)
        end
    end
end

local function showMsg(text)
    printStringNow(text, 2000)
end

Debug.showMessage = showMsg

local function applySteerNoise()
    if steerNoiseDuration > 0 then
        steerNoiseDuration = steerNoiseDuration - 1
        setGameKeyState(0, 0)
    elseif steerNoiseCooldown > 0 then
        steerNoiseCooldown = steerNoiseCooldown - 1
    elseif math.random(100) <= 10 then
        steerNoiseValue = 0
        steerNoiseDuration = math.random(1, 3)
        steerNoiseCooldown = math.random(8, 30)
        setGameKeyState(0, 0)
    end
end

local function getObstacleAhead(car, targetX, targetY)
    local bestHit = nil
    local bestScore = -999.0
    for i = 1, math.min(#S.obstacleHits, 32) do
        local hit = S.obstacleHits[i]
        local sideScan = hit.sideScan == true
        local objectLike = hit.nearObjectScan == true or hit.kind == "obj" or hit.lowBlockScan == true
        local maxDist = sideScan and 6.5 or 8.0
        local maxLateral = sideScan and 2.55 or 2.6
        local lateral = sideScan and (hit.clearance or hit.lateral or 99.0) or (hit.lateral or 99.0)
        local forward = hit.forward or hit.worldDist or 0.0
        local urgency = hit.urgency or obstacleUrgency(hit)
        local minUrgency = sideScan and 0.46 or 0.42
        if objectLike then
            maxDist = sideScan and 12.0 or 15.0
            maxLateral = sideScan and 3.0 or 3.15
            minUrgency = sideScan and 0.18 or 0.16
        end
        if urgency >= minUrgency
            and hit.worldDist < maxDist
            and lateral < maxLateral
            and forward > -0.75
            and (not hit.zDelta or hit.zDelta < 2.2) then
            local score = urgency * 2.4 - hit.worldDist * 0.08 - lateral * 0.18
            if hit.lowBlockScan then score = score + 0.12 end
            if hit.avoidDir and hit.avoidDir ~= 0 then score = score + 0.08 end
            if score > bestScore then
                bestScore = score
                bestHit = hit
            end
        end
    end
    if bestHit then
        return bestHit.x, bestHit.y, bestHit.z or 0, bestHit.avoidDir or 0, bestHit.worldDist, bestHit.sideScan == true, bestHit.urgency or obstacleUrgency(bestHit)
    end

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
        return ox, oy, carZ, 0, getDistanceBetweenCoords2d(carX, carY, ox, oy), false, 0.65
    end
    local ok2, nearObj = pcall(getClosestObject, checkX, checkY, carZ, 4.0, false, false)
    if ok2 and nearObj and nearObj ~= 0 then
        local avoidable = isAvoidableObject(nearObj)
        if not avoidable then return nil end
        local ok3, ox, oy = readObjectCoordinates(nearObj)
        if ok3 and ox then return ox, oy, carZ, 0, getDistanceBetweenCoords2d(carX, carY, ox, oy), false, 0.60 end
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

function routeAvoidDirFromPoint(carX, carY, targetX, targetY, obsX, obsY)
    local dx = targetX - carX
    local dy = targetY - carY
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.1 then return 0 end
    local cross = dx * (obsY - carY) - dy * (obsX - carX)
    return cross > 0 and -1 or 1
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

local function getCarForwardAxes(car)
    local heading = math.rad(getCarHeading(car))
    local nx = math.sin(heading)
    local ny = math.cos(heading)
    local len = math.sqrt(nx * nx + ny * ny)
    if len < 0.1 then return 0.0, 1.0, -1.0, 0.0 end
    nx, ny = nx / len, ny / len
    return nx, ny, -ny, nx
end

function handleRouteRejoinRecovery(car, carX, carY, targetX, targetY, currentSpeed)
    local now = os.clock()
    if now < (S.rejoinDisableUntil or 0.0) or now < (S.rejoinCooldownUntil or 0.0) then
        return false
    end
    if play_index <= 20 or #current_route == 0 or currentSpeed > 25.0 then
        return false
    end

    local fx, fy, lx, ly = getCarForwardAxes(car)
    local relX = targetX - carX
    local relY = targetY - carY
    local forward = relX * fx + relY * fy
    local lateral = relX * lx + relY * ly
    local dist = math.sqrt(relX * relX + relY * relY)

    if forward > -1.5 or dist > 22.0 or math.abs(lateral) < 2.0 then
        return false
    end

    local bestIdx, bestScore = nil, math.huge
    for i = play_index + 1, math.min(play_index + 120, #current_route) do
        local p = current_route[i]
        local px = p.x - carX
        local py = p.y - carY
        local pf = px * fx + py * fy
        local pl = math.abs(px * lx + py * ly)
        if pf > 2.5 and pf < 45.0 and pl < 14.0 then
            local score = pl * 1.45 + math.abs(pf - 14.0) * 0.35 + (i - play_index) * 0.02
            if score < bestScore then
                bestScore = score
                bestIdx = i
            end
        end
    end

    if bestIdx then
        play_index = bestIdx
        S.rejoinFrames = 0
        S.rejoinSteer = 0
        S.rejoinCooldownUntil = now + 1.5
        S.currentLateral = 0.0
        resetObstacleBypass()
        S.avoidClusterCount = 0
        _G.VR_state = "REJOIN_SKIP"
        _G.VR_playing = now
        writeSharedState("REJOIN_SKIP")
    end
    return false
end

local function pointSegmentProjection(ax, ay, bx, by, px, py)
    local sx = bx - ax
    local sy = by - ay
    local len2 = sx * sx + sy * sy
    if len2 < 0.0001 then
        return 0.0, getDistanceBetweenCoords2d(px, py, ax, ay)
    end
    local t = ((px - ax) * sx + (py - ay) * sy) / len2
    local nearestX = ax + sx * clamp(t, 0.0, 1.0)
    local nearestY = ay + sy * clamp(t, 0.0, 1.0)
    return t, getDistanceBetweenCoords2d(px, py, nearestX, nearestY)
end

local function syncReversePlaybackIndex(route, idx, carX, carY)
    if type(route) ~= "table" or #route == 0 then return idx end
    idx = math.max(1, math.min(tonumber(idx) or 1, #route))
    if routeDriveModeAt(route, idx) ~= DRIVE_BACK then return idx end

    local bestIdx = idx
    local bestDist = math.huge
    local last = idx
    while last < #route and routeDriveModeAt(route, last + 1) == DRIVE_BACK do
        last = last + 1
    end

    for i = idx, last do
        local p = route[i]
        local d = p and getDistanceBetweenCoords2d(carX, carY, p.x, p.y) or math.huge
        if d < bestDist then
            bestDist = d
            bestIdx = i
        end
    end

    if bestIdx > idx and bestDist < 9.0 then
        return bestIdx
    end
    return idx
end

local function advanceReversePlaybackIndex(route, idx, carX, carY, allowFinish)
    if type(route) ~= "table" or #route == 0 then return idx end
    idx = math.max(1, math.min(tonumber(idx) or 1, #route))
    if routeDriveModeAt(route, idx) ~= DRIVE_BACK then return idx end

    if allowFinish and idx == #route then
        local finalPoint = route[idx]
        if finalPoint and getDistanceBetweenCoords2d(carX, carY, finalPoint.x, finalPoint.y) <= 2.8 then
            return idx + 1
        end
    end

    local advanced = 0
    while idx < #route and advanced < 4 do
        local point = route[idx]
        local nextPoint = route[idx + 1]
        if not point or not nextPoint then break end

        local dist = getDistanceBetweenCoords2d(carX, carY, point.x, point.y)
        local nextDist = getDistanceBetweenCoords2d(carX, carY, nextPoint.x, nextPoint.y)
        local nextIsBack = routeDriveModeAt(route, idx + 1) == DRIVE_BACK

        if dist <= 2.8 then
            idx = idx + 1
            advanced = advanced + 1
        elseif nextIsBack then
            local t, segmentDist = pointSegmentProjection(point.x, point.y, nextPoint.x, nextPoint.y, carX, carY)
            if (t > 0.55 and segmentDist < 7.0) or (dist > 4.0 and nextDist + 0.45 < dist) then
                idx = idx + 1
                advanced = advanced + 1
            else
                break
            end
        elseif dist > 5.0 and nextDist + 0.45 < dist then
            -- Last BACK point before FWD: do not chase a missed boundary point forever.
            idx = idx + 1
            advanced = advanced + 1
        else
            break
        end
    end

    return idx
end

local function getReversePathSegment(route, idx)
    local point = route[idx]
    if not point then return nil, nil end
    local nextPoint = route[idx + 1]
    if nextPoint and routeDriveModeAt(route, idx + 1) == DRIVE_BACK then
        return point, nextPoint
    end

    local prevPoint = route[idx - 1]
    if prevPoint and routeDriveModeAt(route, idx - 1) == DRIVE_BACK then
        return prevPoint, point
    end

    return point, point
end

local function applyReverseSteering(car, carX, carY, route, idx)
    local a, b = getReversePathSegment(route, idx)
    if not a or not b then
        lastSteerValue = 0
        setGameKeyState(0, 0)
        return
    end

    local sx = (b.x or a.x) - (a.x or carX)
    local sy = (b.y or a.y) - (a.y or carY)
    local segLen = math.sqrt(sx * sx + sy * sy)
    if segLen < 0.08 then
        lastSteerValue = 0
        setGameKeyState(0, 0)
        return
    end

    sx, sy = sx / segLen, sy / segLen
    local leftX, leftY = -sy, sx
    local lateral = ((carX - a.x) * leftX) + ((carY - a.y) * leftY)
    local absLateral = math.abs(lateral)
    local steer = 0

    if absLateral > 1.05 then
        local strength = math.min(82, math.max(18, math.floor((absLateral - 0.65) * 34)))
        steer = lateral > 0 and -strength or strength
    end

    lastSteerValue = steer
    setGameKeyState(0, steer)
end

local function applyReverseAssist(car, carX, carY, targetX, targetY, currentSpeed, targetSpeed)
    local dx = targetX - carX
    local dy = targetY - carY
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 0.65 then return end

    targetSpeed = math.max(8.0, math.min(targetSpeed or 12.0, 32.0))
    if currentSpeed > targetSpeed * 0.92 then return end

    -- Keep this as a tiny unstuck nudge only. A strong target-vector velocity
    -- shove makes the car slide sideways and miss the recorded reverse path.
    if currentSpeed > 0.6 or dist < 3.5 then return end
    local fx, fy = getCarForwardAxes(car)
    local backwardDot = dx * (-fx) + dy * (-fy)
    if backwardDot <= 0.4 then return end
    local desiredVelocity = 0.08
    pcall(setCarVelocity, car, -fx * desiredVelocity, -fy * desiredVelocity, 0.0)
end

local function readControlByte(address)
    local ok, value = pcall(readMemory, address, 1, false)
    if not ok then return 0 end
    return tonumber(value) or 0
end

local function isReverseRecordingInputActive(car)
    local sDown = isPhysicalKeyDown(0x53)
    local wDown = isPhysicalKeyDown(0x57)
    local brakeInput = readControlByte(CONFIG.controls.brakeAddress)
    local ok, speed = pcall(getCarSpeed, car)
    return ((sDown or brakeInput > 150) and not wDown)
        or (ok and speed and speed < -0.35)
end

local function getRecordedForwardMotion(car, heading, prev, x, y)
    local velocityNames = {
        "getCarVelocity",
        "getCarSpeedVector",
        "getVehicleVelocity",
        "getVehicleSpeedVector",
        "getCarMoveSpeed",
    }
    local fx, fy = getRecordingForwardAxes(heading)

    for _, name in ipairs(velocityNames) do
        local fn = _G and _G[name] or nil
        if type(fn) == "function" then
            local ok, a, b, c = pcall(fn, car)
            if ok then
                local vx, vy = nil, nil
                if type(a) == "boolean" then
                    vx, vy = tonumber(b), tonumber(c)
                elseif type(a) == "table" then
                    vx, vy = tonumber(a.x or a[1]), tonumber(a.y or a[2])
                else
                    vx, vy = tonumber(a), tonumber(b)
                end
                if vx and vy then
                    return vx * fx + vy * fy
                end
            end
        end
    end

    if prev then
        return ((x or 0.0) - (prev.x or 0.0)) * fx + ((y or 0.0) - (prev.y or 0.0)) * fy
    end
    return nil
end

local function scanRouteAhead(route, idx, car)
    local n = #route
    local carX, carY, carZ = getCarCoordinates(car)
    local carForwardX, carForwardY, carLeftX, carLeftY = getCarForwardAxes(car)
    local scanPoint = route[math.min(idx + LOOKAHEAD, n)] or route[idx]
    if scanPoint then
        local rdx = scanPoint.x - carX
        local rdy = scanPoint.y - carY
        local rLen = math.sqrt(rdx * rdx + rdy * rdy)
        if rLen > 2.0 then
            carForwardX, carForwardY = rdx / rLen, rdy / rLen
            carLeftX, carLeftY = -carForwardY, carForwardX
        end
    end
    S.obstacleHits = {}
    S.obstacleProbes = {}
    local best = math.huge
    local bestDir = 0
    local bestThreat = math.huge
    local found = {}
    local originZ = carZ + 0.75

    local function lateralFromSegment(ax, ay, bx, by, px, py)
        local rx = bx - ax
        local ry = by - ay
        local rLen = math.sqrt(rx*rx + ry*ry)
        if rLen < 0.1 then return 99, 0 end
        local cross = rx * (py - ay) - ry * (px - ax)
        return math.abs(cross) / rLen, cross
    end

    local function registerHit(kind, ox, oy, oz, segX, segY, prevX, prevY, routeIdx, avoidDirHint, modelId)
        modelId = tonumber(modelId)
        if kind == "obj" and not shouldAvoidObjectModel(modelId) then return end
        if kind ~= "obj" and kind ~= "car" then return end
        local lateralDist, cross = lateralFromSegment(prevX, prevY, segX, segY, ox, oy)
        local worldDist = getDistanceBetweenCoords2d(carX, carY, ox, oy)
        local relX = ox - carX
        local relY = oy - carY
        local forwardDist = relX * carForwardX + relY * carForwardY
        local carLateral = relX * carLeftX + relY * carLeftY
        local clearance = math.abs(carLateral)
        local key = string.format("%s:%d:%d:%d", kind, math.floor(ox * 2), math.floor(oy * 2), math.floor((oz or carZ) * 2))
        local sideScan = math.abs(avoidDirHint or 0) > 1
        local lowBlockScan = math.abs(avoidDirHint or 0) >= 3
        local maxLateral = sideScan and 4.4 or 3.2
        local minWorldDist = sideScan and 1.0 or 3.0
        if sideScan and forwardDist < -1.5 then return end
        local sidePenalty = sideScan and math.max(0.0, clearance - 1.1) or lateralDist
        local threat = worldDist + sidePenalty * (sideScan and 14 or 16) + math.max(0, routeIdx - idx) * 0.30 + (sideScan and 0.4 or 0.0)
        if lowBlockScan then
            threat = threat + 1.8
        end
        if sideScan and worldDist < 8.0 and clearance < 2.8 then
            threat = threat - 2.8
        end
        if kind == "solid" then threat = threat - 2.0 end
        local existing = found[key]

        if worldDist > minWorldDist and lateralDist < maxLateral and (not sideScan or clearance < 5.2) and (not existing or threat < existing.threat) then
            found[key] = {
                kind = kind,
                modelId = modelId,
                x = ox, y = oy, z = oz or carZ,
                worldDist = worldDist,
                lateral = lateralDist,
                clearance = clearance,
                forward = forwardDist,
                carLateral = carLateral,
                cross = cross,
                threat = threat,
                urgency = 0.0,
                routeIdx = routeIdx,
                avoidDir = avoidDirHint or 0,
                zDelta = 0.0,
                sideScan = sideScan,
                lowBlockScan = lowBlockScan,
            }
        end
    end

    local function classifyEntityType(entityType)
        if entityType == 2 then return "car" end
        if entityType == 3 then return "ped" end
        if entityType == 1 then return "obj" end
        return "solid"
    end

    local function samplePoint(fromX, fromY, fromZ, sampleX, sampleY, sampleZ, routeIdx, avoidDirHint)
        local probeFromZ = fromZ or originZ
        local probeToZ = sampleZ or probeFromZ
        local sideScan = math.abs(avoidDirHint or 0) > 1
        local lowBlockScan = math.abs(avoidDirHint or 0) >= 3
        if #S.obstacleProbes < 280 then
            table.insert(S.obstacleProbes, {
                x = sampleX, y = sampleY, z = probeToZ, hit = false,
                fromX = fromX, fromY = fromY, fromZ = probeFromZ,
                sideScan = sideScan,
                lowBlockScan = lowBlockScan,
                laneHint = avoidDirHint or 0,
            })
        end

        local ok, result, colPoint = pcall(processLineOfSight,
            fromX, fromY, probeFromZ,
            sampleX, sampleY, probeToZ,
            true, true, false, true, true, false, false, false)
        if ok and result and colPoint and colPoint.pos then
            local kind = classifyEntityType(colPoint.entityType)
            local modelId = collisionObjectModelId(colPoint)
            if shouldAvoidObjectModel(modelId) then
                kind = "obj"
            elseif kind == "obj" or kind == "solid" or kind == "ped" then
                return
            end
            local hx, hy, hz = colPoint.pos[1], colPoint.pos[2], colPoint.pos[3]
            local nz = (colPoint.normal and colPoint.normal[3]) or 0.0
            local expectedZ = probeToZ
            local hitWorldDist = getDistanceBetweenCoords2d(carX, carY, hx, hy)
            local hitZ = hz or expectedZ
            local heightAboveCar = hitZ - carZ
            if kind == "car" and hitWorldDist < 2.6 then
                return
            end
            if lowBlockScan then
                if heightAboveCar < 0.20 or heightAboveCar > 1.05 then
                    return
                end
                if kind == "solid" and nz > 0.78 and math.abs(hitZ - expectedZ) < 0.55 then
                    return
                end
            elseif kind == "solid" and nz > 0.62 and math.abs(hitZ - expectedZ) < 1.45 then
                return
            elseif kind ~= "car" and hitZ < carZ + 0.15 then
                return
            end
            if #S.obstacleProbes > 0 then
                local probe = S.obstacleProbes[#S.obstacleProbes]
                probe.x, probe.y, probe.z, probe.hit, probe.kind = hx, hy, hitZ, true, kind
                probe.modelId = modelId
            end
            registerHit(kind, hx, hy, hitZ, sampleX, sampleY, fromX, fromY, routeIdx, avoidDirHint, modelId)
            local key = string.format("%s:%d:%d:%d", kind, math.floor(hx * 2), math.floor(hy * 2), math.floor(hitZ * 2))
            if found[key] then
                found[key].zDelta = math.abs((hz or probeToZ) - expectedZ)
                found[key].urgency = obstacleUrgency(found[key])
            end
        end
    end

    local function sampleNearbyObject(centerX, centerY, centerZ, routeIdx, avoidDirHint, radius)
        local sideScan = math.abs(avoidDirHint or 0) > 1
        local ok, obj = pcall(getClosestObject, centerX, centerY, centerZ, radius or 1.85, false, false)
        if not ok or not obj or obj == 0 then return end
        local avoidable, modelId = isAvoidableObject(obj)
        if not avoidable then return end

        local ok2, ox, oy, oz = readObjectCoordinates(obj)
        if not ok2 or not ox then return end

        local objZ = oz or centerZ
        if objZ < carZ - 1.2 or objZ > carZ + 2.0 then return end

        local markerZ = objZ + 0.55
        if #S.obstacleProbes < 280 then
            table.insert(S.obstacleProbes, {
                x = ox, y = oy, z = markerZ, hit = true, kind = "obj", modelId = modelId,
                fromX = centerX, fromY = centerY, fromZ = centerZ,
                sideScan = sideScan,
                laneHint = avoidDirHint or 0,
            })
        end

        local ax = centerX - carForwardX
        local ay = centerY - carForwardY
        local bx = centerX + carForwardX
        local by = centerY + carForwardY
        registerHit("obj", ox, oy, markerZ, bx, by, ax, ay, routeIdx, avoidDirHint, modelId)

        local key = string.format("%s:%d:%d:%d", "obj", math.floor(ox * 2), math.floor(oy * 2), math.floor(markerZ * 2))
        if found[key] then
            found[key].zDelta = math.abs(objZ - centerZ)
            found[key].urgency = obstacleUrgency(found[key])
            found[key].nearObjectScan = true
            found[key].threat = found[key].threat - 1.2
        end
    end

    local function registerStreamedObject(ox, oy, oz, modelId)
        if not shouldAvoidObjectModel(modelId) then return end
        local objZ = oz or carZ
        if objZ < carZ - 1.2 or objZ > carZ + 2.2 then return end

        local relX = ox - carX
        local relY = oy - carY
        local forward = relX * carForwardX + relY * carForwardY
        local lateral = relX * carLeftX + relY * carLeftY
        local clearance = math.abs(lateral)
        if forward < 1.5 or forward > 55.0 or clearance > 5.2 then return end

        local hint = 0
        if lateral > 0.85 then
            hint = -2
        elseif lateral < -0.85 then
            hint = 2
        end

        local markerZ = objZ + 0.55
        local ax = ox - carForwardX
        local ay = oy - carForwardY
        local bx = ox + carForwardX
        local by = oy + carForwardY
        registerHit("obj", ox, oy, markerZ, bx, by, ax, ay, idx + forward * 0.25, hint, modelId)

        local key = string.format("%s:%d:%d:%d", "obj", math.floor(ox * 2), math.floor(oy * 2), math.floor(markerZ * 2))
        if found[key] then
            found[key].zDelta = math.abs(objZ - carZ)
            found[key].nearObjectScan = true
            found[key].streamedObjectScan = true
            found[key].urgency = obstacleUrgency(found[key])
            found[key].threat = found[key].threat - 2.4
        end

        if #S.obstacleProbes < 280 then
            table.insert(S.obstacleProbes, {
                x = ox, y = oy, z = markerZ, hit = true, kind = "obj", modelId = modelId,
                fromX = carX, fromY = carY, fromZ = carZ + 0.65,
                sideScan = hint ~= 0,
                laneHint = hint,
            })
        end
    end

    local function scanStreamedObjects()
        local ok, objects = pcall(getAllObjects)
        if not ok or type(objects) ~= "table" then return end
        local scanned = 0
        for _, obj in pairs(objects) do
            if obj and obj ~= 0 then
                local avoidable, modelId = isAvoidableObject(obj)
                if avoidable then
                    local ok2, ox, oy, oz = readObjectCoordinates(obj)
                    if ok2 and ox then
                        registerStreamedObject(ox, oy, oz, modelId)
                    end
                    scanned = scanned + 1
                    if scanned >= 220 then return end
                end
            end
        end
    end

    do
        local frontIdx = math.min(idx + LOOKAHEAD, n)
        local frontPoint = route[frontIdx] or route[idx]
        if frontPoint then
            local fx = carForwardX
            local fy = carForwardY
            local fLen = math.sqrt(fx * fx + fy * fy)
            if fLen > 0.1 then
                local nx = fx / fLen
                local ny = fy / fLen
                local lx = carLeftX
                local ly = carLeftY
                local frontOffset = 1.15
                local shoulderOffset = 2.35
                local outerOffset = 3.55
                local frontZ = (frontPoint.z or carZ) + 0.65
                local carSpeed = getCarSpeed(car)
                local forwardReach = math.max(48.0, math.min(72.0, 36.0 + carSpeed * 0.22))
                local coneOffsets = {-2.4, -1.8, -1.2, -0.6, 0.0, 0.6, 1.2, 1.8, 2.4}
                for dist = 6, forwardReach, 4 do
                    local fromDist = math.max(0.0, dist - 4.0)
                    local distAlpha = dist / forwardReach
                    local fromAlpha = fromDist / forwardReach
                    local fromCX = carX + nx * fromDist
                    local fromCY = carY + ny * fromDist
                    local fromCZ = originZ + (frontZ - originZ) * fromAlpha
                    local toCX = carX + nx * dist
                    local toCY = carY + ny * dist
                    local toCZ = originZ + (frontZ - originZ) * distAlpha
                    samplePoint(fromCX, fromCY, fromCZ, toCX, toCY, toCZ, idx + dist * 0.25, 0)
                    samplePoint(fromCX + lx * frontOffset, fromCY + ly * frontOffset, fromCZ, toCX + lx * frontOffset, toCY + ly * frontOffset, toCZ, idx + dist * 0.25, -1)
                    samplePoint(fromCX - lx * frontOffset, fromCY - ly * frontOffset, fromCZ, toCX - lx * frontOffset, toCY - ly * frontOffset, toCZ, idx + dist * 0.25, 1)
                    if dist >= 10 then
                        samplePoint(fromCX + lx * shoulderOffset, fromCY + ly * shoulderOffset, fromCZ, toCX + lx * shoulderOffset, toCY + ly * shoulderOffset, toCZ, idx + dist * 0.25, -2)
                        samplePoint(fromCX - lx * shoulderOffset, fromCY - ly * shoulderOffset, fromCZ, toCX - lx * shoulderOffset, toCY - ly * shoulderOffset, toCZ, idx + dist * 0.25, 2)
                    end
                    if dist >= 18 then
                        samplePoint(fromCX + lx * outerOffset, fromCY + ly * outerOffset, fromCZ, toCX + lx * outerOffset, toCY + ly * outerOffset, toCZ, idx + dist * 0.25, -2)
                        samplePoint(fromCX - lx * outerOffset, fromCY - ly * outerOffset, fromCZ, toCX - lx * outerOffset, toCY - ly * outerOffset, toCZ, idx + dist * 0.25, 2)
                    end

                    if dist <= 48 then
                        local objZ = carZ + 0.65
                        sampleNearbyObject(toCX, toCY, objZ, idx + dist * 0.25, 0, 1.85)
                        sampleNearbyObject(toCX + lx * frontOffset, toCY + ly * frontOffset, objZ, idx + dist * 0.25, -1, 1.65)
                        sampleNearbyObject(toCX - lx * frontOffset, toCY - ly * frontOffset, objZ, idx + dist * 0.25, 1, 1.65)
                        if dist >= 10 then
                            sampleNearbyObject(toCX + lx * shoulderOffset, toCY + ly * shoulderOffset, objZ, idx + dist * 0.25, -2, 1.45)
                            sampleNearbyObject(toCX - lx * shoulderOffset, toCY - ly * shoulderOffset, objZ, idx + dist * 0.25, 2, 1.45)
                        end
                    end
                end

                for dist = 3.0, math.min(forwardReach, 34.0), 2.0 do
                    local fromDist = math.max(0.0, dist - 2.0)
                    for _, off in ipairs(coneOffsets) do
                        local hint = 0
                        if off > 0.75 then
                            hint = -3
                        elseif off < -0.75 then
                            hint = 3
                        end
                        local fromX = carX + nx * fromDist + lx * off
                        local fromY = carY + ny * fromDist + ly * off
                        local toX = carX + nx * dist + lx * off
                        local toY = carY + ny * dist + ly * off
                        samplePoint(fromX, fromY, carZ + 0.82, toX, toY, carZ + 0.82, idx + dist * 0.25, hint)
                    end
                end
            end
        end
    end

    scanStreamedObjects()

    do
        local sideIdx = math.min(idx + 2, n)
        local sidePoint = route[sideIdx] or route[idx]
        if sidePoint then
            local fx = carForwardX
            local fy = carForwardY
            local fLen = math.sqrt(fx * fx + fy * fy)
            if fLen > 0.1 then
                local nx = fx / fLen
                local ny = fy / fLen
                local lx = carLeftX
                local ly = carLeftY
                local sideTopZ = (sidePoint.z or carZ) + 0.55
                for dist = 0, 8, 2 do
                    local alpha = dist / 8.0
                    local baseX = carX + nx * dist
                    local baseY = carY + ny * dist
                    local baseZ = originZ + (sideTopZ - originZ) * alpha
                    local sideReach = 2.1 + dist * 0.12
                    samplePoint(baseX, baseY, baseZ, baseX + lx * sideReach, baseY + ly * sideReach, baseZ, idx + dist * 0.2, -2)
                    samplePoint(baseX, baseY, baseZ, baseX - lx * sideReach, baseY - ly * sideReach, baseZ, idx + dist * 0.2, 2)
                    samplePoint(baseX + nx * 0.9, baseY + ny * 0.9, baseZ, baseX + nx * 1.8 + lx * (sideReach + 0.6), baseY + ny * 1.8 + ly * (sideReach + 0.6), baseZ, idx + dist * 0.2, -2)
                    samplePoint(baseX + nx * 0.9, baseY + ny * 0.9, baseZ, baseX + nx * 1.8 - lx * (sideReach + 0.6), baseY + ny * 1.8 - ly * (sideReach + 0.6), baseZ, idx + dist * 0.2, 2)
                end
            end
        end
    end

    do
        local nearIdx = math.min(idx + 1, n)
        local nearPoint = route[nearIdx] or route[idx]
        if nearPoint then
            local fx = carForwardX
            local fy = carForwardY
            local fLen = math.sqrt(fx * fx + fy * fy)
            if fLen > 0.1 then
                local nx = fx / fLen
                local ny = fy / fLen
                local lx = carLeftX
                local ly = carLeftY
                local cornerForward = 1.6
                local cornerSide = 1.25
                local cornerZ = originZ + 0.05

                samplePoint(
                    carX + nx * cornerForward + lx * cornerSide,
                    carY + ny * cornerForward + ly * cornerSide,
                    cornerZ,
                    carX + nx * 2.8 + lx * 2.9,
                    carY + ny * 2.8 + ly * 2.9,
                    cornerZ,
                    idx + 0.2,
                    -2
                )
                samplePoint(
                    carX + nx * cornerForward - lx * cornerSide,
                    carY + ny * cornerForward - ly * cornerSide,
                    cornerZ,
                    carX + nx * 2.8 - lx * 2.9,
                    carY + ny * 2.8 - ly * 2.9,
                    cornerZ,
                    idx + 0.2,
                    2
                )
                samplePoint(
                    carX + nx * 0.9 + lx * 1.45,
                    carY + ny * 0.9 + ly * 1.45,
                    cornerZ,
                    carX + nx * 1.3 + lx * 2.4,
                    carY + ny * 1.3 + ly * 2.4,
                    cornerZ,
                    idx + 0.1,
                    -2
                )
                samplePoint(
                    carX + nx * 0.9 - lx * 1.45,
                    carY + ny * 0.9 - ly * 1.45,
                    cornerZ,
                    carX + nx * 1.3 - lx * 2.4,
                    carY + ny * 1.3 - ly * 2.4,
                    cornerZ,
                    idx + 0.1,
                    2
                )
            end
        end
    end

    do
        local nx, ny = carForwardX, carForwardY
        local lx, ly = carLeftX, carLeftY
        local sweepTopZ = carZ + 1.35
        for dist = 3.0, 9.0, 1.5 do
            local baseX = carX + nx * dist
            local baseY = carY + ny * dist
            local lowZ = carZ + 0.65
            local highZ = sweepTopZ
            samplePoint(baseX, baseY, lowZ, baseX + lx * 3.15, baseY + ly * 3.15, lowZ, idx + dist * 0.2, -2)
            samplePoint(baseX, baseY, lowZ, baseX - lx * 3.15, baseY - ly * 3.15, lowZ, idx + dist * 0.2, 2)
            samplePoint(baseX, baseY, highZ, baseX + lx * 3.30, baseY + ly * 3.30, highZ, idx + dist * 0.2, -2)
            samplePoint(baseX, baseY, highZ, baseX - lx * 3.30, baseY - ly * 3.30, highZ, idx + dist * 0.2, 2)
        end
    end

    do
        local nx, ny = carForwardX, carForwardY
        local lx, ly = carLeftX, carLeftY
        local lowZ = carZ + 0.38
        for dist = 4.0, 34.0, 3.0 do
            local fromDist = math.max(0.0, dist - 2.5)
            local fromX = carX + nx * fromDist
            local fromY = carY + ny * fromDist
            local toX = carX + nx * dist
            local toY = carY + ny * dist
            samplePoint(fromX, fromY, lowZ, toX, toY, lowZ, idx + dist * 0.18, 0)
            samplePoint(fromX + lx * 1.35, fromY + ly * 1.35, lowZ, toX + lx * 1.35, toY + ly * 1.35, lowZ, idx + dist * 0.18, -3)
            samplePoint(fromX - lx * 1.35, fromY - ly * 1.35, lowZ, toX - lx * 1.35, toY - ly * 1.35, lowZ, idx + dist * 0.18, 3)
            sampleNearbyObject(toX, toY, carZ + 0.45, idx + dist * 0.18, 0, 1.9)
            sampleNearbyObject(toX + lx * 1.35, toY + ly * 1.35, carZ + 0.45, idx + dist * 0.18, -3, 1.55)
            sampleNearbyObject(toX - lx * 1.35, toY - ly * 1.35, carZ + 0.45, idx + dist * 0.18, 3, 1.55)
            if dist <= 18.0 then
                samplePoint(toX, toY, lowZ, toX + lx * 3.3, toY + ly * 3.3, lowZ, idx + dist * 0.18, -3)
                samplePoint(toX, toY, lowZ, toX - lx * 3.3, toY - ly * 3.3, lowZ, idx + dist * 0.18, 3)
            end
        end
    end

    local routePoint = route[math.min(idx + LOOKAHEAD, n)] or route[idx]
    local routeDx = routePoint and routePoint.x - carX or carForwardX
    local routeDy = routePoint and routePoint.y - carY or carForwardY
    local routeLen = math.sqrt(routeDx * routeDx + routeDy * routeDy)
    local routeDot = routeLen > 0.1 and ((routeDx / routeLen) * carForwardX + (routeDy / routeLen) * carForwardY) or 1.0
    local scanRouteCorridor = routeDot > -0.25 or getCarSpeed(car) < 5.0

    for i = idx + 6, scanRouteCorridor and math.min(idx + 320, n) or idx + 5, 3 do
        local p = route[i]
        local prev = route[math.max(1, i - 1)]
        local prevZ = (prev.z or carZ) + 0.45
        local pz = (p.z or carZ) + 0.45
        samplePoint(prev.x, prev.y, prevZ, p.x, p.y, pz, i, 0)
        local segX = p.x - prev.x
        local segY = p.y - prev.y
        local segLen = math.sqrt(segX * segX + segY * segY)
        if segLen > 0.1 then
            local lx = -segY / segLen
            local ly = segX / segLen
            local laneOffset = 1.2
            local shoulderOffset = 2.3
            local outerOffset = 3.4
            samplePoint(prev.x + lx * laneOffset, prev.y + ly * laneOffset, prevZ, p.x + lx * laneOffset, p.y + ly * laneOffset, pz, i, -1)
            samplePoint(prev.x - lx * laneOffset, prev.y - ly * laneOffset, prevZ, p.x - lx * laneOffset, p.y - ly * laneOffset, pz, i, 1)
            if ((i - idx) % 6) == 0 and (i - idx) <= 180 then
                sampleNearbyObject(p.x, p.y, pz, i, 0, 1.8)
                sampleNearbyObject(p.x + lx * laneOffset, p.y + ly * laneOffset, pz, i, -1, 1.55)
                sampleNearbyObject(p.x - lx * laneOffset, p.y - ly * laneOffset, pz, i, 1, 1.55)
            end
            if ((i - idx) % 6) == 0 then
                samplePoint(prev.x + lx * shoulderOffset, prev.y + ly * shoulderOffset, prevZ, p.x + lx * shoulderOffset, p.y + ly * shoulderOffset, pz, i, -2)
                samplePoint(prev.x - lx * shoulderOffset, prev.y - ly * shoulderOffset, prevZ, p.x - lx * shoulderOffset, p.y - ly * shoulderOffset, pz, i, 2)
            end
            if ((i - idx) % 9) == 0 then
                samplePoint(prev.x + lx * outerOffset, prev.y + ly * outerOffset, prevZ, p.x + lx * outerOffset, p.y + ly * outerOffset, pz, i, -2)
                samplePoint(prev.x - lx * outerOffset, prev.y - ly * outerOffset, prevZ, p.x - lx * outerOffset, p.y - ly * outerOffset, pz, i, 2)
            end
        end
    end

    local bestUrgency = 0.0
    for _, hit in pairs(found) do
        hit.urgency = obstacleUrgency(hit)
        local clearance = hit.clearance or hit.lateral or 99.0
        local usable = (hit.sideScan and hit.lateral < 4.4 and clearance < 3.4 and hit.worldDist < 22.0 and hit.urgency >= (hit.lowBlockScan and 0.26 or 0.14))
            or (not hit.sideScan and hit.lateral < 2.8 and hit.urgency >= 0.10)
        if usable and hit.threat < bestThreat then
            bestThreat = hit.threat
            best = hit.worldDist
            bestUrgency = hit.urgency
            if hit.avoidDir and hit.avoidDir ~= 0 then
                bestDir = hit.avoidDir
            else
                bestDir = hit.cross > 0 and -1 or 1
            end
        end
        table.insert(S.obstacleHits, hit)
    end

    table.sort(S.obstacleHits, function(a, b)
        return a.threat < b.threat
    end)

    local planDist, planDir, planUrgency, planCount = computeObstacleClusterPlan()
    S.avoidClusterCount = planCount or 0
    if planDir ~= 0 and (bestDir == 0 or planDist < best + 18.0 or planUrgency > bestUrgency * 0.75) then
        best = planDist
        bestDir = planDir
        bestUrgency = math.max(bestUrgency, planUrgency)
    end

    if #S.obstacleHits == 0 then
        best = math.huge
        bestDir = 0
        bestUrgency = 0.0
        S.avoidClusterCount = 0
    elseif bestDir > 0 then
        bestDir = 1
    elseif bestDir < 0 then
        bestDir = -1
    end

    return best, bestDir, bestUrgency
end

local function isPlayerControlling()
    local reverseKey = isPhysicalKeyDown(0x53)
    local botReverseOwner = syntheticReverseKeyDown
        or S.bumpActive
        or os.clock() < (S.backToForwardUntil or 0.0)
    if botReverseOwner and reverseKey then
        reverseKey = false
    end
    return isPhysicalKeyDown(0x57)
        or reverseKey
        or isPhysicalKeyDown(0x41)
        or isPhysicalKeyDown(0x44)
        or isPhysicalKeyDown(0x20)
end

local function isReversePlaybackContext(route, pidx)
    if not playing or type(route) ~= "table" or #route == 0 then return false end
    pidx = math.max(1, math.min(tonumber(pidx) or 1, #route))
    local first = math.max(1, pidx - 2)
    local last = math.min(#route, pidx + (CONFIG.recovery.reverseLookaheadPoints or 24))
    local here = route[pidx]
    for i = first, last do
        local p = route[i]
        if isRoutePointReverse(p) then
            if i <= pidx + 8 then return true end
            if here and here.x and here.y and p.x and p.y then
                local d = getDistanceBetweenCoords2d(here.x, here.y, p.x, p.y)
                if d <= (CONFIG.recovery.reverseLookaheadRadius or 16.0) then
                    return true
                end
            end
        end
    end
    return false
end

local function suppressFreezeForIntentionalReverse(now, route, pidx)
    if isReversePlaybackContext(route, pidx) then
        S.reversePlaybackGraceUntil = math.max(
            S.reversePlaybackGraceUntil or 0.0,
            now + (CONFIG.recovery.reverseTransitionGraceSeconds or 2.4)
        )
    end
    return now < (S.reversePlaybackGraceUntil or 0.0)
end

local function clearFreezeRecoveryOnly(now)
    now = now or os.clock()
    S.freezeTestLatched = false
    S.freezeRecoveryMode = ""
    S.frozenByAdmin = false
    S.refreshSent = false
    S.freezeRefreshSentAt = 0.0
    S.freezeFightUntil = 0.0
    S.freezeReleaseUntil = 0.0
    S.freezeRefreshAt = 0.0
    S.freezeResumeDelay = 0.0
    freezeTimer = 0
    suddenStopFrames = 0
    if pauseReleaseReason == "FROZEN"
        or pauseReleaseReason == "FREEZE_TEST"
        or pauseReleaseReason == "FREEZE_WAIT"
        or pauseReleaseReason == "FREEZE_REFRESH"
        or pauseReleaseReason == "FREEZE_RESUME" then
        pauseReleaseReason = ""
    end
    syncPausedState(now)
end

local function startBackToForwardTransition()
    local now = os.clock()
    if freezeRecoveryOwnsControls() then
        releaseControls(pauseReleaseReason ~= "" and pauseReleaseReason or "FREEZE_WAIT")
        return false
    end
    if not sharedFreezeActive() then
        clearFreezeRecoveryOnly(now)
    end
    S.backToForwardUntil = math.max(
        S.backToForwardUntil or 0.0,
        now + (CONFIG.recovery.backToForwardCoastSeconds or 0.85)
    )
    S.freezeRecoveryGraceUntil = math.max(S.freezeRecoveryGraceUntil or 0.0, S.backToForwardUntil + 0.8)
    S.gasLiftFrames = 0
    gasLevel = 0
    brakeLevel = 0
    lastSteerValue = 0
    setSyntheticReverseKey(false, true)
    setGameKeyState(0, 0)
    writeDriveControls(0, 0)
    return true
end

local function handleBackToForwardTransition()
    local now = os.clock()
    if freezeRecoveryOwnsControls() then
        S.backToForwardUntil = 0.0
        releaseControls(pauseReleaseReason ~= "" and pauseReleaseReason or "FREEZE_WAIT")
        return true
    end
    if now >= (S.backToForwardUntil or 0.0) then return false end
    releaseControls("R_TO_FWD")
    printStringNow("~y~R >> FWD", 100)
    return true
end

local function stopBumpRecovery(reason)
    setSyntheticReverseKey(false, true)
    resetBumpState(false)
    gasLevel = 0
    brakeLevel = 0
    lastSteerValue = 0
    setGameKeyState(0, 0)
    writeDriveControls(0, 0)
    if reason then
        _G.VR_state = reason
        _G.VR_playing = os.clock()
        writeSharedState(reason)
    end
end

local function isBumpRecoveryAllowed(route, pidx, now)
    now = now or os.clock()
    if not CONFIG.recovery.bumpEnabled then return false end
    if freezeRecoveryOwnsControls() then return false end
    if not playing or paused or recording then return false end
    if S.bumpActive or now < (S.bumpCooldownUntil or 0.0) then return false end
    if sharedFreezeActive() then return false end
    if S.dialogPaused or S.testArbotasPaused or now < S.dialogReleaseUntil then return false end
    if now < S.rotateFightUntil or now < S.rotateReleaseUntil then return false end
    if now < (S.backToForwardUntil or 0.0) then return false end
    if isPlayerControlling() then return false end
    if type(route) ~= "table" or #route == 0 then return false end
    if routeDriveModeAt(route, pidx) == DRIVE_BACK then return false end
    return true
end

local function startBumpRecovery(car, route, pidx, reason)
    local now = os.clock()
    if freezeRecoveryOwnsControls() then
        releaseControls(pauseReleaseReason ~= "" and pauseReleaseReason or "FREEZE_WAIT")
        return false
    end
    if not isBumpRecoveryAllowed(route, pidx, now) then return false end

    local cx, cy = getCarCoordinates(car)
    local recent = math.max(math.abs(lastDriveSpeed or 0.0), S.recentDriveSpeed or 0.0)
    local botPushingForward = (gasLevel or 0) > 45 or (S.routeObstacleUrgency or 0.0) > 0.08
    if recent < (CONFIG.recovery.bumpMinRecentSpeed or 2.0) and not botPushingForward then return false end

    local speedFactor = clamp01(recent / 42.0)
    local minDistance = (CONFIG.recovery.bumpReverseDistanceMin or 2.4) + speedFactor * 0.9
    local maxDistance = (CONFIG.recovery.bumpReverseDistanceMax or 6.8) + speedFactor * 0.8
    local reverseSeconds = (CONFIG.recovery.bumpReverseMinSeconds or 0.65)
        + speedFactor * ((CONFIG.recovery.bumpReverseMaxSeconds or 1.45) - (CONFIG.recovery.bumpReverseMinSeconds or 0.65))

    local steerLimit = CONFIG.recovery.bumpSteerMax or 72
    local steer = clamp(lastSteerValue or 0, -steerLimit, steerLimit)
    if math.abs(steer) < 18 then
        steer = 0
    end
    -- Bump recovery is a simple back-away move. Holding the old route steer here
    -- made it look like the bot was fighting itself with joystick input.
    steer = 0

    S.bumpActive = true
    S.bumpPhase = "reverse"
    S.bumpReason = reason or "stuck"
    S.bumpStartedAt = now
    S.bumpUntil = now + reverseSeconds
    S.bumpCooldownUntil = now + (CONFIG.recovery.bumpCooldownSeconds or 3.4)
    S.bumpGraceUntil = now + reverseSeconds + (CONFIG.recovery.bumpFreezeGraceSeconds or 1.8)
    S.freezeRecoveryGraceUntil = math.max(S.freezeRecoveryGraceUntil or 0.0, S.bumpGraceUntil)
    S.bumpStartX = cx
    S.bumpStartY = cy
    S.bumpMinDistance = minDistance
    S.bumpMaxDistance = maxDistance
    S.bumpSteer = steer
    resetForwardNoProgress()
    setSyntheticReverseKey(false, true)
    gasLevel = 0
    brakeLevel = 0
    lastSteerValue = 0
    writeDriveControls(0, 0)
    freezeTimer = 0
    suddenStopFrames = 0
    collisionCooldown = 0
    resetObstacleBypass()

    dbg("recovery", "bump recovery started: " .. tostring(S.bumpReason))
    return true
end

local resyncAfterBump

local function updateBumpRecovery(car, carX, carY)
    if not S.bumpActive then return false end
    local now = os.clock()

    if S.freezeTestLatched or S.frozenByAdmin or sharedFreezeActive()
        or S.dialogPaused or S.testArbotasPaused or now < S.dialogReleaseUntil
        or now < S.rotateFightUntil or now < S.rotateReleaseUntil
        or isPlayerControlling() then
        stopBumpRecovery("BUMP_CANCEL")
        return false
    end

    local backed = getDistanceBetweenCoords2d(carX, carY, S.bumpStartX or carX, S.bumpStartY or carY)
    if S.bumpPhase == "reverse" then
        setSyntheticReverseKey(true)
        gasLevel = 0
        brakeLevel = 0
        lastSteerValue = S.bumpSteer or 0
        setGameKeyState(0, lastSteerValue)
        writeDriveControls(0, 0)
        _G.VR_gas = gasLevel
        _G.VR_brake = brakeLevel
        _G.VR_steer = lastSteerValue
        _G.VR_state = "BUMP_BACK"
        _G.VR_playing = now
        writeSharedState("BUMP_BACK")
        printStringNow(string.format("~y~BUMP BACK ~w~%.1fm", backed), 100)

        local reverseElapsed = now - (S.bumpStartedAt or now)
        if reverseElapsed >= (CONFIG.recovery.bumpFreezeEscalateSeconds or 0.85)
            and backed <= (CONFIG.recovery.bumpFreezeEscalateDistance or 0.25) then
            logEvent("RECOVERY", string.format("bump could not move %.2fm in %.2fs; escalating to freeze", backed, reverseElapsed))
            startFreezeRecovery("real")
            return true
        end

        local backedEnough = backed >= (S.bumpMinDistance or 2.4)
        local backedTooFar = backed >= (S.bumpMaxDistance or 6.8)
        local hardTimeDone = now >= ((S.bumpStartedAt or now) + (CONFIG.recovery.bumpReverseHardMaxSeconds or 2.6))
        local plannedTimeDone = now >= (S.bumpUntil or now)
        if backedTooFar or hardTimeDone or (plannedTimeDone and backedEnough) then
            S.bumpPhase = "coast"
            S.bumpUntil = now + (CONFIG.recovery.bumpCoastSeconds or 0.32)
            setSyntheticReverseKey(false, true)
            gasLevel = 0
            brakeLevel = 0
            lastSteerValue = 0
            setGameKeyState(0, 0)
            writeDriveControls(0, 0)
        end
        return true
    end

    if S.bumpPhase == "coast" then
        setSyntheticReverseKey(false, true)
        gasLevel = 0
        brakeLevel = 0
        lastSteerValue = 0
        setGameKeyState(0, 0)
        writeDriveControls(0, 0)
        _G.VR_state = "BUMP_WAIT"
        _G.VR_playing = now
        writeSharedState("BUMP_WAIT")
        printStringNow("~y~BUMP WAIT", 100)
        if now >= (S.bumpUntil or 0.0) then
            S.freezeRecoveryGraceUntil = math.max(S.freezeRecoveryGraceUntil or 0.0, now + (CONFIG.recovery.bumpFreezeGraceSeconds or 1.8))
            S.rejoinDisableUntil = math.max(S.rejoinDisableUntil or 0.0, now + 1.0)
            freezeTimer = 0
            suddenStopFrames = 0
            S.recentDriveSpeed = 0.0
            S.recentDriveUntil = 0.0
            lastDriveSpeed = 0.0
            resyncAfterBump(carX, carY)
            stopBumpRecovery("BUMP_DONE")
            startBackToForwardTransition()
            dbg("recovery", "bump recovery finished")
            return true
        end
        return true
    end

    stopBumpRecovery("BUMP_DONE")
    resyncAfterBump(carX, carY)
    startBackToForwardTransition()
    return true
end

resyncAfterBump = function(carX, carY)
    if type(current_route) ~= "table" or #current_route == 0 then return false end
    play_index = math.max(1, math.min(tonumber(play_index) or 1, #current_route))

    local first = math.max(1, play_index - (CONFIG.recovery.bumpResyncBackPoints or 10))
    local last = math.min(#current_route, play_index + (CONFIG.recovery.bumpResyncAheadPoints or 45))
    local bestIdx = play_index
    local bestScore = math.huge
    local bestDist = math.huge

    for i = first, last do
        if routeDriveModeAt(current_route, i) ~= DRIVE_BACK then
            local p = current_route[i]
            if p and p.x and p.y then
                local d = getDistanceBetweenCoords2d(carX, carY, p.x, p.y)
                local backPenalty = i < play_index and (play_index - i) * 0.45 or 0.0
                local forwardPenalty = i > play_index and (i - play_index) * 0.03 or 0.0
                local score = d + backPenalty + forwardPenalty
                if score < bestScore then
                    bestScore = score
                    bestDist = d
                    bestIdx = i
                end
            end
        end
    end

    if bestIdx ~= play_index and bestDist <= (CONFIG.recovery.bumpResyncMaxDistance or 28.0) then
        play_index = bestIdx
        playbackDriveMode = routeDriveModeAt(current_route, play_index)
        steerBuf = {0, 0}
        S.currentLateral = 0.0
        resetObstacleBypass()
        collisionCooldown = 0
        resetForwardNoProgress()
        dbg("recovery", "bump resync to " .. tostring(play_index))
        return true
    end

    resetForwardNoProgress()
    return false
end

local function updateForwardNoProgress(route, pidx, cx, cy, absSpeed)
    if type(route) ~= "table" or #route == 0 then
        resetForwardNoProgress()
        return false
    end

    pidx = math.max(1, math.min(tonumber(pidx) or 1, #route))
    local point = route[pidx]
    if not point or routeDriveModeAt(route, pidx) == DRIVE_BACK then
        resetForwardNoProgress()
        return false
    end

    local pushingForward = (gasLevel or 0) >= (CONFIG.recovery.forwardNoProgressGas or 80)
    local movingEnough = (absSpeed or 0.0) > (CONFIG.recovery.forwardNoProgressSpeed or 8.0)
    if not pushingForward or movingEnough or S.bumpActive or S.freezeTestLatched or S.frozenByAdmin then
        resetForwardNoProgress()
        return false
    end

    local dist = getDistanceBetweenCoords2d(cx, cy, point.x, point.y)
    if (S.forwardNoProgressIndex or 0) ~= pidx then
        S.forwardNoProgressIndex = pidx
        S.forwardNoProgressDist = dist
        S.forwardNoProgressFrames = 0
        return false
    end

    local epsilon = CONFIG.recovery.forwardProgressEpsilon or 0.06
    local lastDist = S.forwardNoProgressDist or dist
    if dist >= lastDist - epsilon then
        S.forwardNoProgressFrames = (S.forwardNoProgressFrames or 0) + 1
    else
        S.forwardNoProgressFrames = math.max(0, (S.forwardNoProgressFrames or 0) - 3)
    end
    S.forwardNoProgressDist = dist

    return (S.forwardNoProgressFrames or 0) >= (CONFIG.recovery.forwardNoProgressFrames or 44)
end

local function typeSAMPCommand(cmd)
    cmd = tostring(cmd or "")
    if cmd == "" then return false end

    local ffiok, ffi = pcall(require, "ffi")
    if not ffiok then
        logEvent("INPUT", "typeSAMPCommand failed: ffi unavailable")
        return false
    end

    if not commandInputFfiReady then
        pcall(ffi.cdef, "void keybd_event(unsigned char, unsigned char, unsigned long, unsigned long*);")
        pcall(ffi.cdef, "short VkKeyScanA(char ch);")
        commandInputFfiReady = true
    end

    local u32ok, u32 = pcall(ffi.load, "user32")
    if not u32ok then
        logEvent("INPUT", "typeSAMPCommand failed: user32 unavailable")
        return false
    end

    local function tapKey(vk, holdMs)
        u32.keybd_event(vk, 0, 0, nil)
        wait(holdMs or 35)
        u32.keybd_event(vk, 0, 2, nil)
    end

    local function releaseTypingKeys()
        local keys = {0x10, 0x11, 0x12, 0x57, 0x41, 0x53, 0x44, 0x20, 0x0D}
        for _, vk in ipairs(keys) do
            u32.keybd_event(vk, 0, 2, nil)
        end
    end

    local function tapCharacter(ch)
        local byte = string.byte(ch)
        if not byte then return false end

        local vk, needShift = nil, false
        if ch == "/" then
            local ok, scan = pcall(u32.VkKeyScanA, byte)
            if ok and scan and scan >= 0 then
                vk = scan % 256
                needShift = math.floor(scan / 256) % 2 == 1
            else
                vk = 0xBF -- VK_OEM_2, slash on common GTA/SA-MP keyboard layouts.
            end
        elseif byte >= 97 and byte <= 122 then
            vk = byte - 32
        elseif byte >= 65 and byte <= 90 then
            vk = byte
            needShift = true
        elseif byte >= 48 and byte <= 57 then
            vk = byte
        else
            local ok, scan = pcall(u32.VkKeyScanA, byte)
            if not ok or not scan or scan < 0 then return false end
            vk = scan % 256
            needShift = math.floor(scan / 256) % 2 == 1
        end

        if needShift then u32.keybd_event(0x10, 0, 0, nil) end
        tapKey(vk, 30)
        if needShift then u32.keybd_event(0x10, 0, 2, nil) end
        return true
    end

    lua_thread.create(function()
        releaseTypingKeys()
        tapKey(0x54, 50) -- T opens SA-MP chat in this setup.
        wait(350)
        for i = 1, #cmd do
            if not tapCharacter(cmd:sub(i, i)) then
                logEvent("INPUT", "typeSAMPCommand skipped character at " .. tostring(i))
            end
            wait(45)
        end
        wait(180)
        tapKey(0x0D, 40)
        releaseTypingKeys()
    end)
    return true
end

local function handleFreeze(car, route, pidx)
    local cx, cy = getCarCoordinates(car)
    local speed = getCarSpeed(car)
    local absSpeed = math.abs(speed or 0.0)
    local moved = getDistanceBetweenCoords2d(cx, cy, lastX, lastY)
    local now = os.clock()
    local externalFreeze = sharedFreezeActive()

    if externalFreeze then
        if not S.freezeTestLatched then
            logEvent("RECOVERY", "external freeze detected")
            startFreezeRecovery("test")
        end
        resetForwardNoProgress()
        lastDriveSpeed = speed
        lastX, lastY = cx, cy
        return true
    end

    if S.dialogPaused or S.testArbotasPaused or now < S.dialogReleaseUntil
        or now < S.rotateFightUntil or now < S.rotateReleaseUntil
        or now < (S.backToForwardUntil or 0.0)
        or ((S.bumpActive or now < (S.bumpGraceUntil or 0.0)) and not externalFreeze)
        or isPlayerControlling() then
        freezeTimer = 0
        suddenStopFrames = 0
        S.recentDriveSpeed = 0.0
        S.recentDriveUntil = 0.0
        resetForwardNoProgress()
        lastDriveSpeed = speed
        lastX, lastY = cx, cy
        return false
    end

    if S.freezeTestLatched and S.freezeRecoveryMode == "test" then
        resetFreezeRecovery()
        resetForwardNoProgress()
        lastDriveSpeed = speed
        lastX, lastY = cx, cy
        return false
    end

    if suppressFreezeForIntentionalReverse(now, route, pidx) then
        freezeTimer = 0
        suddenStopFrames = 0
        S.frozenByAdmin = false
        S.refreshSent = false
        S.recentDriveSpeed = 0.0
        S.recentDriveUntil = 0.0
        resetForwardNoProgress()
        lastDriveSpeed = speed
        lastX, lastY = cx, cy
        return false
    end

    if now < S.freezeRecoveryGraceUntil then
        freezeTimer = 0
        suddenStopFrames = 0
        S.frozenByAdmin = false
        S.refreshSent = false
        resetForwardNoProgress()
        lastDriveSpeed = speed
        lastX, lastY = cx, cy
        return false
    end

    if absSpeed > 8.0 or moved > 0.45 then
        S.recentDriveSpeed = math.max((S.recentDriveSpeed or 0.0) * 0.82, absSpeed)
        S.recentDriveUntil = now + 2.4
    end

    local stoppedNow = absSpeed < 0.75 and moved < 0.14
    if stoppedNow then
        suddenStopFrames = suddenStopFrames + 1
    elseif absSpeed > 2.0 or moved > 0.35 then
        suddenStopFrames = 0
    end

    local stoppedAfterMoving = suddenStopFrames >= 8
        and (S.recentDriveSpeed or 0.0) > 18.0
        and now < (S.recentDriveUntil or 0.0)

    if stoppedAfterMoving then
        freezeTimer = math.max(freezeTimer, 4)
        if startBumpRecovery(car, route, pidx, "sudden_stop") then
            lastDriveSpeed = speed
            lastX, lastY = cx, cy
            return false
        end
        if not S.freezeTestLatched then
            startFreezeRecovery("real")
        end
        lastDriveSpeed = speed
        lastX, lastY = cx, cy
        return true
    end

    if updateForwardNoProgress(route, pidx, cx, cy, absSpeed) then
        if startBumpRecovery(car, route, pidx, "no_progress") then
            lastDriveSpeed = speed
            lastX, lastY = cx, cy
            return false
        end
    end

    if stoppedNow then
        freezeTimer = freezeTimer + 1
        local botTryingForward = (gasLevel or 0) > 70
            or (S.recentDriveSpeed or 0.0) > 1.2
            or math.abs(lastDriveSpeed or 0.0) > 1.0
        if freezeTimer > 12 and botTryingForward then
            if startBumpRecovery(car, route, pidx, "stuck") then
                lastDriveSpeed = speed
                lastX, lastY = cx, cy
                return false
            end
        end
        if freezeTimer > 22 and ((S.recentDriveSpeed or 0.0) > 5.0 or math.abs(lastDriveSpeed or 0.0) > 3.0) then
            if not S.freezeTestLatched then
                startFreezeRecovery("real")
            end
        end
        if freezeTimer > 150 then
            local point = route[pidx]
            if point then
                local th = getHeadingFromVector2d(point.x - cx, point.y - cy)
                local diff = math.abs(getCarHeading(car) - th)
                if diff > 180 then diff = 360 - diff end
                if diff > 100 and startBumpRecovery(car, route, pidx, "misaligned") then
                    lastDriveSpeed = speed
                    lastX, lastY = cx, cy
                    return false
                end
            end
        end
    else
        freezeTimer = 0
        suddenStopFrames = 0
        resetForwardNoProgress()
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
    if not playing then return end
    if freezeRecoveryOwnsControls() then
        releaseControls(pauseReleaseReason ~= "" and pauseReleaseReason or "FREEZE_WAIT")
        return
    end
    local heading = getCarHeading(car)
    local now = os.clock()
    if now < (S.rotateIgnoreUntil or 0.0) then
        lastCarHeading = heading
        return
    end
    local diff = math.abs(heading - lastCarHeading)
    if diff > 180 then diff = 360 - diff end
    local rotateMode = consumeRotateFlag()
    local triggered = diff > 150 or (_G.VR_ADMIN_ROTATED == true) or rotateMode ~= nil
    if triggered then _G.VR_ADMIN_ROTATED = false end
    lastCarHeading = heading
    if not triggered then return end
    syncPausedState()
    -- Rotation is now always handled as a safe control release/reaction.
    -- The old destructive path could fire on false 180s.
    local reaction = math.random(600, 1300) / 1000.0
    S.rotateFightUntil = now + reaction
    S.rotateReleaseUntil = S.rotateFightUntil + 1.0
    syncPausedState(now)
    pressRotateReaction()
    lua_thread.create(function()
        local fightUntil = S.rotateFightUntil
        local untilTime = S.rotateReleaseUntil
        while os.clock() < untilTime do
            if freezeRecoveryOwnsControls() then
                releaseControls(pauseReleaseReason ~= "" and pauseReleaseReason or "FREEZE_WAIT")
            elseif os.clock() < fightUntil then
                pressRotateReaction()
            else
                releaseControls("ROTATE_CONFUSED")
            end
            wait(0)
        end
        if S.rotateReleaseUntil == untilTime then
            S.rotateFightUntil = 0.0
            syncPausedState()
        end
    end)
end

local function finishDialogPause()
    local now = os.clock()
    if S.bumpActive then
        stopBumpRecovery("BUMP_DIALOG")
    end
    S.testArbotasPaused = false
    S.dialogPaused = false
    S.dialogReleaseUntil = now + (math.random(500, 1000) / 1000.0)
    freezeTimer = 0
    suddenStopFrames = 0
    S.recentDriveSpeed = 0.0
    S.recentDriveUntil = 0.0
    lastDriveSpeed = 0.0
    pauseReleaseReason = "DIALOG_WAIT"
    syncPausedState(now)
    releaseControls("DIALOG_WAIT")
end

local function handleArbotas()
    local fakeDialogMode = sharedDialogMode()
    if fakeDialogMode == "fake_arbotas" or _G.VR_TEST_ARBOTAS then
        if S.bumpActive then
            stopBumpRecovery("BUMP_DIALOG")
        end
        S.testArbotasPaused = true
        S.dialogPaused = true
        S.dialogReleaseUntil = 0.0
        syncPausedState()
        releaseControls("AR_BOTAS_TEST")
        return
    end
    if _G.VR_DIALOG_ACTIVE then
        if S.bumpActive then
            stopBumpRecovery("BUMP_DIALOG")
        end
        S.dialogPaused = true
        S.dialogReleaseUntil = 0.0
        syncPausedState()
        releaseControls("DIALOG")
        return
    elseif S.testArbotasPaused then
        finishDialogPause()
        return
    end
    if not playing or samp == 0 then return end
    if not isSampDialogActive() then
        if S.dialogPaused then
            finishDialogPause()
        end
        return
    end
    S.dialogPaused = true
    S.dialogReleaseUntil = 0.0
    if S.bumpActive then
        stopBumpRecovery("BUMP_DIALOG")
    end
    syncPausedState()
    releaseControls("DIALOG")
    return
end

Utils.clamp01 = clamp01
Utils.clamp = clamp
Utils.findNearestWaypoint = findNearestWaypoint

RouteStorage.save = saveRoute
RouteStorage.load = loadRoute
RouteStorage.saveRoute = RouteStorage.save
RouteStorage.loadRoute = RouteStorage.load

function RouteStorage.ensurePathsDir()
    if not doesDirectoryExist(paths_dir) then
        createDirectory(paths_dir)
    end
end

function RouteStorage.validateRoute(route)
    if type(route) ~= "table" or #route < 2 then return false end
    for _, p in ipairs(route) do
        if type(p) ~= "table"
            or type(p.x) ~= "number"
            or type(p.y) ~= "number"
            or type(p.z) ~= "number"
            or type(p.speed) ~= "number"
            or type(p.heading) ~= "number" then
            return false
        end
        if p.reverse ~= nil and type(p.reverse) ~= "boolean" then
            return false
        end
        if p.drive ~= nil and type(p.drive) ~= "string" then
            return false
        end
    end
    return true
end

function RouteStorage.inspectRoute(route)
    local summary = { total = 0, forward = 0, back = 0, bad = 0 }
    if type(route) ~= "table" then
        summary.bad = 1
        return summary
    end
    summary.total = #route
    for _, p in ipairs(route) do
        if type(p) ~= "table" or type(p.x) ~= "number" or type(p.y) ~= "number" then
            summary.bad = summary.bad + 1
        elseif isRoutePointReverse(p) then
            summary.back = summary.back + 1
        else
            summary.forward = summary.forward + 1
        end
    end
    return summary
end

function RouteStorage.logRouteSummary(name, route, action)
    local s = RouteStorage.inspectRoute(route)
    logEvent("ROUTE", string.format("%s %s points=%d fwd=%d back=%d bad=%d",
        tostring(action or "route"),
        tostring(name or current_name),
        s.total or 0,
        s.forward or 0,
        s.back or 0,
        s.bad or 0))
    if (s.bad or 0) > 0 then
        printStringNow("~y~Dangis VR: route has invalid points, check debug log.", 3000)
    end
end

function RouteRecorder.startRecording()
    if not isCharInAnyCar(PLAYER_PED) then
        showMsg("~r~Turi buti masinos viduje!")
        return false
    end
    if S.bumpActive then
        stopBumpRecovery("BUMP_REC")
    end
    releaseControls("REC_START")
    setSyntheticReverseKey(false, true)
    recording = true
    playing = false
    current_route = {}
    recordReverseFrames = 0
    recordForwardBrakeFrames = 0
    recordDriveMode = DRIVE_FORWARD
    start_x, start_y, start_z = getCharCoordinates(PLAYER_PED)
    lastRecordHeading = getCarHeading(storeCarCharIsInNoSave(PLAYER_PED))
    tick = os.clock() * 1000
    refreshStateView()
    dbg("route", "recording started")
    showMsg("~g~Irasymas pradetas! Grizk i starta uzdaryt kilpa!")
    return true
end

function RouteRecorder.stopRecording()
    recording = false
    current_route = normalizeRouteReverseFlags(current_route)
    if #current_route > 0 and RouteStorage.save(current_name, current_route) then
        RouteStorage.logRouteSummary(current_name, current_route, "saved")
        showMsg("~g~Kelias issaugotas! Tasku: " .. #current_route)
    end
    refreshStateView()
end

function RouteRecorder.recordTick()
    if not recording then return end
    if not isCharInAnyCar(PLAYER_PED) then
        recording = false
        refreshStateView()
        showMsg("~r~Irasymas sustabdytas - islejai masina!")
        return
    end

    local time = os.clock() * 1000
    local car = storeCarCharIsInNoSave(PLAYER_PED)
    local posX, posY, posZ = getCarCoordinates(car)
    local currentH = getCarHeading(car)
    local hDiff = math.abs(currentH - lastRecordHeading)
    if hDiff > 180 then hDiff = 360 - hDiff end
    if hDiff > 15 or (time - tick > recordingDelay) then
        local speed = getCarSpeed(car)
        local reverseIntent = isReverseRecordingInputActive(car)
        local prev = current_route[#current_route]
        local absSpeed = math.abs(speed or 0.0)
        local prevSpeed = prev and math.abs(prev.speed or 0.0) or 0.0
        local forwardMotion = nil
        local recordHudState = ""

        if prev then
            local dx = posX - prev.x
            local dy = posY - prev.y
            if dx * dx + dy * dy > 0.0025 then
                forwardMotion = getRecordedForwardMotion(car, currentH, prev, posX, posY) or 0.0
            end
        end

        local rollingForwardBrake = recordDriveMode ~= DRIVE_BACK
            and reverseIntent
            and (absSpeed > 2.0 or prevSpeed > 2.0 or (forwardMotion and forwardMotion > 0.04))
        local movingBackward = forwardMotion and forwardMotion < -0.025
        local stoppedForReverse = absSpeed < 1.15 and prevSpeed < 1.6
        local settledAfterBrake = absSpeed < 0.95 and (not forwardMotion or math.abs(forwardMotion) < 0.045)

        if not reverseIntent then
            recordDriveMode = DRIVE_FORWARD
            recordReverseFrames = 0
            recordForwardBrakeFrames = 0
            recordHudState = ""
        elseif rollingForwardBrake then
            -- In GTA, S means brake while rolling forward. Do not record BACK
            -- until the forward braking phase has genuinely settled.
            recordDriveMode = DRIVE_FORWARD
            recordReverseFrames = 0
            recordForwardBrakeFrames = 6
            recordHudState = "BRAKE"
        elseif recordDriveMode == DRIVE_BACK then
            recordReverseFrames = 10
            recordForwardBrakeFrames = 0
            recordHudState = "BACK"
        elseif recordForwardBrakeFrames > 0 then
            if movingBackward or stoppedForReverse or settledAfterBrake then
                recordForwardBrakeFrames = 0
                recordReverseFrames = math.min(10, recordReverseFrames + 4)
                recordDriveMode = recordReverseFrames >= 4 and DRIVE_BACK or DRIVE_FORWARD
                recordHudState = recordDriveMode == DRIVE_BACK and "BACK" or "S"
            else
                recordDriveMode = DRIVE_FORWARD
                recordReverseFrames = 0
                recordHudState = "WAIT"
            end
        else
            if stoppedForReverse or movingBackward then
                recordReverseFrames = math.min(10, recordReverseFrames + 4)
            else
                recordReverseFrames = math.max(0, recordReverseFrames - 1)
            end
            recordDriveMode = recordReverseFrames >= 4 and DRIVE_BACK or DRIVE_FORWARD
            recordHudState = recordDriveMode == DRIVE_BACK and "BACK" or "S"
        end

        local reverse = recordDriveMode == DRIVE_BACK
        table.insert(current_route, {x=posX, y=posY, z=posZ, speed=speed, heading=currentH, drive=recordDriveMode, reverse=reverse})
        lastRecordHeading = currentH
        tick = os.clock() * 1000
        local modeText = ""
        if reverse then
            modeText = " ~b~BACK"
        elseif reverseIntent then
            modeText = recordHudState == "BRAKE" and " ~y~BRAKE" or (recordHudState == "WAIT" and " ~y~WAIT" or " ~y~S")
        end
        printStringNow('~g~Irasymas ~w~X:'..math.floor(posX)..' Y:'..math.floor(posY)..' G:'..math.floor(speed)..modeText, 1000)
        local dist = getDistanceBetweenCoords2d(posX, posY, start_x, start_y)
        if dist < 5.0 and #current_route > 50 then
            recording = false
            current_route = normalizeRouteReverseFlags(current_route)
            if RouteStorage.save(current_name, current_route) then
                RouteStorage.logRouteSummary(current_name, current_route, "saved_loop")
                showMsg("~g~Kilpa uzdaryta! Issaugota: " .. current_name)
            end
        end
    end
    refreshStateView()
end

ObstacleAvoidance.scanObstacles = scanRouteAhead
ObstacleAvoidance.updateBypass = updateObstacleBypass
ObstacleAvoidance.getObstacleAhead = getObstacleAhead

RecoverySystem.handleFreeze = handleFreeze
RecoverySystem.resetFreezeRecovery = resetFreezeRecovery
RecoverySystem.updateBumpRecovery = updateBumpRecovery

function RecoverySystem.updateControlThread()
    local now = os.clock()
    syncPausedState(now)
    local freezeActive = sharedFreezeActive()

    if freezeActive and playing and not S.freezeTestLatched then
        logEvent("RECOVERY", "external freeze detected by control thread")
        startFreezeRecovery("test")
        now = os.clock()
    end

    if (S.bumpActive or now < (S.backToForwardUntil or 0.0))
        and not freezeActive
        and not S.freezeTestLatched
        and not S.frozenByAdmin then
        refreshStateView()
        return
    end

    if S.freezeTestLatched then
        if not S.refreshSent then
            releaseControls("FREEZE_WAIT")
            if now >= (S.freezeRefreshAt or 0.0) then
                local resumeDelay = tonumber(S.freezeResumeDelay) or 0.0
                if resumeDelay <= 0.0 then
                    resumeDelay = CONFIG.recovery.freezeResumeDelayMinSeconds or 0.5
                end
                logEvent("RECOVERY", "freeze recovery sending /refresh")
                if typeSAMPCommand("/refresh") then
                    S.refreshSent = true
                    S.freezeRefreshSentAt = now
                    S.freezeReleaseUntil = now + resumeDelay
                else
                    S.freezeRefreshAt = now + 0.75
                    logEvent("RECOVERY", "freeze recovery /refresh typing failed; retry scheduled")
                end
            end
        elseif now < (S.freezeReleaseUntil or 0.0) then
            releaseControls("FREEZE_REFRESH")
        else
            releaseControls("FREEZE_RESUME")
            resetFreezeRecovery()
        end
    elseif now < S.rotateFightUntil then
        pressRotateReaction()
    elseif now < S.rotateReleaseUntil then
        releaseControls("ROTATE_CONFUSED")
    elseif paused or freezeActive then
        releaseControls(pauseReleaseReason ~= "" and pauseReleaseReason or "SAFE")
    end
    refreshStateView()
end

AdminProtection.handleAdminCheck = handleAdminRotate
DialogBridge.update = handleArbotas
DialogBridge.writeBotState = writeSharedState

function RouteFollower.resetPlaybackStartState()
    setSyntheticReverseKey(false, true)
    writeDriveControls(0, 0)
    playbackDriveMode = DRIVE_FORWARD
    S.lapWander = (math.random() * 3.0) - 1.5
    S.lapCount = 0
    gasLevel = 0; brakeLevel = 0
    S.gasLiftFrames = 0
    S.nextGasLift = os.clock() + math.random(20, 60)
    S.nudgeFrames = 0; S.nudgeOffset = 0.0
    S.nextNudge = os.clock() + math.random(12, 40)
    S.currentLateral = 0.0
    S.manualPaused = false
    S.dialogPaused = false
    S.testArbotasPaused = false
    S.dialogReleaseUntil = 0.0
    S.frozenByAdmin = false
    S.freezeTestLatched = false
    S.freezeRecoveryMode = ""
    S.freezeRefreshSentAt = 0.0
    S.freezeFightUntil = 0.0
    S.freezeReleaseUntil = 0.0
    S.freezeRefreshAt = 0.0
    S.freezeResumeDelay = 0.0
    S.freezeRecoveryGraceUntil = 0.0
    S.reversePlaybackGraceUntil = 0.0
    S.backToForwardUntil = 0.0
    resetBumpState(true)
    S.routeObstacleDist = math.huge
    S.routeAvoidDir = 0
    S.routeObstacleUrgency = 0.0
    S.routeObstacleTimer = 0
    S.obstacleHits = {}
    S.obstacleProbes = {}
    S.rejoinFrames = 0
    S.rejoinSteer = 0
    S.rejoinCooldownUntil = 0.0
    S.rejoinDisableUntil = os.clock() + 4.0
    resetObstacleBypass()
    S.avoidClusterCount = 0
    suddenStopFrames = 0
    freezeTimer = 0
    S.recentDriveSpeed = 0.0
    S.recentDriveUntil = 0.0
    collisionCooldown = 0
    avoidSteerDir = 0
    S.avoidRouteDir = 0
    S.avoidSideHit = false
    lastDriveSpeed = 0.0
    pauseReleaseReason = ""
    S.rotateFightUntil = 0.0
    S.rotateReleaseUntil = 0.0
    clearRotateTrigger()
    S.rotateIgnoreUntil = os.clock() + CONFIG.recovery.rotateStartIgnoreSeconds
    steerBuf = {0, 0}
    if isCharInAnyCar(PLAYER_PED) then
        lastCarHeading = getCarHeading(storeCarCharIsInNoSave(PLAYER_PED))
    end
    refreshStateView()
end

function RouteFollower.startPlayback()
    RouteFollower.resetPlaybackStartState()
    if #currentTrail > 0 then
        lastTrail = currentTrail
        currentTrail = {}
    end
    current_route = normalizeRouteReverseFlags(current_route)
    if #current_route > 5 then
        RouteStorage.logRouteSummary(current_name, current_route, "play_memory")
        play_index = 1; playbackDriveMode = routeDriveModeAt(current_route, 1); playing = true; syncPausedState()
        refreshStateView()
        showMsg("~g~Vaziavimas pradetas!")
        return true
    end

    local route = RouteStorage.load(current_name)
    if RouteStorage.validateRoute(route) then
        RouteStorage.logRouteSummary(current_name, route, "play_file")
        current_route = route; play_index = 1; playbackDriveMode = routeDriveModeAt(current_route, 1); playing = true; syncPausedState()
        refreshStateView()
        showMsg("~g~Kelias ikrautas ir paleistas: " .. current_name)
        return true
    end

    refreshStateView()
    showMsg("~r~Nera irasyto kelio!")
    return false
end

function RouteFollower.stopPlayback()
    if S.bumpActive then
        stopBumpRecovery("BUMP_STOP")
    end
    resetForwardNoProgress()
    playing = false
    releaseControls("STOPPED")
    refreshStateView()
    showMsg("~r~Vaziavimas sustabdytas!")
end

function RouteFollower.stopAll()
    if S.bumpActive then
        stopBumpRecovery("BUMP_ALL_STOP")
    end
    recording = false; playing = false; repeating = false
    playbackDriveMode = DRIVE_FORWARD
    recordDriveMode = DRIVE_FORWARD
    recordReverseFrames = 0
    recordForwardBrakeFrames = 0
    S.manualPaused = false; play_index = 1
    S.dialogPaused = false; S.testArbotasPaused = false; S.frozenByAdmin = false; S.freezeTestLatched = false
    S.dialogReleaseUntil = 0.0
    S.freezeRecoveryMode = ""
    S.freezeRefreshSentAt = 0.0
    S.freezeFightUntil = 0.0
    S.freezeReleaseUntil = 0.0
    S.freezeRefreshAt = 0.0
    S.freezeResumeDelay = 0.0
    S.freezeRecoveryGraceUntil = 0.0
    S.reversePlaybackGraceUntil = 0.0
    S.backToForwardUntil = 0.0
    resetBumpState(true)
    S.currentLateral = 0.0
    S.nudgeFrames = 0
    S.nudgeOffset = 0.0
    S.routeObstacleDist = math.huge
    S.routeAvoidDir = 0
    S.routeObstacleUrgency = 0.0
    S.routeObstacleTimer = 0
    S.obstacleHits = {}
    S.obstacleProbes = {}
    S.rejoinFrames = 0
    S.rejoinSteer = 0
    S.rejoinCooldownUntil = 0.0
    S.rejoinDisableUntil = 0.0
    resetObstacleBypass()
    S.avoidClusterCount = 0
    suddenStopFrames = 0
    freezeTimer = 0
    lastDriveSpeed = 0.0
    S.recentDriveSpeed = 0.0
    S.recentDriveUntil = 0.0
    steerBuf = {0, 0}
    collisionCooldown = 0
    avoidSteerDir = 0
    S.avoidRouteDir = 0
    S.avoidSideHit = false
    pauseReleaseReason = ""
    S.rotateFightUntil = 0.0
    S.rotateReleaseUntil = 0.0
    S.rotateIgnoreUntil = 0.0
    clearRotateTrigger()
    syncPausedState()
    releaseControls("ALL_STOP")
    refreshStateView()
    showMsg("~r~Viskas sustabdyta!")
end

function RouteFollower.updateTrail(carX, carY, carZ)
    trailTick = trailTick + 1
    if trailTick >= 8 then
        trailTick = 0
        if #currentTrail < CONFIG.obstacle.maxTrailPoints then
            table.insert(currentTrail, {x=carX, y=carY, z=carZ})
        end
    end
end

function ObstacleAvoidance.updateScan(car)
    if routeDriveModeAt(current_route, play_index) == DRIVE_BACK then
        S.routeObstacleTimer = 0
        S.routeObstacleDist = math.huge
        S.routeAvoidDir = 0
        S.routeObstacleUrgency = 0.0
        S.obstacleHits = {}
        S.obstacleProbes = {}
        resetObstacleBypass()
        return
    end

    S.routeObstacleTimer = S.routeObstacleTimer + 1
    if S.routeObstacleTimer >= CONFIG.obstacle.scanEveryFrames then
        S.routeObstacleTimer = 0
        local scannedDist, scannedDir, scannedUrgency = scanRouteAhead(current_route, play_index, car)
        S.routeObstacleDist = scannedDist
        S.routeObstacleUrgency = scannedUrgency or 0.0
        if collisionCooldown <= 0 or S.routeAvoidDir == 0 then
            S.routeAvoidDir = scannedDir
        end
    end
end

function RouteFollower.updatePlayback()
    if playing and #current_route > 0 and sharedFreezeActive() and not S.freezeTestLatched then
        logEvent("RECOVERY", "external freeze detected by playback gate")
        startFreezeRecovery("test")
    end
    if playing and freezeRecoveryOwnsControls() then
        releaseControls(pauseReleaseReason ~= "" and pauseReleaseReason or "FREEZE_WAIT")
        refreshStateView()
        return
    end

    if not (playing and not paused and #current_route > 0) then return end

    if not isCharInAnyCar(PLAYER_PED) then
        playing = false; repeating = false
        syncPausedState()
        if S.bumpActive then
            stopBumpRecovery("BUMP_NO_CAR")
        end
        releaseControls("NO_CAR")
        refreshStateView()
        showMsg("~r~Vaziavimas sustabdytas - islejei masina!")
        return
    end

    local car = storeCarCharIsInNoSave(PLAYER_PED)
    local carX, carY, carZ = getCarCoordinates(car)

    if isPlayerControlling() then
        if not overrideActive then
            overrideActive = true
            if S.bumpActive then
                stopBumpRecovery("BUMP_OVERRIDE")
            end
            releaseControls("OVERRIDE")
        end
        printStringNow("~y~OVERRIDE ACTIVE", 100)
        refreshStateView()
        return
    end

    overrideActive = false

    -- Recovery mini-states must run before normal playback systems; otherwise
    -- freeze/obstacle/route logic can write controls during bump or R >> FWD.
    if S.bumpActive then
        if RecoverySystem.updateBumpRecovery(car, carX, carY) then
            refreshStateView()
            return
        end
    end

    if handleBackToForwardTransition() then
        refreshStateView()
        return
    end

    RouteFollower.updateTrail(carX, carY, carZ)
    ObstacleAvoidance.updateScan(car)
    AdminProtection.handleAdminCheck(car)
    RecoverySystem.handleFreeze(car, current_route, play_index)

    if S.bumpActive then
        if RecoverySystem.updateBumpRecovery(car, carX, carY) then
            refreshStateView()
            return
        end
    end

    if S.freezeTestLatched then
        -- Freeze recovery thread owns inputs so real and test freezes behave identically.
    elseif S.frozenByAdmin or sharedFreezeActive() then
        releaseControls(pauseReleaseReason ~= "" and pauseReleaseReason or "FROZEN")
    elseif _G.VR_TEST_ARBOTAS then
        releaseControls("AR_BOTAS_TEST")
    elseif not paused then
        local point = current_route[play_index]
        local speedMult = 1.0
        local driveMode = getPlaybackDriveMode(current_route, play_index)
        local reverseMode = driveMode == DRIVE_BACK
        local tX, tY, tZ

        if reverseMode then
            local syncedIndex = syncReversePlaybackIndex(current_route, play_index, carX, carY)
            if syncedIndex ~= play_index then
                play_index = syncedIndex
                playbackDriveMode = routeDriveModeAt(current_route, play_index)
                point = current_route[play_index]
                if not point then return end
                driveMode = playbackDriveMode
                reverseMode = driveMode == DRIVE_BACK
                steerBuf = {0, 0}
            end
            local advancedIndex = advanceReversePlaybackIndex(current_route, play_index, carX, carY, false)
            if advancedIndex ~= play_index then
                local oldMode = driveMode
                play_index = advancedIndex
                playbackDriveMode = routeDriveModeAt(current_route, play_index)
                point = current_route[play_index]
                if not point then return end
                driveMode = playbackDriveMode
                reverseMode = driveMode == DRIVE_BACK
                steerBuf = {0, 0}
                if oldMode == DRIVE_BACK and driveMode == DRIVE_FORWARD then
                    startBackToForwardTransition()
                    refreshStateView()
                    return
                end
            end
        end

        if reverseMode then
            -- Backing up needs the exact recorded waypoint. Forward driving can
            -- keep the smoothed spline/lateral route behavior.
            tX, tY, tZ = point.x, point.y, point.z
            if S.bypassActive or math.abs(S.currentLateral or 0.0) > 0.05 then
                resetObstacleBypass()
                S.currentLateral = 0.0
            end
            collisionCooldown = 0
        else
            tX, tY, tZ = getSplineTarget(current_route, play_index)
        end

        if not reverseMode and play_index < #current_route then
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
                local now = os.clock()
                local targetLateral = S.lapWander + S.nudgeOffset
                local obstacleAvoidActive = updateObstacleBypass(now)
                if S.bypassActive and collisionCooldown > 0 then
                    collisionCooldown = 0
                end
                if math.abs(S.avoidLateralTarget or 0.0) > 0.05 then
                    obstacleAvoidActive = now < (S.avoidHoldUntil or 0.0) or math.abs(S.avoidLateralTarget) > 0.35
                    if obstacleAvoidActive then
                        targetLateral = S.lapWander * 0.12
                    end
                    targetLateral = targetLateral + S.avoidLateralTarget
                end
                if collisionCooldown > 0 then
                    local collisionDir = S.avoidRouteDir ~= 0 and S.avoidRouteDir or (S.routeAvoidDir ~= 0 and S.routeAvoidDir or 0)
                    local urgency = math.max(S.routeObstacleUrgency or 0.0, 0.50)
                    local collisionPush = S.bypassActive
                        and math.min(0.35, 0.12 + urgency * 0.22)
                        or (0.45 + urgency * 0.70 + math.min(0.20, collisionCooldown * 0.010))
                    if collisionDir ~= 0 then
                        targetLateral = targetLateral + collisionDir * collisionPush
                    end
                end
                if S.bypassActive then
                    targetLateral = clamp(targetLateral, -3.35, 3.35)
                end
                local lateralLerp = obstacleAvoidActive
                    and (S.bypassReturning and 0.030 or (S.routeObstacleDist > 28.0 and 0.050 or 0.070))
                    or (S.routeObstacleUrgency > 0.65 and 0.11 or (S.routeObstacleUrgency > 0.35 and 0.08 or 0.045))
                S.currentLateral = S.currentLateral + (targetLateral - S.currentLateral) * lateralLerp
                tX = tX + (-ndy / nd) * S.currentLateral
                tY = tY + (ndx / nd) * S.currentLateral
            end
        end

        draw_line(tX, tY, carX, carY, carZ, reverseMode and COLOR_ROUTE_BACK or COLOR_ROUTE_FORWARD)

        local rawCurrentSpeed = getCarSpeed(car)
        local currentSpeed = reverseMode and math.abs(rawCurrentSpeed) or rawCurrentSpeed
        local targetSpeed = (reverseMode and math.abs(point.speed or 0) or point.speed) * speedMult
        local steerTargetX, steerTargetY = tX, tY
        setSyntheticReverseKey(reverseMode)
        if S.bypassActive then
            targetSpeed = math.min(targetSpeed, 46.0)
        end

        local rejoiningRoute = reverseMode and false or handleRouteRejoinRecovery(car, carX, carY, tX, tY, currentSpeed)
        if not rejoiningRoute then
            local obsX, obsY, obsZ, obsDir, obsDist, obsSide, obsUrgency = nil, nil, nil, nil, nil, nil, nil
            if not reverseMode then
                obsX, obsY, obsZ, obsDir, obsDist, obsSide, obsUrgency = getObstacleAhead(car, tX, tY)
            end
            if obsX and collisionCooldown == 0 and not reverseMode then
                S.avoidSideHit = obsSide == true
                avoidSteerDir = avoidDir(car, obsX, obsY, tX, tY)
                S.avoidRouteDir = (obsDir and obsDir ~= 0)
                    and (obsDir < 0 and -1 or 1)
                    or routeAvoidDirFromPoint(carX, carY, tX, tY, obsX, obsY)
                S.routeAvoidDir = S.avoidRouteDir
                if obsDist then
                    S.routeObstacleDist = math.min(S.routeObstacleDist, obsDist)
                end
                local closeUrgency = obsDist and ((18.0 - obsDist) / 14.0) or 0.55
                if closeUrgency < 0.0 then closeUrgency = 0.0 end
                if closeUrgency > 1.0 then closeUrgency = 1.0 end
                S.routeObstacleUrgency = math.max(S.routeObstacleUrgency or 0.0, obsUrgency or closeUrgency)
                if not S.bypassActive and ((obsDist and obsDist < 5.5) or (obsUrgency and obsUrgency > 0.78)) then
                    collisionCooldown = (obsDist and obsDist < 4.0) and 30 or 18
                end
            end

            if (S.bypassActive or reverseMode) and collisionCooldown > 0 then
                collisionCooldown = 0
            end

            if collisionCooldown > 0 then
                collisionCooldown = collisionCooldown - 1
                if S.avoidRouteDir ~= 0 then
                    S.routeAvoidDir = S.avoidRouteDir
                end
                local avoidSteerOut = avoidSteerDir
                if S.avoidSideHit then
                    avoidSteerOut = avoidSteerDir < 0 and -128 or 128
                end
                lastSteerValue = avoidSteerOut
                setGameKeyState(0, avoidSteerOut)
                if S.avoidSideHit then
                    if currentSpeed < 16 then
                        gasLevel = 135
                    elseif currentSpeed < 34 then
                        gasLevel = 75
                    else
                        gasLevel = 0
                    end
                else
                    if currentSpeed < 12 then
                        gasLevel = 145
                    elseif currentSpeed < 28 then
                        gasLevel = 85
                    elseif currentSpeed < 42 then
                        gasLevel = 35
                    else
                        gasLevel = 0
                    end
                end
                brakeLevel = 0
                writeDriveControls(gasLevel, 0)
            elseif not reverseMode and not S.bypassActive and sharpTurnAhead(current_route, play_index) and currentSpeed > targetSpeed * 0.7 then
                turning_mechanism(steerTargetX, steerTargetY, carX, carY, car)
                if os.clock() > (S.avoidHoldUntil or 0.0) then
                    applySteerNoise()
                end
                local excess = math.max(0, currentSpeed - targetSpeed * 0.7)
                brakeLevel = math.min(255, math.floor(excess * 30))
                gasLevel = math.max(0, gasLevel - 25)
                writeDriveControls(gasLevel, brakeLevel)
            else
                if reverseMode then
                    applyReverseSteering(car, carX, carY, current_route, play_index)
                else
                    turning_mechanism(steerTargetX, steerTargetY, carX, carY, car)
                end
                if not reverseMode and os.clock() > (S.avoidHoldUntil or 0.0) then
                    applySteerNoise()
                end
                if reverseMode then
                    gasLevel = 0
                    -- Synthetic S already owns reverse. Do not also write the
                    -- brake byte here; combined inputs feel like handbrake/space
                    -- and prevent a smooth controlled backing path.
                    brakeLevel = 0
                    applyReverseAssist(car, carX, carY, tX, tY, currentSpeed, targetSpeed)
                else
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
                            local brakeCap = S.bypassActive and 95 or 255
                            local brakeGain = S.bypassActive and 12 or 30
                            brakeLevel = math.min(brakeCap, math.floor(excess * brakeGain))
                            gasLevel = math.max(0, gasLevel - 25)
                        end
                    end
                end
                writeDriveControls(gasLevel, brakeLevel)
            end
        end

        printStringNow('~g~VR Bot ~w~' .. play_index .. '/' .. #current_route .. ' ~y~' .. math.floor(currentSpeed) .. 'km/h' .. (reverseMode and ' ~b~BACK' or ''), 100)
        if not rejoiningRoute then
            _G.VR_state   = "PLAYING"
            writeSharedState("PLAYING")
        end

        if reverseMode then
            local advancedIndex = advanceReversePlaybackIndex(current_route, play_index, carX, carY, true)
            if advancedIndex ~= play_index then
                local oldMode = playbackDriveMode
                play_index = advancedIndex
                playbackDriveMode = routeDriveModeAt(current_route, play_index)
                steerBuf = {0, 0}
                if oldMode == DRIVE_BACK and playbackDriveMode == DRIVE_FORWARD then
                    startBackToForwardTransition()
                end
            end
        elseif locateCharInCar2d(PLAYER_PED, point.x, point.y, routeRadius, routeRadius, false) then
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

        if play_index > #current_route then
            if repeating then
                play_index = 1
                playbackDriveMode = routeDriveModeAt(current_route, 1)
                S.lapWander = (math.random() * 3.0) - 1.5
                gasLevel = 0; brakeLevel = 0
                S.gasLiftFrames = 0
                S.nudgeFrames = 0; S.nudgeOffset = 0.0
                S.currentLateral = 0.0
                S.reversePlaybackGraceUntil = 0.0
                S.backToForwardUntil = 0.0
                resetBumpState(true)
                S.rejoinFrames = 0; S.rejoinSteer = 0
                S.rejoinCooldownUntil = 0.0
                S.rejoinDisableUntil = os.clock() + 2.5
                resetObstacleBypass()
                S.avoidClusterCount = 0
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

    _G.VR_gas     = gasLevel
    _G.VR_brake   = brakeLevel
    _G.VR_steer   = lastSteerValue
    _G.VR_playing = os.clock()
    refreshStateView()
end

function InputHandler.handleHotkeys()
    if isKeyJustPressed(VK_F2) then
        if not recording then
            RouteRecorder.startRecording()
        else
            RouteRecorder.stopRecording()
        end
    end

    if isKeyJustPressed(VK_F10) then
        if recording then
            RouteRecorder.stopRecording()
        end
        if not playing then
            RouteFollower.startPlayback()
        else
            RouteFollower.stopPlayback()
        end
    end

    if isKeyJustPressed(VK_F11) then
        repeating = not repeating
        refreshStateView()
        showMsg(repeating and "~g~Kartojimas IJUNGTAS!" or "~r~Kartojimas ISJUNGTAS!")
    end

    if isKeyJustPressed(VK_F6) then
        if playing then
            S.manualPaused = not S.manualPaused
            syncPausedState()
            if S.manualPaused then
                if S.bumpActive then
                    stopBumpRecovery("BUMP_PAUSED")
                end
                releaseControls("PAUSED")
                showMsg("~y~Pristabdyta!")
            else
                showMsg("~g~Tesiama!")
            end
            refreshStateView()
        end
    end

    if isKeyJustPressed(VK_F7) then
        RouteFollower.stopAll()
    end

    if isKeyJustPressed(VK_F9) then
        showTrail = not showTrail
        if not showTrail then
            currentTrail = {}
            lastTrail = {}
        end
        showMsg(showTrail and "~g~Trajektorija IJUNGTA!" or "~r~Trajektorija ISJUNGTA!")
    end

    if isKeyJustPressed(VK_F3) then
        if not S.showObstacleDots then
            S.showObstacleDots = true
            S.obstacleDebugMode = 1
        elseif (S.obstacleDebugMode or 1) == 1 then
            S.obstacleDebugMode = 2
        else
            S.showObstacleDots = false
            S.obstacleDebugMode = 0
        end
        if not S.showObstacleDots then
            S.obstacleHits = {}
            S.obstacleProbes = {}
        end
        if not S.showObstacleDots then
            showMsg("~r~Kliuciu debug ISJUNGTAS!")
        elseif S.obstacleDebugMode == 2 then
            showMsg("~g~Kliuciu debug PILNAS!")
        else
            showMsg("~g~Kliuciu taskai IJUNGTI!")
        end
    end
    refreshStateView()
end

function MainLoop.drawTrailDebug()
    if not showTrail then return end
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

    local function drawRouteString(route)
        if type(route) ~= "table" or #route < 2 then return end
        local step = math.max(1, math.floor(#route / 1400))
        for i = 1, #route - 1, step do
            local p = route[i]
            local p2 = route[math.min(#route, i + step)]
            if p and p2 and getDistanceBetweenCoords2d(px, py, p.x, p.y) < 230 then
                local z1 = p.z or pz
                local z2 = p2.z or pz
                if isPointOnScreen(p.x, p.y, z1, 0.0) or isPointOnScreen(p2.x, p2.y, z2, 0.0) then
                    local sx, sy = convert3DCoordsToScreen(p.x, p.y, z1)
                    local sx2, sy2 = convert3DCoordsToScreen(p2.x, p2.y, z2)
                    local color = isRoutePointReverse(p2) and COLOR_ROUTE_BACK or COLOR_ROUTE_FORWARD
                    if color == COLOR_ROUTE_BACK then
                        renderDrawLine(sx, sy, sx2, sy2, 4, COLOR_ROUTE_BACK_OUTLINE)
                    end
                    renderDrawLine(sx, sy, sx2, sy2, 2, color)
                end
            end
        end
    end

    if not playing then
        drawRouteString(current_route)
    end
    drawTrailArrows(lastTrail,    0xCCFFFF00)
    drawTrailArrows(currentTrail, 0xCC00FFFF)
end

local function fileHasDangisScriptName(path)
    local file = io.open(path, "r")
    if not file then return false end
    local text = file:read(4096) or ""
    file:close()
    return text:find("script_name%s*%(%s*'dangis_vr'%s*%)") ~= nil
        or text:find('script_name%s*%(%s*"dangis_vr"%s*%)') ~= nil
end

local function findActiveDangisScripts()
    local found = {}
    local dir = tostring(getWorkingDirectory() or ".")
    local cmdDir = dir:gsub("/", "\\"):gsub('"', "")
    local command = 'dir /b /a-d "' .. cmdDir .. '\\*.lua" 2>nul'
    local ok, pipe = pcall(io.popen, command, "r")
    if not ok or not pipe then
        logEvent("STARTUP", "duplicate scan unavailable")
        return found
    end

    for name in pipe:lines() do
        if type(name) == "string" and name:lower():sub(-4) == ".lua" then
            local fullPath = dir .. "/" .. name
            if fileHasDangisScriptName(fullPath) then
                table.insert(found, name)
            end
        end
    end
    pipe:close()
    return found
end

local function warnDuplicateDangisScripts()
    local scripts = findActiveDangisScripts()
    if #scripts <= 1 then
        logEvent("STARTUP", "duplicate scan ok: " .. tostring(#scripts) .. " active dangis script")
        return false
    end

    local names = table.concat(scripts, ", ")
    logEvent("STARTUP", "duplicate dangis scripts detected: " .. names)
    printStringNow("~r~DANGIS WARNING: duplicate scripts active!", 6000)
    printStringNow("~y~Disable old dangis_vr copies in moonloader.", 6000)
    return true
end

local function performSafeStartupReset()
    setSyntheticReverseKey(false, true)
    S.manualPaused = false
    S.dialogPaused = false
    S.testArbotasPaused = false
    S.dialogReleaseUntil = 0.0
    S.rotateFightUntil = 0.0
    S.rotateReleaseUntil = 0.0
    S.rotateIgnoreUntil = 0.0
    S.backToForwardUntil = 0.0
    S.reversePlaybackGraceUntil = 0.0
    S.freezeRecoveryGraceUntil = 0.0
    resetBumpState(true)
    clearFreezeRecoveryOnly(os.clock())
    clearRotateTrigger()
    os.remove(freeze_flag_file)
    gasLevel = 0
    brakeLevel = 0
    lastSteerValue = 0
    pauseReleaseReason = ""
    setGameKeyState(0, 0)
    writeDriveControls(0, 0)
    _G.VR_gas = 0
    _G.VR_brake = 0
    _G.VR_steer = 0
    _G.VR_state = "IDLE"
    _G.VR_playing = os.clock()
    writeSharedState("IDLE")
    logEvent("STARTUP", "safe startup reset complete")
end

function MainLoop.initialize()
    trimDebugLogFile()
    logEvent("STARTUP", "Dangis VR v5.48 loading")
    printStringNow("~y~Dangis VR: ~w~Laukiama...", 5000)
    wait(8000)
    RouteStorage.ensurePathsDir()
    warnDuplicateDangisScripts()
    samp = getModuleHandle("samp.dll")
    performSafeStartupReset()
    refreshStateView()
    printStringNow("~g~Dangis VR v5.48 ikelta!", 3000)
    printStringNow("~w~F2-Irasyti F10-Paleisti F11-Kartoti F6-Pauze F7-Sustabdyti", 5000)
end

function MainLoop.startThreads()
    lua_thread.create(function()
        while true do
            wait(100)
            DialogBridge.update()
        end
    end)

    lua_thread.create(function()
        while true do
            wait(0)
            RecoverySystem.updateControlThread()
        end
    end)

    lua_thread.create(function()
        while true do
            wait(0)
            RouteRecorder.recordTick()
        end
    end)

    lua_thread.create(function()
        while true do
            wait(0)
            RouteFollower.updatePlayback()
        end
    end)
end

function main()
    MainLoop.initialize()
    MainLoop.startThreads()

    while true do
        wait(0)
        InputHandler.handleHotkeys()
        MainLoop.drawTrailDebug()
    end
end

