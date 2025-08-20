-- ui.lua — TacoRotSwingTimer (Wrath 3.3.5a)
-- Three independent frames (MH, OH, Ranged). Each moves & toggles separately.

local ADDON_NAME = "TacoRotSwingTimer"
local ns = _G[ADDON_NAME] or {}
_G[ADDON_NAME] = ns

ns.compat = ns.compat or {}
local compat = ns.compat

local db, state
local frames = {}  -- key -> {frame, bar, left, right, spark}

local COLORS = {
  mh = {0.90, 0.20, 0.20},
  oh = {0.20, 0.55, 0.95},
  rg = {1.00, 0.85, 0.20},
}
local TITLES = { mh="Main-Hand", oh="Off-Hand", rg="Ranged" }

local function SafeSetShown(f, on) 
  if f then 
    if on then 
      f:Show() 
    else 
      f:Hide() 
    end 
  end 
end

local function ApplyBackdrop(frame, alpha)
  if compat and compat.ApplyBackdrop then compat.ApplyBackdrop(frame, alpha); return end
  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile="Interface\\ChatFrame\\ChatFrameBackground",
      edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
      tile=true, tileSize=16, edgeSize=12,
      insets={left=2,right=2,top=2,bottom=2},
    })
    frame:SetBackdropColor(0,0,0, alpha or 0.75)
  end
end

local function NewSingleFrame(key)
  local f = CreateFrame("Frame", "TRST_"..key:upper(), UIParent)
  f:SetFrameStrata("MEDIUM")
  f:SetMovable(true); f:EnableMouse(true)
  ApplyBackdrop(f, 0.75)

  local bar = CreateFrame("StatusBar", nil, f)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetMinMaxValues(0,1); bar:SetValue(0)
  bar:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -5)
  bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -5, 5)

  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(bar)
  if compat and compat.SetTexColor then compat.SetTexColor(bg, 0,0,0, 0.45) else bg:SetTexture(0,0,0,0.45) end

  local r,g,b = unpack(COLORS[key])
  local tex = bar:GetStatusBarTexture()
  if tex and tex.SetVertexColor then tex:SetVertexColor(r,g,b,0.95) end

  local left = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  local fontPath = select(1,left:GetFont())
  left:SetFont(fontPath, (db and db.fontSize or 12), "OUTLINE")
  left:SetPoint("LEFT", bar, "LEFT", 4, 0)
  left:SetText(TITLES[key])

  local right = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  right:SetFont(fontPath, (db and db.fontSize or 12), "OUTLINE")
  right:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
  right:SetText("")

  local spark = bar:CreateTexture(nil, "ARTWORK")
  if compat and compat.SetTexColor then compat.SetTexColor(spark, 0,1,0, 1) else spark:SetTexture(0,1,0,1) end
  spark:SetWidth(10); spark:SetHeight(14)
  spark:SetPoint("CENTER", bar, "LEFT", 0, 0)

  f:SetScript("OnMouseDown", function(self, btn)
    if btn=="LeftButton" and not db.locked then self:StartMoving() end
  end)
  f:SetScript("OnMouseUp", function(self)
    self:StopMovingOrSizing()
    local _,_,_,x,y = self:GetPoint(1)
    if key=="mh" then db.mhX, db.mhY = x or 0, y or 0
    elseif key=="oh" then db.ohX, db.ohY = x or 0, y or 0
    else db.rgX, db.rgY = x or 0, y or 0
    end
  end)

  return {frame=f, bar=bar, left=left, right=right, spark=spark}
end

-- sizing/placement helpers
local function size_one(o)
  if not o or not o.frame then return end
  local h = (db.barHeight or 18) + 10
  o.frame:SetWidth(db.width or 240)
  o.frame:SetHeight(h)
end

local function place_one(key, o)
  if not o or not o.frame then return end
  o.frame:ClearAllPoints()
  if key=="mh" then
    o.frame:SetPoint("CENTER", UIParent, "CENTER", db.mhX or 0, db.mhY or 120)
  elseif key=="oh" then
    o.frame:SetPoint("CENTER", UIParent, "CENTER", db.ohX or 0, db.ohY or 84)
  else
    o.frame:SetPoint("CENTER", UIParent, "CENTER", db.rgX or 0, db.rgY or 48)
  end
