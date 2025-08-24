-- core.lua — TacoRotSwingTimer (Wrath 3.3.5a)
-- ElvUI/oUF-style single-sweep timers.
-- Ranged (Auto Shot + Shoot wand) anchors on FIRE time; CLEU hit is fallback-only.
-- Melee bars freeze at 100% while out of melee range; resume on next landed swing.

local ADDON_NAME = "TacoRotSwingTimer"

local AceAddon   = LibStub("AceAddon-3.0")
local SwingTimer = AceAddon:NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")

-- shared namespace with ui.lua
local ns = _G[ADDON_NAME] or {}
_G[ADDON_NAME] = ns

-- ---------------------------------------------------------------------------

local C = {
  AUTO_SHOT  = 75,
  SHOOT_WAND = 5019, -- "Shoot"

  SLAM_SPELLS = { [1464]=true,[8820]=true,[11604]=true,[11605]=true,[25241]=true,[25242]=true,[47474]=true,[47475]=true },

  -- tight melee-range probes (prefer class 5-yd abilities; fallback to interact)
  MELEE_RANGE_PROBE = {
    WARRIOR   = {78},              -- Heroic Strike
    ROGUE     = {1752},            -- Sinister Strike
    HUNTER    = {2973},            -- Raptor Strike
    DRUID     = {6807,1082,33876,33878}, -- Maul, Claw, Mangle(Cat/Bear)
    PALADIN   = {35395},           -- Crusader Strike
    DEATHKNIGHT = {45462,45902},   -- Plague Strike, Blood Strike
    SHAMAN    = {17364},           -- Stormstrike
  },
}

-- On-next-swing specials reset MH when they LAND
local MELEE_ONHIT_SPELL = {
  -- Hunter: Raptor Strike
  [2973]=true,[14260]=true,[14261]=true,[14262]=true,[14263]=true,[14264]=true,[14265]=true,[14266]=true,[27014]=true,[48995]=true,[48996]=true,
  -- Druid (Bear): Maul
  [6807]=true,[6808]=true,[6809]=true,[8972]=true,[9745]=true,[9880]=true,[9881]=true,[26996]=true,[48479]=true,[48480]=true,
  -- Warrior: Heroic Strike + Cleave
  [78]=true,[284]=true,[285]=true,[1608]=true,[11564]=true,[11565]=true,[11566]=true,[11567]=true,[25286]=true,[29707]=true,[30324]=true,[47449]=true,[47450]=true,
  [845]=true,[7369]=true,[11608]=true,[11609]=true,[20569]=true,[25231]=true,[47519]=true,[47520]=true,
}
for id in pairs(C.SLAM_SPELLS) do MELEE_ONHIT_SPELL[id] = true end

-- Known wand speeds (fallbacks)
local WAND_SPEEDS = {
  [11287]=1.5,[11288]=1.6,[5071]=1.6,[5207]=1.5,[13064]=1.6,[18483]=1.6,[25314]=1.5,[28064]=1.5,[34348]=1.4,[45114]=1.5,
  [49992]=1.8,[50631]=1.8,[50635]=1.8,[50684]=1.8,
}

-- ---------------------------------------------------------------------------
-- runtime state (consumed by ui.lua)

local state = {
  mhSpeed=2.0, ohSpeed=0, rangedSpeed=2.0,
  hasOH=false,

  lastSwingMH=0, nextSwingMH=0,
  lastSwingOH=0, nextSwingOH=0,
  lastRanged=0,  nextRanged=0,

  inCombat=false, isMeleeAuto=false, autoRepeat=false,

  isWand=false, wandSpeed=nil,

  slamGrace=0,           -- extends MH/OH visibility while Slam is casting
  meleeInRange=false,    -- live range gate (for freeze behavior)

  debugAllEvents=false,
  wandLogging=false,
}
ns.GetState = function() return state end

-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Helpers

local function IsInMeleeRange(unit)
  unit = unit or "target"
  if not UnitExists(unit) or UnitIsDead(unit) or not UnitCanAttack("player", unit) then
    return false
  end
  local _, class = UnitClass("player")
  local probes = C.MELEE_RANGE_PROBE[class or ""]
  if probes then
    for i=1,#probes do
      local name = GetSpellInfo(probes[i])
      if name then
        local r = IsSpellInRange(name, unit)
        if r == 1 then return true end
        if r == 0 then return false end -- definite OOR
      end
    end
  end
  -- fallback: ~10yd interact (3) — if false, you're definitely OOR
  return CheckInteractDistance(unit, 3) == 1
