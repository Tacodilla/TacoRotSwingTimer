-- ui.lua
local ADDON, ns = ...
local compat = ns and ns.compat or {}
local db, state

-- Handle `Frame:SetShown` absence on older clients
local function SafeSetShown(frame, show)
    if frame.SetShown then
        frame:SetShown(show)
    else
        if show then frame:Show() else frame:Hide() end
    end
end

-- Build one WST-style status bar
local function NewBar(name, parent, r, g, b)
    local bar = CreateFrame("StatusBar", name, parent)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    compat.ApplyBackdrop(bar, 0.7)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(true)
    compat.SetTexColor(bar.bg, 0, 0, 0, 0.5)

    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.text:SetText("")

    bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.label:SetPoint("LEFT", bar, "LEFT", 4, 0)
    bar.label:SetTextColor(0.9, 0.9, 0.9)

    bar.spark = bar:CreateTexture(nil, "OVERLAY")
    bar.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    bar.spark:SetBlendMode("ADD")
    bar.spark:SetWidth(12)
    bar.spark:Hide()

    bar:SetStatusBarColor(r, g, b, 1)
    return bar
end

-- Root anchor (movable)
local root = CreateFrame("Frame", ADDON.."Anchor", UIParent)
root:SetMovable(true)
root:EnableMouse(true)
root:RegisterForDrag("LeftButton")
root:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
root:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local a, p, r, x, y = self:GetPoint()
    db.point = { a, p, r, x, y }
end)

-- Create bars
local mhBar = NewBar(ADDON.."MH", root, 0.2, 0.7, 1.0)
local ohBar = NewBar(ADDON.."OH", root, 0.6, 0.4, 1.0)
local rgBar = NewBar(ADDON.."RG", root, 1.0, 0.7, 0.2)

mhBar.label:SetText("Main-hand")
ohBar.label:SetText("Off-hand")
rgBar.label:SetText("Ranged")

-- Layout helper respecting config width/height
local function LayoutBars()
    local w = db.width or 260
    local h = db.height or 14
    local gap = math.max(4, math.floor(h * 0.5))

    root:SetSize(w, h*3 + gap*2)

    local function sizeBar(b)
        b:SetWidth(w)
        b:SetHeight(h)
        b.spark:SetHeight(h + 6)
    end
    sizeBar(mhBar); sizeBar(ohBar); sizeBar(rgBar)

    mhBar:ClearAllPoints()
    ohBar:ClearAllPoints()
    rgBar:ClearAllPoints()
    mhBar:SetPoint("TOP", root, "TOP")
    ohBar:SetPoint("TOP", mhBar, "BOTTOM", 0, -gap)
    rgBar:SetPoint("TOP", ohBar, "BOTTOM", 0, -gap)
end

-- Formatting and updates
local function fmtTime(t)
    if t <= 0 then return "0.00s" end
    if t >= 10 then return string.format("%.1fs", t) end
    return string.format("%.2fs", t)
end

local function UpdateVisual(bar, remain, duration)
    remain = math.max(0, remain or 0)
    duration = math.max(0.001, duration or 1)
    local pct = 1 - (remain / duration)
    bar:SetValue(pct)
    bar.text:SetText(fmtTime(remain))
    local w = bar:GetWidth()
    bar.spark:ClearAllPoints()
    bar.spark:SetPoint("CENTER", bar, "LEFT", w * pct, 0)
    if remain > 0 and remain < duration then bar.spark:Show() else bar.spark:Hide() end
end

root:SetScript("OnUpdate", function()
    local now = GetTime()
    if db.showMelee then
        UpdateVisual(mhBar, (state.mhNext or 0) - now, state.mhSpeed or 2.0)
    end
    if db.showOffhand and state.hasOH and state.ohSpeed then
        UpdateVisual(ohBar, (state.ohNext or 0) - now, state.ohSpeed or 1.5)
    end
    if db.showRanged and state.autoRepeat then
        UpdateVisual(rgBar, (state.rangedNext or 0) - now, state.rangedSpeed or 2.0)
    end
end)

-- Exposed API used by core.lua
function ns.CreateUI()
    return { root=root, mh=mhBar, oh=ohBar, rg=rgBar }
end

function ns.RefreshConfig()
    db = ns.GetConfig()
    state = ns.GetState()
end

function ns.RestorePosition()
    local p = db.point
    root:ClearAllPoints()
    root:SetPoint(p[1], p[2], p[3], p[4], p[5])
end

function ns.UpdateLockState()
    root:EnableMouse(not db.locked)
end

function ns.UpdateScaleAlpha()
    root:SetScale(db.scale or 1.0)
    root:SetAlpha(db.alpha or 1.0)
end

function ns.UpdateAllBars()
    mhBar.label:SetText("Main-hand")
    ohBar.label:SetText("Off-hand")
    rgBar.label:SetText("Ranged")
end

function ns.UpdateVisibility()
    local show = db.showOutOfCombat or state.inCombat or state.autoRepeat
    SafeSetShown(root, show)
    SafeSetShown(mhBar, db.showMelee)
    SafeSetShown(ohBar, db.showOffhand and state.hasOH)
    SafeSetShown(rgBar, db.showRanged)
end

function ns.ApplyDimensions()
    LayoutBars()
end
