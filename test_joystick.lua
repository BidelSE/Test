script_name('test_joystick')
script_version('1.0')
require 'lib.moonloader'

-- Joystick / gamepad detector.
-- Shows live axis values, button states, and POV hat.
-- Uses winmm.dll joyGetPosEx — no samp.* needed, works in VMware.
-- Ctrl+F10 : toggle overlay on/off

local font  = nil
local show  = true   -- on by default so you see it immediately
local tick  = 0
local data  = {}     -- last scanned state per joystick slot

-- ── FFI setup ─────────────────────────────────────────────────────────────────

local ffi, winmm

local function initFFI()
    local ok
    ok, ffi = pcall(require, "ffi")
    if not ok then return false end

    pcall(ffi.cdef, [[
        typedef unsigned long DWORD;
        typedef unsigned int  UINT;

        typedef struct {
            DWORD dwSize;
            DWORD dwFlags;
            DWORD dwXpos;
            DWORD dwYpos;
            DWORD dwZpos;
            DWORD dwRpos;
            DWORD dwUpos;
            DWORD dwVpos;
            DWORD dwButtons;
            DWORD dwButtonNumber;
            DWORD dwPOV;
            DWORD dwReserved1;
            DWORD dwReserved2;
        } JOYINFOEX;

        typedef struct {
            UINT  wMid;
            UINT  wPid;
            char  szPname[32];
            UINT  wXmin; UINT wXmax;
            UINT  wYmin; UINT wYmax;
            UINT  wZmin; UINT wZmax;
            UINT  wNumButtons;
            UINT  wPeriodMin;
            UINT  wPeriodMax;
            UINT  wRmin; UINT wRmax;
            UINT  wUmin; UINT wUmax;
            UINT  wVmin; UINT wVmax;
            UINT  wCaps;
            UINT  wMaxAxes;
            UINT  wNumAxes;
            UINT  wMaxButtons;
            char  szRegKey[32];
            char  szOEMVxD[260];
        } JOYCAPSA;

        UINT joyGetNumDevs();
        UINT joyGetPosEx(UINT uJoyID, JOYINFOEX* pji);
        UINT joyGetDevCapsA(UINT uJoyID, JOYCAPSA* pjc, UINT cbjc);
    ]])

    local wok
    wok, winmm = pcall(ffi.load, "winmm")
    return wok
end

-- ── joystick polling ──────────────────────────────────────────────────────────

local JOY_RETURNALL = 0xFF
local JOYERR_NOERROR = 0

