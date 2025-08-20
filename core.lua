-- core.lua
local ADDON, ns = ...
local compat = ns and ns.compat or {}

local CONSTANTS = {
    DEFAULT_MH_SPEED = 2.0,
    DEFAULT_OH_SPEED = 1.5,
    DEFAULT_RANGED_SPEED = 2.0,
    OH_STAGGER_MULTIPLIER = 0.5,
    AUTO_SHOT_SPELL_ID = 75,
    MIN_SCALE = 0.5,
    MAX_SCALE = 3.0,
    MIN_ALPHA = 0.2,
    MAX_ALPHA = 1.0,
}
ns.CONSTANTS = CONSTANTS

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
    updateRate = 0.05,
    showSparkEffect = true,
    showTimeText = true,
    barTexture = "Interface\\TargetingFrame\\UI-StatusBar",
    fontFace = "GameFontHighlightSmall",
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
    mhSpeed = CONSTANTS.DEFAULT_MH_SPEED, ohSpeed = nil, rangedSpeed = CONSTANTS.DEFAULT_RANGED_SPEED,
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
    state.mhSpeed = mh or CONSTANTS.DEFAULT_MH_SPEED
    state.ohSpeed = oh
    state.hasOH = (oh ~= nil)

    local _,_,rs = UnitRangedDamage("player")
    state.rangedSpeed = (rs and rs > 0) and rs or CONSTANTS.DEFAULT_RANGED_SPEED
end

local function ResetBars(now)
    now = now or GetTime()
    state.mhNext = now + (state.mhSpeed or CONSTANTS.DEFAULT_MH_SPEED)
    if state.hasOH and state.ohSpeed then
        -- Stagger OH on first init, classic approximation
        state.ohNext = now + (state.ohSpeed * CONSTANTS.OH_STAGGER_MULTIPLIER)
    else
        state.ohNext = 0
    end
    if state.autoRepeat then
        state.rangedNext = now + (state.rangedSpeed or CONSTANTS.DEFAULT_RANGED_SPEED)
    end
end

local function GetSwingHand(hasMainHand, hasOffHand)
    if not hasOffHand then
        return "MH"
    end
    -- simple alternating logic; could be replaced with more advanced checks
    return state.lastHand == "MH" and "OH" or "MH"
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
            else
                state.rangedSpeed = CONSTANTS.DEFAULT_RANGED_SPEED
            end
        end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        UpdateAttackSpeeds()

    elseif event == "START_AUTOREPEAT_SPELL" then
        state.autoRepeat = true
        local now = GetTime()
        if state.rangedNext < now then
            state.rangedNext = now + (state.rangedSpeed or CONSTANTS.DEFAULT_RANGED_SPEED)
        end
        ns.UpdateVisibility()

    elseif event == "STOP_AUTOREPEAT_SPELL" then
        state.autoRepeat = false
        ns.UpdateVisibility()

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- In 3.3.5a, combat log arguments are passed directly to the event handler
        local timestamp, subevent, hideCaster, srcGUID, sourceName, sourceFlags, sourceRaidFlags,
              destGUID, destName, destFlags, destRaidFlags, spellId, spellName, spellSchool = ...

        if srcGUID == playerGUID then
            local now = GetTime()
            if subevent == "SWING_DAMAGE" or subevent == "SWING_MISSED" then
                local hand = GetSwingHand(true, state.hasOH)
                if hand == "MH" then
                    state.mhNext = now + (state.mhSpeed or CONSTANTS.DEFAULT_MH_SPEED)
                else
                    state.ohNext = now + (state.ohSpeed or CONSTANTS.DEFAULT_OH_SPEED)
                end
                state.lastHand = hand
            elseif subevent == "SPELL_CAST_SUCCESS" then
                -- spellId is now directly available from the event arguments
                if spellId == CONSTANTS.AUTO_SHOT_SPELL_ID then
                    state.rangedNext = now + (state.rangedSpeed or CONSTANTS.DEFAULT_RANGED_SPEED)
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

local function validateNumber(value, min, max, name)
    local num = tonumber(value)
    if not num then
        print(name .. " must be a number")
        return nil
    end
    if num < min or num > max then
        print(name .. " must be between " .. min .. " and " .. max)
        return nil
    end
    return num
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
        local v = validateNumber(b, CONSTANTS.MIN_SCALE, CONSTANTS.MAX_SCALE, "Scale")
        if v then db.scale = v; ns.UpdateScaleAlpha(); print("Scale set to "..v) end
    elseif a == "alpha" and b ~= "" then
        local v = validateNumber(b, CONSTANTS.MIN_ALPHA, CONSTANTS.MAX_ALPHA, "Alpha")
        if v then db.alpha = v; ns.UpdateScaleAlpha(); print("Alpha set to "..v) end
    elseif a == "width" and b ~= "" then
        local v = validateNumber(b, 120, 600, "Width")
        if v then db.width = v; ns.ApplyDimensions(); print("Width set to "..v) end
    elseif a == "height" and b ~= "" then
        local v = validateNumber(b, 8, 40, "Height")
        if v then db.height = v; ns.ApplyDimensions(); print("Height set to "..v) end
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
