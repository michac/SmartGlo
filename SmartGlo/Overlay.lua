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
local SizeMarks

--- One element per RULE, keyed by what the rule says rather than by its position in the list.
--- A glow table is rebuilt on every store load, so an identity keyed on the table itself dies
--- every reload -- and an element may host an arm-once aura container, which must not.
function Overlay.KeyOf(glow)
  return ("%d|%s|%s"):format(glow.subject, ns.Rules.Describe(glow.when),
    glow.bind ~= nil and ns.Rules.DescribeBind(glow.bind) or "-")
end

--- Visibility is ALPHA, all the way down. The mark spins permanently rather than starting on
--- a threshold — a count's crossing is never observed, so there is nothing to start it on —
--- and an animation does not advance while an ancestor is hidden. Alpha composites over a
--- turn that never stops.
local function Build()
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetFrameStrata("MEDIUM")
  f:SetAlpha(0)
  f.elements = {}
  return f
end

--- Three alpha channels, one owner each, decided at build and never shared: the subject frame
--- is attached-and-not-editing, the element frame is the readable `when` gate, and the mark
--- is the sealed bind. A sealed alpha and a plain one cannot share a channel -- reading back
--- the plain one after a secret has been written to it is what taints.
local function BuildElement(host)
  local e = CreateFrame("Frame", nil, host)
  e:SetAllPoints(host)
  e:SetAlpha(0)

  -- Our own Texture, tinted here and turning here. Both kinds of glow reveal THIS mark: a
  -- gate by drawing it, a count by having the client take its occluder away.
  local mark = e:CreateTexture(nil, "OVERLAY")
  mark:SetTexture(ns.Look.MASTER)
  mark:SetPoint("CENTER")
  mark:SetAlpha(0)
  ns.Look.Spin(mark)

  e.mark = mark
  return e
end

--- The mark is a FRACTION of the row it rides, so its size follows the host's -- and an
--- element built after the host was anchored has to be sized on arrival, not only on the next
--- anchor, or it draws at nothing.
function SizeMarks(f)
  local width = f:GetWidth()
  if type(width) ~= "number" or width <= 0 then return end
  local size = width * ns.Look.FRACTION
  for _, e in pairs(f.elements) do e.mark:SetSize(size, size) end
end

--- One persistent frame per subject: a count element's aura container is hosted on its element
--- as a CHILD, which is what puts the occluder above the mark, and may only be armed once — so
--- neither the host nor the element can be pooled and rebuilt underneath it.
function Overlay.For(subject)
  local f = frames[subject]
  if f == nil then
    f = Build()
    frames[subject] = f
  end
  return f
end

function Overlay.Element(glow)
  local host = Overlay.For(glow.subject)
  local key = Overlay.KeyOf(glow)
  local e = host.elements[key]
  if e == nil then
    e = BuildElement(host)
    host.elements[key] = e
    SizeMarks(host)
  end
  return e
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
  SizeMarks(f)
  f:SetAlpha(1)
end

function Overlay.Detach(f)
  f:ClearAllPoints()
  f:SetAlpha(0)
end

function Overlay.SetVisible(f, visible)
  if visible then f:SetAlpha(1) else f:SetAlpha(0) end
end

--- The gate, and the tint that goes with it. The COLOUR write is unconditional -- vertex
--- colour carries no secret and is a different channel from alpha. The MARK's alpha is
--- written only for an element whose mark nothing has sealed. A count element is NOT sealed
--- here: its occluder is a sibling drawn above the mark, not another writer of the mark's
--- alpha. Only a duration bind owns that channel, and then a write here would be a second
--- owner of one channel.
function Overlay.SetLit(e, lit, color, sealed)
  local rgb = ns.Look.Rgb(color)
  e.mark:SetVertexColor(rgb[1], rgb[2], rgb[3])
  e:SetAlpha(lit and 1 or 0)
  if not sealed then
    e.mark:SetAlpha(lit and 1 or 0)
  end
end