local function pollAll()
    local result = {}
    if not (ffi and winmm) then
        result[1] = { err = "FFI/winmm not available" }
        return result
    end

    local numSlots = tonumber(winmm.joyGetNumDevs()) or 0
    if numSlots == 0 then
        result[1] = { err = "no joystick driver installed" }
        return result
    end

    for slot = 0, math.min(numSlots - 1, 3) do   -- check up to 4 slots
        local info = ffi.new("JOYINFOEX")
        info.dwSize  = ffi.sizeof("JOYINFOEX")
        info.dwFlags = JOY_RETURNALL

        local ret = tonumber(winmm.joyGetPosEx(slot, info))

        if ret == JOYERR_NOERROR then
            -- read device name
            local caps = ffi.new("JOYCAPSA")
            local name = "joystick"
            if tonumber(winmm.joyGetDevCapsA(slot, caps, ffi.sizeof("JOYCAPSA"))) == 0 then
                name = ffi.string(caps.szPname)
            end

            -- decode buttons into a string like "1 3 5"
            local btns, nb = {}, tonumber(info.dwButtonNumber) or 0
            local bmask = tonumber(info.dwButtons) or 0
            for b = 0, 31 do
                if bit.band(bmask, bit.lshift(1, b)) ~= 0 then
                    table.insert(btns, tostring(b + 1))
                end
            end

            -- POV hat
            local pov = tonumber(info.dwPOV) or 0xFFFF
            local povStr = (pov == 0xFFFF or pov == 0xFFFFFFFF) and "center"
                or string.format("%d°", pov / 100)

            -- normalise axes to -100..+100
            local function norm(v, lo, hi)
                lo, hi = lo or 0, hi or 65535
                local mid = (hi + lo) / 2
                local range = (hi - lo) / 2
                if range == 0 then return 0 end
                return math.floor(((tonumber(v) or mid) - mid) / range * 100 + 0.5)
            end

            table.insert(result, {
                slot    = slot,
                name    = name,
                x       = norm(info.dwXpos),
                y       = norm(info.dwYpos),
                z       = norm(info.dwZpos),
                r       = norm(info.dwRpos),
                u       = norm(info.dwUpos),
                v       = norm(info.dwVpos),
                buttons = #btns > 0 and table.concat(btns, " ") or "none",
                nb      = nb,
                pov     = povStr,
            })
        elseif ret == 160  -- MMSYSERR_NODRIVER  (no driver for this slot)
            or ret == 161  -- MMSYSERR_INVALPARAM
            or ret == 165  -- JOYERR_PARMS (slot mapped but no device — common in VMware)
            or ret == 166  -- JOYERR_NOCANDO
            or ret == 167  -- JOYERR_UNPLUGGED
        then
            -- slot present but nothing connected — skip silently
        else
            table.insert(result, { slot = slot, err = string.format("slot %d: unknown error %d", slot, ret) })
        end
    end

    if #result == 0 then
        result[1] = { err = "no joystick connected" }
    end

    return result
end

-- ── build display lines ───────────────────────────────────────────────────────

local function buildLines()
    local out = {}
    local devices = pollAll()

    for _, d in ipairs(devices) do
        if d.err then
            table.insert(out, { text = d.err, col = 0xFFFF4444 })
        else
            table.insert(out, { text = string.format("Slot %d: %s", d.slot, d.name), col = 0xFFFFCC44 })
            table.insert(out, { text = string.format("  X:%-4d  Y:%-4d  Z:%-4d", d.x, d.y, d.z), col = 0xFFCCCCFF })
            table.insert(out, { text = string.format("  R:%-4d  U:%-4d  V:%-4d", d.r, d.u, d.v), col = 0xFFCCCCFF })
            table.insert(out, { text = string.format("  Buttons(%d): %s", d.nb, d.buttons), col = d.nb > 0 and 0xFF44FF44 or 0xFF888888 })
            table.insert(out, { text = string.format("  POV: %s", d.pov), col = 0xFFCCCCCC })
        end
    end

    return out
end

-- ── main ─────────────────────────────────────────────────────────────────────

function main()
    wait(0)

    local ffiOk = initFFI()

    while true do
        wait(0)

        if isKeyDown(0x11) and isKeyJustPressed(VK_F10) then
            show = not show
            data = {}
            printStringNow(show and "~g~Joystick debug ON" or "~r~Joystick debug OFF", 1500)
        end

        if not font then
            font = renderCreateFont("Arial", 9, 4)
        end

        if show then
            tick = tick + 1
            if tick >= 10 then   -- poll every 10 frames (~6 times/sec)
                tick = 0
                data = ffiOk and buildLines()
                    or { { text = "FFI unavailable — cannot read joystick", col = 0xFFFF4444 } }
            end

            if font and data and #data > 0 then
                local x, y, lh = 8, 480, 12
                local bw = 300
                renderDrawBox(x-3, y-3, bw, #data*lh+10, 0xCC000000)
                renderDrawBox(x-3, y-3, bw, 13, 0xFF222200)
                renderFontDrawText(font, "JOYSTICK  Ctrl+F10", x, y, 0xFFFFCC44)
                for i, row in ipairs(data) do
                    renderFontDrawText(font, row.text, x, y + i*lh, row.col)
                end
            end
        end
    end
end