end

local function IsWandEquipped()
  local itemId = GetInventoryItemID("player", 18)
  if not itemId then return false end
  local name, _, _, _, _, itemType, itemSubType = GetItemInfo(itemId)
  if itemType and itemType:lower():find("weapon") and itemSubType and itemSubType:lower():find("wand") then
    return true
  end
  name = (name or ""):lower()
  return name:find("wand") ~= nil
end

local function GetRangedSpeed()
  if UnitRangedAttackSpeed then
    local spd = UnitRangedAttackSpeed("player")
    if spd and spd > 0 and spd < 10 then return spd end
  end
  if UnitRangedDamage then
    local _,_,spd = UnitRangedDamage("player")
    if spd and spd > 0 and spd < 10 then return spd end
  end
  return 2.0
end

local function GetWandSpeed()
  local itemId = GetInventoryItemID("player", 18)
  if itemId and WAND_SPEEDS[itemId] then return WAND_SPEEDS[itemId] end
  local spd = GetRangedSpeed()
  if spd and spd > 0 then return spd end
  -- tooltip scrape fallback (Wrath)
  if not state._wandTip then
    state._wandTip = CreateFrame("GameTooltip", ADDON_NAME.."WandTooltip", UIParent, "GameTooltipTemplate")
    state._wandTip:SetOwner(UIParent, "ANCHOR_NONE")
  end
  local tip = state._wandTip
  tip:ClearLines(); tip:SetInventoryItem("player", 18)
  for i=1, tip:NumLines() do
    local line = _G[ADDON_NAME.."WandTooltipTextLeft"..i]
    local text = line and line:GetText()
    if text then
      local s = text:match("Speed (%d+%.%d+)") or text:match("Speed (%d+)") or text:match("(%d+%.%d+) Speed") or text:match("(%d+) Speed")
      s = s and tonumber(s)
      if s and s > 0 and s < 10 then return s end
    end
  end
  return 1.5
end

local function UpdateSpeeds()
  local mh, oh = UnitAttackSpeed("player")
  if mh and mh > 0 then state.mhSpeed = mh end
  if oh and oh > 0 then state.ohSpeed = oh; state.hasOH = true else state.ohSpeed = 0; state.hasOH = false end

  state.isWand = IsWandEquipped()
  if state.isWand then
    state.wandSpeed   = GetWandSpeed()
    state.rangedSpeed = state.wandSpeed
  else
    state.rangedSpeed = GetRangedSpeed()
  end
end

-- preserve bar progress when a speed changes
local function RescaleAnchor(last, nextAt, oldSpeed, newSpeed)
  local now = GetTime()
  if (not last or last <= 0) or (not nextAt or nextAt <= now) or (not oldSpeed or oldSpeed <= 0) then
    return last, nextAt, (newSpeed or oldSpeed)
  end
  newSpeed = newSpeed or oldSpeed
  local remainingFrac = (nextAt - now) / oldSpeed
  if remainingFrac < 0 then remainingFrac = 0 end
  if remainingFrac > 1 then remainingFrac = 1 end
  local newNext = now + newSpeed * remainingFrac
  local newLast = now - newSpeed * (1 - remainingFrac)
  return newLast, newNext, newSpeed
end

-- parry haste trim
local function ParryHasteTrim(last, nextAt, speed)
  if not last or last <= 0 or not nextAt or nextAt <= 0 or not speed or speed <= 0 then return last, nextAt end
  local now = GetTime()
  local f = (nextAt - now) / speed
  if f <= 0 then return last, nextAt end
  local target
  if f > 0.6 then target = 0.6 elseif f > 0.2 then target = 0.2 elseif f > 0.1 then target = 0.1 else return last, nextAt end
  local newNext = now + speed * target
  local newLast = now - speed * (1 - target)
  return newLast, newNext
end

local function ClearBar(which)
  if which == "MH" then state.lastSwingMH, state.nextSwingMH = 0, 0
  elseif which == "OH" then state.lastSwingOH, state.nextSwingOH = 0, 0
  elseif which == "RG" then state.lastRanged,  state.nextRanged  = 0, 0 end
end

