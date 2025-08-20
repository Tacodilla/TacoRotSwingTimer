-- core.lua — TacoRotSwingTimer (Wrath 3.3.5a)
-- Requires: AceAddon-3.0, AceConsole-3.0, AceEvent-3.0, AceTimer-3.0, AceDB-3.0

local ADDON_NAME = "TacoRotSwingTimer"

local AceAddon   = LibStub("AceAddon-3.0")
local SwingTimer = AceAddon:NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")

-- shared namespace with ui.lua
local ns = _G[ADDON_NAME] or {}
_G[ADDON_NAME] = ns

-- constants
local C = {
  AUTO_SHOT = 75,
  DEF_MH = 2.0, DEF_OH = 1.5, DEF_R = 2.0,
}

-- runtime state (read by UI)
local state = {
  mhSpeed=C.DEF_MH, ohSpeed=C.DEF_OH, rangedSpeed=C.DEF_R,
  mhNext=0, ohNext=0, rangedNext=0,
  hasOH=false, lastHand="MH",
  inCombat=false, isMeleeAuto=false, autoRepeat=false,
}
ns.GetState = function() return state end

-- DB defaults (added per-bar size + gap + toggles)
local defaults = {
  profile = {
    locked=false, scale=1.0, alpha=1.0,
    width=240, barHeight=18, gap=6,
    posX=0, posY=120,

    showOutOfCombat=true,
    showMelee=true,      -- Main-Hand
    showOffhand=true,    -- Off-Hand
    showRanged=true,     -- Ranged
    fontSize=12,
  }
}

local function num(x) return tonumber(x) end
local function pr(self, msg) self:Print(msg) end

-- speeds
local function UpdateSpeeds()
  local mh, oh = UnitAttackSpeed("player")
  if mh and mh>0 then state.mhSpeed = mh end
  if oh and oh>0 then state.ohSpeed = oh; state.hasOH = true else state.hasOH = false end
  if UnitRangedAttackSpeed then
    local rs = UnitRangedAttackSpeed("player")
    if rs and rs>0 then state.rangedSpeed = rs end
  end
end

local playerGUID, tick
local function RebuildUI(self) ns.BuildUI(self.db.profile, state); ns.ApplyDimensions(); ns.UpdateVisibility() end
local function ToggleTick(self, on)
  if on then
    if tick then self:CancelTimer(tick) end
    tick = self:ScheduleRepeatingTimer(function() ns.UpdateBars(GetTime(), state) end, 0.05)
  else
    if tick then self:CancelTimer(tick) end
    tick = nil
  end
end

function SwingTimer:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("TacoRotSwingTimerDB", defaults, true)
  self:RegisterChatCommand("swingtimer", "SlashCommand")
  self:RegisterChatCommand("st", "SlashCommand")
end

function SwingTimer:OnEnable()
  playerGUID = UnitGUID("player")
  UpdateSpeeds()
  RebuildUI(self)
  ToggleTick(self, true)

  -- world/combat state
  self:RegisterEvent("PLAYER_ENTERING_WORLD", function() playerGUID = UnitGUID("player"); UpdateSpeeds(); ns.UpdateVisibility() end)
  self:RegisterEvent("PLAYER_REGEN_DISABLED", function() state.inCombat = true;  ns.UpdateVisibility() end)
  self:RegisterEvent("PLAYER_REGEN_ENABLED",  function() state.inCombat = false; ns.UpdateVisibility() end)

  -- melee auto attack (Wrath)
  self:RegisterEvent("PLAYER_ENTER_COMBAT", function() state.isMeleeAuto = true;  ns.UpdateVisibility() end)
  self:RegisterEvent("PLAYER_LEAVE_COMBAT", function() state.isMeleeAuto = false; ns.UpdateVisibility() end)

  -- hunter auto shot toggles
  self:RegisterEvent("START_AUTOREPEAT_SPELL", function() state.autoRepeat = true;  ns.UpdateVisibility() end)
  self:RegisterEvent("STOP_AUTOREPEAT_SPELL",  function() state.autoRepeat = false; ns.UpdateVisibility() end)

  -- speed refreshers
  self:RegisterEvent("UNIT_ATTACK_SPEED", function(_,u) if u=="player" then UpdateSpeeds() end end)
  self:RegisterEvent("UNIT_INVENTORY_CHANGED", function(_,u) if u=="player" then UpdateSpeeds() end end)
  if UnitRangedAttackSpeed then
    self:RegisterEvent("UNIT_RANGEDDAMAGE", function(_,u) if u=="player" then UpdateSpeeds() end end)
  end

  -- combat log (3.3.5 header)
  self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

function SwingTimer:OnDisable()
  ToggleTick(self, false)
  local root = ns.GetUI and ns.GetUI(); if root then root:Hide() end
