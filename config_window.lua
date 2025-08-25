-- config_window.lua — small standalone options window (AceGUI, no Blizz Options)

local ADDON_NAME = "TacoRotSwingTimer"
local SwingTimer  = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
local AceGUI     = LibStub("AceGUI-3.0")
local ns         = _G[ADDON_NAME]

local function applyDims()
  if ns.ApplyDimensions then ns.ApplyDimensions() end
  if ns.UpdateVisibility then ns.UpdateVisibility() end
end

local function setAndApply(key, val)
  local db = SwingTimer.db.profile
  db[key] = val
  if key == "updateRate" and ns.SetUpdateRate then ns.SetUpdateRate(val) end
  applyDims()
end

local function simpleCheck(container, label, key, order, onChange)
  local w = AceGUI:Create("CheckBox")
  w:SetLabel(label)
  w:SetValue(SwingTimer.db.profile[key])
  w:SetCallback("OnValueChanged", function(_,_,v)
    SwingTimer.db.profile[key] = v
    if onChange then onChange(v) end
    applyDims()
  end)
  container:AddChild(w)
  w:SetRelativeWidth(0.48)
  return w
end

local function simpleSlider(container, label, key, min, max, step, fmt, convertToVal, convertFromVal)
  local w = AceGUI:Create("Slider")
  w:SetLabel(label)
  w:SetSliderValues(min, max, step)
  local val = SwingTimer.db.profile[key]
  if convertFromVal then val = convertFromVal(val) end
  w:SetValue(val)
  w:SetCallback("OnValueChanged", function(_,_,v)
    if convertToVal then v = convertToVal(v) end
    setAndApply(key, v)
  end)
  w.editbox:Hide() -- cleaner look on Wrath
  w:SetFullWidth(true)
  return w
end

local function button(container, text, cb)
  local b = AceGUI:Create("Button")
  b:SetText(text)
  b:SetCallback("OnClick", cb)
  b:SetRelativeWidth(0.48)
  container:AddChild(b)
  return b
end

local function pulseTest()
  local st = ns.GetState()
  local now = GetTime()
  st.lastSwingMH = now; st.nextSwingMH = now + (st.mhSpeed or 2)
  if st.hasOH then st.lastSwingOH = now; st.nextSwingOH = now + (st.ohSpeed or 1.5) end
  st.lastRanged = now; st.nextRanged = now + (st.rangedSpeed or 2)
  if ns.UpdateBars then ns.UpdateBars(now, st) end
  applyDims()
end

local function onClose(frame)
  -- Save window position & size
  local db = SwingTimer.db.profile
  local f = frame.frame
  local point, _, _, x, y = f:GetPoint(1)
  db.config = db.config or {}
  db.config.point, db.config.x, db.config.y = point or "CENTER", x or 0, y or 0
  db.config.w, db.config.h = f:GetWidth(), f:GetHeight()
end

local function buildUI()
  if SwingTimer._cfgFrame and SwingTimer._cfgFrame.Release then
    SwingTimer._cfgFrame:Release()
    SwingTimer._cfgFrame = nil
  end

  local db = SwingTimer.db.profile
  local f = AceGUI:Create("Frame")
  SwingTimer._cfgFrame = f

  f:SetTitle("TacoRot Swing Timer")
  f:SetStatusText("Left-click minimap icon to reopen · Right-click minimap icon to Lock/Unlock")
  f:SetLayout("Flow")
  f:EnableResize(true)

  -- Restore pos/size
  db.config = db.config or {}
  f.frame:ClearAllPoints()
  f.frame:SetPoint(db.config.point or "CENTER", UIParent, db.config.point or "CENTER", db.config.x or 0, db.config.y or 0)
  f:SetWidth(db.config.w or 380)
  f:SetHeight(db.config.h or 360)

  f:SetCallback("OnClose", function(widget) onClose(widget) end)

  -- Row 1: Locks / show OOC
  simpleCheck(f, "Lock frames", "locked", nil, function(v) if ns.Lock then ns.Lock(v) end end)
  simpleCheck(f, "Always show out of combat", "showOutOfCombat")

  -- Row 2: show bars
  simpleCheck(f, "Show Main-Hand", "showMelee")
  simpleCheck(f, "Show Off-Hand", "showOffhand")
  simpleCheck(f, "Show Ranged", "showRanged")

  -- Sliders
  f:AddChild(simpleSlider(f, "Scale", "scale", 0.5, 3.0, 0.01))
  f:AddChild(simpleSlider(f, "Alpha", "alpha", 0.1, 1.0, 0.01))
  f:AddChild(simpleSlider(f, "Bar width", "width", 120, 600, 1))
  f:AddChild(simpleSlider(f, "Bar height", "barHeight", 8, 40, 1))
  f:AddChild(simpleSlider(f, "Gap between bars", "gap", 0, 24, 1))

  -- FPS slider (stored as updateRate)
  local function toRate(fps) return 1 / math.max(1, fps) end
  local function fromRate(rate) return math.floor(0.5 + (1 / (rate > 0 and rate or 0.016))) end
  f:AddChild(simpleSlider(f, "Animation FPS", "updateRate", 15, 240, 1, nil, toRate, fromRate))

  -- Buttons row
  button(f, "Test Pulse", pulseTest)
  button(f, (db.locked and "Unlock Frames" or "Lock Frames"), function()
    db.locked = not db.locked
    if ns.Lock then ns.Lock(db.locked) end
    buildUI() -- refresh button text
  end)

  -- Minimap icon toggle (when DBIcon present)
  local Icon = LibStub("LibDBIcon-1.0", true)
  if Icon then
    local show = AceGUI:Create("CheckBox")
    show:SetLabel("Show minimap icon")
    show:SetValue(not (db.minimap and db.minimap.hide))
    show:SetCallback("OnValueChanged", function(_,_,v)
      db.minimap = db.minimap or {}
      db.minimap.hide = not v
      if v then Icon:Show(ADDON_NAME) else Icon:Hide(ADDON_NAME) end
    end)
    show:SetFullWidth(true)
    f:AddChild(show)
  end

  -- Close
  local close = AceGUI:Create("Button")
  close:SetText("Close")
  close:SetCallback("OnClick", function() f:Hide() end)
  close:SetFullWidth(true)
  f:AddChild(close)
end

function SwingTimer:OpenConfig()
  if not AceGUI then return end
  if not self._cfgFrame or not self._cfgFrame.frame or not self._cfgFrame.frame:IsShown() then
    buildUI()
  end
  self._cfgFrame:Show()
end

function SwingTimer:CloseConfig()
  if self._cfgFrame and self._cfgFrame.Hide then
    self._cfgFrame:Hide()
  end
end

