-- Compat-335.lua
-- Minimal helpers for 3.3.5a so ui.lua can call compat.* safely

local ADDON_NAME = "TacoRotSwingTimer"
local ns = _G[ADDON_NAME] or {}
_G[ADDON_NAME] = ns

ns.compat = ns.compat or {}
local compat = ns.compat

-- Backdrop helper: gives a simple dark bg with a thin tooltip border
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

-- Texture color helper (works on any Texture)
function compat.SetTexColor(tex, r, g, b, a)
    if tex and tex.SetTexture then
        tex:SetTexture(r or 0, g or 0, b or 0, a or 1)
    end
end
