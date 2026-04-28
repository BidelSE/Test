script_name('test_arbotas')
script_version('2.0')
require 'lib.moonloader'

-- F5 : open a REAL SAMP list dialog that mimics /arbotas.
--      testdialogspy (Ctrl+F9) and isSampDialogActive() in the bot both see it.
--      arbotas_auto.lua will detect and auto-answer it after a delay,
--      giving a full end-to-end test of the pipeline.
-- F5 again (while open) : dismiss the dialog.

local DIALOG_ID = 9998   -- high ID to avoid collisions with server dialogs
local active    = false

local function fakeLine()
    local r = math.random(5)
    if r == 1 then
        return string.format("O(x %s y) = z^%d",
            math.random(2) == 1 and "^" or "*", math.random(100, 9999))
    elseif r == 2 then
        return string.format("%d %d %05d",
            math.random(100, 9999), math.random(1000, 9999), math.random(10000, 99999))
    elseif r == 3 then
        return string.format("%d + %05d",
            math.random(1000, 9999), math.random(1000, 99999))
    elseif r == 4 then
        return string.format("* %d %05d",
            math.random(1000, 9999), math.random(10000, 99999))
    else
        return string.format("|%s ; * %s%s%s",
            string.char(math.random(65, 90)),
            string.char(math.random(97, 122)),
            string.char(math.random(97, 122)),
            string.char(math.random(97, 122)))
    end
end

function main()
    wait(0)
    while true do
        wait(0)

        if isKeyJustPressed(VK_F5) then
            if active then
                -- Cancel the dialog (button 0 = right/cancel button).
                sampSendDialogResponse(DIALOG_ID, 0, 0, "")
                active = false
                printStringNow("~r~Arbotas testas uzdarytas!", 2000)
            else
                -- Build item list: 2 fixed header rows + 8-13 random rows (one empty).
                local nItems  = math.random(8, 13)
                local emptyAt = math.random(1, nItems)  -- 1-based within actual items

                local rows = {
                    "Pasirinkite tuscia eilute",
                    "Pasirinkus blogai galima gauti Ban",
                }
                for i = 1, nItems do
                    rows[#rows + 1] = (i == emptyAt) and "" or fakeLine()
                end

                -- 0-based index of the empty row (2 header rows before it).
                local emptyIdx = 2 + (emptyAt - 1)

                sampShowDialog(DIALOG_ID,
                    "Ar{IDF:fIF-} zmogus",
                    table.concat(rows, "\n"),
                    "Gerai", "", 2)   -- style 2 = LIST

                active = true
                printStringNow(
                    "~g~Arbotas testas! Tuscia eilute: [" .. tostring(emptyIdx) .. "]", 4000)
            end
        end
    end
end

-- Clear active flag when the dialog is dismissed (by arbotas_auto or manually).
function onSendDialogResponse(id, button, index, input)
    if id == DIALOG_ID then
        active = false
    end
end
