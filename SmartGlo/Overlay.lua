-- The overlay: one frame per subject, carrying the look on our own texture.
--
-- Anchored two-point to the item frame and never PARENTED to it -- re-parenting a CDM item
-- frame breaks the viewer's pandemic-frame anchor chain, re-anchoring does not
-- (cooldown-manager.md, CooldownViewerMixin:AnchorPandemicStateFrame).

local _, ns = ...

local Overlay = {}
ns.Overlay = Overlay

local LEVEL_ABOVE_ITEM = 5

local frames = {}

--- Visibility is ALPHA, all the way down. The mark spins permanently rather than starting on
--- a threshold — a count's crossing is never observed, so there is nothing to start it on —
--- and an animation does not advance while an ancestor is hidden. Alpha composites over a
--- turn that never stops.
local function Build()
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetFrameStrata("MEDIUM")
  f:SetAlpha(0)

  -- Our own Texture, tinted here and turning here. Both kinds of glow reveal THIS mark: a
  -- gate by drawing it, a count by having the client take its occluder away.
  local mark = f:CreateTexture(nil, "OVERLAY")
  mark:SetTexture(ns.Look.MASTER)
  mark:SetPoint("CENTER")
  mark:SetAlpha(0)
  ns.Look.Spin(mark)

  f.mark = mark
  return f
end

--- One persistent frame per subject: a count element's aura container is hosted on it as a
--- CHILD, which is what puts the occluder above the mark, and may only be armed once — so
--- the host cannot be pooled and rebuilt under it.
function Overlay.For(subject)
  local f = frames[subject]
  if f == nil then
    f = Build()
    frames[subject] = f
  end
  return f
end

function Overlay.Existing()
  return frames
end

--- `SetScale` at pool acquire leaves GetWidth reading 50 at every icon-size setting, so the
--- overlay takes the item's EFFECTIVE scale and its own units then match the icon's.
function Overlay.Anchor(f, item)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", item, "TOPLEFT", 0, 0)
  f:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", 0, 0)
  local ok, scale = pcall(item.GetEffectiveScale, item)
  if ok and type(scale) == "number" and scale > 0 then
    f:SetScale(scale / UIParent:GetEffectiveScale())
  end
  local levelOk, level = pcall(item.GetFrameLevel, item)
  if levelOk and type(level) == "number" then
    f:SetFrameLevel(level + LEVEL_ABOVE_ITEM)
  end
  local width = f:GetWidth()
  if type(width) == "number" and width > 0 then
    local size = width * ns.Look.FRACTION
    f.mark:SetSize(size, size)
  end
  f:SetAlpha(1)
end

function Overlay.Detach(f)
  f:ClearAllPoints()
  f:SetAlpha(0)
end

function Overlay.SetVisible(f, visible)
  if visible then f:SetAlpha(1) else f:SetAlpha(0) end
end

function Overlay.SetLit(f, lit, color)
  local rgb = ns.Look.Rgb(color)
  f.mark:SetVertexColor(rgb[1], rgb[2], rgb[3])
  if lit then f.mark:SetAlpha(1) else f.mark:SetAlpha(0) end
end
