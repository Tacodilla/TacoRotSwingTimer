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
  AUTO_SHOT = 75,         -- spellID
  DEF_MH = 2.0, DEF_OH = 1.5, DEF_R = 2.0,
}

-- Hunter melee specials that should RESET MH swing when they land.
-- Raptor Strike (all ranks through WotLK) + Mongoose Bite ranks.
-- Abilities that should reset the MH timer when they LAND (Wrath 3.3.5a).
local MELEE_ONHIT_SPELL = {
  -- Hunter: Raptor Strike (all ranks)
  [2973]=true,[14260]=true,[14261]=true,[14262]=true,[14263]=true,[14264]=true,[14265]=true,[14266]=true,[27014]=true,[48995]=true,[48996]=true,

  -- Hunter: Mongoose Bite (all ranks)
  [1495]=true,[14269]=true,[14270]=true,[14271]=true,[36916]=true,

  -- Druid (Bear): Maul (all ranks)
  [6807]=true,[6808]=true,[6809]=true,[8972]=true,[9745]=true,[9880]=true,[9881]=true,[26996]=true,[48479]=true,[48480]=true,

  -- Warrior: Heroic Strike (all ranks)
  [78]=true,[284]=true,[285]=true,[1608]=true,[11564]=true,[11565]=true,[11566]=true,[11567]=true,[25286]=true,[29707]=true,[30324]=true,[47449]=true,[47450]=true,

  -- Warrior: Cleave (all ranks)
  [845]=true,[7369]=true,[11608]=true,[11609]=true,[20569]=true,[25231]=true,[47519]=true,[47520]=true,

  -- Rogue: Sinister Strike (many servers treat as yellow-only; include if your realm resets swing on SS)
  [1752]=true,[1757]=true,[1758]=true,[1759]=true,[1760]=true,[8621]=true,[11293]=true,[11294]=true,[26861]=true,[26862]=true,[48637]=true,[48638]=true,
}



-- runtime state
local state = {
  mhSpeed=2.0, ohSpeed=1.5, rangedSpeed=2.0,
  mhNext=0, ohNext=0, rangedNext=0,
  mhLast=nil, ohLast=nil, rangedLast=nil,
  lastHand="MH",
  inCombat=false, isMeleeAuto=false, autoRepeat=false,
  timeOffset=nil, -- GetTime() - CLEU timestamp (smoothed)
}
ns.GetState = function() return state end

-- DB defaults
local defaults = {
  profile = {
    updateRate=1/60,
    locked=false, scale=1.0, alpha=1.0,
    width=240, barHeight=18, gap=6,
    posX=0, posY=120,
    showOutOfCombat=true,
    showMelee=true, showOffhand=true, showRanged=true,
    fontSize=12,
  }
}

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
  -- re-anchor nexts off the last known swing moment so changes snap correctly
  if state.mhLast then state.mhNext = state.mhLast + (state.mhSpeed or C.DEF_MH) end
  if state.ohLast then state.ohNext = state.ohLast + (state.ohSpeed or C.DEF_OH) end
  if state.rangedLast then state.rangedNext = state.rangedLast + (state.rangedSpeed or C.DEF_R) end
end

-- map CLEU server timestamp -> local GetTime() space (smoothed)
local function localEventTime(cleuTS)
  local now = GetTime()
  local estOffset = now - cleuTS
  if not state.timeOffset then
    state.timeOffset = estOffset
  else
    state.timeOffset = state.timeOffset * 0.98 + estOffset * 0.02
  end
  return cleuTS + state.timeOffset
end

local playerGUID, tick
local function RebuildUI(self) ns.BuildUI(self.db.profile, state); ns.ApplyDimensions(); ns.UpdateVisibility() end
local function ToggleTick(self, on)
  if tick then self:CancelTimer(tick); tick = nil end
  -- UI's smooth driver handles animation; no periodic tick needed.
end

-- --------------------------- WoW events ------------------------------------
function SwingTimer:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("SwingTimerDB", defaults, true)
  self:RegisterChatCommand("st", "SlashCommand")
  self:RegisterChatCommand("swingtimer", "SlashCommand")
end

function SwingTimer:OnEnable()
  playerGUID = UnitGUID("player")
  self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  self:RegisterEvent("PLAYER_REGEN_ENABLED")
  self:RegisterEvent("PLAYER_REGEN_DISABLED")
  self:RegisterEvent("PLAYER_ENTER_COMBAT")
  self:RegisterEvent("PLAYER_LEAVE_COMBAT")
  self:RegisterEvent("START_AUTOREPEAT_SPELL")
  self:RegisterEvent("STOP_AUTOREPEAT_SPELL")
  self:RegisterEvent("UNIT_ATTACK_SPEED")
  self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
  self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")

  UpdateSpeeds(); RebuildUI(self)
  if ns.SetUpdateRate and self.db and self.db.profile then ns.SetUpdateRate(self.db.profile.updateRate or (1/60)) end
end

function SwingTimer:OnDisable()
  ToggleTick(self, false)
end

-- combat state
function SwingTimer:PLAYER_REGEN_DISABLED() state.inCombat = true; ToggleTick(self, true); ns.UpdateVisibility() end
function SwingTimer:PLAYER_REGEN_ENABLED()  state.inCombat = false; ToggleTick(self, false); ns.UpdateVisibility() end

function SwingTimer:PLAYER_ENTER_COMBAT()
  state.isMeleeAuto = true
  -- when swapping to melee, refresh speeds and seed an immediate MH cycle
  UpdateSpeeds()
  local now = GetTime()
  state.mhLast = now
  state.mhNext = now + (state.mhSpeed or C.DEF_MH)
end

