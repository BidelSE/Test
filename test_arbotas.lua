script_name('test_arbotas')
script_version('1.0')
require 'lib.moonloader'

-- F5        : show fake Ar zmogus dialog, bot auto-answers after 3-7s
-- F5 again  : close dialog early

local active = false
local lines = {}
local emptyIdx = 0
local cursor = 1
local botResult = nil
local botRunning = false
local font = nil

local function fakeLine()
    local r = math.random(5)
    if r == 1 then
        return string.format("O(x %s y) = z^%d", math.random(2)==1 and "^" or "*", math.random(100, 9999))
    elseif r == 2 then
        return string.format("%d %d %05d", math.random(100,9999), math.random(1000,9999), math.random(10000,99999))
    elseif r == 3 then
        return string.format("%d + %05d", math.random(1000,9999), math.random(1000,99999))
    elseif r == 4 then
        return string.format("* %d %05d", math.random(1000,9999), math.random(10000,99999))
    else
        return string.format("|%s ; * %s%s%s", string.char(math.random(65,90)),
            string.char(math.random(97,122)), string.char(math.random(97,122)), string.char(math.random(97,122)))
    end
end

function main()
    wait(0)
    _G.VR_TEST_ARBOTAS = false
    while true do
        wait(0)

        if isKeyJustPressed(VK_F5) then
            if active then
                active = false
                botResult = nil
                botRunning = false
                _G.VR_TEST_ARBOTAS = false
            else
                local nItems = math.random(8, 13)
                local ePos   = math.random(3, nItems)
                lines = {}
                for i = 1, nItems do
                    lines[i] = (i == ePos) and "" or fakeLine()
                end
                emptyIdx   = ePos
                cursor     = 1
                botResult  = nil
                botRunning = true
                active     = true
                _G.VR_TEST_ARBOTAS = true

                lua_thread.create(function()
                    wait(math.random(3000, 7000))
                    for _ = 1, emptyIdx - 1 do
                        cursor = math.min(cursor + 1, #lines)
                        wait(math.random(40, 90))
                    end
                    wait(math.random(300, 800))
                    botResult  = lines[cursor] == ""
                    botRunning = false
                    wait(3000)
                    active             = false
                    botResult          = nil
                    _G.VR_TEST_ARBOTAS = false
                end)
            end
        end

        -- lazy font creation
        if not font then
            font = renderCreateFont("Arial", 11, 1)
        end

        if active and font then
            local dw      = 310
            local lineH   = 17
            local headerH = 54
            local dh      = headerH + #lines * lineH + 28
            local dx, dy  = 485, 110

            -- border + background
            renderDrawBox(dx - 2, dy - 2, dw + 4, dh + 4, 0xFF888888)
            renderDrawBox(dx, dy, dw, dh, 0xFF111111)

            -- title bar
            renderDrawBox(dx, dy, dw, 18, 0xFF880000)
            renderFontDrawText(font, "Ar zmogus", dx + 4, dy + 2, 0xFFFFFFFF)

            -- header rows
            renderDrawBox(dx, dy + 18, dw, 18, 0xFF661111)
            renderFontDrawText(font, "Pasirinkite tuscia eilute",             dx + 4, dy + 20, 0xFFFF6666)
            renderFontDrawText(font, "Pasirinkus blogai galima gauti Ban",    dx + 4, dy + 36, 0xFFFF4444)

            -- list items
            for i, line in ipairs(lines) do
                local ly = dy + headerH + (i - 1) * lineH
                if i == cursor then
                    renderDrawBox(dx, ly, dw, lineH, 0xFF223366)
                end
                if line ~= "" then
                    renderFontDrawText(font, line, dx + 4, ly + 2, 0xFF44AAFF)
                end
            end

            -- button bar
            local btnY = dy + headerH + #lines * lineH + 4
            renderDrawBox(dx, btnY, dw, 20, 0xFF222222)
            renderFontDrawText(font, "[ Gerai ]", dx + dw/2 - 25, btnY + 2, 0xFFAAAAAA)

            -- bot status
            if botResult == true then
                renderFontDrawText(font, "BOT: Teisingai! (tuscia eilute surasta)", dx + 4, btnY + 4, 0xFF22FF22)
            elseif botResult == false then
                renderFontDrawText(font, "BOT: Neteisingai!", dx + 4, btnY + 4, 0xFFFF2222)
            elseif botRunning then
                renderFontDrawText(font, "BOT galvoja...", dx + 4, btnY + 4, 0xFFFFFF00)
            end
        end
    end
end
