script_name('arbotas_handler')
script_version('1.0')
require 'lib.moonloader'

-- Detects the "Ar zmogus" list dialog, finds the empty row, and responds.
-- Uses sampSendDialogResponse (requires non-VMware or a patched samp lua module).
--
-- Fallback (F-keys): if samp.* is nil this script is a no-op; the main bot's
-- file-based dialog detection (vr_dialog_watch + handleArbotas) takes over.
--
-- KEY BINDINGS (for manual testing):
--   Ctrl+F12  — print current dialog ID + title to chat

local TITLE_PATTERN   = "zmogus"   -- matched case-insensitively after stripping color codes
local MIN_DELAY_MS    = 1500
local MAX_DELAY_MS    = 3000

local handled         = false
local logAllDialogs   = false      -- toggled by Ctrl+F12 first press
local lastLoggedId    = -1

-- ── helpers ──────────────────────────────────────────────────────────────────

local function hasSamp()
    return type(sampIsDialogActive) == "function"
end

local function strip(s)
    -- remove {RRGGBB} color codes and leading/trailing whitespace
    return (s or ""):gsub("{%x%x%x%x%x%x}", ""):match("^%s*(.-)%s*$")
end

local function parseItems(text)
    local items = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(items, strip(line))
    end
    return items
end

local function findEmptyIndex(items)
    for i, v in ipairs(items) do
        if v == "" then return i - 1 end  -- 0-based for sampSendDialogResponse
    end
    return nil
end

local function chatMsg(msg, color)
    if type(sampAddChatMessage) == "function" then
        sampAddChatMessage("[arbotas] " .. msg, color or 0xFFFFFF)
    end
end

-- ── dialog logger (Ctrl+F12) ─────────────────────────────────────────────────

local function logCurrentDialog()
    if not hasSamp() then
        chatMsg("samp.* not available", 0xFF4444)
        return
    end
    if not sampIsDialogActive() then
        chatMsg("No dialog open", 0xAAAAAA)
        return
    end
    local id   = sampGetCurrentDialogId()
    local ok, dtype, b1, b2, title, text = pcall(sampGetDialogInfo)
    if not ok then
        chatMsg(string.format("dialog id=%d  sampGetDialogInfo() failed", id), 0xFF8800)
        return
    end
    local cleanTitle = strip(title)
    chatMsg(string.format("id=%-5d type=%d title='%s'", id, dtype or -1, cleanTitle), 0xFFFF44)
    -- print each item line
    if dtype == 2 then  -- list dialog
        local items = parseItems(text or "")
        for i, v in ipairs(items) do
            local marker = (v == "") and "<-- EMPTY" or ""
            chatMsg(string.format("  [%d] '%s' %s", i - 1, v, marker), 0xCCCCCC)
        end
    end
end

-- ── main auto-handler ────────────────────────────────────────────────────────

function main()
    wait(0)

    -- graceful degradation: if samp.* is nil, just sit idle and let
    -- the main bot's memory-based handler deal with arbotas
    if not hasSamp() then
        while true do wait(1000) end
    end

    -- wait for player spawn
    repeat wait(500) until sampIsLocalPlayerSpawned and sampIsLocalPlayerSpawned()

    chatMsg("loaded (samp API available)", 0x44FF44)

    while true do
        wait(0)

        -- Ctrl+F12: log current dialog
        if isKeyDown(0x11) and isKeyJustPressed(VK_F12) then
            logCurrentDialog()
        end

        if sampIsDialogActive() then
            local id = sampGetCurrentDialogId()

            -- ── universal logger ──────────────────────────────────────────
            if id ~= lastLoggedId then
                lastLoggedId = id
                local ok2, dtype, _, _, title, _ = pcall(sampGetDialogInfo)
                if ok2 then
                    local cleanTitle = strip(title)
                    -- Always print new dialog IDs so you can identify them
                    chatMsg(string.format("new dialog id=%d type=%d title='%s'",
                        id, dtype or -1, cleanTitle), 0xFFAA00)
                end
            end

            -- ── arbotas detection ─────────────────────────────────────────
            if not handled then
                local ok3, dtype, b1, _, title, text = pcall(sampGetDialogInfo)
                if ok3 and dtype == 2 then   -- list dialog
                    local cleanTitle = strip(title):lower()
                    if cleanTitle:find(TITLE_PATTERN) then
                        handled = true

                        local items    = parseItems(text or "")
                        local emptyIdx = findEmptyIndex(items)

                        if emptyIdx then
                            chatMsg(string.format(
                                "arbotas detected (id=%d). empty at index %d. responding in %.1f-%.1fs",
                                id, emptyIdx, MIN_DELAY_MS / 1000, MAX_DELAY_MS / 1000), 0x44FF44)

                            lua_thread.create(function()
                                local delay = math.random(MIN_DELAY_MS, MAX_DELAY_MS)
                                wait(delay)

                                -- re-check dialog is still open before responding
                                if sampIsDialogActive() and sampGetCurrentDialogId() == id then
                                    sampSendDialogResponse(id, 1, emptyIdx, "")
                                    chatMsg(string.format("responded (index=%d, delay=%dms)",
                                        emptyIdx, delay), 0x44FF44)
                                else
                                    chatMsg("dialog closed before response — skipped", 0xFF8800)
                                end
                            end)
                        else
                            chatMsg(string.format(
                                "arbotas detected (id=%d) but no empty row found!", id), 0xFF4444)
                            -- log all items so you can debug
                            for i, v in ipairs(items) do
                                chatMsg(string.format("  [%d] '%s'", i - 1, v), 0xCCCCCC)
                            end
                        end
                    end
                end
            end

        else
            -- dialog closed: reset handled flag and logger
            if handled then
                handled = false
            end
            lastLoggedId = -1
        end
    end
end
