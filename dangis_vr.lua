script_name('dangis_vr')
script_version('5.49')
require 'lib.moonloader'

local VR_VERSION = "5.49"

local recording = false
local playing = false
local repeating = false
local paused = false
local current_route = {}
local play_index = 1
local current_name -- from CONFIG.route.defaultName
local paths_dir = getWorkingDirectory() .. "/dangis_paths/"
local shared_state_file = getWorkingDirectory() .. "/dangis_vr_state.txt"
local freeze_flag_file = getWorkingDirectory() .. "/dangis_vr_freeze.flag"
local rotate_flag_file = getWorkingDirectory() .. "/dangis_vr_rotate.flag"
local dialog_flag_file = getWorkingDirectory() .. "/dangis_vr_dialog.flag"
local debug_log_file = getWorkingDirectory() .. "/dangis_vr_debug.log"
local start_x, start_y = 0, 0
local recordLeftStart = false
-- routeRadius, recordingDelay, LOOKAHEAD and current_name are loaded from CONFIG.route.
local routeRadius
local tick = 0
local recordingDelay
local lastRecordHeading = 0

local lastSteerValue = 0
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
local reverseActive = false
-- Playback thresholds were tuned in frames; frameScale converts the real frame
-- time into those reference frames so behaviour does not change with FPS.
local frameScale = 1.0
local lastPlaybackTickAt = nil
local commandJob = nil



local showTrail = false
local currentTrail = {}
local lastTrail = {}
local trailTick = 0

local samp = 0

