-- ui.lua
local ADDON, ns = ...
local compat = ns and ns.compat or {}
local db, state

local BAR_W, BAR_H, PAD = 220, 18, 6

local function NewStatusBar(name, parent, color)
    local f = CreateFrame("StatusBar", name, parent)
    f:SetSize(BAR_W, BAR_H)
    f:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    f:SetMinMaxValues(0, 1)
    f:SetValue(0)

    compat.ApplySimpleBackdrop(f, 0.7)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(true)
    compat.SetTexColor(f.bg, 0, 0, 0, 0.5)

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("CENTER")

    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("LEFT", f, "LEFT", 4, 0)

    f:SetStatusBarColor(color.r, color.g, color.b, 1)
    return f
end

local root = CreateFrame("Frame", ADDON.."Anchor", UIParent)
root:SetSize(BAR_W, BAR_H*3 + PAD*2)
root:SetMovable(true)
root:EnableMouse(true)
root:RegisterForDrag("LeftButton")
root:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
root:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local a, p, r, x, y = self:GetPoint()
    db.point = { a, p, r, x, y }
end)

local mhBar = NewStatusBar(ADDON.."MHBar", root, {r=0.2,g=0.7,b=1.0})
local ohBar = NewStatusBar(ADDON.."OHBar", root, {r=0.6,g=0.4,b=1.0})
local rgBar = NewStatusBar(ADDON.."RGBar", root, {r=1.0,g=0.7,b=0.2})

mhBar:SetPoint("TOP", root, "TOP")
ohBar:SetPoint("TOP", mhBar, "BOTTOM", 0, -PAD)
rgBar:SetPoint("TOP", ohBar, "BOTTOM", 0, -PAD)

mhBar.label:SetText("Main-hand")
ohBar.label:SetText("Off-hand")
rgBar.label:SetText("Ranged")

local function UpdateBar(bar, remain, duration)
    local pct = 1 - (remain / duration)
    bar:SetValue(pct)
    bar.text:SetText(string.format("%.1fs", remain))
end

root:SetScript("OnUpdate", function()
    local now = GetTime()
    if db.showMelee then
        local dur = state.mhSpeed or 2.0
        UpdateBar(mhBar, (state.mhNext or 0) - now, dur)
    end
    if db.showOffhand and state.hasOH then
        local dur = state.ohSpeed or 1.5
        UpdateBar(ohBar, (state.ohNext or 0) - now, dur)
    end
    if db.showRanged and state.autoRepeat then
        local dur = state.rangedSpeed or 2.0
        UpdateBar(rgBar, (state.rangedNext or 0) - now, dur)
    end
end)

-- API back
function ns.CreateUI()
    return { root=root, mh=mhBar, oh=ohBar, rg=rgBar }
end
function ns.RestorePosition()
    local p = db.point
    root:ClearAllPoints()
    root:SetPoint(p[1], p[2], p[3], p[4], p[5])
end
function ns.UpdateLockState()
    root:EnableMouse(not db.locked)
end
function ns.UpdateVisibility()
    root:SetShown(db.showOutOfCombat or state.inCombat or state.autoRepeat)
end
function ns.UpdateScaleAlpha()
    root:SetScale(db.scale or 1.0)
    root:SetAlpha(db.alpha or 1.0)
end
function ns.UpdateAllBars() end
function ns.RefreshConfig()
    db = ns.GetConfig()
    state = ns.GetState()
end
