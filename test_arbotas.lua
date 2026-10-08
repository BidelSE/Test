script_name('test_arbotas')
script_version('3.0')
require 'lib.moonloader'

-- sampShowDialog is VM-blocked, so this script fakes the arbotas dialog by
-- writing directly into the SAMP dialog struct in memory.
-- No visual dialog appears, but arbotas_auto.lua will detect it, wait the
-- human-like delay, and fire the DOWN x N + ENTER sequence.
-- The keystrokes go to the game world (no real dialog is shown), so test
-- in a parked vehicle or somewhere safe. Verify via the printStringNow messages.
--
-- F5 : inject fake dialog   |   F5 again : clear it

local ffi = require("ffi")
pcall(ffi.cdef, [[
    int IsBadReadPtr(const void* lp, unsigned int ucb);
]])
local _k32 = ffi.load("kernel32")

local function _ok(addr, n)
    if not addr or addr < 0x10000 or addr > 0x7FFFFFFF then return false end
    return _k32.IsBadReadPtr(ffi.cast("void*", addr), n or 1) == 0
end

local function rDword(addr)
    if not _ok(addr, 4) then return nil end
    return tonumber(ffi.cast("uint32_t*", addr)[0])
end

local function wByte(addr, val)  ffi.cast("uint8_t*",  addr)[0] = val end
local function wWord(addr, val)  ffi.cast("uint16_t*", addr)[0] = val end
local function wDword(addr, val) ffi.cast("uint32_t*", addr)[0] = val end

local DIALOG_ID = 9998
local active    = false
local _blobBuf  = nil   -- global keeps FFI buffer alive (prevents GC)
local samp      = 0

local function fakeLine()
    local r = math.random(5)
    if r == 1 then
        return string.format("{99CCFF}O(x %s y) = z^%d",
            math.random(2) == 1 and "^" or "*", math.random(100, 9999))
    elseif r == 2 then
        return string.format("{AADDFF}%d %d %05d",
            math.random(100, 9999), math.random(1000, 9999), math.random(10000, 99999))
    elseif r == 3 then
        return string.format("{88CCFF}%d + %05d",
            math.random(1000, 9999), math.random(1000, 99999))
    elseif r == 4 then
        return string.format("{FFAA44}* %d %05d",
            math.random(1000, 9999), math.random(10000, 99999))
    else
        return string.format("{FFDDAA}|%s ; * %s%s%s",
            string.char(math.random(65, 90)),
            string.char(math.random(97, 122)),
            string.char(math.random(97, 122)),
            string.char(math.random(97, 122)))
    end
end

function main()
    wait(3000)
    samp = getModuleHandle("samp.dll")
    if samp == 0 then
        printStringNow("~r~test_arbotas: samp.dll nav!", 3000)
        return
    end
    printStringNow("~g~test_arbotas v3.0 ikelta! (F5 = fake dialog)", 2500)

    while true do
        wait(0)

        if isKeyJustPressed(VK_F5) then
            local dPtr = rDword(samp + 0x21A0B8)
            if not dPtr or dPtr < 0x01000000 then
                printStringNow("~r~test_arbotas: dPtr invalid!", 2000)
            elseif active then
                wDword(dPtr + 0x28, 0)   -- shown = false
                _blobBuf = nil
                active   = false
                printStringNow("~r~Fake arbotas uzdarytas!", 2000)
            else
                local nItems  = 10
                local emptyAt = math.random(1, nItems - 1)
                local rows = {
                    "Pasirinkite tuscia eilute",
                    "{FF4444}Pasirinkus blogai galima gauti Ban",
                }
                for i = 1, nItems do
                    rows[#rows + 1] = (i == emptyAt) and " " or fakeLine()
                end
                local blob     = table.concat(rows, "\n")
                local emptyIdx = 2 + (emptyAt - 1)

                _blobBuf = ffi.new("char[?]", #blob + 1)
                ffi.copy(_blobBuf, blob)
                local blobAddr = tonumber(ffi.cast("uintptr_t", _blobBuf))

                wWord( dPtr + 0x04, DIALOG_ID)  -- dialog ID
                wByte( dPtr + 0x05, 2)           -- LIST type
                wDword(dPtr + 0x28, 1)           -- shown = true
                wDword(dPtr + 0x34, blobAddr)    -- items blob pointer

                active = true
                printStringNow(string.format(
                    "~g~Fake arbotas injected! Tuscia: [%d] (nematomas)", emptyIdx), 5000)
            end
        end
    end
end
