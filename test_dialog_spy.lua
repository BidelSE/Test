script_name('test_dialog_spy')
script_version('2.6')
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
    if not dPtr or dPtr == 0 then
        table.insert(out, "no dialog (dPtr=0)")
        return out, false
    end

    -- Sanity-check dPtr: must look like a typical heap address, not a small int
    -- or a DLL address.  Avoids dereferencing garbage left in the pointer slot.
    if dPtr < 0x01000000 or dPtr > 0x3FFFFFFF then
        table.insert(out, string.format("dPtr=0x%08X (out of heap range, skipped)", dPtr))
        return out, false
    end

    table.insert(out, string.format("dPtr=0x%08X", dPtr))

    local shown  = rDword(dPtr + 0x28)
    local isOpen = shown == 1
    table.insert(out, string.format("+0x28 shown=%d (%s)", shown or 0, isOpen and "OPEN" or "closed"))

    local dialogID   = rWord(dPtr + 0x04)
    local dialogType = rByte(dPtr + 0x05)
    table.insert(out, string.format("ID=%-5s  Type=%s (%s)",
        dialogID   and tostring(dialogID)   or "?",
        dialogType and tostring(dialogType) or "?",
        dialogType == 2 and "LIST" or dialogType == 1 and "INPUT" or
        dialogType == 0 and "MSGBOX" or "?"))

    -- ── items via confirmed pointer at dPtr+0x34 ─────────────────────────────
    -- Only dereference +0x34 (confirmed offset).  No range scanning — following
    -- random pointers from the struct caused unnecessary read attempts.
    local p34 = rDword(dPtr + 0x34)
    local blob, blobOff = nil, nil

    if p34 and p34 >= 0x01000000 and p34 <= 0x3FFFFFFF then
        local s = rStr(p34, 4096)
        if s then
            local nl = 0; s:gsub("\n", function() nl = nl + 1 end)
            if nl >= 1 then blob, blobOff = s, 0x34 end
        end
    end

    if blob then
        local nl = 0; blob:gsub("\n", function() nl = nl + 1 end)
        table.insert(out, string.format("items @+0x34 ptr (%d lines):", nl + 1))
        local items = parseItems(blob)
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
        local p34str = p34 and string.format("0x%08X", p34) or "nil"
        table.insert(out, string.format("items: p34=%s no blob", p34str))
    end

    -- hex dump: first 4 rows (64 bytes) covering all confirmed offsets
    table.insert(out, "hex:")
    for row = 0, 3 do
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
                local ok, newLines, wasOpen = pcall(scan)
                if not ok then
                    newLines = { "scan error: " .. tostring(newLines) }
                    wasOpen  = false
                end
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