local S = {
    gasLiftFrames = 0, nextGasLift = 0,
    lapWander = 0.0,
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
    frozenByAdmin = false, refreshSent = false,
    -- A test_freeze flag that recovery already handled; cleared when the flag goes away.
    externalFreezeAck = false,
    recentDriveSpeed = 0.0, recentDriveUntil = 0.0,
    testArbotasPaused = false,
    dialogPaused = false,
    dialogReleaseUntil = 0.0,
    freezeTestLatched = false,
    freezeRecoveryMode = "",
    freezeRefreshSentAt = 0.0,
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
        radius = 8.0,           -- distance that counts as reaching a waypoint
        recordingDelay = 80,    -- ms between recorded points
        lookahead = LOOKAHEAD,  -- points ahead used for the steering target
        pathsDir = paths_dir,
        defaultName = "route1", -- saved as <name>.txt; the previous copy is kept as .txt.bak
    },
    controls = {
        steerKey = 0,
        -- CPad NewState buttons (GTA SA 1.0 US). In a car: Cross = accelerate,
        -- Square = brake (reverses once the car has stopped), RightShoulder1 = handbrake.
        gasAddress = 0xB73458 + 0x20,
        footBrakeAddress = 0xB73458 + 0x1C,
        handbrakeAddress = 0xB73458 + 0x0C,
        -- "foot": slow down with the real brake. "hand": pre-5.49 behaviour,
        -- which (unintentionally) braked with the handbrake.
        brakeMode = "foot",
        footBrakeMinSpeed = 1.0, -- never hold the brake below this forward speed (it would reverse)
        -- "bangbang": full-lock steering as before. "smooth": proportional steering.
        steering = "bangbang",
        smoothFullLockDegrees = 25.0,
    },
    timing = {
        -- The frame-counted thresholds were tuned at about this FPS (measured
        -- from dangis_vr_debug.log); they now follow real frame time instead.
        referenceFps = 30,
        minFrameScale = 0.25,
        maxFrameScale = 2.0,
    },
    obstacle = {
        models = AVOID_OBJECT_MODELS,
        scanEveryFrames = 6,
        -- Route points further away are not ray-cast; hits beyond ~62 m are ignored anyway.
        corridorRadius = 70.0,
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
        bumpMinRecentSpeed = 2.0,
        bumpResyncBackPoints = 10,
        bumpResyncAheadPoints = 45,
        bumpResyncMaxDistance = 28.0,
        bumpFreezeEscalateSeconds = 1.2,
        bumpFreezeEscalateDistance = 0.25,
        forwardNoProgressFrames = 44,
        forwardNoProgressGas = 80,
        forwardNoProgressSpeed = 8.0,
        forwardProgressEpsilon = 0.06,
        refreshRetrySeconds = 0.75,
        -- Freezes started by test_freeze.lua go through the same states but
        -- only send a real /refresh to the server when this is true.
        typeRefreshInFreezeTest = false,
    },
    dialog = {
        sharedFile = dialog_flag_file,
    },
    debug = {
        enabled = false,
        logToFile = true,
        logFile = debug_log_file,
        maxLogBytes = 65536,
        trimCheckEvery = 50,
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

routeRadius = CONFIG.route.radius
recordingDelay = CONFIG.route.recordingDelay
LOOKAHEAD = CONFIG.route.lookahead
current_name = CONFIG.route.defaultName

-- Guarded raw memory reads (IsBadReadPtr) for dialog, entity and vehicle data.
-- Plain FFI reads are used because readMemory inside pcall can kill a
-- MoonLoader coroutine.
local Mem = { ffi = nil, k32 = nil }

function Mem.init()
    if Mem.ffi ~= nil then return Mem.ffi ~= false end
    local ok, ffi = pcall(require, "ffi")
    if not ok then
        Mem.ffi = false
        return false
    end
    pcall(ffi.cdef, "int IsBadReadPtr(const void* lp, unsigned int ucb);")
    local k32ok, k32 = pcall(ffi.load, "kernel32")
    if not k32ok then
        Mem.ffi = false
        return false
    end
    Mem.ffi, Mem.k32 = ffi, k32
    return true
end

function Mem.read(ctype, addr, size)
    if not addr or addr < 0x10000 or addr > 0x7FFFFFFF then return nil end
    if not Mem.init() then return nil end
    if Mem.k32.IsBadReadPtr(Mem.ffi.cast("void*", addr), size) ~= 0 then return nil end
    return tonumber(Mem.ffi.cast(ctype, addr)[0])
end

function Mem.readByte(addr) return Mem.read("uint8_t*", addr, 1) end
function Mem.readWord(addr) return Mem.read("uint16_t*", addr, 2) end
function Mem.readDword(addr) return Mem.read("uint32_t*", addr, 4) end
function Mem.readFloat(addr) return Mem.read("float*", addr, 4) end

-- Keyboard and focus helpers. Synthetic keys are only used to type chat
-- commands, and only while this game's window is the active window, so
-- nothing is ever typed into another program.
local Win32 = { ready = nil, held = {}, focusCheckedAt = -1.0, focusCached = true }

function Win32.init()
    if Win32.ready ~= nil then return Win32.ready end
    Win32.ready = false
    local ok, ffi = pcall(require, "ffi")
    if not ok then return false end
    pcall(ffi.cdef, "void keybd_event(unsigned char bVk, unsigned char bScan, unsigned long dwFlags, unsigned long* dwExtraInfo);")
    pcall(ffi.cdef, "short GetAsyncKeyState(int vKey);")
    pcall(ffi.cdef, "short VkKeyScanA(char ch);")
    pcall(ffi.cdef, "unsigned int MapVirtualKeyA(unsigned int uCode, unsigned int uMapType);")
    pcall(ffi.cdef, "void* GetForegroundWindow(void);")
    pcall(ffi.cdef, "unsigned long GetWindowThreadProcessId(void* hWnd, unsigned long* lpdwProcessId);")
    pcall(ffi.cdef, "unsigned long GetCurrentProcessId(void);")
    local u32ok, u32 = pcall(ffi.load, "user32")
    if not u32ok then return false end
    local k32ok, k32 = pcall(ffi.load, "kernel32")
    Win32.ffi, Win32.u32 = ffi, u32
    Win32.k32 = k32ok and k32 or nil
    Win32.ready = true
    return true
end

-- True while a window of this process (the game or SA-MP) is in front.
-- Unknown -> true, which keeps the pre-5.49 behaviour.
function Win32.isGameForeground()
    local now = os.clock()
    if now - Win32.focusCheckedAt < 0.05 then return Win32.focusCached end
    Win32.focusCheckedAt = now
    local focused = true
    if Win32.init() and Win32.k32 then
        local ok, result = pcall(function()
            local hwnd = Win32.u32.GetForegroundWindow()
            if hwnd == nil then return false end
            local pid = Win32.ffi.new("unsigned long[1]")
            Win32.u32.GetWindowThreadProcessId(hwnd, pid)
            return tonumber(pid[0]) == tonumber(Win32.k32.GetCurrentProcessId())
        end)
        if ok then focused = result end
    end
    Win32.focusCached = focused
    return focused
end

function Win32.keyDown(vk)
    if not Win32.init() then return false end
    local ok, state = pcall(Win32.u32.GetAsyncKeyState, vk)
    state = ok and tonumber(state) or 0
    return state < 0
end

-- Real keyboards always send a hardware scan code; games reading the
-- keyboard through DirectInput ignore key events without one.
function Win32.scanCode(vk)
    local ok, scan = pcall(Win32.u32.MapVirtualKeyA, vk, 0)
    scan = ok and tonumber(scan) or 0
    return scan % 256
end

function Win32.press(vk)
    if not Win32.init() then return false end
    Win32.u32.keybd_event(vk, Win32.scanCode(vk), 0, nil)
    Win32.held[vk] = true
    return true
end

function Win32.release(vk)
    if not Win32.init() then return false end
    Win32.u32.keybd_event(vk, Win32.scanCode(vk), 2, nil) -- KEYEVENTF_KEYUP
    Win32.held[vk] = nil
    return true
end

function Win32.releaseHeld()
    for vk in pairs(Win32.held) do
        Win32.release(vk)
    end
end

function Win32.releaseKeys(keys)
    for _, vk in ipairs(keys) do
        Win32.release(vk)
    end
end

-- Optional MoonLoader functions, looked up once instead of on every call.
local API = {}
local function optionalApi(...)
    for _, name in ipairs({...}) do
        local fn = _G[name]
        if type(fn) == "function" then return fn, name end
    end
    return nil, nil
end
API.objectModel, API.objectModelName = optionalApi("getObjectModel", "getObjectModelId", "getObjectModelID", "getObjectModelIndex")
API.closestObject = optionalApi("getClosestObject")
API.closestCar = optionalApi("getClosestCar")
API.allObjects = optionalApi("getAllObjects")
API.carPointer = optionalApi("getCarPointer")

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

-- Keeps the newest half of the log when it grows past maxLogBytes, instead of
-- wiping it. Checked at startup and every trimCheckEvery writes.
local function trimDebugLogFile()
    if not CONFIG.debug.logToFile then return end
    local path = CONFIG.debug.logFile or debug_log_file
    local maxBytes = CONFIG.debug.maxLogBytes or 65536
    local file = io.open(path, "rb")
    if not file then return end
    local size = file:seek("end") or 0
    if size <= maxBytes then
        file:close()
        return
    end
    local keep = math.floor(maxBytes / 2)
    file:seek("set", size - keep)
    local tail = file:read("*a") or ""
    file:close()
    local firstNewline = tail:find("\n", 1, true)
    if firstNewline then
        tail = tail:sub(firstNewline + 1)
    end
    local out = io.open(path, "wb")
    if not out then return end
    out:write(string.format("[%.3f] [LOG] trimmed older entries\n", os.clock()))
    out:write(tail)
    out:close()
end

local logWritesSinceTrim = 0

local function logEvent(category, message)
    if not CONFIG.debug.logToFile then return end
    local file = io.open(CONFIG.debug.logFile or debug_log_file, "a")
    if not file then return end
    file:write(string.format("[%.3f] [%s] %s\n", os.clock(), tostring(category or "INFO"), tostring(message or "")))
    file:close()
    logWritesSinceTrim = logWritesSinceTrim + 1
    if logWritesSinceTrim >= (CONFIG.debug.trimCheckEvery or 50) then
        logWritesSinceTrim = 0
        trimDebugLogFile()
    end
end

local function clampPadValue(value)
    value = math.floor(tonumber(value) or 0)
    if value < 0 then return 0 end
    if value > 255 then return 255 end
    return value
end

-- Writes this frame's pedals into the game pad. Nothing is written while the
-- route is not playing, so a stopped bot never overrides the player's keys.
-- gas/brake are 0..255. reverse=true holds the brake button with no gas,
-- which is how GTA reverses once the car has stopped.
local function writeDriveControls(gas, brake, reverse)
    reverseActive = false
    if not playing then return end
    if S.freezeTestLatched or S.frozenByAdmin then
        gas, brake, reverse = 0, 0, false
    end
    local controls = CONFIG.controls
    gas = clampPadValue(gas)
    brake = clampPadValue(brake)
    local footBrake, handbrake = 0, 0
    if reverse then
        gas = 0
        footBrake = 255
        reverseActive = true
    elseif brake > 0 then
        local forwardSpeed = S.forwardSpeed
        if controls.brakeMode == "foot" and forwardSpeed ~= nil then
            -- Holding the brake near standstill would start reversing.
            if forwardSpeed > (controls.footBrakeMinSpeed or 1.0) then
                footBrake = brake
            end
        else
            handbrake = brake
        end
    end
    writeMemory(controls.gasAddress, 2, gas, false)
    writeMemory(controls.footBrakeAddress, 2, footBrake, false)
    if controls.brakeMode ~= "foot" or handbrake > 0 then
        writeMemory(controls.handbrakeAddress, 2, handbrake, false)
    end
end

function dbg(category, message)
    category = tostring(category or "INFO")
    logEvent(category:upper(), message)
    if not CONFIG.debug.enabled then return end
    if not CONFIG.debug.categories[category:lower()] then return end
    printStringNow(string.format("~w~[%s] %s", category, tostring(message)), 1000)
end

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

local function getAvoidObjectModel(obj)
    if not obj or obj == 0 or not API.objectModel then return nil end
    local ok, modelId = pcall(API.objectModel, obj)
    modelId = ok and tonumber(modelId) or nil
    if modelId and modelId > 0 then return modelId end
    return nil
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

-- processLineOfSight reports the hit entity as a raw CEntity pointer, not a
-- script handle, so its type and model are read from the entity itself.
local function collisionEntityPointer(colPoint)
    if not colPoint then return nil end
    local ok, entity = pcall(function() return colPoint.entity end)
    entity = ok and tonumber(entity) or nil
    if entity and entity >= 0x10000 then return entity end
    return nil
end

local function collisionObjectModelId(colPoint)
    local entity = collisionEntityPointer(colPoint)
    if not entity then return nil end
    local modelId = Mem.readWord(entity + 0x22) -- CEntity::m_nModelIndex
    if modelId and modelId > 0 then return modelId end
    return nil
end

-- GTA entity types: 1 building, 2 vehicle, 3 ped, 4 object, 5 dummy.
local function collisionEntityType(colPoint)
    if not colPoint then return nil end
    local ok, entityType = pcall(function() return colPoint.entityType end)
    entityType = ok and tonumber(entityType) or nil
    if entityType then return entityType end
    local entity = collisionEntityPointer(colPoint)
    local typeByte = entity and Mem.readByte(entity + 0x36) -- low 3 bits = m_nType
    return typeByte and (typeByte % 8) or nil
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

-- GTA headings run counter-clockwise from north: the nose points along
-- (-sin h, cos h).
local function getRecordingForwardAxes(heading)
    local h = math.rad(heading or 0.0)
    return -math.sin(h), math.cos(h)
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
        -- The previous recording stays available as <name>.txt.bak.
        os.remove(bakPath)
        if storageFileExists(path) then
            if not os.rename(path, bakPath) then
                copyStorageFile(path, bakPath)
                os.remove(path)
            end
        end
        if os.rename(tmpPath, path) then
            return true
        end
        if copyStorageFile(tmpPath, path) then
            os.remove(tmpPath)
            return true
        end
        if storageFileExists(bakPath) then
            copyStorageFile(bakPath, path)
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
    local relative = math.rad(getHeadingFromVector2d(posX - carPosX, posY - carPosY) + math.abs(getCarHeading(car) - 360.0))
    local heading = getHeadingFromVector2d(math.deg(math.sin(relative)), math.deg(math.cos(relative)))
    local steer
    if CONFIG.controls.steering == "smooth" then
        -- Signed angle to the target: positive = target on the right.
        local err = heading <= 180.0 and heading or heading - 360.0
        local fullLock = CONFIG.controls.smoothFullLockDegrees or 25.0
        if math.abs(err) < 0.75 then
            steer = 0
        else
            steer = math.floor(clamp(err / fullLock * 128.0, -128.0, 128.0) + 0.5)
        end
    elseif heading > 180.0 and 355.0 > heading then
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

-- Player input only counts while the game window is active; keys typed into
-- other programs must not trigger OVERRIDE.
local function isPhysicalKeyDown(vk)
    if not Win32.isGameForeground() then return false end
    if isKeyDown(vk) then return true end
    return Win32.keyDown(vk)
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

local lastSharedStateText = nil
local lastSharedStateWriteAt = -1.0

-- Read by hud_aswd.lua and test_freeze.lua. A new state is written at once;
-- an unchanged one at most every 50 ms instead of every frame.
-- Lines: state, gas, brake, steer, timestamp, reversing (1/0).
local function writeSharedState(state)
    state = tostring(state or "IDLE")
    local now = os.clock()
    if state == lastSharedStateText and now - lastSharedStateWriteAt < 0.05 then return end
    local file = io.open(shared_state_file, "w")
    if not file then return end
    file:write(state .. "\n")
    file:write(tostring(math.floor(gasLevel or 0)) .. "\n")
    file:write(tostring(math.floor(brakeLevel or 0)) .. "\n")
    file:write(tostring(math.floor(lastSteerValue or 0)) .. "\n")
    file:write(string.format("%.3f\n", now))
    file:write((reverseActive and "1" or "0") .. "\n")
    file:close()
    lastSharedStateText = state
    lastSharedStateWriteAt = now
    if state ~= lastLoggedSharedState then
        logEvent("STATE", tostring(lastLoggedSharedState or "nil") .. " -> " .. state)
        lastLoggedSharedState = state
    end
end

-- test_freeze.lua signals through dangis_vr_freeze.flag (checked at most every 50 ms).
-- forceRead: skip the cache. The control thread does this once per frame, so a
-- new flag is seen in the first frame it exists and outranks bump recovery.
local freezeFlagCached, freezeFlagCheckedAt = false, -1.0
local function sharedFreezeActive(forceRead)
    local now = os.clock()
    if forceRead or now - freezeFlagCheckedAt >= 0.05 then
        freezeFlagCached = fileExists(freeze_flag_file)
        freezeFlagCheckedAt = now
    end
    return freezeFlagCached
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
end

local function sharedDialogMode()
    return readSharedFile(dialog_flag_file)
end

local function isSampDialogActive()
    if samp == 0 then return false end
    local dPtr = Mem.readDword(samp + 0x21A0B8)
    if not dPtr or dPtr == 0 then return false end
    if dPtr < 0x01000000 or dPtr > 0x7FFFFFFF then return false end
    return Mem.readDword(dPtr + 0x28) == 1
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
    pauseReleaseReason = reason or pauseReleaseReason or "SAFE"
    gasLevel = 0
    brakeLevel = 0
    lastSteerValue = 0
    if playing then
        setGameKeyState(0, 0)
        writeDriveControls(0, 0)
        if freezeRecoveryOwnsControls() then
            -- foot-brake mode never writes the handbrake; a freeze neutralises it too
            writeMemory(CONFIG.controls.handbrakeAddress, 2, 0, false)
        end
    end
    reverseActive = false
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
    setGameKeyState(0, 0)
    writeDriveControls(255, 0)
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

-- Nearest point searched around the current index first, so a route that
-- crosses or runs close to itself cannot make the bot jump to another part of
-- the lap. Falls back to the whole route when nothing nearby is within maxDist.
local function findNearestWaypointNear(route, carX, carY, centerIdx, back, ahead, maxDist)
    local n = #route
    if n == 0 then return 1 end
    centerIdx = math.max(1, math.min(tonumber(centerIdx) or 1, n))
    local best, bestDist = centerIdx, math.huge
    for i = math.max(1, centerIdx - back), math.min(n, centerIdx + ahead) do
        local d = getDistanceBetweenCoords2d(carX, carY, route[i].x, route[i].y)
        if d < bestDist then bestDist = d; best = i end
    end
    if bestDist <= maxDist then return best end
    return findNearestWaypoint(route, carX, carY)
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
    resetBumpState(false)
    S.backToForwardUntil = 0.0
    S.freezeTestLatched = true
    S.freezeRecoveryMode = mode or "real"
    S.frozenByAdmin = true
    S.refreshSent = false
    S.refreshJob = nil
    S.refreshBlockedReason = nil
    S.freezeRefreshSentAt = 0.0
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
            play_index = findNearestWaypointNear(current_route, cx, cy, play_index, 20, 150, 25.0)
        end
    end

    S.freezeTestLatched = false
    S.freezeRecoveryMode = ""
    S.frozenByAdmin = false
    S.refreshSent = false
    S.refreshJob = nil
    -- A test flag that is still set has been handled: hold still until it is
    -- removed instead of starting another recovery (and another /refresh).
    S.externalFreezeAck = sharedFreezeActive()
    S.freezeRefreshSentAt = 0.0
    S.freezeReleaseUntil = 0.0
    S.freezeRefreshAt = 0.0
    S.freezeResumeDelay = 0.0
    S.freezeRecoveryGraceUntil = os.clock() + (CONFIG.recovery.freezeRecoveryGraceSeconds or 2.1)
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

-- Per-frame smoothing rates were tuned at CONFIG.timing.referenceFps; this
-- gives the same response per second at any frame rate.
local function scaledLerp(rate)
    return 1.0 - (1.0 - rate) ^ frameScale
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

        S.bypassOffset = S.bypassOffset + (wantedOffset - S.bypassOffset) * scaledLerp(0.16)
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
        S.avoidLateralTarget = (S.avoidLateralTarget or 0.0) * (0.985 ^ frameScale)
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

local function applySteerNoise()
    if steerNoiseDuration > 0 then
        steerNoiseDuration = steerNoiseDuration - 1
        lastSteerValue = 0
        setGameKeyState(0, 0)
    elseif steerNoiseCooldown > 0 then
        steerNoiseCooldown = steerNoiseCooldown - 1
    elseif math.random(100) <= 10 then
        steerNoiseDuration = math.random(1, 3)
        steerNoiseCooldown = math.random(8, 30)
        lastSteerValue = 0
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
        return bestHit.x, bestHit.y, bestHit.avoidDir or 0, bestHit.worldDist, bestHit.sideScan == true, bestHit.urgency or obstacleUrgency(bestHit)
    end

    local carX, carY, carZ = getCarCoordinates(car)
    local dx = targetX - carX
    local dy = targetY - carY
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.1 then return nil end
    local nx, ny = dx / d, dy / d
    local checkX = carX + nx * 12
    local checkY = carY + ny * 12
    if API.closestCar then
        local ok1, nearest = pcall(API.closestCar, checkX, checkY, carZ, 5.0, {}, 0)
        if ok1 and nearest and nearest ~= 0 and nearest ~= car then
            local ox, oy = getCarCoordinates(nearest)
            return ox, oy, 0, getDistanceBetweenCoords2d(carX, carY, ox, oy), false, 0.65
        end
    end
    if API.closestObject then
        local ok2, nearObj = pcall(API.closestObject, checkX, checkY, carZ, 4.0, false, false)
        if ok2 and nearObj and nearObj ~= 0 then
            local avoidable = isAvoidableObject(nearObj)
            if not avoidable then return nil end
            local ok3, ox, oy = readObjectCoordinates(nearObj)
            if ok3 and ox then return ox, oy, 0, getDistanceBetweenCoords2d(carX, carY, ox, oy), false, 0.60 end
        end
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

-- GTA headings run counter-clockwise from north, so the nose points along
-- (-sin h, cos h). Returns forward x/y and left x/y.
local function getCarForwardAxes(car)
    local heading = math.rad(getCarHeading(car))
    local nx = -math.sin(heading)
    local ny = math.cos(heading)
    return nx, ny, -ny, nx
end

-- Signed speed along the car's nose in getCarSpeed units (m/s): positive =
-- rolling forward, negative = rolling backward, nil if it cannot be read.
local function getCarForwardSpeed(car)
    if not API.carPointer then return nil end
    local ok, ptr = pcall(API.carPointer, car)
    ptr = ok and tonumber(ptr) or nil
    if not ptr or ptr == 0 then return nil end
    local vx = Mem.readFloat(ptr + 0x44) -- CPhysical::m_vecMoveSpeed
    local vy = Mem.readFloat(ptr + 0x48)
    if not vx or not vy then return nil end
    local fx, fy = getCarForwardAxes(car)
    return (vx * fx + vy * fy) * 50.0
end

-- Skips play_index ahead when the car has already passed its target point.
function handleRouteRejoinRecovery(car, carX, carY, targetX, targetY, currentSpeed)
    local now = os.clock()
    if now < (S.rejoinDisableUntil or 0.0) or now < (S.rejoinCooldownUntil or 0.0) then
        return
    end
    if play_index <= 20 or #current_route == 0 or currentSpeed > 25.0 then
        return
    end

    local fx, fy, lx, ly = getCarForwardAxes(car)
    local relX = targetX - carX
    local relY = targetY - carY
    local forward = relX * fx + relY * fy
    local lateral = relX * lx + relY * ly
    local dist = math.sqrt(relX * relX + relY * relY)

    if forward > -1.5 or dist > 22.0 or math.abs(lateral) < 2.0 then
        return
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
        S.rejoinCooldownUntil = now + 1.5
        S.currentLateral = 0.0
        resetObstacleBypass()
        S.avoidClusterCount = 0
        writeSharedState("REJOIN_SKIP")
    end
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

local function isReverseRecordingInputActive()
    local sDown = isPhysicalKeyDown(0x53)
    local wDown = isPhysicalKeyDown(0x57)
    -- Pad Square is the brake/reverse button (keyboard S or a gamepad).
    local brakeInput = readControlByte(CONFIG.controls.footBrakeAddress)
    return (sDown or brakeInput > 150) and not wDown
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

    -- GTA entity types: 1 building, 2 vehicle, 3 ped, 4 object, 5 dummy.
    local function classifyEntityType(entityType)
        if entityType == 2 then return "car" end
        if entityType == 3 then return "ped" end
        if entityType == 4 then return "obj" end
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
            local entityType = collisionEntityType(colPoint)
            local kind = classifyEntityType(entityType)
            local modelId = collisionObjectModelId(colPoint)
            if (entityType == 4 or entityType == nil) and shouldAvoidObjectModel(modelId) then
                kind = "obj"
            elseif kind ~= "car" then
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
        if not API.closestObject then return end
        local ok, obj = pcall(API.closestObject, centerX, centerY, centerZ, radius or 1.85, false, false)
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
        if not API.allObjects then return end
        local ok, objects = pcall(API.allObjects)
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

    -- Only ray-cast route points near the car: hits further than ~62 m never
    -- influence avoidance, and the far corridor was most of the scan cost.
    local corridorRadius = CONFIG.obstacle.corridorRadius or 70.0
    for i = idx + 6, scanRouteCorridor and math.min(idx + 320, n) or idx + 5, 3 do
        local p = route[i]
        local prev = route[math.max(1, i - 1)]
        if getDistanceBetweenCoords2d(carX, carY, p.x, p.y) <= corridorRadius then
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

-- The bot reverses through the pad, not the S key, so any W/A/S/D/Space
-- press seen here is the player.
local function isPlayerControlling()
    return isPhysicalKeyDown(0x57)
        or isPhysicalKeyDown(0x53)
        or isPhysicalKeyDown(0x41)
        or isPhysicalKeyDown(0x44)
        or isPhysicalKeyDown(0x20)
end

local function isReversePlaybackContext(route, pidx)
    if not playing or type(route) ~= "table" or #route == 0 then return false end
    pidx = math.max(1, math.min(tonumber(pidx) or 1, #route))
    local first = math.max(1, pidx - 2)
    local last = math.min(#route, pidx + (CONFIG.recovery.reverseLookaheadPoints or 90))
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
    S.refreshJob = nil
    S.freezeRefreshSentAt = 0.0
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
    resetBumpState(false)
    gasLevel = 0
    brakeLevel = 0
    lastSteerValue = 0
    if playing then
        setGameKeyState(0, 0)
    end
    writeDriveControls(0, 0)
    if reason then
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
    local minDistance = (CONFIG.recovery.bumpReverseDistanceMin or 2.0) + speedFactor * 0.9
    local maxDistance = (CONFIG.recovery.bumpReverseDistanceMax or 6.0) + speedFactor * 0.8
    local reverseMin = CONFIG.recovery.bumpReverseMinSeconds or 0.85
    local reverseSeconds = reverseMin + speedFactor * ((CONFIG.recovery.bumpReverseMaxSeconds or 1.65) - reverseMin)

    -- Bump recovery is a simple straight back-away move (steering held at 0).
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
    S.bumpSteer = 0
    resetForwardNoProgress()
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
        gasLevel = 0
        brakeLevel = 0
        lastSteerValue = S.bumpSteer or 0
        setGameKeyState(0, lastSteerValue)
        writeDriveControls(0, 0, true)
        writeSharedState("BUMP_BACK")
        printStringNow(string.format("~y~BUMP BACK ~w~%.1fm", backed), 100)

        local reverseElapsed = now - (S.bumpStartedAt or now)
        if reverseElapsed >= (CONFIG.recovery.bumpFreezeEscalateSeconds or 1.2)
            and backed <= (CONFIG.recovery.bumpFreezeEscalateDistance or 0.25) then
            logEvent("RECOVERY", string.format("bump could not move %.2fm in %.2fs; escalating to freeze", backed, reverseElapsed))
            startFreezeRecovery("real")
            return true
        end

        local backedEnough = backed >= (S.bumpMinDistance or 2.0)
        local backedTooFar = backed >= (S.bumpMaxDistance or 6.0)
        local hardTimeDone = now >= ((S.bumpStartedAt or now) + (CONFIG.recovery.bumpReverseHardMaxSeconds or 2.6))
        local plannedTimeDone = now >= (S.bumpUntil or now)
        if backedTooFar or hardTimeDone or (plannedTimeDone and backedEnough) then
            S.bumpPhase = "coast"
            S.bumpUntil = now + (CONFIG.recovery.bumpCoastSeconds or 0.32)
            gasLevel = 0
            brakeLevel = 0
            lastSteerValue = 0
            setGameKeyState(0, 0)
            writeDriveControls(0, 0)
        end
        return true
    end

    if S.bumpPhase == "coast" then
        gasLevel = 0
        brakeLevel = 0
        lastSteerValue = 0
        setGameKeyState(0, 0)
        writeDriveControls(0, 0)
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

    -- Expected progress per frame shrinks with shorter frames, so both the
    -- epsilon and the counter are in reference frames.
    local epsilon = (CONFIG.recovery.forwardProgressEpsilon or 0.06) * frameScale
    local lastDist = S.forwardNoProgressDist or dist
    if dist >= lastDist - epsilon then
        S.forwardNoProgressFrames = (S.forwardNoProgressFrames or 0) + frameScale
    else
        S.forwardNoProgressFrames = math.max(0, (S.forwardNoProgressFrames or 0) - 3 * frameScale)
    end
    S.forwardNoProgressDist = dist

    return (S.forwardNoProgressFrames or 0) >= (CONFIG.recovery.forwardNoProgressFrames or 44)
end

-- Types a chat command with the keyboard. Returns a job whose done / ok /
-- finishedAt fields the caller polls, or nil and a reason when typing cannot
-- start. It never types while another window is active or a SA-MP dialog is
-- open, and it stops (releasing every key) if either happens mid-way.
local function typeSAMPCommand(cmd)
    cmd = tostring(cmd or "")
    if cmd == "" then return nil, "empty command" end
    if commandJob and not commandJob.done then return nil, "already typing" end
    if not Win32.init() then return nil, "user32 unavailable" end
    if not Win32.isGameForeground() then return nil, "game window not active" end
    if isSampDialogActive() then return nil, "dialog open" end

    local job = { cmd = cmd, done = false, ok = false, cancelled = false, startedAt = os.clock() }
    commandJob = job

    local function blockedReason()
        if job.cancelled then return "cancelled" end
        if not Win32.isGameForeground() then return "game window lost focus" end
        if isSampDialogActive() then return "dialog opened" end
        return nil
    end

    local function tapKey(vk, holdMs)
        Win32.press(vk)
        wait(holdMs or 35)
        Win32.release(vk)
    end

    local function tapCharacter(ch)
        local byte = string.byte(ch)
        if not byte then return false end
        local vk
        local needShift = false
        if byte >= 97 and byte <= 122 then
            vk = byte - 32
        elseif byte >= 65 and byte <= 90 then
            vk = byte
            needShift = true
        elseif byte >= 48 and byte <= 57 then
            vk = byte
        else
            local ok, scan = pcall(Win32.u32.VkKeyScanA, byte)
            scan = ok and tonumber(scan) or -1
            if scan >= 0 then
                vk = scan % 256
                needShift = math.floor(scan / 256) % 2 == 1
            elseif ch == "/" then
                vk = 0xBF -- VK_OEM_2, slash on common GTA/SA-MP keyboard layouts.
            else
                return false
            end
        end
        if needShift then Win32.press(0x10) end
        tapKey(vk, 30)
        if needShift then Win32.release(0x10) end
        return true
    end

    lua_thread.create(function()
        Win32.releaseKeys({0x10, 0x11, 0x12})
        local reason = blockedReason()
        if not reason then
            tapKey(0x54, 50) -- T opens SA-MP chat in this setup.
            wait(350)
        end
        for i = 1, #cmd do
            reason = reason or blockedReason()
            if reason then break end
            if not tapCharacter(cmd:sub(i, i)) then
                logEvent("INPUT", "typeSAMPCommand skipped character at " .. tostring(i))
            end
            wait(45)
        end
        if not reason then
            wait(180)
            reason = blockedReason()
        end
        if not reason then
            tapKey(0x0D, 40)
        end
        Win32.releaseHeld()
        job.reason = reason
        job.ok = reason == nil
        job.finishedAt = os.clock()
        job.done = true
        if reason then
            logEvent("INPUT", "typing '" .. cmd .. "' stopped: " .. reason)
        end
    end)
    return job
end

local function handleFreeze(car, route, pidx)
    local cx, cy = getCarCoordinates(car)
    local speed = getCarSpeed(car)
    local absSpeed = math.abs(speed or 0.0)
    local moved = getDistanceBetweenCoords2d(cx, cy, lastX, lastY)
    local now = os.clock()
    local externalFreeze = sharedFreezeActive()

    if externalFreeze then
        if not S.freezeTestLatched and not S.externalFreezeAck then
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
        suddenStopFrames = suddenStopFrames + frameScale
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
        freezeTimer = freezeTimer + frameScale
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
    local triggered = diff > 150 or rotateMode ~= nil
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
        while playing and os.clock() < untilTime do
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
    -- Other scripts can only signal through files: each MoonLoader script has
    -- its own Lua state, so their _G values are never visible here.
    local fakeDialogMode = sharedDialogMode()
    if fakeDialogMode == "fake_arbotas" then
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
    if S.testArbotasPaused then
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
    RouteFollower.clearTransientState()
    releaseControls("REC_START")
    recording = true
    playing = false
    current_route = {}
    recordReverseFrames = 0
    recordForwardBrakeFrames = 0
    recordDriveMode = DRIVE_FORWARD
    recordLeftStart = false
    start_x, start_y = getCharCoordinates(PLAYER_PED)
    lastRecordHeading = getCarHeading(storeCarCharIsInNoSave(PLAYER_PED))
    tick = os.clock() * 1000
    dbg("route", "recording started")
    showMsg("~g~Irasymas pradetas! Grizk i starta uzdaryt kilpa!")
    return true
end

-- prefix: optional text shown before the "saved" message.
function RouteRecorder.stopRecording(prefix)
    recording = false
    current_route = normalizeRouteReverseFlags(current_route)
    if #current_route < 2 then
        showMsg((prefix or "") .. "~r~Per mazai tasku - kelias neissaugotas!")
    elseif RouteStorage.save(current_name, current_route) then
        RouteStorage.logRouteSummary(current_name, current_route, "saved")
        showMsg((prefix or "") .. "~g~Kelias issaugotas! Tasku: " .. #current_route)
    else
        logEvent("ROUTE", "saving " .. tostring(current_name) .. " failed")
        showMsg((prefix or "") .. "~r~Nepavyko issaugoti kelio!")
    end
end

function RouteRecorder.recordTick()
    if not recording then return end
    if not isCharInAnyCar(PLAYER_PED) then
        -- Keep what was recorded instead of silently dropping it.
        RouteRecorder.stopRecording("~r~Irasymas sustabdytas - islejai masina!~n~")
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
        local reverseIntent = isReverseRecordingInputActive()
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
        printStringNow('~g~Irasymas ~w~X:'..math.floor(posX)..' Y:'..math.floor(posY)..' G:'..math.floor(speed * 3.6)..modeText, 1000)
        local dist = getDistanceBetweenCoords2d(posX, posY, start_x, start_y)
        if dist > 20.0 then
            recordLeftStart = true
        end
        -- Close the loop only after the car has left the start area; points are
        -- recorded while standing still, so waiting ~4 s at the start used to
        -- end the recording immediately.
        if recordLeftStart and dist < 5.0 and #current_route > 50 then
            recording = false
            current_route = normalizeRouteReverseFlags(current_route)
            if RouteStorage.save(current_name, current_route) then
                RouteStorage.logRouteSummary(current_name, current_route, "saved_loop")
                showMsg("~g~Kilpa uzdaryta! Issaugota: " .. current_name)
            end
        end
    end
end

ObstacleAvoidance.scanObstacles = scanRouteAhead
ObstacleAvoidance.updateBypass = updateObstacleBypass
ObstacleAvoidance.getObstacleAhead = getObstacleAhead

RecoverySystem.handleFreeze = handleFreeze
RecoverySystem.resetFreezeRecovery = resetFreezeRecovery
RecoverySystem.updateBumpRecovery = updateBumpRecovery

local function freezeResumeDelay()
    local delay = tonumber(S.freezeResumeDelay) or 0.0
    if delay <= 0.0 then
        delay = CONFIG.recovery.freezeResumeDelayMinSeconds or 0.5
    end
    return delay
end

-- State name while the car is held still because of a freeze.
local function frozenHoldReason()
    if S.externalFreezeAck and not S.freezeTestLatched then return "FREEZE_HOLD" end
    return pauseReleaseReason ~= "" and pauseReleaseReason or "FREEZE_WAIT"
end

local function updateRefreshStep(now)
    local retry = CONFIG.recovery.refreshRetrySeconds or 0.75
    if not S.refreshSent then
        releaseControls("FREEZE_WAIT")
        if now < (S.freezeRefreshAt or 0.0) then return end
        if S.freezeRecoveryMode == "test" and not CONFIG.recovery.typeRefreshInFreezeTest then
            logEvent("RECOVERY", "freeze test: /refresh not sent (typeRefreshInFreezeTest = false)")
            S.refreshSent = true
            S.refreshJob = nil
            S.freezeRefreshSentAt = now
            S.freezeReleaseUntil = now + freezeResumeDelay()
            return
        end
        local job, reason = typeSAMPCommand("/refresh")
        if job then
            logEvent("RECOVERY", "freeze recovery sending /refresh")
            S.refreshSent = true
            S.refreshJob = job
            S.refreshBlockedReason = nil
            S.freezeRefreshSentAt = now
            S.freezeReleaseUntil = math.huge -- set once typing has finished
        else
            S.freezeRefreshAt = now + retry
            if reason ~= S.refreshBlockedReason then
                S.refreshBlockedReason = reason
                logEvent("RECOVERY", "freeze recovery waiting to send /refresh: " .. tostring(reason))
            end
        end
        return
    end

    local job = S.refreshJob
    if job and not job.done then
        releaseControls("FREEZE_REFRESH")
        return
    end
    if job and not job.ok then
        logEvent("RECOVERY", "freeze recovery /refresh interrupted (" .. tostring(job.reason) .. "); retry scheduled")
        S.refreshJob = nil
        S.refreshSent = false
        S.freezeRefreshAt = now + retry
        releaseControls("FREEZE_WAIT")
        return
    end
    if job then
        -- Resume only after the command has actually been typed and sent.
        local finishedAt = job.finishedAt or now
        logEvent("RECOVERY", string.format("freeze recovery /refresh typed in %.2fs", finishedAt - (job.startedAt or finishedAt)))
        S.freezeReleaseUntil = finishedAt + freezeResumeDelay()
        S.refreshJob = nil
    end
    if now < (S.freezeReleaseUntil or 0.0) then
        releaseControls("FREEZE_REFRESH")
    else
        releaseControls("FREEZE_RESUME")
        resetFreezeRecovery()
    end
end

function RecoverySystem.updateControlThread()
    local now = os.clock()
    syncPausedState(now)
    -- Runs before the playback thread each frame: read the flag fresh here.
    local freezeActive = sharedFreezeActive(true)
    if not freezeActive then
        S.externalFreezeAck = false
    end

    if freezeActive and playing and not S.freezeTestLatched and not S.externalFreezeAck then
        logEvent("RECOVERY", "external freeze detected by control thread")
        startFreezeRecovery("test")
        now = os.clock()
    end

    if (S.bumpActive or now < (S.backToForwardUntil or 0.0))
        and not freezeActive
        and not S.freezeTestLatched
        and not S.frozenByAdmin then
        return
    end

    if S.freezeTestLatched then
        updateRefreshStep(now)
    elseif now < S.rotateFightUntil then
        pressRotateReaction()
    elseif now < S.rotateReleaseUntil then
        releaseControls("ROTATE_CONFUSED")
    elseif playing and (paused or freezeActive) then
        -- Only an active route holds the controls; a stopped bot never does.
        if freezeActive and not paused then
            releaseControls(frozenHoldReason())
        else
            releaseControls(pauseReleaseReason ~= "" and pauseReleaseReason or "SAFE")
        end
    end
end

AdminProtection.handleAdminCheck = handleAdminRotate
DialogBridge.update = handleArbotas
DialogBridge.writeBotState = writeSharedState

function RouteFollower.resetPlaybackStartState()
    writeDriveControls(0, 0)
    playbackDriveMode = DRIVE_FORWARD
    S.lapWander = (math.random() * 3.0) - 1.5
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
    S.refreshSent = false
    S.refreshJob = nil
    S.externalFreezeAck = false
    S.forwardSpeed = nil
    S.freezeRefreshSentAt = 0.0
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
end

-- Clears every pause and recovery source. Used whenever playback ends so a
-- stopped bot cannot keep holding the controls (e.g. stopping while paused or
-- while a dialog was open used to leave the car without throttle until F7).
function RouteFollower.clearTransientState()
    if S.bumpActive then
        stopBumpRecovery(nil)
    end
    resetBumpState(true)
    if commandJob and not commandJob.done then
        commandJob.cancelled = true
    end
    S.refreshJob = nil
    S.refreshSent = false
    S.manualPaused = false
    S.dialogPaused = false
    S.testArbotasPaused = false
    S.dialogReleaseUntil = 0.0
    S.freezeTestLatched = false
    S.freezeRecoveryMode = ""
    S.frozenByAdmin = false
    S.freezeRefreshSentAt = 0.0
    S.freezeReleaseUntil = 0.0
    S.freezeRefreshAt = 0.0
    S.freezeResumeDelay = 0.0
    S.freezeRecoveryGraceUntil = 0.0
    S.reversePlaybackGraceUntil = 0.0
    S.backToForwardUntil = 0.0
    S.rotateFightUntil = 0.0
    S.rotateReleaseUntil = 0.0
    overrideActive = false
    freezeTimer = 0
    suddenStopFrames = 0
    syncPausedState()
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
        showMsg("~g~Vaziavimas pradetas!")
        return true
    end

    local route = RouteStorage.load(current_name)
    if RouteStorage.validateRoute(route) then
        RouteStorage.logRouteSummary(current_name, route, "play_file")
        current_route = route; play_index = 1; playbackDriveMode = routeDriveModeAt(current_route, 1); playing = true; syncPausedState()
        showMsg("~g~Kelias ikrautas ir paleistas: " .. current_name)
        return true
    end

    showMsg("~r~Nera irasyto kelio!")
    return false
end

function RouteFollower.stopPlayback()
    RouteFollower.clearTransientState()
    playing = false
    releaseControls("STOPPED")
    showMsg("~r~Vaziavimas sustabdytas!")
end

function RouteFollower.stopAll()
    if recording then
        RouteRecorder.stopRecording()
    end
    RouteFollower.clearTransientState()
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

    S.routeObstacleTimer = S.routeObstacleTimer + frameScale
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

-- frameScale = real frame time in reference frames (1.0 at referenceFps).
-- A long gap (pause, override, lag spike) is clamped so it cannot count as
-- many frames at once.
local function updateFrameScale()
    local now = os.clock()
    if not playing or lastPlaybackTickAt == nil then
        frameScale = 1.0
    else
        frameScale = clamp((now - lastPlaybackTickAt) * (CONFIG.timing.referenceFps or 30),
            CONFIG.timing.minFrameScale or 0.25, CONFIG.timing.maxFrameScale or 2.0)
    end
    lastPlaybackTickAt = playing and now or nil
end

function RouteFollower.updatePlayback()
    updateFrameScale()
    if playing and #current_route > 0 and sharedFreezeActive() and not S.freezeTestLatched and not S.externalFreezeAck then
        logEvent("RECOVERY", "external freeze detected by playback gate")
        startFreezeRecovery("test")
    end
    if playing and freezeRecoveryOwnsControls() then
        releaseControls(frozenHoldReason())
        return
    end

    if not (playing and not paused and #current_route > 0) then return end

    if not isCharInAnyCar(PLAYER_PED) then
        RouteFollower.clearTransientState()
        playing = false; repeating = false
        releaseControls("NO_CAR")
        showMsg("~r~Vaziavimas sustabdytas - islejei masina!")
        return
    end

    local car = storeCarCharIsInNoSave(PLAYER_PED)
    local carX, carY, carZ = getCarCoordinates(car)
    S.forwardSpeed = getCarForwardSpeed(car)

    if isPlayerControlling() then
        if not overrideActive then
            overrideActive = true
            if S.bumpActive then
                stopBumpRecovery("BUMP_OVERRIDE")
            end
            releaseControls("OVERRIDE")
        end
        printStringNow("~y~OVERRIDE ACTIVE", 100)
        return
    end

    overrideActive = false

    -- Recovery mini-states must run before normal playback systems; otherwise
    -- freeze/obstacle/route logic can write controls during bump or R >> FWD.
    if S.bumpActive then
        if RecoverySystem.updateBumpRecovery(car, carX, carY) then
            return
        end
    end

    if handleBackToForwardTransition() then
        return
    end

    RouteFollower.updateTrail(carX, carY, carZ)
    ObstacleAvoidance.updateScan(car)
    AdminProtection.handleAdminCheck(car)
    RecoverySystem.handleFreeze(car, current_route, play_index)

    if S.bumpActive then
        if RecoverySystem.updateBumpRecovery(car, carX, carY) then
            return
        end
    end

    if S.freezeTestLatched then
        -- Freeze recovery thread owns inputs so real and test freezes behave identically.
    elseif S.frozenByAdmin or sharedFreezeActive() then
        releaseControls(pauseReleaseReason ~= "" and pauseReleaseReason or "FROZEN")
    elseif not paused then
        local point = current_route[play_index]
        local driveMode = getPlaybackDriveMode(current_route, play_index)
        local reverseMode = driveMode == DRIVE_BACK
        local tX, tY

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
                    return
                end
            end
        end

        if reverseMode then
            -- Backing up needs the exact recorded waypoint. Forward driving can
            -- keep the smoothed spline/lateral route behavior.
            tX, tY = point.x, point.y
            if S.bypassActive or math.abs(S.currentLateral or 0.0) > 0.05 then
                resetObstacleBypass()
                S.currentLateral = 0.0
            end
            collisionCooldown = 0
        else
            tX, tY = getSplineTarget(current_route, play_index)
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
                S.currentLateral = S.currentLateral + (targetLateral - S.currentLateral) * scaledLerp(lateralLerp)
                tX = tX + (-ndy / nd) * S.currentLateral
                tY = tY + (ndx / nd) * S.currentLateral
            end
        end

        draw_line(tX, tY, carX, carY, carZ, reverseMode and COLOR_ROUTE_BACK or COLOR_ROUTE_FORWARD)

        local rawCurrentSpeed = getCarSpeed(car)
        local currentSpeed = reverseMode and math.abs(rawCurrentSpeed) or rawCurrentSpeed
        local targetSpeed = reverseMode and math.abs(point.speed or 0) or (point.speed or 0)
        local steerTargetX, steerTargetY = tX, tY
        local reverseDrive = false
        if S.bypassActive then
            targetSpeed = math.min(targetSpeed, 46.0)
        end

        if not reverseMode then
            handleRouteRejoinRecovery(car, carX, carY, tX, tY, currentSpeed)
        end
        do
            local obsX, obsY, obsDir, obsDist, obsSide, obsUrgency = nil, nil, nil, nil, nil, nil
            if not reverseMode then
                obsX, obsY, obsDir, obsDist, obsSide, obsUrgency = getObstacleAhead(car, tX, tY)
            end
            if obsX and collisionCooldown <= 0 and not reverseMode then
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
                collisionCooldown = math.max(0, collisionCooldown - frameScale)
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
                gasLevel = math.max(0, gasLevel - 25 * frameScale)
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
                    brakeLevel = 0
                    -- Reverse = brake button held with no gas (it brakes first
                    -- while still rolling forward). Ease off only when already
                    -- backing faster than the recorded reverse speed.
                    local reverseLimit = math.max(3.0, targetSpeed) + 1.0
                    reverseDrive = S.forwardSpeed == nil or S.forwardSpeed > -reverseLimit
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
                            gasLevel = math.min(255, gasLevel + 18 * frameScale)
                            brakeLevel = math.max(0, brakeLevel - 50 * frameScale)
                        elseif currentSpeed < targetSpeed + 1.5 then
                            brakeLevel = math.max(0, brakeLevel - 50 * frameScale)
                        else
                            local excess = currentSpeed - (targetSpeed + 1.5)
                            local brakeCap = S.bypassActive and 95 or 255
                            local brakeGain = S.bypassActive and 12 or 30
                            brakeLevel = math.min(brakeCap, math.floor(excess * brakeGain))
                            gasLevel = math.max(0, gasLevel - 25 * frameScale)
                        end
                    end
                end
                writeDriveControls(gasLevel, brakeLevel, reverseDrive)
            end
        end

        -- getCarSpeed is in m/s.
        printStringNow('~g~VR Bot ~w~' .. play_index .. '/' .. #current_route .. ' ~y~' .. math.floor(currentSpeed * 3.6) .. 'km/h' .. (reverseMode and ' ~b~BACK' or ''), 100)
        writeSharedState("PLAYING")

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
                play_index = findNearestWaypointNear(current_route, carX, carY, play_index, 40, 300, 30.0)
            else
                local closestIdx, closestDist = play_index, carDist
                for i = play_index, math.min(play_index + 10, #current_route) do
                    -- Never jump into a BACK section early: a reverse leg that
                    -- retraces the forward path is closer than its start point.
                    if routeDriveModeAt(current_route, i) ~= DRIVE_FORWARD then break end
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
                S.rejoinCooldownUntil = 0.0
                S.rejoinDisableUntil = os.clock() + 2.5
                resetObstacleBypass()
                S.avoidClusterCount = 0
                local delayFrames = math.random(1, 2)
                steerBuf = {}
                for i = 1, delayFrames do steerBuf[i] = 0 end
                showMsg("~g~Kilpa baigta! Kartojama!")
            else
                RouteFollower.clearTransientState()
                playing = false; play_index = 1
                releaseControls("DONE")
                showMsg("~g~Kelias baigtas!")
            end
        end
    end
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

-- Running scripts named dangis_vr (an old copy under another file name would
-- make two bots fight over the controls).
local function findActiveDangisScripts()
    local ok, list = pcall(function() return script.list() end)
    if not ok or type(list) ~= "table" then return nil end
    local found = {}
    for _, s in ipairs(list) do
        local okName, name = pcall(function() return s.name end)
        if okName and name == "dangis_vr" then
            local okPath, path = pcall(function() return s.path end)
            table.insert(found, tostring(okPath and path or name))
        end
    end
    return found
end

-- Returns the warning text when more than one copy is running.
local function checkDuplicateDangisScripts()
    local scripts = findActiveDangisScripts()
    if not scripts then
        logEvent("STARTUP", "duplicate scan unavailable")
        return nil
    end
    if #scripts <= 1 then
        logEvent("STARTUP", "duplicate scan ok: " .. tostring(#scripts) .. " running dangis_vr script")
        return nil
    end
    logEvent("STARTUP", "duplicate dangis_vr scripts running: " .. table.concat(scripts, ", "))
    return "~r~DANGIS WARNING: duplicate scripts active!~n~~y~Disable old dangis_vr copies in moonloader."
end

local function logApiAvailability()
    local function has(value) return value and "yes" or "MISSING" end
    logEvent("STARTUP", string.format(
        "api: objectModel=%s closestObject=%s closestCar=%s allObjects=%s carPointer=%s user32=%s",
        API.objectModelName or "MISSING", has(API.closestObject), has(API.closestCar),
        has(API.allObjects), has(API.carPointer), has(Win32.init())))
end

local function performSafeStartupReset()
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
    writeSharedState("IDLE")
    logEvent("STARTUP", "safe startup reset complete")
end

function MainLoop.initialize()
    -- Release keys an older version (synthetic S) or an interrupted command
    -- may have left pressed; done before the startup wait.
    Win32.releaseKeys({0x53, 0x10, 0x11, 0x12})
    trimDebugLogFile()
    logEvent("STARTUP", string.format("==== %s Dangis VR v%s loading ====", os.date("%Y-%m-%d %H:%M:%S"), VR_VERSION))
    printStringNow("~y~Dangis VR: ~w~Laukiama...", 5000)
    wait(8000)
    RouteStorage.ensurePathsDir()
    local duplicateWarning = checkDuplicateDangisScripts()
    samp = getModuleHandle("samp.dll")
    logApiAvailability()
    performSafeStartupReset()
    -- printStringNow replaces the previous text, so show one combined message.
    printStringNow(duplicateWarning
        or ("~g~Dangis VR v" .. VR_VERSION .. " ikelta!~n~~w~F2-Irasyti F10-Paleisti F11-Kartoti F6-Pauze F7-Sustabdyti"),
        duplicateWarning and 8000 or 5000)
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

-- Runs on unload, reload (Ctrl+R / AutoReboot) and crashes: release every key
-- the typing thread may be holding and leave the HUD a truthful state.
function onScriptTerminate(scr, quitGame)
    if scr ~= thisScript() then return end
    if commandJob and not commandJob.done then
        commandJob.cancelled = true
    end
    Win32.releaseHeld()
    if not quitGame then
        playing = false
        reverseActive = false
        writeSharedState("IDLE")
        logEvent("STARTUP", "script terminated")
    end
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
