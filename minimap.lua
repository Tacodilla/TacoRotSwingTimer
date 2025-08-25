-- minimap.lua — minimap launcher (LDB/DBIcon) with a no-lib fallback

local ADDON_NAME = "TacoRotSwingTimer"
local SwingTimer  = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
local LDB   = LibStub("LibDataBroker-1.1", true)
local Icon  = LibStub("LibDBIcon-1.0", true)

local function tooltip(tt)
  tt:AddLine("TacoRot Swing Timer")
  tt:AddLine("|cffffff00Left-Click|r  Open options")
  tt:AddLine("|cffffff00Right-Click|r Lock/Unlock frames")
end

local function toggleLock()
  local db = SwingTimer.db.profile
  db.locked = not db.locked
  local ns = _G[ADDON_NAME]
  if ns and ns.Lock then ns.Lock(db.locked) end
end

function SwingTimer:ToggleConfig()
  if not self._cfgFrame or not self._cfgFrame.frame or not self._cfgFrame.frame:IsShown() then
    self:OpenConfig()
  else
    self:CloseConfig()
  end
end

-- LDB/DBIcon path (preferred)
local function registerLDB()
  SwingTimer.db.profile.minimap = SwingTimer.db.profile.minimap or { hide=false }
  SwingTimer._ldbObj = LDB:NewDataObject(ADDON_NAME, {
    type = "launcher",
    label = "SwingTimer",
    icon  = "Interface\\Icons\\INV_Sword_04",
    OnClick = function(_, button)
      if button == "LeftButton" then
        SwingTimer:ToggleConfig()
      else
        toggleLock()
      end
    end,
    OnTooltipShow = tooltip,
  })
  if Icon then
    Icon:Register(ADDON_NAME, SwingTimer._ldbObj, SwingTimer.db.profile.minimap)
    if SwingTimer.db.profile.minimap.hide then Icon:Hide(ADDON_NAME) end
  end
end

-- Fallback: a tiny button glued to the Minimap if LDB/DBIcon not available
local function registerFallback()
  local b = CreateFrame("Button", ADDON_NAME.."MiniBtn", Minimap)
  b:SetSize(32, 32)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  b:SetNormalTexture("Interface\\AddOns\\"..ADDON_NAME.."\\media\\mini") -- optional; else use a default
  b:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 2, -2)

  b:SetScript("OnClick", function(_, btn)
    if btn == "LeftButton" then SwingTimer:ToggleConfig() else toggleLock() end
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:ClearLines(); tooltip(GameTooltip); GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function SwingTimer:_RegisterMinimap()
  if LDB then registerLDB() else registerFallback() end
end

-- Hook OnEnable after DB exists
local origEnable = SwingTimer.OnEnable
function SwingTimer:OnEnable(...)
  if origEnable then origEnable(self, ...) end
  self:_RegisterMinimap()
end

