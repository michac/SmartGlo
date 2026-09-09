--@probe
-- question:  does an icon-crop escape land EXACTLY over the icon it was cropped from, and
--            what sub-unit trim closes the last of the gap? The output is sealed in the
--            product, so the alignment has to be settled where nothing is sealed.
-- opened:    2026-09-08
-- expires:   2026-09-22
-- lands-in:  Look.OCCLUDE_MIN / _MAX / _X / _Y
--@endprobe
--
-- Nothing here is sealed and no aura container is built: the question is geometry. Each tile
-- redraws what one Cooldown Manager row draws -- the icon untrimmed across the whole rect,
-- our spinning mark over it -- and lays a candidate occluder on top as a FontString escape.
-- A tile that looks like an untouched icon is a crop that lands.
--
-- ⚠ The panel takes the OVERLAY'S SCALE. Sizes inside an escape are in the FontString's own
-- coordinate space and the drawn size rounds to whole units, so a replica at a different
-- scale rounds differently from the row it is standing in for -- and then disagrees with it.
--
-- `/sg tune` is the better instrument of the two: it moves the real icon's own occluder.

local _, ns = ...

local FONT = "Fonts\\FRIZQT__.TTF"
local IMPLOSION = 196277
local PAD = 30

local TRIMS = { -0.5, -0.25, 0, 0.25, 0.5 }

local panel

local function Label(parent, text)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(FONT, 10, "OUTLINE")
  fs:SetTextColor(0.8, 0.8, 0.8)
  fs:SetText(text)
  return fs
end

--- One tile. `half` nil draws no occluder at all -- the control, i.e. what the player is meant
--- to see AT the threshold.
local function Tile(parent, x, y, width, icon, half, trim, caption)
  local tile = CreateFrame("Frame", nil, parent)
  tile:SetSize(width, width)
  tile:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

  -- Untrimmed across the whole rect, which is how CooldownViewer.xml draws it: the Icon is
  -- `setAllPoints` and there is no SetTexCoord anywhere in Blizzard_CooldownViewer.
  local art = tile:CreateTexture(nil, "BACKGROUND")
  art:SetTexture(icon)
  art:SetAllPoints(tile)

  local mark = tile:CreateTexture(nil, "ARTWORK")
  mark:SetTexture(ns.Look.MASTER)
  local rgb = ns.Look.Rgb(ns.Look.DEFAULT)
  mark:SetVertexColor(rgb[1], rgb[2], rgb[3])
  mark:SetSize(width * ns.Look.FRACTION, width * ns.Look.FRACTION)
  mark:SetPoint("CENTER")
  ns.Look.Spin(mark)

  local text = Label(tile, caption)
  text:SetPoint("TOP", tile, "BOTTOM", 0, -2)
  text:SetWidth(width + PAD)

  if half == nil then return nil end

  local escape, crop = ns.Look.IconEscape(icon, width, half)
  local fs = tile:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  fs:SetPoint("CENTER", tile, "CENTER", trim, ns.Look.OCCLUDE_Y)
  fs:SetText(escape)
  return crop
end

local function Build(subject, icon, width, scale)
  local step = width + PAD
  local chosen = ns.Look.ChooseCrop(width)
  local halves = { chosen.half - 2, chosen.half - 1, chosen.half, chosen.half + 1 }

  local f = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
  f:SetScale(scale)
  f:SetSize(math.max(420, step * 5 + 40), 2 * (width + 40) + 60)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f.TitleText:SetText("Smart Glo -- occluder probe")

  ns.Printf("occluder probe on %s: icon %d, %d units wide at scale %.3f.",
    ns.SpellLabel(subject), icon, width, scale)

  local row1 = -34
  Tile(f, 20, row1, width, icon, nil, 0, "control: no occluder")
  for i, half in ipairs(halves) do
    local crop = Tile(f, 20 + step * i, row1, width, icon, half, 0,
      ("%d/64, %d units\nres %+.3f"):format(half * 2, ns.Look.CropAt(width, half).size,
        ns.Look.CropAt(width, half).residual))
    local mine = (half == chosen.half) and " <- chosen" or ""
    ns.Printf("  crop %d/64: %d units, residual %+.4f%s", crop.half * 2, crop.size,
      crop.residual, mine)
  end

  local row2 = row1 - (width + 36)
  for i, trim in ipairs(TRIMS) do
    Tile(f, 20 + step * (i - 1), row2, width, icon, chosen.half, trim,
      ("chosen crop\nx trim %+.2f"):format(trim))
  end
  return f
end

local function Resolve(subject)
  local icon = ns.Attach.IconOf(subject)
  local overlay = ns.Overlay.For(subject)
  local width = overlay:GetWidth()
  if icon == nil or type(width) ~= "number" or width <= 0 then return nil end
  return icon, width, overlay:GetScale()
end

ns.RegisterCommand{
  name = "probe",
  args = "occluder [spellID] | close",
  desc = "candidate icon-crop occluders beside the mark they hide",
  handler = function(rest)
    local which, arg = string.match(rest or "", "^(%S*)%s*(%S*)$")
    which = string.lower(which or "")
    if which == "close" then
      if panel then panel:Hide() end
      return
    end
    if which ~= "occluder" then
      ns.Print("usage: /sg probe occluder [spellID] | /sg probe close")
      return
    end

    local subject = tonumber(arg) or IMPLOSION
    -- The enumeration is Attach's; a subject it has not bound has no icon and no width, and
    -- guessing either is exactly the mistake the probe exists to avoid.
    local icon, width, scale = Resolve(subject)
    if icon == nil then
      ns.Printf("%s has no laid-out Cooldown Manager row with a rule on it -- "
        .. "/sg profile demonology first.", ns.SpellLabel(subject))
      return
    end

    if panel then panel:Hide() end
    panel = Build(subject, icon, width, scale)
    panel:Show()
    ns.Print("top row: which crop looks like an UNTOUCHED icon? bottom row: which x trim does?")
  end,
}

ns.RegisterCommand{
  name = "tune",
  args = "x <n> | y <n> | show",
  desc = "nudge the live occluder's sub-unit trim and re-arm",
  handler = function(rest)
    local what, value = string.match(rest or "", "^(%S*)%s*(%S*)$")
    what = string.lower(what or "")

    if what == "x" or what == "y" then
      local n = tonumber(value)
      if n == nil then
        ns.Print("usage: /sg tune x -0.25   (units, not pixels; the FontString's own space)")
        return
      end
      if what == "x" then ns.Look.OCCLUDE_X = n else ns.Look.OCCLUDE_Y = n end
      -- A formatter is fixed at handover, so a trim change is a fresh container.
      ns.Count.Rearm()
    elseif what ~= "" and what ~= "show" then
      ns.Print("usage: /sg tune x <n> | /sg tune y <n> | /sg tune show")
      return
    end

    ns.Printf("trim %+.2f,%+.2f |cff999999(session only -- it is not saved)|r",
      ns.Look.OCCLUDE_X, ns.Look.OCCLUDE_Y)
    for _, subject in ipairs(ns.Store.Subjects()) do
      local icon, width = Resolve(subject)
      if icon ~= nil then
        local crop = ns.Look.ChooseCrop(width)
        ns.Printf("  %s: %d units wide, crop %d/64 drawn at %d, residual %+.4f",
          ns.SpellLabel(subject), width, crop.half * 2, crop.size, crop.residual)
      end
    end
    ns.Count.ReportStatus()
  end,
}