function SwingTimer:PLAYER_LEAVE_COMBAT()
  state.isMeleeAuto = false
end

function SwingTimer:START_AUTOREPEAT_SPELL() state.autoRepeat = true end
function SwingTimer:STOP_AUTOREPEAT_SPELL()  state.autoRepeat = false end
function SwingTimer:UNIT_ATTACK_SPEED() UpdateSpeeds() end
function SwingTimer:PLAYER_EQUIPMENT_CHANGED() UpdateSpeeds() end
function SwingTimer:ACTIVE_TALENT_GROUP_CHANGED() UpdateSpeeds() end

-- helpers
local function clampPeriod(base, observed)
  if not base or base <= 0 then base = 2.0 end
  local minP = base * 0.40
  local maxP = base * 1.60
  if not observed or observed <= 0 then return base end
  if observed < minP then return minP end
  if observed > maxP then return maxP end
  return observed
end

local function assignHand(t)
  if not state.hasOH then return "MH" end
  local dn = math.huge
  local hand = state.lastHand == "MH" and "OH" or "MH"
  if state.mhNext then
    local d = math.abs(t - state.mhNext); if d < dn then dn = d; hand = "MH" end
  end
  if state.ohNext then
    local d = math.abs(t - state.ohNext); if d < dn then dn = d; hand = "OH" end
  end
  return hand
end

-- --------------------------- Combat Log (Wrath 3.3.5a) ---------------------
-- Header order: timestamp, eventType, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...
local function OnCLEU(timestamp, eventType, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)
  if srcGUID ~= playerGUID then return end
  local t = localEventTime(timestamp)

  -- --- MELEE AUTOS ---
  if eventType == "SWING_DAMAGE" or eventType == "SWING_MISSED" then
    local hand = assignHand(t)
    if hand == "MH" then
      local base = state.mhSpeed or C.DEF_MH
      local observed = state.mhLast and (t - state.mhLast) or base
      local period = clampPeriod(base, observed)
      state.mhLast = t
      state.mhNext = t + period
      state.lastHand = "MH"
    else
      local base = state.ohSpeed or C.DEF_OH
      local observed = state.ohLast and (t - state.ohLast) or base
      local period = clampPeriod(base, observed)
      state.ohLast = t
      state.ohNext = t + period
      state.lastHand = "OH"
    end
    return
  end

  -- --- RANGED AUTOS ---
  if eventType == "RANGE_DAMAGE" or eventType == "RANGE_MISSED" then
    local base = state.rangedSpeed or C.DEF_R
    local observed = state.rangedLast and (t - state.rangedLast) or base
    local period = clampPeriod(base, observed)
    state.rangedLast = t
    state.rangedNext = t + period
    return
  end

  -- --- SPECIALS THAT CONSUME / REPLACE MH SWING (e.g., Raptor Strike) ---
  if eventType == "SPELL_DAMAGE" or eventType == "SPELL_MISSED" then
    local spellId = ...
    if MELEE_ONHIT_SPELL[spellId] then
      -- make sure we’re using current weapon speed
      UpdateSpeeds()
      local base = state.mhSpeed or C.DEF_MH
      local observed = state.mhLast and (t - state.mhLast) or base
      local period = clampPeriod(base, observed)
      state.mhLast = t
      state.mhNext = t + period
      state.lastHand = "MH"
      return
    end
  end

  if eventType == "SPELL_CAST_SUCCESS" then
    local spellId = ...
    if spellId == C.AUTO_SHOT and state.autoRepeat then
      local base = state.rangedSpeed or C.DEF_R
      state.rangedLast = t
      state.rangedNext = t + base
      return
    end
  end
end

-- AceEvent passes (self, event, ...)
function SwingTimer:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
  OnCLEU(...)
end

-- --------------------------- Commands --------------------------------------
local function help(self)
  pr(self, "|cffffd200TacoRotSwingTimer:|r")
  pr(self, "/st lock|unlock       - lock movement")
  pr(self, "/st reset            - center group")
  pr(self, "/st scale <0.5-3.0>  - frame scale")
  pr(self, "/st alpha <0.1-1.0>  - frame alpha")
  pr(self, "/st width <px>       - bar width")
  pr(self, "/st height <px>      - bar height")
  pr(self, "/st gap <px>         - space between bars")
  pr(self, "/st fps <15-240>     - animation FPS (default 60)")
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

  if cmd=="fps" and narg then
    local fps = math.max(15, math.min(240, narg))
    db.updateRate = 1 / fps
    if ns.SetUpdateRate then ns.SetUpdateRate(db.updateRate) end
    pr(self, "Animation FPS set to "..fps)
    return
  end

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

  if input:match("^mh%s+on$") then setbar("mh", true); return end
  if input:match("^mh%s+off$") then setbar("mh", false); return end
  if input:match("^oh%s+on$") then setbar("oh", true); return end
  if input:match("^oh%s+off$") then setbar("oh", false); return end
  if input:match("^rg%s+on$") then setbar("rg", true); return end
  if input:match("^rg%s+off$") then setbar("rg", false); return end
  if input:match("^ranged%s+on$") then setbar("rg", true); return end
  if input:match("^ranged%s+off$") then setbar("rg", false); return end

  if cmd=="test" then
    local now = GetTime()
    state.mhLast = now;     state.mhNext = now + (state.mhSpeed or C.DEF_MH)
    if state.hasOH then state.ohLast = now; state.ohNext = now + (state.ohSpeed or C.DEF_OH) end
    state.rangedLast = now; state.rangedNext = now + (state.rangedSpeed or C.DEF_R)
    ns.UpdateBars(now, state); ns.UpdateVisibility(); pr(self,"Test pulses queued."); return
  end

  pr(self,"Unknown command."); help(self)
end