-- ---------------------------------------------------------------------------
-- Update loop — hide bars after a completed single sweep (+ Slam grace)
-- MH/OH only clear while IN melee range; out-of-range = freeze at 100%.

function SwingTimer:UpdateSwingPredictions()
  local now = GetTime()
  state.meleeInRange = IsInMeleeRange("target")

  -- MH
  if state.lastSwingMH > 0 and state.mhSpeed > 0 then
    local expire = state.lastSwingMH + state.mhSpeed + (state.slamGrace or 0)
    if state.meleeInRange and now >= expire then
      ClearBar("MH")
    end
  end

  -- OH
  if state.hasOH and state.lastSwingOH > 0 and state.ohSpeed > 0 then
    local expire = state.lastSwingOH + state.ohSpeed + (state.slamGrace or 0)
    if state.meleeInRange and now >= expire then
      ClearBar("OH")
    end
  end

  -- Ranged (no range freeze logic; auto-shot/wand unaffected by melee range)
  if state.lastRanged > 0 and state.rangedSpeed > 0 then
    if now >= (state.lastRanged + state.rangedSpeed) then
      ClearBar("RG")
    end
  end
end

-- ---------------------------------------------------------------------------
-- Addon lifecycle

local playerGUID
local function RebuildUI(self) ns.BuildUI(self.db.profile, state); ns.ApplyDimensions(); ns.UpdateVisibility() end

function SwingTimer:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("SwingTimerDB", defaults, true)
  self:RegisterChatCommand("st", "SlashCommand")
  self:RegisterChatCommand("swingtimer", "SlashCommand")
end

function SwingTimer:OnEnable()
  playerGUID = UnitGUID("player")
  self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  self:RegisterEvent("UNIT_ATTACK_SPEED")
  self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
  self:RegisterEvent("PLAYER_TARGET_CHANGED")
  self:RegisterEvent("PLAYER_REGEN_ENABLED")
  self:RegisterEvent("PLAYER_REGEN_DISABLED")
  self:RegisterEvent("PLAYER_ENTER_COMBAT")
  self:RegisterEvent("PLAYER_LEAVE_COMBAT")
  self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
  self:RegisterEvent("UNIT_SPELLCAST_START")
  self:RegisterEvent("UNIT_SPELLCAST_STOP")
  self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
  self:RegisterEvent("START_AUTOREPEAT_SPELL")
  self:RegisterEvent("STOP_AUTOREPEAT_SPELL")

  self.updateTimer = self:ScheduleRepeatingTimer("UpdateSwingPredictions", 0.05)

  UpdateSpeeds(); RebuildUI(self)
  if ns.SetUpdateRate and self.db and self.db.profile then
    ns.SetUpdateRate(self.db.profile.updateRate or (1/60))
  end
end

function SwingTimer:OnDisable()
  if self.updateTimer then self:CancelTimer(self.updateTimer) end
  self.updateTimer = nil
  if state._wandTip then state._wandTip:Hide(); state._wandTip = nil end
end

function SwingTimer:PLAYER_TARGET_CHANGED()
  state.meleeInRange = IsInMeleeRange("target")
end

function SwingTimer:PLAYER_REGEN_DISABLED()
  state.inCombat = true
  ns.UpdateVisibility()
end

function SwingTimer:PLAYER_REGEN_ENABLED()
  state.inCombat = false
  state.isMeleeAuto = false
  state.autoRepeat = false
  ClearBar("MH"); ClearBar("OH"); ClearBar("RG")
  ns.UpdateVisibility()
end

function SwingTimer:PLAYER_ENTER_COMBAT()
  -- Some servers/dummies don’t fire this; we also toggle isMeleeAuto on first SWING_* below.
  state.isMeleeAuto = true
  UpdateSpeeds()
end

function SwingTimer:PLAYER_LEAVE_COMBAT()
  state.isMeleeAuto = false
  ClearBar("MH"); ClearBar("OH")
end

