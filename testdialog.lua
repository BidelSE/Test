script_name('testdialog_safe')
script_version('1.4')
require 'lib.moonloader'

-- Safe passive watcher. It avoids broad memory scanning because MoonLoader can
-- kill the coroutine when pcall wraps memory opcodes.

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

local function publishDialogState(isActive)
    _G.VR_DIALOG_ACTIVE = isActive
    _G.VR_DIALOG_TITLE = isActive and "SAMP Dialog" or nil
end

function main()
    wait(0)
    samp = getModuleHandle("samp.dll")
    publishDialogState(false)

    while true do
        wait(0)

        if not font then
            font = renderCreateFont("Arial", 10, 1)
        end

        if os.clock() - lastScanTime > 0.10 then
            lastScanTime = os.clock()
            active = false

            active = realDialogActive()

            if fakeDialogActive() then
                active = true
            end

            publishDialogState(active)
        end

        if font then
            local x, y = 18, 410
            local bg = active and 0xCC661111 or 0xAA111111
            renderDrawBox(x, y, 210, 34, bg)
            renderFontDrawText(font, active and "DIALOG ACTIVE" or "DIALOG inactive", x + 6, y + 5, active and 0xFFFFFF00 or 0xFF888888)
            renderFontDrawText(font, "safe watcher", x + 6, y + 20, 0xFFCCCCCC)
        end
    end
end
