script_name('test_dialog_spy')
script_version('2.7')
require 'lib.moonloader'

-- Memory-only dialog debugger. No samp.* functions used.
-- Ctrl+F9 : toggle overlay on/off
--
-- For each item:
--   * unique color codes used (with x<count> if repeated)
--   * stripped text
--   * <-- EMPTY  if the row is blank
--   * <-- WHITE  if the row has 3+ {fXfXfX} codes AND looks like "N N N"
--                (the strict "N N N" guard excludes header rows that happen
--                to use white-ish color codes for word rendering)
-- Lines are also rendered in their first color code, so a glance tells you
-- which row is genuinely white.

local samp         = 0
local font         = nil
local show         = false
local lines        = {}
local lineColors   = {}    -- parallel ARGB color for each entry in `lines`
local tick         = 0
local lastOpenData = {}
local lastOpenCols = {}
local lastOpenTime = 0
local KEEP_SECS    = 8

local ffi = require("ffi")
pcall(ffi.cdef, [[
    int IsBadReadPtr(const void* lp, unsigned int ucb);
]])
local _k32 = ffi.load("kernel32")

local function _ok(addr, n)
    if not addr or addr < 0x10000 or addr > 0x7FFFFFFF then return false end
    return _k32.IsBadReadPtr(ffi.cast("void*", addr), n or 1) == 0
end

local function rByte(addr)
    if not _ok(addr, 1) then return nil end
    return ffi.cast("uint8_t*",  addr)[0]
end

local function rWord(addr)
    if not _ok(addr, 2) then return nil end
    return ffi.cast("uint16_t*", addr)[0]
end

local function rDword(addr)
    if not _ok(addr, 4) then return nil end
    return ffi.cast("uint32_t*", addr)[0]
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
    if #s < 1 then return nil end
    return s
end

local function stripColor(s)
    return (s:gsub("{%x%x%x%x%x%x}", ""):match("^%s*(.-)%s*$"))
end

local function looksLikeThreeNumbers(s)
    return s:match("^%s*%d+%s+%d+%s+%d+%s*$") ~= nil
end

local function isWhiteCode(code)
    return code:sub(1,1):lower() == 'f'
       and code:sub(3,3):lower() == 'f'
       and code:sub(5,5):lower() == 'f'
end

local function hexToARGB(hex)
    local n = tonumber(hex, 16)
    if not n then return 0xFFCCCCCC end
    return 0xFF000000 + n
end

local function push(out, cols, text, color)
    table.insert(out, text)
    table.insert(cols, color or 0xFFCCCCCC)
end

