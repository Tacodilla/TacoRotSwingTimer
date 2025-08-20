-- ui.lua - TacoRotSwingTimer (3.3.5a)
-- Builds the three swing bars and exposes a small UI API to core.lua.

local ADDON_NAME = "TacoRotSwingTimer"
local ns = _G[ADDON_NAME] or {}          -- be defensive in case core hiccups
_G[ADDON_NAME] = ns

-- ----- Compat guard (in case Compat-335.lua didn't run) --------------------
ns.compat = ns.compat or {}
local compat = ns.compat

if not compat.ApplyBackdrop then
    function compat.ApplyBackdrop(frame, alpha)
        if not frame or not frame.SetBackdrop then return end
        frame:SetBackdrop({
            bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile     = true, tileSize = 16, edgeSize = 12,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        frame:SetBackdropColor(0, 0, 0, alpha or 0.7)
    end
end

if not compat.SetTexColor then
    function compat.SetTexColor(tex, r, g, b, a)
        if tex and tex.SetTexture then tex:SetTexture(r or 0, g or 0, b or 0, a or 1) end
    end
end
-- --------------------------------------------------------------------------

local C = ns.CONSTANTS or {}

-- These are initialized when UI is created
local db, state
local root, mhBar, ohBar, rgBar

-- 3.3.5 fallback for :SetShown
local function SafeSetShown(frame, show)
    if not frame then return end
    if frame.SetShown then
        frame:SetShown(show)
    else
        if show then frame:Show() else frame:Hide() end
    end
end

-- Build one status bar
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

-- Layout helper respecting db width/height
local function LayoutBars()
    if not db or not root then return end

    local w = db.width or 260
    local h = db.height or 14
    local gap = math.max(4, math.floor(h * 0.5))

    root:SetSize(w, h * 3 + gap * 2)

    local function sizeBar(b)
        if not b then return end
        b:SetWidth(w)
        b:SetHeight(h)
        if b.spark then b.spark:SetHeight(h + 6) end
    end

    sizeBar(mhBar); sizeBar(ohBar); sizeBar(rgBar)

    if mhBar then
        mhBar:ClearAllPoints()
        mhBar:SetPoint("TOP", root, "TOP")
    end
    if ohBar then
        ohBar:ClearAllPoints()
        ohBar:SetPoint("TOP", mhBar, "BOTTOM", 0, -gap)
    end
    if rgBar then
        rgBar:ClearAllPoints()
        rgBar:SetPoint("TOP", ohBar, "BOTTOM", 0, -gap)
    end
end

-- Expose to namespace so core can call ns.ApplyDimensions()
ns.LayoutBars = LayoutBars

-- Formatting + visual updates
local function fmtTime(t)
    if t <= 0 then return "0.00s" end
    if t >= 10 then return string.format("%.1fs", t) end
    return string.format("%.2fs", t)
end

local function UpdateVisual(bar, remain, duration)
    if not bar then return end
    remain   = math.max(0, remain or 0)
    duration = math.max(0.001, duration or 1)
    local pct = 1 - (remain / duration)

    bar:SetValue(pct)

    if db and db.showTimeText then
        bar.text:SetText(fmtTime(remain))
        bar.text:Show()
    else
        bar.text:Hide()
    end

    if db and db.showSparkEffect then
        local w = bar:GetWidth()
        bar.spark:ClearAllPoints()
        bar.spark:SetPoint("CENTER", bar, "LEFT", w * pct, 0)
        if remain > 0 and remain < duration then
            bar.spark:Show()
        else
            bar.spark:Hide()
        end
    else
        bar.spark:Hide()
    end
end

-- OnUpdate driving the three bars
local lastUpdate = 0
local function OnUpdateHandler(self, elapsed)
    if not db or not state then return end

    lastUpdate = lastUpdate + elapsed
    local rate = db.updateRate or 0.05
    if lastUpdate < rate then return end
    lastUpdate = 0

    if not self:IsVisible() then return end

    local now = GetTime()
    if db.showMelee and mhBar then
        UpdateVisual(mhBar, (state.mhNext or 0) - now, state.mhSpeed or C.DEFAULT_MH_SPEED)
    end
    if db.showOffhand and state.hasOH and state.ohSpeed and ohBar then
        UpdateVisual(ohBar, (state.ohNext or 0) - now, state.ohSpeed or C.DEFAULT_OH_SPEED)
    end
    if db.showRanged and state.autoRepeat and rgBar then
        UpdateVisual(rgBar, (state.rangedNext or 0) - now, state.rangedSpeed or C.DEFAULT_RANGED_SPEED)
    end
end

-- ===== Public UI API used by core.lua =====================================

function ns.CreateUI()
    if root then
        return { root = root, mh = mhBar, oh = ohBar, rg = rgBar }
    end

    -- Movable root
    root = CreateFrame("Frame", ADDON_NAME .. "Anchor", UIParent)
    root:SetMovable(true)
    root:EnableMouse(true)
    root:RegisterForDrag("LeftButton")
    root:SetScript("OnDragStart", function(f) if db and not db.locked then f:StartMoving() end end)
    root:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        if db then
            local a, p, r, x, y = f:GetPoint()
            db.point = { a, p, r, x, y }
        end
    end)

    root:SetScript("OnUpdate", OnUpdateHandler)

    -- Bars
    mhBar = NewBar(ADDON_NAME .. "MH", root, 0.2, 0.7, 1.0)
    ohBar = NewBar(ADDON_NAME .. "OH", root, 0.6, 0.4, 1.0)
    rgBar = NewBar(ADDON_NAME .. "RG", root, 1.0, 0.7, 0.2)

    if mhBar and mhBar.label then mhBar.label:SetText("Main-hand") end
    if ohBar and ohBar.label then ohBar.label:SetText("Off-hand") end
    if rgBar and rgBar.label then rgBar.label:SetText("Ranged") end

    -- Start hidden; core controls visibility based on settings/state
    root:Hide()

    return { root = root, mh = mhBar, oh = ohBar, rg = rgBar }
end

function ns.RefreshConfig()
    if ns.GetConfig and ns.GetState then
        db = ns.GetConfig()
        state = ns.GetState()
    end
end

function ns.RestorePosition()
    if not root or not db then return end
    local p = db.point
    if p and #p >= 5 then
        root:ClearAllPoints()
        root:SetPoint(p[1], p[2], p[3], p[4], p[5])
    end
end

function ns.UpdateLockState()
    if root and db then root:EnableMouse(not db.locked) end
end

function ns.UpdateScaleAlpha()
    if not root or not db then return end
    root:SetScale(db.scale or 1.0)
    root:SetAlpha(db.alpha or 1.0)
end

function ns.UpdateAllBars()
    if not db then return end

    if mhBar and mhBar.label then mhBar.label:SetText("Main-hand") end
    if ohBar and ohBar.label then ohBar.label:SetText("Off-hand") end
    if rgBar and rgBar.label then rgBar.label:SetText("Ranged") end

    local tex  = db.barTexture or "Interface\\TargetingFrame\\UI-StatusBar"
    local font = db.fontFace   or "GameFontHighlightSmall"

    for _, bar in pairs({ mhBar, ohBar, rgBar }) do
        if bar then
            bar:SetStatusBarTexture(tex)
            if bar.text then bar.text:SetFontObject(font) end
            if not db.showTimeText then bar.text:Hide() end
            if not db.showSparkEffect then bar.spark:Hide() end
        end
    end
end

function ns.UpdateVisibility()
    if not db or not state or not root then return end
    local show = db.showOutOfCombat or state.inCombat or state.autoRepeat

    SafeSetShown(root, show)
    if mhBar then SafeSetShown(mhBar, db.showMelee) end
    if ohBar then SafeSetShown(ohBar, db.showOffhand and state.hasOH) end
    if rgBar then SafeSetShown(rgBar, db.showRanged) end
end

function ns.ApplyDimensions()
    LayoutBars()
end
