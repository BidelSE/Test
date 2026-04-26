script_name('test_dialog_spy')
script_version('1.0')
require 'lib.moonloader'

-- Reads the SA-MP dialog from memory and prints all found strings to screen.
-- Helps verify that handleArbotas can see the real arbotas dialog content.
-- F9: toggle display on/off

local samp = 0
local active = false
local font = nil
local lines = {}
local scanTick = 0

local function readCString(addr, maxLen)
    if not addr or addr < 0x10000 then return nil end
    local s = ""
    local ok = pcall(function()
        for i = 0, (maxLen or 256) - 1 do
            local b = readMemory(addr + i, 1, false)
            if b == 0 then break end
            if b == 10 then s = s .. "|"
            elseif b >= 32 and b <= 126 then s = s .. string.char(b)
            else s = s .. "?" end
        end
    end)
    return (ok and #s > 0) and s or nil
end

local function scanDialog()
    if samp == 0 then return {"samp.dll not found"} end
    local out = {}
    local dPtr = readMemory(samp + 0x21A0B8, 4, true)
    if dPtr == 0 then return {"No dialog open (dPtr=0)"} end
    local shown = readMemory(dPtr + 0x28, 4, true)
    table.insert(out, string.format("dPtr=0x%X  shown=%d", dPtr, shown))

    -- scan pointer offsets for strings
    for off = 0, 0x60, 4 do
        local ptr = readMemory(dPtr + off, 4, false)
        local s = readCString(ptr, 128)
        if s then
            table.insert(out, string.format("+0x%02X ptr: %s", off, s:sub(1, 60)))
        end
    end
    -- scan inline offsets
    for off = 0x2C, 0x200, 4 do
        local s = readCString(dPtr + off, 64)
        if s and #s > 3 then
            table.insert(out, string.format("+0x%03X inline: %s", off, s:sub(1, 60)))
        end
    end
    if #out == 1 then table.insert(out, "(no strings found in dialog struct)") end
    return out
end

function main()
    wait(0)
    samp = getModuleHandle("samp.dll")
    while true do
        wait(0)

        if isKeyJustPressed(VK_F12) then
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