local function scan()
    local out, cols = {}, {}

    if samp == 0 then
        push(out, cols, "samp.dll not found", 0xFFFF8844)
        return out, cols, false
    end

    local dPtr = rDword(samp + 0x21A0B8)
    if not dPtr or dPtr == 0 then
        push(out, cols, "no dialog (dPtr=0)", 0xFF888888)
        return out, cols, false
    end

    if dPtr < 0x01000000 or dPtr > 0x3FFFFFFF then
        push(out, cols, string.format("dPtr=0x%08X (out of heap range)", dPtr), 0xFFFF8844)
        return out, cols, false
    end

    push(out, cols, string.format("dPtr=0x%08X", dPtr), 0xFF88CCFF)

    local shown  = rDword(dPtr + 0x28)
    local isOpen = shown == 1
    push(out, cols, string.format("+0x28 shown=%d (%s)", shown or 0, isOpen and "OPEN" or "closed"),
        isOpen and 0xFF44FF44 or 0xFFFF8844)

    local dialogID   = rWord(dPtr + 0x04)
    local dialogType = rByte(dPtr + 0x05)
    push(out, cols, string.format("ID=%-5s  Type=%s (%s)",
        dialogID   and tostring(dialogID)   or "?",
        dialogType and tostring(dialogType) or "?",
        dialogType == 2 and "LIST" or dialogType == 1 and "INPUT" or
        dialogType == 0 and "MSGBOX" or "?"), 0xFF88FF88)

    local p34 = rDword(dPtr + 0x34)
    local blob = nil
    if p34 and p34 >= 0x01000000 and p34 <= 0x3FFFFFFF then
        local s = rStr(p34, 4096)
        if s then
            local nl = 0; s:gsub("\n", function() nl = nl + 1 end)
            if nl >= 1 then blob = s end
        end
    end

    if blob then
        local rawLines, stripped = {}, {}
        for line in (blob .. "\n"):gmatch("([^\n]*)\n") do
            table.insert(rawLines, line)
            table.insert(stripped, stripColor(line))
        end
        while #rawLines > 0 and stripped[#stripped] == "" do
            table.remove(rawLines)
            table.remove(stripped)
        end

        push(out, cols, string.format("items @+0x34 ptr (%d lines):", #rawLines), 0xFFFFAA00)

        local emptyIdx, whiteIdx = nil, nil
        for i = 1, #rawLines do
            local idx     = i - 1
            local rawLine = rawLines[i]
            local item    = stripped[i]

            -- Collect unique codes in order of first appearance
            local seen, order = {}, {}
            for code in rawLine:gmatch("{(%x%x%x%x%x%x)}") do
                seen[code] = (seen[code] or 0) + 1
                if seen[code] == 1 then table.insert(order, code) end
            end

            -- Count white-ish codes
            local whiteCount = 0
            for _, code in ipairs(order) do
                if isWhiteCode(code) then
                    whiteCount = whiteCount + seen[code]
                end
            end

            -- Compact code list
            local parts = {}
            for _, c in ipairs(order) do
                if seen[c] > 1 then
                    table.insert(parts, string.format("{%s}x%d", c, seen[c]))
                else
                    table.insert(parts, string.format("{%s}", c))
                end
            end
            local codeTag = #parts > 0 and table.concat(parts, " ") or "(no codes)"

            -- Decide label + line color
            local label, lineCol = "", 0xFFCCCCCC
            if order[1] then lineCol = hexToARGB(order[1]) end
            if item == "" then
                emptyIdx = idx
                label = "  <-- EMPTY"
                lineCol = 0xFF44FF44
            elseif whiteCount >= 3 and looksLikeThreeNumbers(item) then
                if not whiteIdx then whiteIdx = idx end
                label = "  <-- WHITE"
                lineCol = 0xFFFFFFFF
            elseif whiteCount >= 3 then
                label = "  <-- white codes (not N N N)"
            end

            local display = #item > 18 and item:sub(1, 16) .. ".." or item
            push(out, cols,
                string.format("  [%2d] %s '%s'%s", idx, codeTag, display, label),
                lineCol)
        end

        if whiteIdx then
            push(out, cols, string.format(">>> white idx %d <<<", whiteIdx), 0xFFFFFFFF)
        end
        if emptyIdx then
            push(out, cols, string.format(">>> empty idx %d <<<", emptyIdx), 0xFF44FF44)
        end
        if not whiteIdx and not emptyIdx then
            push(out, cols, "no answer detected", 0xFFFF8844)
        end
    else
        local p34str = p34 and string.format("0x%08X", p34) or "nil"
        push(out, cols, string.format("items: p34=%s no blob", p34str), 0xFFFF8844)
    end

    push(out, cols, "hex:", 0xFF888888)
    for row = 0, 3 do
        local hex = string.format(" +%02X:", row * 16)
        for col = 0, 3 do
            local v = rDword(dPtr + row * 16 + col * 4)
            hex = hex .. (v and string.format(" %08X", v) or " ????????")
        end
        push(out, cols, hex, 0xFF888888)
    end

    return out, cols, isOpen
end

function main()
    wait(0)
    samp = getModuleHandle("samp.dll")
    while true do
        wait(0)

        if isKeyDown(0x11) and isKeyJustPressed(VK_F9) then
            show         = not show
            lines        = {}
            lineColors   = {}
            lastOpenData = {}
            lastOpenCols = {}
            printStringNow(show and "~g~Dialog debug ON" or "~r~Dialog debug OFF", 1500)
        end

        if not font then
            font = renderCreateFont("Arial", 9, 4)
        end

        if show then
            tick = tick + 1
            if tick >= 3 then
                tick = 0
                local ok, newLines, newCols, wasOpen = pcall(scan)
                if not ok then
                    newLines = { "scan error: " .. tostring(newLines) }
                    newCols  = { 0xFFFF4444 }
                    wasOpen  = false
                end
                if wasOpen then
                    lastOpenData = newLines
                    lastOpenCols = newCols
                    lastOpenTime = os.clock()
                end
                if wasOpen then
                    lines      = newLines
                    lineColors = newCols
                elseif os.clock() - lastOpenTime < KEEP_SECS and #lastOpenData > 0 then
                    local ago = math.floor(os.clock() - lastOpenTime)
                    lines      = { string.format("[CLOSED %ds ago - last open data]", ago) }
                    lineColors = { 0xFFFFAA00 }
                    for i = 2, #lastOpenData do
                        lines[#lines + 1]      = lastOpenData[i]
                        lineColors[#lineColors + 1] = lastOpenCols[i]
                    end
                else
                    lines      = newLines
                    lineColors = newCols
                end
            end

            if font and #lines > 0 then
                local x, y, lh = 8, 78, 12
                renderDrawBox(x-3, y-3, 720, #lines*lh+10, 0xCC000000)
                renderDrawBox(x-3, y-3, 720, 13, 0xFF002244)
                renderFontDrawText(font, "DIALOG DEBUG  Ctrl+F9", x, y, 0xFF88CCFF)
                for i, l in ipairs(lines) do
                    renderFontDrawText(font, l, x, y + i*lh, lineColors[i] or 0xFFCCCCCC)
                end
            end
        end
    end
end
