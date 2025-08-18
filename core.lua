-- core.lua
local ADDON, ns = ...
local compat = ns and ns.compat or {}

SwingTimerDB = SwingTimerDB or {}

-- Default config
local cfg = {
    locked = false,
    scale = 1.0,
    alpha = 1.0,
    showMelee = true,
    showOffhand = true,
    showRanged = true,
    showOutOfCombat = false,
    width = 260,
    height = 14,
    point = {"CENTER", UIParent, "CENTER", 0, -170},
}

local function copyInto(dst, src)
    for k,v in pairs(src) do
        if type(v) == "table" then
            dst[k] = dst[k] or {}
            copyInto(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function InitSaved()
    SwingTimerDB = SwingTimerDB or {}
    copyInto(SwingTimerDB, cfg)
end

-- State
local playerGUID
local state = {
    mhSpeed = 2.0, ohSpeed = nil, rangedSpeed = 2.0,
    mhNext = 0, ohNext = 0, rangedNext = 0,
    hasOH = false,
    autoRepeat = false,
    lastHand = "MH",
    inCombat = false,
}

-- UI handle (built in ui.lua)
local ui = {}
ns.GetUI     = function() return ui end
ns.GetState  = function() return state end
ns.GetConfig = function() return SwingTimerDB end

-- Speed helpers
local function UpdateAttackSpeeds()
    local mh, oh = UnitAttackSpeed("player")
    state.mhSpeed = mh or 2.0
    state.ohSpeed = oh
    state.hasOH = (oh ~= nil)

    local _,_,rs = UnitRangedDamage("player")
    if rs and rs > 0 then
        state.rangedSpeed = rs
    end
end

local function ResetBars(now)
    now = now or GetTime()
    state.mhNext = now + (state.mhSpeed or 2.0)
    if state.hasOH and state.ohSpeed then
        -- Stagger OH on first init, classic approximation
        state.ohNext = now + (state.ohSpeed * 0.5)
    else
        state.ohNext = 0
    end
    if state.autoRepeat then
        state.rangedNext = now + (state.rangedSpeed or 2.0)
    end
end

-- Event frame
local f = CreateFrame("Frame", ADDON.."EventsFrame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        InitSaved()
        playerGUID = UnitGUID("player")
        UpdateAttackSpeeds()

        if ns.CreateUI then ui = ns.CreateUI() end

        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("UNIT_ATTACK_SPEED")
        self:RegisterEvent("UNIT_RANGEDDAMAGE")
        self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        self:RegisterEvent("START_AUTOREPEAT_SPELL")
        self:RegisterEvent("STOP_AUTOREPEAT_SPELL")
        self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

        ResetBars(GetTime())
        ns.RefreshConfig()
        ns.ApplyDimensions()
        ns.UpdateAllBars()
        ns.UpdateLockState()
        ns.UpdateVisibility()
        ns.UpdateScaleAlpha()
        ns.RestorePosition()

    elseif event == "PLAYER_REGEN_DISABLED" then
        state.inCombat = true
        ns.UpdateVisibility()

    elseif event == "PLAYER_REGEN_ENABLED" then
        state.inCombat = false
        ns.UpdateVisibility()

    elseif event == "UNIT_ATTACK_SPEED" then
        local unit = ...
        if unit == "player" then
            local now = GetTime()
            local oldMH, oldOH = state.mhSpeed, state.ohSpeed
            UpdateAttackSpeeds()
            -- proportionally re-time remaining intervals
            local rMH = math.max(0, state.mhNext - now)
            if oldMH and oldMH > 0 and state.mhSpeed and state.mhSpeed > 0 then
                state.mhNext = now + (rMH / oldMH) * state.mhSpeed
            end
            if state.hasOH and state.ohSpeed and oldOH and oldOH > 0 then
                local rOH = math.max(0, state.ohNext - now)
                state.ohNext = now + (rOH / oldOH) * state.ohSpeed
            end
        end

    elseif event == "UNIT_RANGEDDAMAGE" then
        local unit = ...
        if unit == "player" then
            local _,_,rs = UnitRangedDamage("player")
            if rs and rs > 0 then
                local now = GetTime()
                local old = state.rangedSpeed
                state.rangedSpeed = rs
                local remain = math.max(0, state.rangedNext - now)
                if old and old > 0 then
                    state.rangedNext = now + (remain / old) * state.rangedSpeed
                end
            end
        end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        UpdateAttackSpeeds()

    elseif event == "START_AUTOREPEAT_SPELL" then
        state.autoRepeat = true
        local now = GetTime()
        if state.rangedNext < now then
            state.rangedNext = now + (state.rangedSpeed or 2.0)
        end
        ns.UpdateVisibility()

    elseif event == "STOP_AUTOREPEAT_SPELL" then
        state.autoRepeat = false
        ns.UpdateVisibility()

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subevent, _, srcGUID = CombatLogGetCurrentEventInfo()
        if srcGUID == playerGUID then
            local now = GetTime()
            if subevent == "SWING_DAMAGE" or subevent == "SWING_MISSED" then
                if state.hasOH then
                    if state.lastHand == "MH" then
                        state.ohNext = now + (state.ohSpeed or 1.5)
                        state.lastHand = "OH"
                    else
                        state.mhNext = now + (state.mhSpeed or 2.0)
                        state.lastHand = "MH"
                    end
                else
                    state.mhNext = now + (state.mhSpeed or 2.0)
                    state.lastHand = "MH"
                end
            elseif subevent == "SPELL_CAST_SUCCESS" then
                -- Auto Shot (spell id 75)
                local spellId = select(12, CombatLogGetCurrentEventInfo())
                if spellId == 75 then
                    state.rangedNext = now + (state.rangedSpeed or 2.0)
                end
            end
        end
    end
end)

-- Slash commands
SLASH_SWINGTIMER1 = "/swingtimer"
SLASH_SWINGTIMER2 = "/st"

local function help()
    print("|cff88ff88TacoRotSwingTimer:|r commands")
    print("  /st lock  |  /st unlock  |  /st reset")
    print("  /st scale <0.5-3.0>   |  /st alpha <0.2-1.0>")
    print("  /st width <px>        |  /st height <px>")
    print("  /st togglemelee | /st toggleoffhand | /st toggleranged")
    print("  /st show (out of combat) | /st hide")
end

SlashCmdList["SWINGTIMER"] = function(msg)
    msg = (msg or ""):lower()
    local a, b = msg:match("^(%S+)%s*(.-)$")
    local db = SwingTimerDB

    if a == "lock" then
        db.locked = true
        ns.UpdateLockState()
        print("TacoRotSwingTimer locked.")
    elseif a == "unlock" then
        db.locked = false
        ns.UpdateLockState()
        print("TacoRotSwingTimer unlocked. Drag to move.")
    elseif a == "reset" then
        db.point = {"CENTER", UIParent, "CENTER", 0, -170}
        ns.RestorePosition()
        print("Position reset.")
    elseif a == "scale" and b ~= "" then
        local v = tonumber(b)
        if v and v >= 0.5 and v <= 3.0 then
            db.scale = v; ns.UpdateScaleAlpha(); print("Scale set to "..v)
        else print("Scale must be 0.5–3.0") end
    elseif a == "alpha" and b ~= "" then
        local v = tonumber(b)
        if v and v >= 0.2 and v <= 1.0 then
            db.alpha = v; ns.UpdateScaleAlpha(); print("Alpha set to "..v)
        else print("Alpha must be 0.2–1.0") end
    elseif a == "width" and b ~= "" then
        local v = tonumber(b)
        if v and v >= 120 and v <= 600 then
            db.width = v; ns.ApplyDimensions(); print("Width set to "..v)
        else print("Width 120–600") end
    elseif a == "height" and b ~= "" then
        local v = tonumber(b)
        if v and v >= 8 and v <= 40 then
            db.height = v; ns.ApplyDimensions(); print("Height set to "..v)
        else print("Height 8–40") end
    elseif a == "show" then
        db.showOutOfCombat = true; ns.UpdateVisibility(); print("Showing out of combat.")
    elseif a == "hide" then
        db.showOutOfCombat = false; ns.UpdateVisibility(); print("Hiding out of combat.")
    elseif a == "togglemelee" then
        db.showMelee = not db.showMelee; ns.UpdateVisibility()
        print("Melee "..(db.showMelee and "shown" or "hidden"))
    elseif a == "toggleoffhand" then
        db.showOffhand = not db.showOffhand; ns.UpdateVisibility()
        print("Off-hand "..(db.showOffhand and "shown" or "hidden"))
    elseif a == "toggleranged" then
        db.showRanged = not db.showRanged; ns.UpdateVisibility()
        print("Ranged "..(db.showRanged and "shown" or "hidden"))
    else
        help()
    end
end
