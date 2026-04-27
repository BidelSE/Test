script_name('test_dialog_spy')
script_version('2.0')
require 'lib.moonloader'

-- Dialog debugger. Shows ID, type, title and a raw memory view.
-- Two modes:
--   Ctrl+F9        — toggle overlay on/off
--   Ctrl+Shift+F9  — also print current state to chat (for screenshots)
--
-- Priority:
--   1. samp.* API  (sampGetCurrentDialogId / sampGetDialogInfo) if not nil
--   2. Memory read from samp.dll offsets if samp.* is nil

local samp   = 0
local font   = nil
local active = false
local lines  = {}
local tick   = 0

-- ── safe memory helpers ───────────────────────────────────────────────────────

local function rMem(addr, size, signed)
    if not addr or addr < 0x10000 or addr > 0x7FFFFFFF then return nil end
    local ok, v = pcall(readMemory, addr, size, signed or false)
    return ok and v or nil
end

local function readStr(addr, maxLen)
    if not addr or addr < 0x10000 or addr > 0x7FFFFFFF then return nil end
    local s = ""
    local ok = pcall(function()
        for i = 0, (maxLen or 128) - 1 do
            local b = readMemory(addr + i, 1, false)
            if b == 0 then break end
            if b >= 32 and b <= 126 then
                s = s .. string.char(b)
            elseif b > 126 then
                s = s .. "?"
            else
                s = s .. "."
            end
        end
    end)
    return ok and s or nil
end

-- try to read an inline string AND a pointer-to-string at the same offset
local function tryStr(base, off, maxLen)
    local inlineStr = readStr(base + off, maxLen or 64)
    if inlineStr and #inlineStr >= 2 then
        return inlineStr
    end
    local ptr = rMem(base + off, 4, false)
    if ptr and ptr > 0x10000 then
        local pStr = readStr(ptr, maxLen or 64)
        if pStr and #pStr >= 2 then return "[ptr] " .. pStr end
    end
    return nil
end

-- ── scan via memory ───────────────────────────────────────────────────────────

local function scanMem()
    local out = {}
    if samp == 0 then
        table.insert(out, "samp.dll  NOT FOUND")
        return out
    end

    -- ① The pointer at samp+0x21A0B8
    local dPtr = rMem(samp + 0x21A0B8, 4, false)
    table.insert(out, string.format("samp+0x21A0B8 → dPtr = 0x%08X", dPtr or 0))

    if not dPtr or dPtr == 0 then
        table.insert(out, "  dPtr is NULL — no dialog active")
        return out
    end

    -- ② Shown flag (confirmed working offset)
    local shown = rMem(dPtr + 0x28, 4, false)
    table.insert(out, string.format("  +0x28 shown = %s (%d)", shown == 1 and "YES" or "no", shown or 0))

    if shown ~= 1 then
        table.insert(out, "  (dialog pointer exists but not shown)")
    end

    -- ③ Raw dword candidates for dialog ID and type
    --    Try the most common layouts seen in SA-MP 0.3.7 plugins
    local id_a  = rMem(dPtr + 0x00, 2, false)   -- word at +0x00 (common)
    local id_b  = rMem(dPtr + 0x00, 4, false)   -- dword at +0x00
    local id_c  = rMem(dPtr + 0x04, 4, false)   -- dword at +0x04
    local id_d  = rMem(dPtr + 0x24, 4, false)   -- dword just before shown
    local typ_a = rMem(dPtr + 0x02, 1, false)   -- byte at +0x02
    local typ_b = rMem(dPtr + 0x04, 1, false)   -- byte at +0x04
    table.insert(out, string.format("  ID candidates:  [+0x00 word]=%s  [+0x00 dword]=%s  [+0x04]=%s  [+0x24]=%s",
        id_a  and tostring(id_a)  or "?",
        id_b  and tostring(id_b)  or "?",
        id_c  and tostring(id_c)  or "?",
        id_d  and tostring(id_d)  or "?"))
    table.insert(out, string.format("  Type candidates: [+0x02 byte]=%s  [+0x04 byte]=%s",
        typ_a and tostring(typ_a) or "?",
        typ_b and tostring(typ_b) or "?"))

    -- ④ Also check samp+0x21A0AC directly (some builds store dialog ID there)
    local directId = rMem(samp + 0x21A0AC, 2, false)
    table.insert(out, string.format("  samp+0x21A0AC (direct ID) = %s", directId and tostring(directId) or "?"))

    -- ⑤ Scan for title string at common inline offsets
    local titleOffsets = {0x08, 0x0C, 0x10, 0x14, 0x18, 0x1C, 0x20, 0x2C, 0x30, 0x34}
    for _, off in ipairs(titleOffsets) do
        local s = tryStr(dPtr, off, 48)
        if s and #s >= 2 then
            table.insert(out, string.format("  title @ +0x%02X: '%s'", off, s))
        end
    end

    -- ⑥ Hex dump of first 48 bytes from dPtr (8 dwords per row)
    table.insert(out, "  --- hex dump dPtr+0x00 ---")
    for row = 0, 2 do
        local hex = string.format("  +%02X:", row * 16)
        for col = 0, 3 do
            local v = rMem(dPtr + row * 16 + col * 4, 4, false)
            hex = hex .. (v and string.format(" %08X", v) or " ????????")
        end
        table.insert(out, hex)
    end

    return out
