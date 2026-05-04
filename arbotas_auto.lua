script_name('arbotas_auto')
script_version('1.4')
require 'lib.moonloader'

-- Handles two /arbotas dialog types detected via direct SAMP memory reads:
--
--   "baltai"  – one row has all 3 numbers in a white-ish color ({fXfXfX}).
--               An empty row may appear as a distractor — it is ignored.
--               White-color check runs FIRST so the distractor never wins.
--
--   "tuscia"  – one row is blank (space that stripColor trims to "").
--               Only reached when no white-colored row exists.
--
-- No samp.* API used anywhere.

local samp = 0

local ffi = require("ffi")
pcall(ffi.cdef, "int IsBadReadPtr(const void* lp, unsigned int ucb);")
local _k32 = ffi.load("kernel32")

local function _ok(addr, n)
    if not addr or addr < 0x10000 or addr > 0x7FFFFFFF then return false end
    return _k32.IsBadReadPtr(ffi.cast("void*", addr), n or 1) == 0
end

local function rByte(addr)
    if not _ok(addr, 1) then return nil end
    return tonumber(ffi.cast("uint8_t*", addr)[0])
end

local function rWord(addr)
    if not _ok(addr, 2) then return nil end
    return tonumber(ffi.cast("uint16_t*", addr)[0])
end

local function rDword(addr)
    if not _ok(addr, 4) then return nil end
    return tonumber(ffi.cast("uint32_t*", addr)[0])
end

local function rStr(addr, maxLen)
    if not _ok(addr, 1) then return nil end
    local s      = ""
    local limit  = (maxLen or 128) - 1
    local okPage = math.floor(addr / 4096)
    for i = 0, limit do
        local cur  = addr + i
        local page = math.floor(cur / 4096)
        if page ~= okPage then
            if not _ok(cur, 1) then break end
            okPage = page
        end
        local b = ffi.cast("uint8_t*", cur)[0]
        if b == 0 then break end
        if b == 0x0A then
            s = s .. "\n"
        elseif b >= 32 and b <= 126 then
            s = s .. string.char(b)
        elseif b > 126 then
            s = s .. "?"
        end
    end
    return #s >= 1 and s or nil
end

local function stripColor(s)
    return (s:gsub("{%x%x%x%x%x%x}", ""):match("^%s*(.-)%s*$"))
end

-- True when rawLine has 3+ color codes where R1, G1, B1 are all 'f'/'F'.
-- Catches white/near-white shades: {FFFFFF}, {F5F5F5}, {FAFAFA}, etc.
-- The "baltai" dialog uses exactly this range; colored distractors (e.g.
-- {44FF44}, {AADDFF}) have non-'f' first digits and never match.
local function isAllWhiteLine(rawLine)
    local count = 0
    for code in rawLine:gmatch("{(%x%x%x%x%x%x)}") do
        if code:sub(1,1):lower() == 'f'
        and code:sub(3,3):lower() == 'f'
        and code:sub(5,5):lower() == 'f' then
            count = count + 1
        end
    end
    return count >= 3
end

-- Returns dialogId, targetIdx (0-based), kind ("baltai"|"tuscia"); or nil.
local function scanArbotasDialog()
    if samp == 0 then return nil end
    local dPtr = rDword(samp + 0x21A0B8)
    if not dPtr or dPtr < 0x01000000 or dPtr > 0x7FFFFFFF then return nil end
    if rDword(dPtr + 0x28) ~= 1 then return nil end
    if rByte(dPtr + 0x05) ~= 2 then return nil end

    local dialogId = rWord(dPtr + 0x04)
    local p34      = rDword(dPtr + 0x34)
    if not p34 or p34 < 0x01000000 or p34 > 0x7FFFFFFF then return nil end

    local blob = rStr(p34, 4096)
    if not blob then return nil end

    local rawLines = {}
    local stripped = {}
    for line in (blob .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(rawLines, line)
        table.insert(stripped, stripColor(line))
    end
    while #rawLines > 0 and stripped[#stripped] == "" do
        table.remove(rawLines)
        table.remove(stripped)
    end

    if #rawLines < 5 or #rawLines > 20 then return nil end

    -- "baltai" check first: a fake empty row in this dialog must not win.
    for i, rawLine in ipairs(rawLines) do
        if isAllWhiteLine(rawLine) then
            return dialogId, i - 1, "baltai"
        end
    end

    -- "tuscia" check: exactly one blank row, no white-colored rows present.
    local emptyIdx, emptyCount = nil, 0
    for i, s in ipairs(stripped) do
        if s == "" then
            emptyCount = emptyCount + 1
            emptyIdx   = i - 1
        end
    end
    if emptyCount == 1 then
        return dialogId, emptyIdx, "tuscia"
    end

    return nil
end

local function navigateAndClick(targetIdx)
    pcall(ffi.cdef, "void keybd_event(unsigned char, unsigned char, unsigned long, unsigned long*);")
    local u32ok, u32 = pcall(ffi.load, "user32")
    if not u32ok then
        printStringNow("~r~Arbotas: user32 failed!", 3000)
        return
    end

    lua_thread.create(function()
        wait(math.random(300, 600))
        for i = 1, targetIdx do
            u32.keybd_event(0x28, 0x50, 0x01, nil)  -- VK_DOWN press (extended key, scan E0 50)
            u32.keybd_event(0x28, 0x50, 0x03, nil)  -- VK_DOWN release
            wait(math.random(65, 130))
        end
        wait(math.random(200, 450))
        u32.keybd_event(0x0D, 0, 0, nil)   -- VK_RETURN press
        u32.keybd_event(0x0D, 0, 2, nil)   -- VK_RETURN release
    end)
end

function main()
    wait(3000)
    samp = getModuleHandle("samp.dll")
    if samp == 0 then
        printStringNow("~r~arbotas_auto: samp.dll nav!", 3000)
        return
    end
    printStringNow("~g~Arbotas auto v1.4 ikelta!", 2000)

    local lastAnsweredId = -1
    local dialogWasOpen  = false
    local pending        = false
    local pendingId      = -1
    local pendingIdx     = -1
    local pendingKind    = ""
    local pendingAt      = 0

    while true do
        wait(0)
        local now = os.clock()

        local dialogId, targetIdx, kind = scanArbotasDialog()
        local dialogOpen = dialogId ~= nil

        if not dialogOpen and dialogWasOpen then
            lastAnsweredId = -1
            if pending then
                pending = false
                printStringNow("~y~Arbotas: dialogo nebebuvo, praleista.", 2000)
            end
        end
        dialogWasOpen = dialogOpen

        if pending and now >= pendingAt then
            pending = false
            if dialogId == pendingId and targetIdx == pendingIdx then
                lastAnsweredId = pendingId
                navigateAndClick(pendingIdx)
                printStringNow(string.format(
                    "~g~Arbotas: einu i eilute [%d] (%s)...", pendingIdx, pendingKind), 4000)
            else
                printStringNow("~y~Arbotas: dialogo nebebuvo, praleista.", 2000)
            end
        end

        if not pending and dialogOpen and dialogId ~= lastAnsweredId then
            pending     = true
            pendingId   = dialogId
            pendingIdx  = targetIdx
            pendingKind = kind
            local delay = math.random(2000, 5500) / 1000.0
            pendingAt   = now + delay
            printStringNow(string.format(
                "~y~Arbotas (%s) aptiktas! Atsakysiu po %.1fs... [%d]",
                kind, delay, targetIdx), 6000)
        end
    end
end
