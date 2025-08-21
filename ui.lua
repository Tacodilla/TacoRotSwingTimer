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
  mh = {0.90, 0.20, 0.20}, -- red
  oh = {0.20, 0.55, 0.95}, -- blue
  rg = {0.95, 0.85, 0.20}, -- yellow
}

local function tex(frame)
  local t = frame:CreateTexture(nil, "BACKGROUND")
  t:SetAllPoints(true)
  return t
end

local function mkbar(parent, key)
  local f = CreateFrame("Frame", ADDON_NAME.."_"..key, UIParent)
  f:SetMovable(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local x, y = self:GetCenter()
    db.posX = math.floor(x - UIParent:GetWidth()/2 + 0.5)
    db.posY = math.floor(y - UIParent:GetHeight()/2 + 0.5)
  end)

  compat.ApplyBackdrop(f, 0.6)

  local bar = CreateFrame("StatusBar", nil, f)
  bar:SetPoint("TOPLEFT", 4, -4)
  bar:SetPoint("BOTTOMRIGHT", -4, 4)
  bar:SetMinMaxValues(0, 1); bar:SetValue(0)

  local back = bar:CreateTexture(nil, "ARTWORK")
  back:SetAllPoints(true)
  compat.SetTexColor(back, 0.2, 0.2, 0.2, 0.9) -- neutral gray background

  local fill = bar:CreateTexture(nil, "BORDER")
  bar:SetStatusBarTexture(fill)
  local c = COLORS[key] or {0.7,0.7,0.7}
  fill:SetTexture(c[1], c[2], c[3], 1)

  local left  = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  local right = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  left:SetPoint("LEFT", 6, 0); right:SetPoint("RIGHT", -6, 0)

  local spark = bar:CreateTexture(nil, "OVERLAY")
  spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
  spark:SetBlendMode("ADD")
  spark:SetWidth(20); spark:SetHeight(30); spark:Hide()

  frames[key] = { frame=f, bar=bar, left=left, right=right, spark=spark }
  return frames[key]
end

local function place_one(key, o)
  local x = (db.posX or 0) + UIParent:GetWidth()/2
  local y = (db.posY or 120) + UIParent:GetHeight()/2
  local dy = (key=="mh" and 0) or (key=="oh" and -(db.barHeight+db.gap)) or (key=="rg" and (db.barHeight+db.gap)) or 0
  o.frame:ClearAllPoints()
  o.frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y + dy)
end

local function fmt(sec)
  if not sec or sec < 0 then return "" end
  if sec >= 10 then
    return string.format("%.1f", sec)
  else
    return string.format("%.2f", sec)
  end
end

function ns.BuildUI(cfg, st)
  db, state = cfg, st
  if not frames.mh then mkbar("UIParent", "mh") end
  if not frames.oh then mkbar("UIParent", "oh") end
  if not frames.rg then mkbar("UIParent", "rg") end

  ns.ApplyDimensions()
  ns.UpdateVisibility()

  -- smooth animation driver (single, shared)
  if not ns._driver then
    ns._driver = CreateFrame("Frame")
    ns._updateRate = ns._updateRate or (1/60) -- default ~60 FPS
    ns._acc = 0
    ns._driver:SetScript("OnUpdate", function(_, elapsed)
      local step = ns._updateRate or 0
      if step <= 0 then
        if ns.GetState then ns.UpdateBars(GetTime(), ns.GetState()) end
        return
      end
      ns._acc = ns._acc + elapsed
      if ns._acc >= step then
        ns._acc = 0
        if ns.GetState then ns.UpdateBars(GetTime(), ns.GetState()) end
      end
    end)
  end

  for k,o in pairs(frames) do place_one(k, o) end
end

local function apply(o, now, nextAt, period)
  if not o or not period or period <= 0 then
    if o then o.bar:SetValue(0); o.right:SetText(""); o.spark:Hide() end
    return
  end
  local remaining = math.max(0, (nextAt or now) - now)
  local t = 1 - math.min(1, remaining / period)
  o.bar:SetValue(t)

  -- spark glide
  local barW = (db.width or 240) - 8
  local sx = 4 + barW * t
  o.spark:ClearAllPoints()
  o.spark:SetPoint("CENTER", o.bar, "LEFT", sx, 0)
  o.spark:SetAlpha(0.8)
  if remaining > 0 then o.spark:Show() else o.spark:Hide() end

  o.right:SetText(fmt(remaining))
end

function ns.UpdateBars(now, st)
  state = st or state
  if not state then return end

  local mh = frames.mh
  local oh = frames.oh
  local rg = frames.rg

  -- Use observed periods when available (next - last), else fallback to base speeds.
  local mPer = (state.mhNext and state.mhLast) and (state.mhNext - state.mhLast) or (state.mhSpeed or 2.0)
  local oPer = (state.ohNext and state.ohLast) and (state.ohNext - state.ohLast) or (state.ohSpeed or 1.5)
  local rPer = (state.rangedNext and state.rangedLast) and (state.rangedNext - state.rangedLast) or (state.rangedSpeed or 2.0)

  if mh then
    mh.left:SetText("MH")
    apply(mh, now, state.mhNext, mPer)
  end

  -- OH: always label; animate only if an offhand exists
  if oh then
    oh.left:SetText("OH")
    if state.hasOH then
      apply(oh, now, state.ohNext, oPer)
    else
      oh.bar:SetValue(0); oh.right:SetText("0.00"); oh.spark:Hide()
    end
  end

  if rg then
    rg.left:SetText("Ranged")
    apply(rg, now, state.rangedNext, rPer)
  end
end

-- 3.3.5a Show/Hide visibility
function ns.UpdateVisibility()
  if not db then return end
  local inCombat = state and state.inCombat
  local showOOC  = db.showOutOfCombat

  local function set_shown(f, want)
    if not f then return end
    if want then f:Show() else f:Hide() end
  end

  -- MH
  if frames.mh then
    set_shown(frames.mh.frame, db.showMelee and (showOOC or inCombat))
  end

  -- OH (no hasOH gate so the frame can be positioned even without an offhand)
  if frames.oh then
    set_shown(frames.oh.frame, db.showOffhand and (showOOC or inCombat))
  end

  -- Ranged
  if frames.rg then
    set_shown(frames.rg.frame, db.showRanged and (showOOC or inCombat))
  end
end

function ns.ApplyDimensions()
  if not db then return end
  local w, h, s, a = db.width or 240, db.barHeight or 18, db.scale or 1, db.alpha or 1
  for _,o in pairs(frames) do
    o.frame:SetScale(s); o.frame:SetAlpha(a)
    o.frame:SetWidth(w + 8); o.frame:SetHeight(h + 8)
    o.left:SetFont("Fonts\\FRIZQT__.TTF", db.fontSize or 12, "OUTLINE")
    o.right:SetFont("Fonts\\FRIZQT__.TTF", db.fontSize or 12, "OUTLINE")
  end
end

function ns.Lock(locked)
  if not frames then return end
  for _,o in pairs(frames) do
    o.frame:EnableMouse(not locked)
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

-- Smooth update rate setter
function ns.SetUpdateRate(secPerTick)
  ns._updateRate = tonumber(secPerTick) or (1/60)
end

-- compatibility getters (not used by core anymore but kept for safety)
ns.GetConfig = ns.GetConfig or function() return db end
