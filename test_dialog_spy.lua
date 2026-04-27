script_name('test_dialog_spy')
script_version('2.1')
require 'lib.moonloader'

-- Memory-only dialog debugger. No samp.* functions used.
-- Ctrl+F9 : toggle overlay on/off

local samp = 0
local font = nil
local show = false
local lines = {}
local tick  = 0

local function rWord(addr)
    if not addr or addr < 0x10000 or addr > 0x7FFFFFFF then return nil end
    local ok, v = pcall(readMemory, addr, 2, false)
    return ok and v or nil
end

local function rDword(addr)
    if not addr or addr < 0x10000 or addr > 0x7FFFFFFF then return nil end
    local ok, v = pcall(readMemory, addr, 4, false)
    return ok and v or nil
end

local function rByte(addr)
    if not addr or addr < 0x10000 or addr > 0x7FFFFFFF then return nil end
    local ok, v = pcall(readMemory, addr, 1, false)
    return ok and v or nil
end

local function rStr(addr, maxLen)
    if not addr or addr < 0x10000 or addr > 0x7FFFFFFF then return nil end
    local s = ""
    local ok = pcall(function()
        for i = 0, (maxLen or 96) - 1 do
            local b = readMemory(addr + i, 1, false)
            if b == 0 then break end
            s = s .. (b >= 32 and b <= 126 and string.char(b) or (b > 126 and "?" or "."))
        end
    end)
    if not ok or #s < 2 then return nil end
    return s
end

-- try offset as inline string first, then as a pointer to string
local function tryStr(base, off, maxLen)
    local s = rStr(base + off, maxLen or 64)
    if s then return s end
    local ptr = rDword(base + off)
    if ptr and ptr > 0x10000 then
        s = rStr(ptr, maxLen or 64)
        if s then return "(ptr) " .. s end
    end
    return nil
end

local function scan()
    local out = {}

    if samp == 0 then
        table.insert(out, "samp.dll not found")
        return out
    end

    -- step 1: follow the pointer at samp+0x21A0B8
    local dPtr = rDword(samp + 0x21A0B8)
    table.insert(out, string.format("samp+0x21A0B8 -> dPtr = 0x%08X", dPtr or 0))

    if not dPtr or dPtr == 0 then
        table.insert(out, "dPtr is NULL — no dialog")
        return out
    end

    -- step 2: shown flag (known working offset)
    local shown = rDword(dPtr + 0x28)
    local isOpen = shown == 1
    table.insert(out, string.format("+0x28 shown = %d  (%s)", shown or 0, isOpen and "OPEN" or "closed"))

    -- step 3: dialog ID candidates
    -- different SA-MP 0.3.7 builds store ID at different spots;
    -- show all of them so you can see which one matches
    local w00  = rWord (dPtr + 0x00)         -- word  at +0x00
    local d00  = rDword(dPtr + 0x00)         -- dword at +0x00
    local d04  = rDword(dPtr + 0x04)         -- dword at +0x04
    local d24  = rDword(dPtr + 0x24)         -- dword just before shown
    local dAC  = rWord (samp + 0x21A0AC)     -- direct word in samp data segment

    table.insert(out, string.format(
        "ID? +0x00w=%-6s +0x00d=%-6s +0x04=%-6s +0x24=%-6s",
        w00 and tostring(w00) or "?",
        d00 and tostring(d00) or "?",
        d04 and tostring(d04) or "?",
        d24 and tostring(d24) or "?"))
    table.insert(out, string.format(
        "    samp+0x21A0AC(word)=%-6s",
        dAC and tostring(dAC) or "?"))

    -- step 4: dialog type candidates
    local b02 = rByte(dPtr + 0x02)
    local b03 = rByte(dPtr + 0x03)
    local b04 = rByte(dPtr + 0x04)
    table.insert(out, string.format(
        "Type? +0x02=%s  +0x03=%s  +0x04=%s",
        b02 and tostring(b02) or "?",
        b03 and tostring(b03) or "?",
        b04 and tostring(b04) or "?"))

    -- step 5: scan for title string at common offsets
    local titleOffsets = {0x08,0x0C,0x10,0x14,0x18,0x1C,0x20,0x2C,0x30,0x34,0x38,0x3C}
    local found = false
    for _, off in ipairs(titleOffsets) do
        local s = tryStr(dPtr, off, 64)
        if s then
            table.insert(out, string.format("str @ +0x%02X: '%s'", off, s))
            found = true
        end
    end
    if not found then
        table.insert(out, "no readable strings found near dPtr")
    end

    -- step 6: raw hex dump — 3 rows of 4 dwords (48 bytes total)
    table.insert(out, "hex dump:")
    for row = 0, 2 do
        local hex = string.format(" +%02X:", row * 16)
        for col = 0, 3 do
            local v = rDword(dPtr + row * 16 + col * 4)
            hex = hex .. (v and string.format(" %08X", v) or " ????????")
        end
        table.insert(out, hex)
    end

    return out
end

function main()
    wait(0)
    samp = getModuleHandle("samp.dll")
    while true do
        wait(0)

        if isKeyDown(0x11) and isKeyJustPressed(VK_F9) then
            show  = not show
            lines = {}
            printStringNow(show and "~g~Dialog debug ON" or "~r~Dialog debug OFF", 1500)
        end

        if not font then
            font = renderCreateFont("Arial", 9, 4)
        end

        if show then
            tick = tick + 1
            if tick >= 15 then
                tick  = 0
                lines = scan()
            end

            if font and #lines > 0 then
                local x, y, lh = 8, 78, 12
                renderDrawBox(x-3, y-3, 560, #lines*lh+10, 0xCC000000)
                renderDrawBox(x-3, y-3, 560, 13, 0xFF002244)
                renderFontDrawText(font, "DIALOG DEBUG  Ctrl+F9", x, y, 0xFF88CCFF)
                for i, l in ipairs(lines) do
                    local col = l:find("OPEN")    and 0xFF44FF44
                             or l:find("str @")   and 0xFFFFFF44
                             or l:find("^ID%?")   and 0xFF88FF88
                             or l:find("^    ")   and 0xFF88FF88
                             or l:find("hex")     and 0xFF888888
                             or l:find("^ %+")    and 0xFF888888
                             or 0xFFCCCCCC
                    renderFontDrawText(font, l, x, y + i*lh, col)
                end
            end
        end
    end
end
