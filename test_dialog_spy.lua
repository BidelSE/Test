script_name('test_dialog_spy')
script_version('1.2')
require 'lib.moonloader'

-- Safe dialog state spy. Does not scan dialog text bytes (can crash MoonLoader).
-- Ctrl+F9: toggle display on/off

local samp = 0
local active = false
local font = nil
local lines = {}
local scanTick = 0

local function scanDialog()
    if samp == 0 then return {"samp.dll not found"} end
    local out = {}
    local dPtr = readMemory(samp + 0x21A0B8, 4, true)
    if dPtr == 0 then return {"No dialog open (dPtr=0)"} end
    local shown = readMemory(dPtr + 0x28, 4, true)
    table.insert(out, string.format("dPtr=0x%X  shown=%d", dPtr, shown))
    table.insert(out, shown == 1 and "Dialog is open" or "Dialog pointer exists, not shown")
    table.insert(out, "Text scan disabled for stability")
    return out
end

function main()
    wait(0)
    samp = getModuleHandle("samp.dll")
    while true do
        wait(0)

        if isKeyDown(0x11) and isKeyJustPressed(VK_F9) then
            active = not active
            if active then
                printStringNow("~g~Dialog spy ON", 1500)
            else
                printStringNow("~r~Dialog spy OFF", 1500)
                lines = {}
            end
        end

        if not font then
            font = renderCreateFont("Arial", 10, 1)
        end

        if active then
            scanTick = scanTick + 1
            if scanTick >= 20 then
                scanTick = 0
                lines = scanDialog()
            end
            if font and #lines > 0 then
                local x, y = 10, 100
                renderDrawBox(x - 2, y - 2, 700, (#lines + 1) * 13 + 4, 0xCC000000)
                for i, l in ipairs(lines) do
                    renderFontDrawText(font, l, x, y + (i - 1) * 13, 0xFFFFFF44)
                end
            end
        end
    end
end
