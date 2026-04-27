script_name('test_dialog_spy')
script_version('2.5')
require 'lib.moonloader'

-- Memory-only dialog debugger. No samp.* functions used.
-- Ctrl+F9 : toggle overlay on/off
--
-- When a list dialog is open it will show each item with its 0-based index
-- and mark the empty row with  <-- EMPTY (index N)  in green.
-- That index is what you pass to sampSendDialogResponse.

local samp         = 0
local font         = nil
local show         = false
local lines        = {}
local tick         = 0
local lastOpenData = {}    -- last scan where dialog was OPEN
local lastOpenTime = 0     -- os.clock() when that scan ran
local KEEP_SECS    = 8     -- keep showing data this long after dialog closes

-- ── FFI memory readers ────────────────────────────────────────────────────────
-- MoonLoader's readMemory corrupts the LuaJIT coroutine state when it hits bad
-- memory, so pcall can never catch it. Use FFI + IsBadReadPtr instead:
-- validate each address range before touching it, then read via raw pointer.

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

-- Read null-terminated string; non-ASCII → '?', 0x0A kept as newline.
-- Checks page validity at every 4 KB boundary so we never cross into a bad page.
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
        return out, false
    end

    local dPtr = rDword(samp + 0x21A0B8)
    table.insert(out, string.format("dPtr=0x%08X", dPtr or 0))

    if not dPtr or dPtr == 0 then
        table.insert(out, "dPtr is NULL — no dialog")
        return out, false
    end

    -- shown flag
    local shown  = rDword(dPtr + 0x28)
    local isOpen = shown == 1
    table.insert(out, string.format("+0x28 shown=%d (%s)", shown or 0, isOpen and "OPEN" or "closed"))

    -- confirmed offsets (from reverse-engineering session)
    local dialogID   = rWord(dPtr + 0x04)   -- confirmed: dPtr+0x04 word = dialog ID
    local dialogType = rByte(dPtr + 0x05)   -- confirmed: dPtr+0x05 byte = type (2=list)
    table.insert(out, string.format("ID=%-5s  Type=%s (%s)",
        dialogID   and tostring(dialogID)   or "?",
        dialogType and tostring(dialogType) or "?",
        dialogType == 2 and "LIST" or dialogType == 1 and "INPUT" or
        dialogType == 0 and "MSGBOX" or "?"))

    -- also show raw ID candidates for future reference
    local w00 = rWord(dPtr + 0x00)
    local d04 = rDword(dPtr + 0x04)
    table.insert(out, string.format("  raw: +0x00w=%s  +0x04d=%s  samp+AC=%s",
        w00 and tostring(w00) or "?",
        d04 and tostring(d04) or "?",
        tostring(rWord(samp + 0x21A0AC) or "?")))

    -- ── items: confirmed pointer at dPtr+0x34 ────────────────────────────────
    -- Walk all dwords 0x00..0xFC, prefer +0x34 (confirmed), fall back to best NL.
    local bestBlob, bestNL, bestOff = nil, 0, nil

    -- First: try the confirmed offset
    local p34 = rDword(dPtr + 0x34)
    if p34 and p34 > 0x10000 then
        local s = rStr(p34, 4096)
        if s then
            local nl = 0; s:gsub("\n", function() nl = nl + 1 end)
            if nl >= 1 then bestBlob, bestNL, bestOff = s, nl, 0x34 end
        end
    end

    -- Also scan other pointers in first 0x60 bytes to find more candidates
    for off = 0x28, 0x5C, 4 do
        if off ~= 0x34 then   -- +0x34 already checked above
            local ptr = rDword(dPtr + off)
            if ptr and ptr >= 0x10000 and ptr < 0x7F000000 then
                local s = rStr(ptr, 4096)
                if s then
                    local nl = 0; s:gsub("\n", function() nl = nl + 1 end)
                    if nl > bestNL then bestBlob, bestNL, bestOff = s, nl, off end
                end
            end
        end
    end

    if bestBlob and bestNL >= 1 then
        table.insert(out, string.format("items ptr+0x%02X (%d lines)%s:",
            bestOff, bestNL + 1, bestOff == 0x34 and " [confirmed]" or ""))
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
        table.insert(out, "items: no blob found")
    end

    -- hex dump: 6 rows × 4 dwords (96 bytes covers known offsets)
    table.insert(out, "hex:")
    for row = 0, 5 do
        local hex = string.format(" +%02X:", row * 16)
        for col = 0, 3 do
            local v = rDword(dPtr + row * 16 + col * 4)
            hex = hex .. (v and string.format(" %08X", v) or " ????????")
        end
        table.insert(out, hex)
    end

    return out, isOpen
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
            lastOpenData = {}
            printStringNow(show and "~g~Dialog debug ON" or "~r~Dialog debug OFF", 1500)
        end

        if not font then
            font = renderCreateFont("Arial", 9, 4)
        end

        if show then
            tick = tick + 1
            if tick >= 3 then   -- poll every 3 frames to catch fast dialogs
                tick  = 0
                local newLines, wasOpen = scan()
                if wasOpen then
                    lastOpenData = newLines
                    lastOpenTime = os.clock()
                end
                -- show live data if dialog is open, otherwise show last-open data
                -- for KEEP_SECS seconds so fast dialogs can be read after they close
                if wasOpen then
                    lines = newLines
                elseif os.clock() - lastOpenTime < KEEP_SECS and #lastOpenData > 0 then
                    -- build a fresh table — do NOT mutate lastOpenData
                    local ago = math.floor(os.clock() - lastOpenTime)
                    lines = { string.format("[CLOSED %ds ago — last open data]", ago) }
                    for i = 2, #lastOpenData do lines[#lines + 1] = lastOpenData[i] end
                else
                    lines = newLines
                end
            end

            if font and #lines > 0 then
                local x, y, lh = 8, 78, 12
                renderDrawBox(x-3, y-3, 560, #lines*lh+10, 0xCC000000)
                renderDrawBox(x-3, y-3, 560, 13, 0xFF002244)
                renderFontDrawText(font, "DIALOG DEBUG  Ctrl+F9", x, y, 0xFF88CCFF)
                for i, l in ipairs(lines) do
                    local col =
                        l:find("<-- EMPTY")    and 0xFF44FF44  or
                        l:find(">>> send")     and 0xFF00FF00  or
                        l:find("OPEN")         and 0xFF44FF44  or
                        l:find("closed")       and 0xFFFF8844  or
                        l:find("items ptr")    and 0xFFFFAA00  or
                        l:find("^  %[")        and 0xFFCCCCFF  or
                        l:find("^ID=")         and 0xFF88FF88  or
                        l:find("^  raw:")      and 0xFF558855  or
                        l:find("hex:")         and 0xFF888888  or
                        l:find("^ %+")         and 0xFF888888  or
                        0xFFCCCCCC
                    renderFontDrawText(font, l, x, y + i*lh, col)
                end
            end
        end
    end
end
