--@probe
-- question:  does an icon-crop escape land EXACTLY over the icon it was cropped from, and at
--            which crop fraction and vertical offset? The output is sealed in the product,
--            so the alignment has to be settled where nothing is sealed.
-- opened:    2026-09-08
-- expires:   2026-09-22
-- lands-in:  Look.OCCLUDE / Look.OCCLUDE_Y
--@endprobe
--
-- Nothing here is sealed and no aura container is built: the question is geometry. Each tile
-- redraws what one Cooldown Manager row draws -- the icon untrimmed across the whole rect,
-- our spinning mark over it -- and lays a candidate occluder on top as a FontString escape.
-- A tile that looks like an untouched icon is a crop that lands.
--
-- Sizes inside an escape are in the FONTSTRING'S coordinate space, so every number below is
-- derived from the tile's own width. The panel's screen scale is therefore free to differ
-- from the icon's without changing what the tiles answer.

local _, ns = ...

local FONT = "Fonts\\FRIZQT__.TTF"
local IMPLOSION = 196277
local PAD = 26

local FRACTIONS = { 0.72, 0.82, 0.92, 1.00 }
local OFFSETS = { -6, -3, 0, 3 }

local panel

local function Label(parent, text)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(FONT, 10, "OUTLINE")
  fs:SetTextColor(0.8, 0.8, 0.8)
  fs:SetText(text)
  return fs
end

--- One tile. `fraction` nil draws no occluder at all -- the control, i.e. what the player is
--- meant to see AT the threshold.
local function Tile(parent, x, y, width, icon, fraction, yOffset, caption)
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

  if fraction == nil then return nil end

  local escape = ns.Look.IconEscape(icon, width, fraction, yOffset)
  local fs = tile:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  fs:SetPoint("CENTER", tile, "CENTER", 0, 0)
  fs:SetText(escape)
  return escape
end

local function Build(subject, icon, width)
  local step = width + PAD
  local f = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(math.max(360, step * 5 + 40), 2 * (width + 34) + 60)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f.TitleText:SetText("Smart Glo -- occluder probe")

  ns.Printf("occluder probe on %s: icon %d, %d units wide.", ns.SpellLabel(subject), icon,
    width)

  local row1 = -34
  Tile(f, 20, row1, width, icon, nil, 0, "control: no occluder")
  for i, fraction in ipairs(FRACTIONS) do
    local escape = Tile(f, 20 + step * i, row1, width, icon, fraction, 0,
      ("crop %.2f, y 0"):format(fraction))
    ns.Printf("  crop %.2f y 0: %s", fraction, (escape:gsub("|", "||")))
  end

  local row2 = row1 - (width + 30)
  for i, yOffset in ipairs(OFFSETS) do
    local escape = Tile(f, 20 + step * (i - 1), row2, width, icon, ns.Look.OCCLUDE, yOffset,
      ("crop %.2f, y %d"):format(ns.Look.OCCLUDE, yOffset))
    ns.Printf("  crop %.2f y %d: %s", ns.Look.OCCLUDE, yOffset, (escape:gsub("|", "||")))
  end
  return f
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
    local icon = ns.Attach.IconOf(subject)
    local width = ns.Overlay.For(subject):GetWidth()
    if icon == nil or type(width) ~= "number" or width <= 0 then
      ns.Printf("%s has no laid-out Cooldown Manager row with a rule on it -- "
        .. "/sg profile demonology first.", ns.SpellLabel(subject))
      return
    end

    if panel then panel:Hide() end
    panel = Build(subject, icon, width)
    panel:Show()
    ns.Print("which tile looks like an UNTOUCHED icon? That crop is the occluder.")
  end,
}
