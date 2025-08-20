-- ui.lua - Fixed for Ace3 Integration
local ADDON_NAME = "TacoRotSwingTimer"
local ns = _G[ADDON_NAME]
local compat = ns and ns.compat or {}
local SwingTimer = ns and ns.SwingTimer

-- Variables that will be initialized when UI is created
local db, state
local root, mhBar, ohBar, rgBar
local C = ns.CONSTANTS or {}

-- Handle Frame:SetShown absence on older clients
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

-- Layout helper respecting config width/height
local function LayoutBars()
    if not db or not root then return end
    
    local w = db.width or 260
    local h = db.height or 14
    local gap = math.max(4, math.floor(h * 0.5))

    root:SetSize(w, h*3 + gap*2)

    local function sizeBar(b)
        if b then
            b:SetWidth(w)
            b:SetHeight(h)
            if b.spark then
                b.spark:SetHeight(h + 6)
            end
        end
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

-- Store reference to LayoutBars for namespace access
ns.LayoutBars = LayoutBars

-- Formatting and updates
local function fmtTime(t)
    if t <= 0 then return "0.00s" end
    if t >= 10 then return string.format("%.1fs", t) end
    return string.format("%.2fs", t)
end

local function UpdateVisual(bar, remain, duration)
    if not bar then return end
    
    remain = math.max(0, remain or 0)
    duration = math.max(0.001, duration or 1)
    local pct = 1 - (remain / duration)
    bar:SetValue(pct)

    if db and db.showTimeText then
        bar.text:SetText(fmtTime(remain))
        bar.text:Show()
    else
        bar.text:Hide()
    end

    local w = bar:GetWidth()
    if db and db.showSparkEffect then
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

-- OnUpdate script function
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

-- MAIN UI CREATION FUNCTION - Called by core.lua after Ace3 is ready
function ns.CreateUI()
    -- Don't create twice
    if root then return { root=root, mh=mhBar, oh=ohBar, rg=rgBar } end
    
    -- Create root anchor (movable)
    root = CreateFrame("Frame", ADDON_NAME.."Anchor", UIParent)
    root:SetMovable(true)
    root:EnableMouse(true)
    root:RegisterForDrag("LeftButton")
    root:SetScript("OnDragStart", function(self) 
        if db and not db.locked then 
            self:StartMoving() 
        end 
    end)
    root:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if db and SwingTimer then
            local a, p, r, x, y = self:GetPoint()
            db.point = { a, p, r, x, y }
        end
    end)
    
    -- Set OnUpdate handler
    root:SetScript("OnUpdate", OnUpdateHandler)

    -- Create bars
    mhBar = NewBar(ADDON_NAME.."MH", root, 0.2, 0.7, 1.0)
    ohBar = NewBar(ADDON_NAME.."OH", root, 0.6, 0.4, 1.0)
    rgBar = NewBar(ADDON_NAME.."RG", root, 1.0, 0.7, 0.2)

    -- Set labels
    if mhBar then mhBar.label:SetText("Main-hand") end
    if ohBar then ohBar.label:SetText("Off-hand") end
    if rgBar then rgBar.label:SetText("Ranged") end

    -- Initially hide the frame - visibility will be controlled by core
    root:Hide()

    return { root=root, mh=mhBar, oh=ohBar, rg=rgBar }
end

-- Configuration refresh - gets latest db and state references
function ns.RefreshConfig()
    if ns.GetConfig and ns.GetState then
        db = ns.GetConfig()
        state = ns.GetState()
    end
end

-- Position restore
function ns.RestorePosition()
    if not root or not db then return end
    local p = db.point
    if p and #p >= 5 then
        root:ClearAllPoints()
        root:SetPoint(p[1], p[2], p[3], p[4], p[5])
    end
end

-- Lock state update
function ns.UpdateLockState()
    if not root or not db then return end
    root:EnableMouse(not db.locked)
end

-- Scale and alpha update
function ns.UpdateScaleAlpha()
    if not root or not db then return end
    root:SetScale(db.scale or 1.0)
    root:SetAlpha(db.alpha or 1.0)
end

-- Update all bar properties
function ns.UpdateAllBars()
    if not db then return end
    
    -- Set labels
    if mhBar and mhBar.label then mhBar.label:SetText("Main-hand") end
    if ohBar and ohBar.label then ohBar.label:SetText("Off-hand") end
    if rgBar and rgBar.label then rgBar.label:SetText("Ranged") end

    local tex = db.barTexture or "Interface\\TargetingFrame\\UI-StatusBar"
    local font = db.fontFace or "GameFontHighlightSmall"
    
    for _, bar in pairs({mhBar, ohBar, rgBar}) do
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

-- Visibility update
function ns.UpdateVisibility()
    if not db or not state or not root then return end

    local show = db.showOutOfCombat or state.inCombat or state.autoRepeat
    SafeSetShown(root, show)
    
    if mhBar then SafeSetShown(mhBar, db.showMelee) end
    if ohBar then SafeSetShown(ohBar, db.showOffhand and state.hasOH) end
    if rgBar then SafeSetShown(rgBar, db.showRanged) end
end

-- Apply dimensions
function ns.ApplyDimensions()
    LayoutBars()
end
