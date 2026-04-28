script_name('arbotas_auto')
script_version('1.3')
require 'lib.moonloader'

-- Detects the real /arbotas server dialog (and test_arbotas.lua test dialog).
-- Waits a human-like delay, then presses DOWN emptyIdx times + ENTER.
--
-- Detection: LIST dialog (type 2), 5-20 items, exactly 1 item that is empty
-- after stripping SAMP color codes and trimming whitespace.
-- A blank row in SAMP is stored as " " (space), which stripColor trims to "".

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

local function parseItems(blob)
    local items = {}
    for line in (blob .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(items, stripColor(line))
    end
    while #items > 0 and items[#items] == "" do
        table.remove(items)
    end
    return items
end

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

    local items = parseItems(blob)
    if #items < 5 or #items > 20 then return nil end

    local emptyIdx, emptyCount = nil, 0
    for i, item in ipairs(items) do
        if item == "" then
            emptyCount = emptyCount + 1
            emptyIdx   = i - 1
        end
    end

    if emptyCount ~= 1 or emptyIdx == nil then return nil end
    return dialogId, emptyIdx
end

-- Press DOWN emptyIdx times then ENTER to select and confirm the blank row.
local function navigateAndClick(emptyIdx)
    pcall(ffi.cdef, "void keybd_event(unsigned char, unsigned char, unsigned long, unsigned long*);")
    local u32ok, u32 = pcall(ffi.load, "user32")
    if not u32ok then
        printStringNow("~r~Arbotas: user32 failed!", 3000)
        return
    end

    lua_thread.create(function()
        wait(math.random(300, 600))    -- let SAMP settle focus on the dialog
        for i = 1, emptyIdx do
            u32.keybd_event(0x28, 0x50, 0x01, nil)  -- VK_DOWN press  (extended key, scan E0 50)
            u32.keybd_event(0x28, 0x50, 0x03, nil)  -- VK_DOWN release (extended | keyup)
            wait(math.random(65, 130))
        end
        wait(math.random(200, 450))
        u32.keybd_event(0x0D, 0, 0, nil)  -- VK_RETURN press
        u32.keybd_event(0x0D, 0, 2, nil)  -- VK_RETURN release
    end)
end

function main()
    wait(3000)
    samp = getModuleHandle("samp.dll")
    if samp == 0 then
        printStringNow("~r~arbotas_auto: samp.dll nav!", 3000)
        return
    end
    printStringNow("~g~Arbotas auto v1.2 ikelta!", 2000)

    local lastAnsweredId = -1
    local dialogWasOpen  = false
    local pending        = false
    local pendingId      = -1
    local pendingIdx     = -1
    local pendingAt      = 0

    while true do
        wait(0)
        local now = os.clock()

        local dialogId, emptyIdx = scanArbotasDialog()
        local dialogOpen = dialogId ~= nil

        -- Reset when dialog closes so the next arbotas (real or test) is detected.
        if not dialogOpen and dialogWasOpen then
            lastAnsweredId = -1
            if pending then
                pending = false
                printStringNow("~y~Arbotas: dialogo nebebuvo, praleista.", 2000)
            end
        end
        dialogWasOpen = dialogOpen

        -- Fire the queued answer once the delay has elapsed.
        if pending and now >= pendingAt then
            pending = false
            if dialogId == pendingId and emptyIdx == pendingIdx then
                lastAnsweredId = pendingId
                navigateAndClick(pendingIdx)
                printStringNow("~g~Arbotas: einu i eilute [" .. tostring(pendingIdx) .. "]...", 4000)
            else
                printStringNow("~y~Arbotas: dialogo nebebuvo, praleista.", 2000)
            end
        end

        -- Detect a new dialog.
        if not pending and dialogOpen and dialogId ~= lastAnsweredId then
            pending    = true
            pendingId  = dialogId
            pendingIdx = emptyIdx
            local delay = math.random(2000, 5500) / 1000.0
            pendingAt  = now + delay
            printStringNow(string.format(
                "~y~Arbotas aptiktas! Atsakysiu po %.1fs... [%d]", delay, emptyIdx), 6000)
        end
    end
end
