-- The one fixed look: a thin border inside the icon, on our own frame, keyed by subject.
--
-- Anchored two-point to the item frame and never PARENTED to it -- re-parenting a CDM item
-- frame breaks the viewer's pandemic-frame anchor chain, re-anchoring does not
-- (cooldown-manager.md, CooldownViewerMixin:AnchorPandemicStateFrame).

local _, ns = ...

local Overlay = {}
ns.Overlay = Overlay

local INSET = 3
local THICKNESS = 2
local LEVEL_ABOVE_ITEM = 5
local COLOR = { 1.0, 0.82, 0.25, 1.0 }

local frames = {}

local function Edge(parent)
  local tex = parent:CreateTexture(nil, "OVERLAY")
  tex:SetColorTexture(COLOR[1], COLOR[2], COLOR[3], COLOR[4])
  return tex
end

local function Build()
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetFrameStrata("MEDIUM")
  f:Hide()

  local top, bottom, left, right = Edge(f), Edge(f), Edge(f), Edge(f)
  top:SetPoint("TOPLEFT", f, "TOPLEFT", INSET, -INSET)
  top:SetPoint("TOPRIGHT", f, "TOPRIGHT", -INSET, -INSET)
  top:SetHeight(THICKNESS)
  bottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", INSET, INSET)
  bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -INSET, INSET)
  bottom:SetHeight(THICKNESS)
  left:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, 0)
  left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT", 0, 0)
  left:SetWidth(THICKNESS)
  right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, 0)
  right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 0)
  right:SetWidth(THICKNESS)

  f.border = { top, bottom, left, right }
  return f
end

--- One persistent frame per subject: a count element's aura container is hosted on it and
--- may only be armed once, so the host cannot be pooled and rebuilt under it.
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

local function SetBorderShown(f, shown)
  for _, tex in ipairs(f.border) do
    tex:SetShown(shown)
  end
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
  f:Show()
end

function Overlay.Detach(f)
  f:ClearAllPoints()
  f:Hide()
end

function Overlay.SetLit(f, lit)
  SetBorderShown(f, lit)
end
