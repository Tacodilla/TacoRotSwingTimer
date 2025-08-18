-- core.lua
local ADDON, ns = ...
local compat = ns and ns.compat or {}

SwingTimerDB = SwingTimerDB or {}

local cfg = {
    locked = false,
    scale = 1.0,
    alpha = 1.0,
    showMelee = true,
    showOffhand = true,
    showRanged = true,
    showOutOfCombat = false,
    point = {"CENTER", UIParent, "CENTER", 0, -150},
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

-- Frames made in ui.lua
local ui = {}

ns.GetUI = function() return ui end
ns.GetState = function() return state end
ns.GetConfig = function() return SwingTimerDB end

-- Update attack speeds
local function UpdateAttackSpeeds()
    local mh, oh = UnitAttackSpeed("player")
    state.mhSpeed = mh or 2.0
    state.ohSpeed = oh
    state.hasOH = (oh ~= nil)

    local _,_,speed = UnitRangedDamage("player")
    if speed and speed > 0 then
        state.rangedSpeed = speed
    end
end

local function ResetBars(now)
    now = now or GetTime()
    state.mhNext = now + (state.mhSpeed or 2.0)
    if state.hasOH and state.ohSpeed then
        state.ohNext = now + (state.ohSpeed * 0.5)
    else
        state.ohNext = 0
    end
    if state.autoRepeat then
        state.rangedNext = now + (state.rangedSpeed or 2.0)
    end
end

-- Event handler
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
            UpdateAttackSpeeds()
        end
    elseif event == "UNIT_RANGEDDAMAGE" then
        local unit = ...
        if unit == "player" then
            local _,_,speed = UnitRangedDamage("player")
            if speed and speed > 0 then
                state.rangedSpeed = speed
            end
        end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        UpdateAttackSpeeds()
    elseif event == "START_AUTOREPEAT_SPELL" then
        state.autoRepeat = true
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

SlashCmdList["SWINGTIMER"] = function(msg)
    msg = (msg or ""):lower()
    local arg, rest = msg:match("^(%S+)%s*(.-)$")
    local db = SwingTimerDB
    if arg == "lock" then
        db.locked = true
        ns.UpdateLockState()
        print("SwingTimer locked.")
    elseif arg == "unlock" then
        db.locked = false
        ns.UpdateLockState()
        print("SwingTimer unlocked. Drag to move.")
    elseif arg == "reset" then
        db.point = { "CENTER", UIParent, "CENTER", 0, -150 }
        ns.RestorePosition()
        print("SwingTimer position reset.")
    else
        print("SwingTimer commands: /st lock, unlock, reset")
    end
end