end

-- ── scan via samp.* API ───────────────────────────────────────────────────────

local function scanAPI()
    local out = {}
    local okActive, isActive = pcall(sampIsDialogActive)
    if not okActive then
        table.insert(out, "samp.* available but sampIsDialogActive() errored")
        return out
    end

    table.insert(out, "--- samp.* API ---")
    table.insert(out, "sampIsDialogActive() = " .. tostring(isActive))

    if not isActive then return out end

    local okId, id = pcall(sampGetCurrentDialogId)
    table.insert(out, "ID  = " .. (okId and tostring(id) or "error"))

    local okInfo, dtype, b1, b2, title, text = pcall(sampGetDialogInfo)
    if okInfo then
        table.insert(out, "Type   = " .. tostring(dtype))
        table.insert(out, "Title  = '" .. (title or "") .. "'")
        table.insert(out, "Btn1   = '" .. (b1 or "") .. "'")
        table.insert(out, "Btn2   = '" .. (b2 or "") .. "'")
        -- show first 3 lines of content
        if text then
            local n = 0
            for line in (text .. "\n"):gmatch("([^\n]*)\n") do
                n = n + 1
                if n <= 4 then
                    table.insert(out, string.format("Item[%d] = '%s'", n-1, line))
                end
            end
        end
    else
        table.insert(out, "sampGetDialogInfo() failed")
    end
    return out
end

-- ── main ──────────────────────────────────────────────────────────────────────

function main()
    wait(0)
    samp = getModuleHandle("samp.dll")

    local hasSampAPI = type(sampIsDialogActive) == "function"

    while true do
        wait(0)

        local ctrlDown  = isKeyDown(0x11)
        local shiftDown = isKeyDown(0x10)

        if ctrlDown and isKeyJustPressed(VK_F9) then
            active = not active
            lines  = {}
            printStringNow(active and "~g~Dialog debug ON" or "~r~Dialog debug OFF", 1500)
        end

        if not font then
            font = renderCreateFont("Arial", 9, 4)
        end

        if active then
            tick = tick + 1
            if tick >= 15 then
                tick  = 0
                lines = hasSampAPI and scanAPI() or scanMem()

                -- Ctrl+Shift+F9 also prints to chat
                if ctrlDown and shiftDown and isKeyDown(VK_F9) and type(sampAddChatMessage) == "function" then
                    for _, l in ipairs(lines) do
                        sampAddChatMessage(l, 0xFFFF44)
                    end
                end
            end

            if font and #lines > 0 then
                local x, y = 8, 80
                local lh   = 12
                local bh   = #lines * lh + 8
                renderDrawBox(x - 3, y - 3, 580, bh, 0xCC000000)
                renderDrawBox(x - 3, y - 3, 580, 14, 0xFF003366)
                renderFontDrawText(font, "DIALOG DEBUG  (Ctrl+F9 toggle)", x, y, 0xFF88CCFF)
                for i, l in ipairs(lines) do
                    local col = l:find("title @") and 0xFFFFFF44
                        or l:find("ID  =")   and 0xFF88FF88
                        or l:find("ID cand") and 0xFF88FF88
                        or l:find("shown.*YES") and 0xFF44FF44
                        or l:find("hex dump")  and 0xFF888888
                        or l:find("^  %+")     and 0xFF888888
                        or 0xFFCCCCCC
                    renderFontDrawText(font, l, x, y + i * lh, col)
                end
            end
        end
    end
end
