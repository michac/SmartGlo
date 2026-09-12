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
--- The mark is a FRACTION of its host, and the host follows the item through a two-point
--- anchor -- so the host resizes on its own whenever the icon does, with no layout event we
--- hook and no re-anchor. Sizing off the frame's own resize is what makes the mark follow an
--- icon-size change, including one made by another addon laying the viewers out.
local function Build()
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetFrameStrata("MEDIUM")
  f:SetAlpha(0)
  f.elements = {}
  f:SetScript("OnSizeChanged", SizeMarks)
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

  -- The plate: a solid hexagon in translucent black, UNDER the mark, so the mark's dark
  -- phase is dim against a known ground rather than against the spell art. It never turns
  -- and never bounces -- it is what the mark lands on, and a plate that moved too would read
  -- as the icon sliding rather than as something happening ON the icon.
  -- ⚠ Black in THREE arguments, and no translucency written here at all: `PLATE_ALPHA` is
  -- baked into the file. A fourth argument would be the same channel `SetAlpha` writes --
  -- `SetVertexColor` adds the aspects {VertexColor, Alpha} -- so the alpha write that follows
  -- clobbers it and the plate draws solid black `[client 2026-09-11]`.
  local plate = e:CreateTexture(nil, "ARTWORK")
  plate:SetTexture(ns.Look.PLATE)
  plate:SetVertexColor(0, 0, 0)
  plate:SetPoint("CENTER")
  plate:SetAlpha(0)

  -- Our own Texture, tinted here and turning here. Both kinds of glow reveal THIS mark: a
  -- gate by drawing it, a count by having the client take its occluder away.
  local mark = e:CreateTexture(nil, "OVERLAY")
  mark:SetTexture(ns.Look.MASTER)
  mark:SetPoint("CENTER")
  mark:SetAlpha(0)
  local _, spin = ns.Look.Spin(mark)

  e.plate = plate
  e.mark = mark
  e.spin = spin
  e.bounce = ns.Look.Bounce(mark)
  return e
end

--- The mark is a FRACTION of the row it rides, so its size follows the host's -- and an
--- element built after the host was anchored has to be sized on arrival, not only on the next
--- anchor, or it draws at nothing. The plate is a fraction of the same one width, so the pair
--- keeps its proportion at every icon size.
--- The bounce is re-armed from the mark's new size here. The host carries the item's scale, so
--- an offset in its units should already be proportional -- but this is the one place that
--- keeps that invariant true, and it costs one call in a loop that already exists.
function SizeMarks(f)
  local width = f:GetWidth()
  if type(width) ~= "number" or width <= 0 then return end
  local mark = width * ns.Look.FRACTION * ns.Look.MARK_SCALE
  local plate = width * ns.Look.FRACTION * ns.Look.PLATE_SCALE
  for _, e in pairs(f.elements) do
    e.mark:SetSize(mark, mark)
    e.plate:SetSize(plate, plate)
    ns.Look.ArmBounce(e.bounce, mark)
  end
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

--- THE ART'S ALPHA, both regions, one call -- and the only door to it. The plate is a second
--- region showing the same thing the mark shows, so anything that decides whether the mark is
--- drawn decides the plate too; a caller that wrote only the mark would leave a lit plate with
--- nothing on it, which is what a sealed bind did until this existed `[client 2026-09-11]`.
--- `alpha` may be a SECRET handed over by a sealed family. It is passed straight through to two
--- `SetAlpha` sinks and never read, compared or multiplied -- which is why the plate's
--- translucency is in the art and not applied here.
function Overlay.SetArt(e, alpha)
  e.mark:SetAlpha(alpha)
  e.plate:SetAlpha(alpha)
end

--- An element outlives the rule that built it -- elements are never destroyed, because a
--- count's aura container may only be armed once. So a rule set replaced under a live overlay
--- leaves marks nothing writes any more, frozen at the alpha they last held, and a sealed one
--- has no ticker left to darken it. Anything no current glow owns is taken dark here.
function Overlay.DarkenStale(live)
  for _, f in pairs(frames) do
    for _, e in pairs(f.elements) do
      if not live[e] then
        e:SetAlpha(0)
        Overlay.SetArt(e, 0)
      end
    end
  end
end

--- The gate, and the tint that goes with it. The COLOUR write is unconditional -- vertex
--- colour carries no secret and is a different channel from alpha. The MARK's alpha is
--- written only for an element whose mark nothing has sealed. A count element is NOT sealed
--- here: its occluder is a sibling drawn above the mark, not another writer of the mark's
--- alpha. Only a duration bind owns that channel, and then a write here would be a second
--- owner of one channel.
function Overlay.SetLit(e, lit, color, sealed, urgent)
  -- A cycling colour has ONE writer and it is not here; `SetTint` either paints a solid or
  -- hands the mark to the shared ticker. Either way vertex colour carries no secret, so this
  -- write is unconditional and never touches the alpha the bind owns.
  ns.Look.SetTint(e.mark, color, urgent)
  e:SetAlpha(lit and 1 or 0)
  if not sealed then
    Overlay.SetArt(e, lit and 1 or 0)
  end
  -- ⚠ The PLATE is not written here for a sealed element, and that is the whole point: it
  -- shows whatever the mark shows, so it belongs to whoever owns the mark's alpha. Giving it
  -- the readable GATE instead left Word of Glory drawing a lit plate with no mark on it
  -- whenever its health bind said dark `[client 2026-09-11]`. The element frame's own alpha
  -- above still gates both, so a sealed element that is not lit shows nothing either way.
  -- Urgent runs the SPIN faster too, so an urgent glow drifts out of phase with the plain
  -- ones beside it on two channels rather than one. Written only when it CHANGES: this runs on
  -- every evaluation, and re-timing a turn that is already turning at that rate is at best
  -- nothing and at worst a visible hitch in it.
  local seconds = urgent and ns.Look.SPIN_SECONDS / ns.Look.URGENT_RATE or ns.Look.SPIN_SECONDS
  if e.spinSeconds ~= seconds then
    e.spin:SetDuration(seconds)
    e.spinSeconds = seconds
  end
  -- The bounce is a fourth channel and owns nothing the other three do: it says how hard the
  -- mark presses, never whether it is drawn. A sealed mark bounces while the client decides
  -- its alpha, and a bounce on a dark mark costs nothing because nothing is visible.
  if urgent and lit then
    if not e.bounce:IsPlaying() then e.bounce:Play() end
  elseif e.bounce:IsPlaying() then
    e.bounce:Stop()
  end
end
