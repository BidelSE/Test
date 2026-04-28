script_name('test_arbotas')
script_version('2.2')
require 'lib.moonloader'

-- F5 : open a REAL SAMP list dialog that mimics /arbotas.
-- F5 again (while open) : dismiss the dialog via Escape key.
-- sampSendDialogResponse is VM-blocked; Escape keystroke is used instead.

local DIALOG_ID = 9998
local active    = false

local ffi = require("ffi")
pcall(ffi.cdef, "void keybd_event(unsigned char, unsigned char, unsigned long, unsigned long*);")
local _u32ok, _u32 = pcall(ffi.load, "user32")

local function sendEscape()
    if not _u32ok then return end
    _u32.keybd_event(0x1B, 0x01, 0,    nil)  -- VK_ESCAPE press
    _u32.keybd_event(0x1B, 0x01, 0x02, nil)  -- VK_ESCAPE release
end

local function fakeLine()
    local r = math.random(5)
    if r == 1 then
        return string.format("{99CCFF}O(x %s y) = z^%d",
            math.random(2) == 1 and "^" or "*", math.random(100, 9999))
    elseif r == 2 then
        return string.format("{AADDFF}%d %d %05d",
            math.random(100, 9999), math.random(1000, 9999), math.random(10000, 99999))
    elseif r == 3 then
        return string.format("{88CCFF}%d + %05d",
            math.random(1000, 9999), math.random(1000, 99999))
    elseif r == 4 then
        return string.format("{FFAA44}* %d %05d",
            math.random(1000, 9999), math.random(10000, 99999))
    else
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
                sendEscape()
                active = false
                printStringNow("~r~Arbotas testas uzdarytas!", 2000)
            else
                -- Empty row is never placed last (parseItems drops trailing blanks).
                local nItems  = 10
                local emptyAt = math.random(1, nItems - 1)

                local rows = {
                    "Pasirinkite tuscia eilute",
                    "{FF4444}Pasirinkus blogai galima gauti Ban",
                }
                for i = 1, nItems do
                    rows[#rows + 1] = (i == emptyAt) and " " or fakeLine()
                end

                local emptyIdx = 2 + (emptyAt - 1)

                local ok, err = pcall(sampShowDialog, DIALOG_ID,
                    "Ar{IDF:fIF-} zmogus",
                    table.concat(rows, "\n"),
                    "Gerai", "", 2)

                if ok then
                    active = true
                    printStringNow(
                        "~g~Arbotas testas! Tuscia: [" .. tostring(emptyIdx) .. "]", 4000)
                else
                    printStringNow("~r~sampShowDialog blokuotas VM!", 3000)
                end
            end
        end
    end
end

function onSendDialogResponse(id, button, index, input)
    if id == DIALOG_ID then
        active = false
    end
end
