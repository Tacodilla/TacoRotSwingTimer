-- core.lua - Ace3 Integrated Version
local ADDON_NAME = "TacoRotSwingTimer"
local SwingTimer = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")
local AceDB = LibStub("AceDB-3.0")

-- Create namespace
local ns = {}
_G[ADDON_NAME] = ns
ns.SwingTimer = SwingTimer

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

-- Default config for AceDB
local defaults = {
    profile = {
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
}

-- State variables
local playerGUID
local state = {
    mhSpeed = CONSTANTS.DEFAULT_MH_SPEED, 
    ohSpeed = nil, 
    rangedSpeed = CONSTANTS.DEFAULT_RANGED_SPEED,
    mhNext = 0, 
    ohNext = 0, 
    rangedNext = 0,
    hasOH = false,
    autoRepeat = false,
    lastHand = "MH",
    inCombat = false,
}

local ui = {}

-- Namespace accessors
ns.GetUI = function() return ui end
ns.GetState = function() return state end
ns.GetConfig = function() return SwingTimer.db.profile end

-- Ace3 addon lifecycle
function SwingTimer:OnInitialize()
    self.db = AceDB:New("SwingTimerDB", defaults, true)
    self:RegisterChatCommand("swingtimer", "SlashCommand")
    self:RegisterChatCommand("st", "SlashCommand")
end

function SwingTimer:OnEnable()
    playerGUID = UnitGUID("player")
    self:UpdateAttackSpeeds()
    
    if ns.CreateUI then 
        ui = ns.CreateUI() 
    end
    
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED") 
    self:RegisterEvent("UNIT_ATTACK_SPEED")
    self:RegisterEvent("UNIT_RANGEDDAMAGE")
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    self:RegisterEvent("START_AUTOREPEAT_SPELL")
    self:RegisterEvent("STOP_AUTOREPEAT_SPELL")
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    
    self:ResetBars(GetTime())
    self:RefreshConfig()
    self:ApplyDimensions()
    self:UpdateAllBars()
    self:UpdateLockState()
    self:UpdateVisibility()
    self:UpdateScaleAlpha()
    self:RestorePosition()
end

-- Event handlers
function SwingTimer:PLAYER_REGEN_DISABLED()
    state.inCombat = true
    self:UpdateVisibility()
end

function SwingTimer:PLAYER_REGEN_ENABLED()
    state.inCombat = false
    self:UpdateVisibility()
end

function SwingTimer:UNIT_ATTACK_SPEED(event, unit)
    if unit == "player" then
        local now = GetTime()
        local oldMH, oldOH = state.mhSpeed, state.ohSpeed
        self:UpdateAttackSpeeds()
        local rMH = math.max(0, state.mhNext - now)
        if oldMH and oldMH > 0 and state.mhSpeed and state.mhSpeed > 0 then
            state.mhNext = now + (rMH / oldMH) * state.mhSpeed
        end
        if state.hasOH and state.ohSpeed and oldOH and oldOH > 0 then
            local rOH = math.max(0, state.ohNext - now)
            state.ohNext = now + (rOH / oldOH) * state.ohSpeed
        end
    end
end

function SwingTimer:UNIT_RANGEDDAMAGE(event, unit)
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
end

function SwingTimer:PLAYER_EQUIPMENT_CHANGED()
    self:UpdateAttackSpeeds()
end

function SwingTimer:START_AUTOREPEAT_SPELL()
    state.autoRepeat = true
    local now = GetTime()
    if state.rangedNext < now then
        state.rangedNext = now + (state.rangedSpeed or CONSTANTS.DEFAULT_RANGED_SPEED)
    end
    self:UpdateVisibility()
end

function SwingTimer:STOP_AUTOREPEAT_SPELL()
    state.autoRepeat = false
    self:UpdateVisibility()
end

function SwingTimer:COMBAT_LOG_EVENT_UNFILTERED(event, timestamp, subevent, hideCaster, srcGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellId, spellName, spellSchool)
    if srcGUID == playerGUID then
        local now = GetTime()
        if subevent == "SWING_DAMAGE" or subevent == "SWING_MISSED" then
            local hand = self:GetSwingHand(true, state.hasOH)
            if hand == "MH" then
                state.mhNext = now + (state.mhSpeed or CONSTANTS.DEFAULT_MH_SPEED)
            else
                state.ohNext = now + (state.ohSpeed or CONSTANTS.DEFAULT_OH_SPEED)
            end
            state.lastHand = hand
        elseif subevent == "SPELL_CAST_SUCCESS" then
            if spellId == CONSTANTS.AUTO_SHOT_SPELL_ID then
                state.rangedNext = now + (state.rangedSpeed or CONSTANTS.DEFAULT_RANGED_SPEED)
            end
        end
    end
end

-- Core functions
function SwingTimer:UpdateAttackSpeeds()
    local mh, oh = UnitAttackSpeed("player")
    state.mhSpeed = mh or CONSTANTS.DEFAULT_MH_SPEED
    state.ohSpeed = oh
    state.hasOH = (oh ~= nil)

    local _,_,rs = UnitRangedDamage("player")
    state.rangedSpeed = (rs and rs > 0) and rs or CONSTANTS.DEFAULT_RANGED_SPEED
end

function SwingTimer:ResetBars(now)
    now = now or GetTime()
    state.mhNext = now + (state.mhSpeed or CONSTANTS.DEFAULT_MH_SPEED)
    if state.hasOH and state.ohSpeed then
        state.ohNext = now + (state.ohSpeed * CONSTANTS.OH_STAGGER_MULTIPLIER)
    else
        state.ohNext = 0
    end
    if state.autoRepeat then
        state.rangedNext = now + (state.rangedSpeed or CONSTANTS.DEFAULT_RANGED_SPEED)
    end
end

function SwingTimer:GetSwingHand(hasMainHand, hasOffHand)
    if not hasOffHand then
        return "MH"
    end
    return state.lastHand == "MH" and "OH" or "MH"
end

-- UI Interface methods
function SwingTimer:RefreshConfig()
    -- Called by UI
end

function SwingTimer:RestorePosition()
    if ns.RestorePosition then ns.RestorePosition() end
end

function SwingTimer:UpdateLockState()
    if ns.UpdateLockState then ns.UpdateLockState() end
end

function SwingTimer:UpdateScaleAlpha()
    if ns.UpdateScaleAlpha then ns.UpdateScaleAlpha() end
end

function SwingTimer:UpdateAllBars()
    if ns.UpdateAllBars then ns.UpdateAllBars() end
end

function SwingTimer:UpdateVisibility()
    if ns.UpdateVisibility then ns.UpdateVisibility() end
end

function SwingTimer:ApplyDimensions()
    if ns.ApplyDimensions then ns.ApplyDimensions() end
end

-- Slash command handler
function SwingTimer:SlashCommand(input)
    input = (input or ""):lower()
    local a, b = input:match("^(%S+)%s*(.-)$")
    local db = self.db.profile

    if a == "lock" then
        db.locked = true
        self:UpdateLockState()
        self:Print("TacoRotSwingTimer locked.")
    elseif a == "unlock" then
        db.locked = false
        self:UpdateLockState()
        self:Print("TacoRotSwingTimer unlocked. Drag to move.")
    elseif a == "reset" then
        db.point = {"CENTER", UIParent, "CENTER", 0, -170}
        self:RestorePosition()
        self:Print("Position reset.")
    elseif a == "scale" and b ~= "" then
        local v = tonumber(b)
        if v and v >= CONSTANTS.MIN_SCALE and v <= CONSTANTS.MAX_SCALE then
            db.scale = v
            self:UpdateScaleAlpha()
            self:Print("Scale set to "..v)
        else
            self:Print("Scale must be between "..CONSTANTS.MIN_SCALE.." and "..CONSTANTS.MAX_SCALE)
        end
    elseif a == "alpha" and b ~= "" then
        local v = tonumber(b)
        if v and v >= CONSTANTS.MIN_ALPHA and v <= CONSTANTS.MAX_ALPHA then
            db.alpha = v
            self:UpdateScaleAlpha()
            self:Print("Alpha set to "..v)
        else
            self:Print("Alpha must be between "..CONSTANTS.MIN_ALPHA.." and "..CONSTANTS.MAX_ALPHA)
        end
    elseif a == "width" and b ~= "" then
        local v = tonumber(b)
        if v and v >= 120 and v <= 600 then
            db.width = v
            self:ApplyDimensions()
            self:Print("Width set to "..v)
        else
            self:Print("Width must be between 120 and 600")
        end
    elseif a == "height" and b ~= "" then
        local v = tonumber(b)
        if v and v >= 8 and v <= 40 then
            db.height = v
            self:ApplyDimensions()
            self:Print("Height set to "..v)
        else
            self:Print("Height must be between 8 and 40")
        end
    elseif a == "show" then
        db.showOutOfCombat = true
        self:UpdateVisibility()
        self:Print("Showing out of combat.")
    elseif a == "hide" then
        db.showOutOfCombat = false
        self:UpdateVisibility()
        self:Print("Hiding out of combat.")
    elseif a == "togglemelee" then
        db.showMelee = not db.showMelee
        self:UpdateVisibility()
        self:Print("Melee "..(db.showMelee and "shown" or "hidden"))
    elseif a == "toggleoffhand" then
        db.showOffhand = not db.showOffhand
        self:UpdateVisibility()
        self:Print("Off-hand "..(db.showOffhand and "shown" or "hidden"))
    elseif a == "toggleranged" then
        db.showRanged = not db.showRanged
        self:UpdateVisibility()
        self:Print("Ranged "..(db.showRanged and "shown" or "hidden"))
    else
        self:Print("|cff88ff88TacoRotSwingTimer:|r commands")
        self:Print("  /st lock  |  /st unlock  |  /st reset")
        self:Print("  /st scale <0.5-3.0>   |  /st alpha <0.2-1.0>")
        self:Print("  /st width <px>        |  /st height <px>")
        self:Print("  /st togglemelee | /st toggleoffhand | /st toggleranged")
        self:Print("  /st show (out of combat) | /st hide")
    end
end