function SwingTimer:UNIT_ATTACK_SPEED(_, unit)
  if unit and unit ~= "player" then return end
  local oldMH, oldOH, oldRG = state.mhSpeed, state.ohSpeed, state.rangedSpeed
  UpdateSpeeds()
  state.lastSwingMH, state.nextSwingMH, state.mhSpeed = RescaleAnchor(state.lastSwingMH, state.nextSwingMH, oldMH, state.mhSpeed)
  if state.hasOH then
    state.lastSwingOH, state.nextSwingOH, state.ohSpeed = RescaleAnchor(state.lastSwingOH, state.nextSwingOH, oldOH, state.ohSpeed)
  else
    ClearBar("OH")
  end
  -- rescale ranged too (haste/quiver changes mid-cycle)
  state.lastRanged, state.nextRanged, state.rangedSpeed = RescaleAnchor(state.lastRanged, state.nextRanged, oldRG, state.rangedSpeed)
end

function SwingTimer:PLAYER_EQUIPMENT_CHANGED()
  local oldMH, oldOH, oldRG = state.mhSpeed, state.ohSpeed, state.rangedSpeed
  UpdateSpeeds()
  state.lastSwingMH, state.nextSwingMH, state.mhSpeed = RescaleAnchor(state.lastSwingMH, state.nextSwingMH, oldMH, state.mhSpeed)
  if state.hasOH then
    state.lastSwingOH, state.nextSwingOH, state.ohSpeed = RescaleAnchor(state.lastSwingOH, state.nextSwingOH, oldOH, state.ohSpeed)
  else
    ClearBar("OH")
  end
  state.lastRanged, state.nextRanged, state.rangedSpeed = RescaleAnchor(state.lastRanged, state.nextRanged, oldRG, state.rangedSpeed)
end

-- Slam: extend "keep bar alive" window while the cast is channeling
function SwingTimer:UNIT_SPELLCAST_START(_, unit, spell)
  if unit ~= "player" then return end
  -- Prime wand on START so the bar moves immediately (SUCCEEDED will re-anchor if needed)
  if GetSpellInfo(C.SHOOT_WAND) == spell then
    UpdateSpeeds()
    state.isWand = true
    state.rangedSpeed = GetWandSpeed()
    local now = GetTime()
    if now - (state.lastRanged or 0) > 0.15 then
      state.lastRanged = now
      state.nextRanged = now + (state.rangedSpeed or 1.5)
      if state.wandLogging then print("|cffffcc00[WAND]|r CAST_START -> fire anchor") end
    end
  end
  for id in pairs(C.SLAM_SPELLS) do
    if GetSpellInfo(id) == spell then
      local name, _, _, startMS, endMS = UnitCastingInfo("player")
      if name and endMS and startMS then state.slamGrace = (endMS - startMS) / 1000 end
      break
    end
  end
end
function SwingTimer:UNIT_SPELLCAST_STOP(_, unit)        if unit=="player" then state.slamGrace = 0 end end
function SwingTimer:UNIT_SPELLCAST_INTERRUPTED(_, unit) if unit=="player" then state.slamGrace = 0 end end

-- Ranged: FIRE-time anchor (Auto Shot / Shoot). CLEU hit is fallback-only.
function SwingTimer:UNIT_SPELLCAST_SUCCEEDED(_, unit, spell, _, _, spellId)
  if unit ~= "player" then return end
  local id = spellId
  if not id then
    if GetSpellInfo(C.AUTO_SHOT)  == spell then id = C.AUTO_SHOT end
    if GetSpellInfo(C.SHOOT_WAND) == spell then id = C.SHOOT_WAND end
  end
  if id == C.AUTO_SHOT or id == C.SHOOT_WAND then
    UpdateSpeeds()
    state.isWand = (id == C.SHOOT_WAND)
    if state.isWand then state.rangedSpeed = GetWandSpeed() end
    local now = GetTime()
    if now - (state.lastRanged or 0) > 0.15 then -- guard against double-anchors
      state.lastRanged = now
      state.nextRanged = now + (state.rangedSpeed or 2.0)
      if state.wandLogging then
        print(string.format("|cffffcc00[WAND/RG]|r SUCCEEDED (%s) -> +%.2fs", id==C.SHOOT_WAND and "Shoot" or "Auto", state.rangedSpeed or -1))
      end
    end
  end
end

function SwingTimer:START_AUTOREPEAT_SPELL()
  state.autoRepeat = true
end
function SwingTimer:STOP_AUTOREPEAT_SPELL()
  state.autoRepeat = false
  ClearBar("RG")
end

-- ---------------------------------------------------------------------------
-- Combat log (Wrath 3.3.5 argument order)

