script_name('test_dialog_spy')
script_version('2.3')
require 'lib.moonloader'

-- Memory-only dialog debugger. No samp.* functions used.
-- Ctrl+F9 : toggle overlay on/off
--
-- When a list dialog is open it will show each item with its 0-based index
-- and mark the empty row with  <-- EMPTY (index N)  in green.
-- That index is what you pass to sampSendDialogResponse.

local samp  = 0
local font  = nil
local show  = false
local lines = {}
local tick  = 0

-- ── safe memory readers ───────────────────────────────────────────────────────

local function rByte(addr)
    if not addr or addr < 0x10000 or addr > 0x7FFFFFFF then return nil end
    local ok, v = pcall(readMemory, addr, 1, false)
    return ok and v or nil
end

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

-- read a null-terminated string; replaces non-printable bytes with '.'
-- also keeps newline (0x0A) as a real newline so we can split items later
local function rStr(addr, maxLen)
    if not addr or addr < 0x10000 or addr > 0x7FFFFFFF then return nil end
    local s = ""
    local ok = pcall(function()
        for i = 0, (maxLen or 128) - 1 do
            local b = readMemory(addr + i, 1, false)
            if b == 0 then break end
            if b == 0x0A then
                s = s .. "\n"
            elseif b >= 32 and b <= 126 then
                s = s .. string.char(b)
            elseif b > 126 then
                s = s .. "?"
            end
        end
    end)
    if not ok or #s < 1 then return nil end
    return s
end

-- try offset as inline string, then as pointer-to-string
local function tryStr(base, off, maxLen)
    local s = rStr(base + off, maxLen or 64)
    if s and #s >= 2 then return s, false end
    local ptr = rDword(base + off)
    if ptr and ptr > 0x10000 then
        s = rStr(ptr, maxLen or 64)
        if s and #s >= 2 then return s, true end
    end
    return nil, false
end

-- strip {RRGGBB} color codes and trim whitespace
local function stripColor(s)
    return (s:gsub("{%x%x%x%x%x%x}", ""):match("^%s*(.-)%s*$"))
end

