script_name('test_arbotas')
script_version('2.1')
require 'lib.moonloader'

-- F5 : open a REAL SAMP list dialog that mimics /arbotas.
--      Matches the real server structure: 2 header rows + 10 actual items,
--      one of them a visible blank black row (the correct answer).
--      Items are colored like the real arbotas so the blank row stands out.
--      testdialogspy (Ctrl+F9) and isSampDialogActive() in the bot both see it.
--      arbotas_auto.lua will navigate to and select the blank row automatically.
-- F5 again (while open) : dismiss the dialog.

local DIALOG_ID = 9998
local active    = false

-- Color codes matching real arbotas item styles.
local function fakeLine()
    local r = math.random(5)
    if r == 1 then
        -- equation style → light blue
        return string.format("{99CCFF}O(x %s y) = z^%d",
            math.random(2) == 1 and "^" or "*", math.random(100, 9999))
    elseif r == 2 then
        -- triple-number style → soft blue
        return string.format("{AADDFF}%d %d %05d",
            math.random(100, 9999), math.random(1000, 9999), math.random(10000, 99999))
    elseif r == 3 then
        -- addition style → slightly lighter blue
        return string.format("{88CCFF}%d + %05d",
            math.random(1000, 9999), math.random(1000, 99999))
    elseif r == 4 then
        -- asterisk style → orange (matches real arbotas)
        return string.format("{FFAA44}* %d %05d",
            math.random(1000, 9999), math.random(10000, 99999))
    else
        -- pipe style → warm beige
        return string.format("{FFDDAA}|%s ; * %s%s%s",
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
                sampSendDialogResponse(DIALOG_ID, 0, 0, "")
                active = false
                printStringNow("~r~Arbotas testas uzdarytas!", 2000)
            else
                -- Real arbotas: 2 header rows + 10 actual items, 1 of them empty.
                -- Empty row is never placed last (parseItems drops trailing blanks,
                -- which would hide it from arbotas_auto detection).
                local nItems  = 10
                local emptyAt = math.random(1, nItems - 1)  -- 1-based within actual items

                local rows = {
                    "Pasirinkite tuscia eilute",
                    "{FF4444}Pasirinkus blogai galima gauti Ban",
                }
                for i = 1, nItems do
                    rows[#rows + 1] = (i == emptyAt) and "" or fakeLine()
                end

                -- 0-based index of the blank row in the full list.
                local emptyIdx = 2 + (emptyAt - 1)

                sampShowDialog(DIALOG_ID,
                    "Ar{IDF:fIF-} zmogus",
                    table.concat(rows, "\n"),
                    "Gerai", "", 2)

                active = true
                printStringNow(
                    "~g~Arbotas testas! Tuscia: [" .. tostring(emptyIdx) .. "]", 4000)
            end
        end
    end
end

function onSendDialogResponse(id, button, index, input)
    if id == DIALOG_ID then
        active = false
    end
end