local function OnCLEU(timestamp, eventType, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)
  local now = GetTime()

  if state.debugAllEvents and srcGUID == playerGUID then
    local args = {...}; local a=""
    for i=1,math.min(4,#args) do a=a.." "..tostring(args[i]) end
    print("|cff88ccff[ST Events]|r "..eventType..a)
  end

  -- Outgoing melee autos
  if srcGUID == playerGUID and (eventType == "SWING_DAMAGE" or eventType == "SWING_MISSED") then
    state.isMeleeAuto = true -- in case PLAYER_ENTER_COMBAT didn't fire (dummy, etc.)
    local mainSpeed, offSpeed = UnitAttackSpeed("player")
    if offSpeed and offSpeed > 0 then
      state.lastSwingMH = now; state.nextSwingMH = now + (mainSpeed or state.mhSpeed or 2.0)
      state.lastSwingOH = now; state.nextSwingOH = now + (offSpeed  or state.ohSpeed or 1.5)
    else
      state.lastSwingMH = now; state.nextSwingMH = now + (mainSpeed or state.mhSpeed or 2.0)
      ClearBar("OH")
    end
    return
  end

  -- Outgoing ranged autos: fallback-only (if fire event didn't anchor)
  if srcGUID == playerGUID and (eventType == "RANGE_DAMAGE" or eventType == "RANGE_MISSED") then
    if state.lastRanged == 0 then
      UpdateSpeeds()
      state.isWand = IsWandEquipped()
      state.lastRanged = now
      state.nextRanged = now + (state.rangedSpeed or 2.0)
      if state.wandLogging then print("|cffffcc00[WAND/RG]|r RANGE_* Fallback -> +"
        ..string.format("%.2f", state.rangedSpeed or -1)) end
    end
    return
  end

  if srcGUID == playerGUID then
    local spellId = ...
    -- Some cores log shots as SPELL_*; still fallback-only
    if (eventType == "SPELL_DAMAGE" or eventType == "SPELL_MISSED") and
       (spellId == C.SHOOT_WAND or spellId == C.AUTO_SHOT) then
      if state.lastRanged == 0 then
        UpdateSpeeds()
        state.isWand = (spellId == C.SHOOT_WAND)
        if state.isWand then state.rangedSpeed = GetWandSpeed() end
        state.lastRanged = now
        state.nextRanged = now + (state.rangedSpeed or 2.0)
        if state.wandLogging then print("|cffffcc00[WAND/RG]|r SPELL_* Fallback -> +"
          ..string.format("%.2f", state.rangedSpeed or -1)) end
      end
      return
    end

    -- On-next-swing specials land
    if (eventType == "SPELL_DAMAGE" or eventType == "SPELL_MISSED" or eventType == "SPELL_CAST_SUCCESS") and MELEE_ONHIT_SPELL[spellId] then
      local mainSpeed, offSpeed = UnitAttackSpeed("player")
      if offSpeed and offSpeed > 0 then
        state.lastSwingMH = now; state.nextSwingMH = now + (mainSpeed or state.mhSpeed or 2.0)
        state.lastSwingOH = now; state.nextSwingOH = now + (offSpeed  or state.ohSpeed or 1.5)
      else
        state.lastSwingMH = now; state.nextSwingMH = now + (mainSpeed or state.mhSpeed or 2.0)
        ClearBar("OH")
      end
      return
    end
  end

  -- Incoming parry -> parry haste trim
  if dstGUID == UnitGUID("player") and eventType == "SWING_MISSED" then
    local missType = ...
    if missType == "PARRY" then
      state.lastSwingMH, state.nextSwingMH = ParryHasteTrim(state.lastSwingMH, state.nextSwingMH, state.mhSpeed)
      if state.hasOH then
        state.lastSwingOH, state.nextSwingOH = ParryHasteTrim(state.lastSwingOH, state.nextSwingOH, state.ohSpeed)
      end
    end
  end
end

function SwingTimer:COMBAT_LOG_EVENT_UNFILTERED(_, ...)
  OnCLEU(...)
end

-- ---------------------------------------------------------------------------
-- Slash

local function help(self)
  pr(self, "|cffffd200TacoRotSwingTimer:|r (Elv-style; ranged anchored on fire)")
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
  pr(self, "/st debug            - print current swing timer state")
  pr(self, "/st events [on|off]  - toggle event spam")
  pr(self, "/st wandlog [on|off] - toggle wand/ranged debug")
end

local function setBoolToggle(current, word, onoff)
  onoff = (onoff or ""):lower()
  if onoff == "on"  then return true,  word.." ON"  end
  if onoff == "off" then return false, word.." OFF" end
  return not current, word.." "..(current and "OFF" or "ON")
end

function SwingTimer:SlashCommand(input)
  input = (input or ""):gsub("^%s+",""):gsub("%s+$","")
  if input == "" or input=="help" or input=="?" then help(self); return end

  local db = self.db.profile
  local cmd, arg = input:match("^(%S+)%s*(.*)$")
  local narg = tonumber(arg)

  if cmd=="lock"   then db.locked=true;  ns.Lock(true);  pr(self,"Locked."); return end
  if cmd=="unlock" then db.locked=false; ns.Lock(false); pr(self,"Unlocked; drag to move."); return end
  if cmd=="reset"  then db.posX=0; db.posY=120; ns.BuildUI(db, state); ns.ApplyDimensions(); ns.UpdateVisibility(); pr(self,"Reset."); return end

  if cmd=="fps" and narg then
    local fps = math.max(15, math.min(240, narg))
    db.updateRate = 1 / fps
    if ns.SetUpdateRate then ns.SetUpdateRate(db.updateRate) end
    pr(self, "Animation FPS set to "..fps); return
  end

  if cmd=="scale"  and narg then db.scale=narg;           ns.ApplyDimensions(); pr(self,("Scale %.2f"):format(narg)); return end
  if cmd=="alpha"  and narg then db.alpha=narg;           ns.ApplyDimensions(); pr(self,("Alpha %.2f"):format(narg)); return end
  if cmd=="width"  and narg then db.width=math.floor(narg);     ns.ApplyDimensions(); pr(self,"Width "..db.width.."px"); return end
  if cmd=="height" and narg then db.barHeight=math.floor(narg); ns.ApplyDimensions(); pr(self,"Height "..db.barHeight.."px"); return end
  if cmd=="gap"    and narg then db.gap=math.floor(narg);       ns.ApplyDimensions(); pr(self,"Gap "..db.gap.."px"); return end

  if cmd=="show" and arg:lower()=="ooc" then
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
  if input:match("^mh%s+on$")     then setbar("mh", true);  return end
  if input:match("^mh%s+off$")    then setbar("mh", false); return end
  if input:match("^oh%s+on$")     then setbar("oh", true);  return end
  if input:match("^oh%s+off$")    then setbar("oh", false); return end
  if input:match("^rg%s+on$")     then setbar("rg", true);  return end
  if input:match("^rg%s+off$")    then setbar("rg", false); return end
  if input:match("^ranged%s+on$") then setbar("rg", true);  return end
  if input:match("^ranged%s+off$")then setbar("rg", false); return end

  if cmd=="debug" then
    local now = GetTime()
    pr(self, "=== Swing Timing (fire-anchored ranged) ===")
    pr(self, string.format("MH: spd=%.2f last=%.2f next=%.2f rem=%.2fs", state.mhSpeed or 0, state.lastSwingMH or 0, state.nextSwingMH or 0, (state.nextSwingMH>0) and (state.nextSwingMH-now) or 0))
    if state.hasOH then
      pr(self, string.format("OH: spd=%.2f last=%.2f next=%.2f rem=%.2fs", state.ohSpeed or 0, state.lastSwingOH or 0, state.nextSwingOH or 0, (state.nextSwingOH>0) and (state.nextSwingOH-now) or 0))
    else
      pr(self, "OH: (none)")
    end
    pr(self, string.format("RG: spd=%.2f last=%.2f next=%.2f rem=%.2fs (wand:%s)", state.rangedSpeed or 0, state.lastRanged or 0, state.nextRanged or 0, (state.nextRanged>0) and (state.nextRanged-now) or 0, state.isWand and "YES" or "NO"))
    pr(self, "MeleeInRange: "..(state.meleeInRange and "YES" or "NO"))
    return
  end

  if cmd=="events" then
    local new, msg = setBoolToggle(state.debugAllEvents, "Event spam", arg)
    state.debugAllEvents = new
    pr(self, msg); return
  end

  if cmd=="wandlog" then
    local new, msg = setBoolToggle(state.wandLogging, "Wand logging", arg)
    state.wandLogging = new
    pr(self, msg); return
  end

  pr(self,"Unknown command."); help(self)
end
