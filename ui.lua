-- ui.lua — TacoRotSwingTimer (Wrath 3.3.5a)
-- Three distinct framed bars (MH, OH, Ranged) with labels, timers, and a spark.

local ADDON_NAME = "TacoRotSwingTimer"
local ns = _G[ADDON_NAME] or {}
_G[ADDON_NAME] = ns

ns.compat = ns.compat or {}
local compat = ns.compat

local function clamp(v,a,b) if v<a then return a elseif v>b then return v and b or b end end
local function SafeSetShown(f, on) if f then if on then f:Show() else f:Hide() end end end

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

local db, state
local root
local boxes = {}  -- {box=Frame, bar=StatusBar, left=FontString, right=FontString, spark=Texture, key="mh"/"oh"/"rg"}

local COLORS = {
  mh = {0.90, 0.20, 0.20},
  oh = {0.20, 0.55, 0.95},
  rg = {1.00, 0.85, 0.20},
}

local TITLES = { mh="Main-Hand", oh="Off-Hand", rg="Ranged" }

local function NewBox(parent, key)
  local box = CreateFrame("Frame", nil, parent)
  ApplyBackdrop(box, 0.75)

  local bar = CreateFrame("StatusBar", nil, box)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetMinMaxValues(0,1); bar:SetValue(0)
  bar:SetPoint("TOPLEFT", box, "TOPLEFT", 5, -5)
  bar:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -5, 5)

  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(bar)
  bg:SetTexture(0,0,0,0.45)

  local r,g,b = unpack(COLORS[key])
  bar:GetStatusBarTexture():SetVertexColor(r,g,b,0.95)

  local left = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  local f = select(1,left:GetFont())
  left:SetFont(f, (db and db.fontSize or 12), "OUTLINE")
  left:SetPoint("LEFT", bar, "LEFT", 4, 0)
  left:SetText(TITLES[key])

  local right = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  right:SetFont(f, (db and db.fontSize or 12), "OUTLINE")
  right:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
  right:SetText("")

  local spark = bar:CreateTexture(nil, "ARTWORK")
  spark:SetTexture(0,1,0,1)
  spark:SetWidth(10); spark:SetHeight(14)
  spark:SetPoint("CENTER", bar, "LEFT", 0, 0)

  return {box=box, bar=bar, left=left, right=right, spark=spark, key=key}
end

local function layout()
  if not root then return end
  local width  = db.width or 240
  local h      = db.barHeight or 18
  local gap    = db.gap or 6

  local order = {"mh","oh","rg"}
  local y = 0
  local total = 0

  for _,key in ipairs(order) do
    local o = boxes[key]
    if o then
      local show = (key=="mh" and db.showMelee ~= false)
                or (key=="oh" and db.showOffhand ~= false and state.hasOH == true)
                or (key=="rg" and db.showRanged ~= false)
      if show then
        o.box:ClearAllPoints()
        o.box:SetPoint("TOP", root, "TOP", 0, -y)
        o.box:SetWidth(width)
        o.box:SetHeight(h + 10)
        o.spark:SetHeight(h - 2)
        SafeSetShown(o.box, true)
        y = y + (h + 10) + gap
        total = total + (h + 10)
      else
        SafeSetShown(o.box, false)
      end
    end
  end
  root:SetWidth(width)
  -- total height + gaps (subtract last gap)
  local visible = 0
  for _,key in ipairs(order) do
    local o = boxes[key]; if o and o.box:IsShown() then visible = visible + 1 end
  end
  local gaps = visible>0 and (visible-1)*gap or 0
  root:SetHeight(total + gaps)
end

-- public API
function ns.BuildUI(profile, _state)
  db, state = profile, _state

  if root then root:Hide(); root:SetParent(nil) end
  root = CreateFrame("Frame", "TRST_Root", UIParent)
  root:SetFrameStrata("MEDIUM")
  root:SetMovable(true); root:EnableMouse(true)

  root:SetPoint("CENTER", UIParent, "CENTER", db.posX or 0, db.posY or 120)
  root:SetScale(db.scale or 1.0)
  root:SetAlpha(db.alpha or 1.0)

  -- drag group
  root:SetScript("OnMouseDown", function(self, btn)
    if btn=="LeftButton" and not db.locked then self:StartMoving() end
  end)
  root:SetScript("OnMouseUp", function(self)
    self:StopMovingOrSizing()
    local _,_,_,x,y = self:GetPoint(1); db.posX, db.posY = x or 0, y or 0
  end)

  -- create three separate boxes
  boxes = {
    mh = NewBox(root, "mh"),
    oh = NewBox(root, "oh"),
    rg = NewBox(root, "rg"),
  }

  layout()
  ns.UpdateVisibility()

  -- lightweight animation tick
  local acc=0
  root:SetScript("OnUpdate", function(_,elapsed)
    acc=acc+elapsed; if acc<0.05 then return end; acc=0
    if ns.GetState then ns.UpdateBars(GetTime(), ns.GetState()) end
  end)

  root:Show()
  return root
end

local function apply(o, now, nextAt, period)
  if not o or not period or period<=0 then
    if o then o.bar:SetValue(0); o.right:SetText(""); o.spark:Hide() end
    return
  end
  local remain = (nextAt or 0) - now
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
  if not root or not s then return end
  apply(boxes.mh, now, s.mhNext, s.mhSpeed)
  if s.hasOH then apply(boxes.oh, now, s.ohNext, s.ohSpeed) end
  apply(boxes.rg, now, s.rangedNext, s.rangedSpeed)
  ns.UpdateVisibility()
end

function ns.UpdateVisibility()
  if not db or not state or not root then return end
  local showRoot = db.showOutOfCombat or state.inCombat or state.isMeleeAuto or state.autoRepeat
  SafeSetShown(root, showRoot)
  layout()
end

function ns.ApplyDimensions()
  if not root then return end
  root:SetScale(db.scale or 1.0)
  root:SetAlpha(db.alpha or 1.0)
  layout()
end

function ns.Lock(lock) if root then db.locked = lock and true or false end end
ns.GetUI     = ns.GetUI     or function() return root end
ns.GetState  = ns.GetState  or function() return state end
ns.GetConfig = ns.GetConfig or function() return db end
