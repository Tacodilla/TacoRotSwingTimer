-- Compat-335.lua
-- Helpers to avoid retail-only APIs

local _, ns = ...
ns.compat = {}

-- Safe color fill for textures on 3.3.5 (no SetColorTexture)
function ns.compat.SetTexColor(tex, r, g, b, a)
    if not tex then return end
    tex:SetTexture(1,1,1) -- plain white
    tex:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
end

-- Backdrop helper
function ns.compat.ApplySimpleBackdrop(frame, alpha)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    frame:SetBackdropColor(0,0,0, alpha or 0.6)
end
