-- Compat-335.lua
local ADDON_NAME = "TacoRotSwingTimer"
local _, ns = ...
if not ns then ns = _G[ADDON_NAME] or {} end
ns.compat = {}

-- Helpers that avoid retail-only APIs (e.g., SetColorTexture).

function ns.compat.SetTexColor(tex, r, g, b, a)
    if not tex then return end
    tex:SetTexture(1,1,1)           -- solid white
    tex:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
end

function ns.compat.ApplyBackdrop(frame, alpha)
    frame:SetBackdrop({
        bgFile  = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile= "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left=3, right=3, top=3, bottom=3 }
    })
    frame:SetBackdropColor(0, 0, 0, alpha or 0.6)
end
