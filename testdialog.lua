script_name('testdialog_safe')
script_version('1.5')
require 'lib.moonloader'

-- Safe passive watcher. It avoids broad memory scanning because MoonLoader can
-- kill the coroutine when pcall wraps memory opcodes.
-- Display only: MoonLoader scripts cannot read each other's globals, so the
-- bot detects dialogs itself and this overlay publishes nothing.

local samp = 0
local font = nil
local active = false
local lastScanTime = 0
local dialog_flag_file = getWorkingDirectory() .. "/dangis_vr_dialog.flag"

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

local function realDialogActive()
    if not samp or samp == 0 then return false end
    local dPtr = safeReadDword(samp + 0x21A0B8)
    if not dPtr or dPtr == 0 then return false end
    if dPtr < 0x01000000 or dPtr > 0x7FFFFFFF then return false end
    return safeReadDword(dPtr + 0x28) == 1
end

local function fakeDialogActive()
    local file = io.open(dialog_flag_file, "r")
    if not file then return false end
    local value = file:read("*l")
    file:close()
    return value == "fake_arbotas"
end

-- Just below the hud_aswd box (which spans 20 px above to 84 px below 42% of
-- the screen height), so the two overlays no longer overlap.
local function overlayPosition()
    local x, y = 18, 410
    if getScreenResolution then
        local _, sh = getScreenResolution()
        if sh and sh > 0 then
            y = math.max(220, math.floor(sh * 0.42)) + 96
        end
    end
    return x, y
end

function main()
    wait(0)
    samp = getModuleHandle("samp.dll")

    while true do
        wait(0)

        if not font then
            font = renderCreateFont("Arial", 10, 1)
        end

        if os.clock() - lastScanTime > 0.10 then
            lastScanTime = os.clock()
            active = realDialogActive() or fakeDialogActive()
        end

        if font then
            local x, y = overlayPosition()
            local bg = active and 0xCC661111 or 0xAA111111
            renderDrawBox(x, y, 210, 34, bg)
            renderFontDrawText(font, active and "DIALOG ACTIVE" or "DIALOG inactive", x + 6, y + 5, active and 0xFFFFFF00 or 0xFF888888)
            renderFontDrawText(font, "safe watcher", x + 6, y + 20, 0xFFCCCCCC)
        end
    end
end