-- parse a newline-separated items blob into a list of clean strings
local function parseItems(blob)
    local items = {}
    for line in (blob .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(items, stripColor(line))
    end
    -- drop trailing empty entries
    while #items > 0 and items[#items] == "" do
        table.remove(items)
    end
    return items
end

-- ── main scan ─────────────────────────────────────────────────────────────────

local function scan()
    local out = {}

    if samp == 0 then
        table.insert(out, "samp.dll not found")
        return out
    end

    local dPtr = rDword(samp + 0x21A0B8)
    table.insert(out, string.format("samp+0x21A0B8 -> dPtr=0x%08X", dPtr or 0))

    if not dPtr or dPtr == 0 then
        table.insert(out, "dPtr is NULL — no dialog")
        return out
    end

    -- shown flag
    local shown  = rDword(dPtr + 0x28)
    local isOpen = shown == 1
    table.insert(out, string.format("+0x28 shown=%d  (%s)", shown or 0, isOpen and "OPEN" or "closed"))

    -- dialog ID candidates
    local w00 = rWord(dPtr + 0x00)
    local d04 = rDword(dPtr + 0x04)
    local w04 = rWord(dPtr + 0x04)
    local d24 = rDword(dPtr + 0x24)
    local dAC = rWord(samp + 0x21A0AC)
    table.insert(out, string.format(
        "ID? +0x00w=%-5s +0x04d=%-6s +0x04w=%-5s +0x24=%-5s",
        w00  and tostring(w00)  or "?",
        d04  and tostring(d04)  or "?",
        w04  and tostring(w04)  or "?",
        d24  and tostring(d24)  or "?"))
    table.insert(out, string.format("    samp+0x21A0AC(w)=%-5s",
        dAC and tostring(dAC) or "?"))

    -- type byte candidates (+0x02, +0x03, +0x05, +0x06)
    local b02 = rByte(dPtr + 0x02)
    local b03 = rByte(dPtr + 0x03)
    local b05 = rByte(dPtr + 0x05)
    local b06 = rByte(dPtr + 0x06)
    table.insert(out, string.format("Type? b02=%s b03=%s b05=%s b06=%s",
        b02 and tostring(b02) or "?",
        b03 and tostring(b03) or "?",
        b05 and tostring(b05) or "?",
        b06 and tostring(b06) or "?"))

    -- ── pointer-follow scan ───────────────────────────────────────────────────
    -- Walk every dword in the first 0x100 bytes. For each valid pointer, read
    -- the memory it points to and look for title strings or items blobs.
    table.insert(out, "-- ptr follow --")
    local ptrBest, ptrBestNL, ptrBestOff = nil, 0, nil
    local ptrTitles = {}

    for off = 0, 0xFC, 4 do
        local ptr = rDword(dPtr + off)
        if ptr and ptr >= 0x10000 and ptr < 0x7F000000 then
            local s = rStr(ptr, 4096)
            if s and #s >= 4 then
                local nl = 0; s:gsub("\n", function() nl = nl + 1 end)
                if nl >= 2 then
                    -- candidate items blob — keep the one with the most newlines
                    if nl > ptrBestNL then
                        ptrBest, ptrBestNL, ptrBestOff = s, nl, off
                    end
                elseif #s >= 4 and #s <= 80 then
                    -- candidate title
                    local preview = s:sub(1, 48)
                    table.insert(ptrTitles, string.format(
                        "  +0x%02X->title: '%s'", off, preview))
                end
            end
        end
    end

    for _, t in ipairs(ptrTitles) do
        table.insert(out, t)
    end

    -- ── item list display ─────────────────────────────────────────────────────
    -- Prefer pointer-follow result; fall back to old fixed-offset scan.
    local bestBlob, bestNL, bestLabel = nil, 0, nil

    if ptrBest then
        bestBlob  = ptrBest
        bestNL    = ptrBestNL
        bestLabel = string.format("items via ptr +0x%02X (%d lines):", ptrBestOff, ptrBestNL + 1)
    else
        -- legacy fixed-offset scan
        local itemOffsets = {0x4C, 0x48, 0x50, 0x54, 0x108, 0x10C}
        local bestIsPtr, bestOff = false, nil
        for _, off in ipairs(itemOffsets) do
            local s = rStr(dPtr + off, 2048)
            if s then
                local nl = 0; s:gsub("\n", function() nl = nl + 1 end)
                if nl > bestNL then bestBlob, bestNL, bestOff, bestIsPtr = s, nl, off, false end
            end
            local ptr = rDword(dPtr + off)
            if ptr and ptr > 0x10000 then
                s = rStr(ptr, 2048)
                if s then
                    local nl = 0; s:gsub("\n", function() nl = nl + 1 end)
                    if nl > bestNL then bestBlob, bestNL, bestOff, bestIsPtr = s, nl, off, true end
                end
            end
        end
        if bestBlob and bestNL >= 1 then
            bestLabel = string.format("items @ +0x%02X %s(%d lines):",
                bestOff, bestIsPtr and "(ptr) " or "", bestNL + 1)
        end
    end

    if bestBlob and bestNL >= 1 then
        table.insert(out, bestLabel)
        local items = parseItems(bestBlob)
        local emptyIdx = nil
        for i, item in ipairs(items) do
            local idx = i - 1
            if item == "" then
                emptyIdx = idx
                table.insert(out, string.format("  [%d] ''  <-- EMPTY", idx))
            else
                local display = #item > 42 and item:sub(1, 40) .. ".." or item
                table.insert(out, string.format("  [%d] '%s'", idx, display))
            end
        end
        if emptyIdx then
            table.insert(out, string.format(">>> send index %d <<<", emptyIdx))
        else
            table.insert(out, "no empty row found in items")
        end
    else
        table.insert(out, "items blob not found (no newlines at any ptr)")
    end

    -- hex dump: 8 rows × 4 dwords (128 bytes)
    table.insert(out, "hex:")
    for row = 0, 7 do
        local hex = string.format(" +%02X:", row * 16)
        for col = 0, 3 do
            local v = rDword(dPtr + row * 16 + col * 4)
            hex = hex .. (v and string.format(" %08X", v) or " ????????")
        end
        table.insert(out, hex)
    end

    return out
end

-- ── render loop ───────────────────────────────────────────────────────────────

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
                    local col =
                        l:find("EMPTY")        and 0xFF44FF44  or
                        l:find(">>> send")      and 0xFF00FF00  or
                        l:find("OPEN")         and 0xFF44FF44  or
                        l:find("->title")      and 0xFFFFFF44  or
                        l:find("items via ptr") and 0xFFFFAA00  or
                        l:find("items @")      and 0xFFFFAA00  or
                        l:find("^  %[")        and 0xFFCCCCFF  or
                        l:find("^ID%?")        and 0xFF88FF88  or
                        l:find("^    samp")    and 0xFF88FF88  or
                        l:find("^Type%?")      and 0xFF88FF88  or
                        l:find("^%-%- ptr")    and 0xFF555566  or
                        l:find("hex:")         and 0xFF888888  or
                        l:find("^ %+")         and 0xFF888888  or
                        0xFFCCCCCC
                    renderFontDrawText(font, l, x, y + i*lh, col)
                end
            end
        end
    end
end
