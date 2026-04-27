script_name('vr_dialog_watch')
script_version('1.2')
require 'lib.moonloader'

-- Safe passive watcher. Avoids broad memory scanning because MoonLoader can
-- kill the coroutine when pcall wraps memory opcodes.
-- Displays dialog status on screen and exports _G.VR_DIALOG_ACTIVE.

local samp = 0
local font = nil
local active = false
local lastScanTime = 0
local dialog_flag_file = getWorkingDirectory() .. "/dangis_vr_dialog.flag"

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

            if samp and samp ~= 0 then
                local dPtr = readMemory(samp + 0x21A0B8, 4, true)
                if dPtr and dPtr ~= 0 then
                    active = readMemory(dPtr + 0x28, 4, true) == 1
                end
            end

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