end

-- combat log (Wrath varargs)
function SwingTimer:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
  local p = {...}
  local eventType, sourceGUID = p[2], p[3]
  if sourceGUID ~= playerGUID then return end

  local now = GetTime()

  if eventType == "SWING_DAMAGE" or eventType == "SWING_MISSED" then
    if state.hasOH and state.lastHand == "MH" then
      state.ohNext = now + (state.ohSpeed or C.DEF_OH); state.lastHand = "OH"
    else
      state.mhNext = now + (state.mhSpeed or C.DEF_MH); state.lastHand = "MH"
    end

  elseif eventType == "SPELL_CAST_SUCCESS" then
    local spellId = p[9]
    if spellId == C.AUTO_SHOT and state.autoRepeat then
      state.rangedNext = now + (state.rangedSpeed or C.DEF_R)
    end

  elseif eventType == "RANGE_DAMAGE" or eventType == "RANGE_MISSED" then
    if state.autoRepeat then state.rangedNext = now + (state.rangedSpeed or C.DEF_R) end
  end
end

-- --------------------------- slash commands --------------------------------
local function help(self)
  pr(self, "|cffffd200TacoRotSwingTimer:|r")
  pr(self, "/st lock|unlock       - lock movement")
  pr(self, "/st reset            - center group")
  pr(self, "/st scale <0.5-3.0>  - frame scale")
  pr(self, "/st alpha <0.1-1.0>  - frame alpha")
  pr(self, "/st width <px>       - bar width")
  pr(self, "/st height <px>      - bar height")
  pr(self, "/st gap <px>         - space between bars")
  pr(self, "/st show ooc         - toggle always-visible out of combat")
  pr(self, "/st mh on|off        - show/hide Main-Hand bar")
  pr(self, "/st oh on|off        - show/hide Off-Hand bar")
  pr(self, "/st rg on|off        - show/hide Ranged bar")
  pr(self, "/st test             - pulse all bars once")
end

function SwingTimer:SlashCommand(input)
  input = (input or ""):gsub("^%s+",""):gsub("%s+$",""):lower()
  local db = self.db.profile
  if input == "" or input=="help" or input=="?" then help(self); return end

  if input=="lock"   then db.locked=true;  ns.Lock(true);  pr(self,"Locked."); return end
  if input=="unlock" then db.locked=false; ns.Lock(false); pr(self,"Unlocked; drag to move."); return end
  if input=="reset"  then db.posX=0; db.posY=120; ns.BuildUI(db, state); ns.ApplyDimensions(); ns.UpdateVisibility(); pr(self,"Reset."); return end

  local cmd, arg = input:match("^(%S+)%s*(.*)$")
  local narg = tonumber(arg)

  if cmd=="scale" and narg then db.scale=narg; ns.ApplyDimensions(); pr(self,("Scale %.2f"):format(narg)); return end
  if cmd=="alpha" and narg then db.alpha=narg; ns.ApplyDimensions(); pr(self,("Alpha %.2f"):format(narg)); return end
  if cmd=="width" and narg then db.width=math.floor(narg); ns.ApplyDimensions(); pr(self,"Width "..db.width.."px"); return end
  if cmd=="height" and narg then db.barHeight=math.floor(narg); ns.ApplyDimensions(); pr(self,"Height "..db.barHeight.."px"); return end
  if cmd=="gap" and narg then db.gap=math.floor(narg); ns.ApplyDimensions(); pr(self,"Gap "..db.gap.."px"); return end

  if cmd=="show" and arg=="ooc" then
    db.showOutOfCombat = not db.showOutOfCombat; ns.UpdateVisibility()
    pr(self, "Always show OOC: "..(db.showOutOfCombat and "ON" or "OFF")); return
  end

  local function setbar(which, on)
    if which=="mh" then db.showMelee = on
    elseif which=="oh" then db.showOffhand = on
    elseif which=="rg" or which=="ranged" then db.showRanged = on
    else pr(self,"Bar must be mh / oh / rg"); return end
    ns.UpdateVisibility(); ns.ApplyDimensions()
    pr(self, (on and "Showing " or "Hiding ")..which.." bar.")
  end

  local which, val = input:match("^(mh|oh|rg)%s+(on|off)$")
  if which and val then setbar(which, val=="on"); return end

  if cmd=="test" then
    local now = GetTime()
    state.mhNext = now + (state.mhSpeed or C.DEF_MH)
    if state.hasOH then state.ohNext = now + (state.ohSpeed or C.DEF_OH) end
    state.rangedNext = now + (state.rangedSpeed or C.DEF_R)
    ns.UpdateBars(now, state); ns.UpdateVisibility(); pr(self,"Test pulses queued."); return
  end

  pr(self,"Unknown command."); help(self)
end