end

-- public API
function ns.BuildUI(profile, _state)
  db, state = profile, _state

  -- if already built, hide & release
  ns.HideAll()

  -- create/refresh three independent frames
  frames.mh = NewSingleFrame("mh")
  frames.oh = NewSingleFrame("oh")
  frames.rg = NewSingleFrame("rg")

  ns.ApplyDimensions()
  ns.UpdateVisibility()

  -- lightweight animation tick per frame (backup in case core tick is paused)
  local acc = 0
  for _,o in pairs(frames) do
    o.frame:SetScript("OnUpdate", function(_,elapsed)
      acc = acc + elapsed; if acc < 0.05 then return end; acc = 0
      if ns.GetState then ns.UpdateBars(GetTime(), ns.GetState()) end
    end)
  end

  for k,o in pairs(frames) do place_one(k, o); end
end

local function apply(o, now, nextAt, period)
  if not o or not period or period<=0 then
    if o then o.bar:SetValue(0); o.right:SetText(""); o.spark:Hide() end
    return
  end

  local remain = (nextAt or 0) - now + (db.visualLag or 0)
  local frac = 1 - (remain / period)
  if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end

  o.bar:SetValue(frac)
  if remain and remain > 0 then
    o.right:SetText(string.format("%.1f", remain))
  else
    o.right:SetText("")
  end

  local w = o.bar:GetWidth() or 0
  o.spark:ClearAllPoints()
  o.spark:SetPoint("CENTER", o.bar, "LEFT", frac * w, 0)
  o.spark:Show()
end

function ns.UpdateBars(now, s)
  if not frames or not s then return end
  if frames.mh then apply(frames.mh, now, s.mhNext, s.mhSpeed) end
  if s.hasOH and frames.oh then apply(frames.oh, now, s.ohNext, s.ohSpeed) end
  if frames.rg then apply(frames.rg, now, s.rangedNext, s.rangedSpeed) end
  ns.UpdateVisibility()
end

-- Fixed UpdateVisibility function with better logic and debugging
function ns.UpdateVisibility()
  if not db or not state or not frames then return end
  
  -- Calculate base visibility condition
  local baseShow = db.showOutOfCombat or state.inCombat or state.isMeleeAuto or state.autoRepeat

  -- Individual frame visibility with explicit boolean checks
  local showMH = baseShow and (db.showMelee == true or (db.showMelee ~= false and db.showMelee == nil))
  local showOH = baseShow and (db.showOffhand == true or (db.showOffhand ~= false and db.showOffhand == nil)) and (state.hasOH == true)
  local showRG = baseShow and (db.showRanged == true or (db.showRanged ~= false and db.showRanged == nil))

  -- Apply visibility
  SafeSetShown(frames.mh and frames.mh.frame, showMH)
  SafeSetShown(frames.oh and frames.oh.frame, showOH)
  SafeSetShown(frames.rg and frames.rg.frame, showRG)
end

function ns.ApplyDimensions()
  if not frames then return end
  for _,o in pairs(frames) do
    if o and o.frame then
      o.frame:SetScale(db.scale or 1.0)
      o.frame:SetAlpha(db.alpha or 1.0)
      size_one(o)
    end
  end
  for k,o in pairs(frames) do place_one(k, o) end
end

function ns.Lock(lock)
  if not frames then return end
  for _,o in pairs(frames) do
    if o and o.frame then
      if lock then
        o.frame:EnableMouse(false)
      else
        o.frame:EnableMouse(true)
      end
    end
  end
end

function ns.HideAll()
  if not frames then frames = {}; return end
  for _,o in pairs(frames) do
    if o and o.frame then o.frame:Hide(); o.frame:SetParent(nil) end
  end
  frames = {}
end

-- Add GetFrames function for debugging
function ns.GetFrames()
  return frames
end

-- compatibility getters (not used by core anymore but kept for safety)
ns.GetConfig = ns.GetConfig or function() return db end