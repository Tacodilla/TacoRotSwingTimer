-- core.lua - Fixed Ace3 Integration
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
    
    playerGUID = UnitGUID("player")
    
    -- Initialize UI namespace functions (but don't create frames yet)
    self:SetupNamespaceFunctions()
end

function SwingTimer:OnEnable()
    -- Register events
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateWeaponInfo")
    self:RegisterEvent("UNIT_INVENTORY_CHANGED", "OnInventoryChanged")
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RegisterEvent("START_AUTOREPEAT_SPELL")
    self:RegisterEvent("STOP_AUTOREPEAT_SPELL")
    
    -- NOW create and initialize the UI
    self:InitializeUI()
    
    -- Update initial state
    self:UpdateWeaponInfo()
    self:RefreshConfig()
    
    self:Print(ADDON_NAME .. " v1.0.0 loaded! Use /swingtimer for options.")
end

function SwingTimer:OnDisable()
    if ns.GetUI and ns.GetUI().root then
        ns.GetUI().root:Hide()
    end
end

-- NEW: Initialize UI after Ace3 is ready
function SwingTimer:InitializeUI()
    -- Create the UI elements
    ui = ns.CreateUI()
    
    -- Configure the UI with our database
    ns.RefreshConfig()
    ns.RestorePosition()
    ns.UpdateLockState()
    ns.UpdateScaleAlpha()
    ns.UpdateAllBars()
    ns.UpdateVisibility()
    ns.ApplyDimensions()
end

-- Set up namespace functions that UI will use
function SwingTimer:SetupNamespaceFunctions()
    -- These functions will be called by ui.lua after frames are created
    function ns.RefreshConfig()
        -- This is called by UI after frames exist
    end
    
    function ns.RestorePosition()
        if ui and ui.root then
            local p = self.db.profile.point
            ui.root:ClearAllPoints()
            ui.root:SetPoint(p[1], p[2], p[3], p[4], p[5])
        end
    end
    
    function ns.UpdateLockState()
        if ui and ui.root then
            ui.root:EnableMouse(not self.db.profile.locked)
        end
    end
    
    function ns.UpdateScaleAlpha()
        if ui and ui.root then
            ui.root:SetScale(self.db.profile.scale or 1.0)
            ui.root:SetAlpha(self.db.profile.alpha or 1.0)
        end
    end
    
    function ns.UpdateAllBars()
        if not ui then return end
        
        local db = self.db.profile
        local tex = db.barTexture or "Interface\\TargetingFrame\\UI-StatusBar"
        local font = db.fontFace or "GameFontHighlightSmall"
        
        for _, bar in pairs({ui.mh, ui.oh, ui.rg}) do
            if bar then
                bar:SetStatusBarTexture(tex)
                if bar.text then
                    bar.text:SetFontObject(font)
                end
                if not db.showTimeText then
                    bar.text:Hide()
                end
                if not db.showSparkEffect then
                    bar.spark:Hide()
                end
            end
        end
    end
    
    function ns.UpdateVisibility()
        if not ui then return end
        
        local db = self.db.profile
        local show = db.showOutOfCombat or state.inCombat or state.autoRepeat
        
        if ui.root.SetShown then
            ui.root:SetShown(show)
            ui.mh:SetShown(db.showMelee)
            ui.oh:SetShown(db.showOffhand and state.hasOH)
            ui.rg:SetShown(db.showRanged)
        else
            -- Fallback for older clients
            if show then ui.root:Show() else ui.root:Hide() end
            if db.showMelee then ui.mh:Show() else ui.mh:Hide() end
            if db.showOffhand and state.hasOH then ui.oh:Show() else ui.oh:Hide() end
            if db.showRanged then ui.rg:Show() else ui.rg:Hide() end
        end
    end
    
    function ns.ApplyDimensions()
        if ui and ui.root and ns.LayoutBars then
            ns.LayoutBars()
        end
    end
end

-- Event handlers
function SwingTimer:OnInventoryChanged(event, unit)
    if unit == "player" then
        self:UpdateWeaponInfo()
    end
end

function SwingTimer:PLAYER_REGEN_DISABLED()
    state.inCombat = true
    self:UpdateVisibility()
end

function SwingTimer:PLAYER_REGEN_ENABLED()
    state.inCombat = false
    self:UpdateVisibility()
end

function SwingTimer:START_AUTOREPEAT_SPELL()
    state.autoRepeat = true
    self:ResetBars()
    self:UpdateVisibility()
end

function SwingTimer:STOP_AUTOREPEAT_SPELL()
    state.autoRepeat = false
    self:UpdateVisibility()
end

function SwingTimer:COMBAT_LOG_EVENT_UNFILTERED()
    local timestamp, eventType, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, 
          destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()
    
    if sourceGUID ~= playerGUID then return end
    
    if eventType == "SWING_DAMAGE" or eventType == "SWING_MISSED" then
        local now = GetTime()
        local hand = self:GetSwingHand(true, state.hasOH)
        
        if hand == "MH" then
            state.mhNext = now + (state.mhSpeed or CONSTANTS.DEFAULT_MH_SPEED)
            state.lastHand = "MH"
        elseif hand == "OH" and state.hasOH then
            state.ohNext = now + (state.ohSpeed or CONSTANTS.DEFAULT_OH_SPEED)
            state.lastHand = "OH"
        end
    elseif eventType == "SPELL_CAST_SUCCESS" then
        local spellId = select(12, CombatLogGetCurrentEventInfo())
        if spellId == CONSTANTS.AUTO_SHOT_SPELL_ID and state.autoRepeat then
            state.rangedNext = GetTime() + (state.rangedSpeed or CONSTANTS.DEFAULT_RANGED_SPEED)
        end
    end
end

function SwingTimer:UpdateWeaponInfo()
    local function GetAttackSpeed(unit)
        local mh, oh = UnitAttackSpeed(unit)
        return mh, oh
    end
    
    local mh, oh = GetAttackSpeed("player")
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

-- UI Interface methods (now properly implemented)
function SwingTimer:RefreshConfig()
    ns.RefreshConfig()
    self:UpdateAllBars()
    self:UpdateVisibility()
    self:UpdateScaleAlpha()
    self:ApplyDimensions()
end

function SwingTimer:RestorePosition()
    ns.RestorePosition()
end

function SwingTimer:UpdateLockState()
    ns.UpdateLockState()
end

function SwingTimer:UpdateScaleAlpha()
    ns.UpdateScaleAlpha()
end

function SwingTimer:UpdateAllBars()
    ns.UpdateAllBars()
end

function SwingTimer:UpdateVisibility()
    ns.UpdateVisibility()
end

function SwingTimer:ApplyDimensions()
    ns.ApplyDimensions()
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
    elseif a == "scale" then
        local newScale = tonumber(b)
        if newScale and newScale >= CONSTANTS.MIN_SCALE and newScale <= CONSTANTS.MAX_SCALE then
            db.scale = newScale
            self:UpdateScaleAlpha()
            self:Print("Scale set to " .. newScale)
        else
            self:Print("Scale must be between " .. CONSTANTS.MIN_SCALE .. " and " .. CONSTANTS.MAX_SCALE)
        end
    elseif a == "alpha" then
        local newAlpha = tonumber(b)
        if newAlpha and newAlpha >= CONSTANTS.MIN_ALPHA and newAlpha <= CONSTANTS.MAX_ALPHA then
            db.alpha = newAlpha
            self:UpdateScaleAlpha()
            self:Print("Alpha set to " .. newAlpha)
        else
            self:Print("Alpha must be between " .. CONSTANTS.MIN_ALPHA .. " and " .. CONSTANTS.MAX_ALPHA)
        end
    elseif a == "show" then
        if b == "ooc" then
            db.showOutOfCombat = not db.showOutOfCombat
            self:UpdateVisibility()
            self:Print("Show out of combat: " .. tostring(db.showOutOfCombat))
        else
            self:Print("Usage: show ooc")
        end
    else
        self:Print("TacoRotSwingTimer v1.0.0 Commands:")
        self:Print("/st lock/unlock - Lock or unlock the frame")
        self:Print("/st reset - Reset position to center")
        self:Print("/st scale X - Set scale (0.5-3.0)")
        self:Print("/st alpha X - Set transparency (0.2-1.0)")
        self:Print("/st show ooc - Toggle show out of combat")
    end
end
