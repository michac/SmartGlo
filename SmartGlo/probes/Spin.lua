--@probe
-- question:  does a Rotation animation reach an inline |T..|t escape inside a FontString, and
--            does any animation run inside an AuraContainer button?
-- opened:    2026-09-08
-- expires:   2026-09-22
-- lands-in:  knowledge/addon-dev/security-taint-and-restricted-data.md §3.5.3
--@endprobe

local _, ns = ...

local FONT = "Fonts\\FRIZQT__.TTF"
local MARK = "Interface\\AddOns\\SmartGlo\\Media\\hex-yellow"
local SIZE = 48
local WILD_IMP = 296553

local panel

local function Label(parent, text)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(FONT, 11, "OUTLINE")
  fs:SetTextColor(0.8, 0.8, 0.8)
  fs:SetText(text)
  return fs
end

--- One tile. `kind` picks what draws; `motion` picks which animation is looped on it.
local function Tile(parent, x, label, kind, motion)
  local host = CreateFrame("Frame", nil, parent)
  host:SetSize(SIZE + 20, SIZE + 20)
  host:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -34)

  local caption = Label(host, label)
  caption:SetPoint("TOP", host, "BOTTOM", 0, -2)
  caption:SetWidth(SIZE + 40)

  local region
  if kind == "texture" then
    region = host:CreateTexture(nil, "OVERLAY")
    region:SetTexture(MARK)
    region:SetSize(SIZE, SIZE)
    region:SetPoint("CENTER")
  else
    region = host:CreateFontString(nil, "OVERLAY")
    region:SetFont(FONT, 20, "OUTLINE")
    region:SetPoint("CENTER")
    if kind == "text" then
      region:SetText("66")
    else
      region:SetText(("|T%s:%d:%d|t"):format(MARK, SIZE, SIZE))
    end
  end

  local group = region:CreateAnimationGroup()
  if motion == "rotate" then
    local a = group:CreateAnimation("Rotation")
    a:SetDegrees(-360)
    a:SetDuration(3)
  elseif motion == "scale" then
    local a = group:CreateAnimation("Scale")
    a:SetScaleFrom(1, 1)
    a:SetScaleTo(1.6, 1.6)
    a:SetDuration(0.7)
    a:SetSmoothing("IN_OUT")
    group:SetLooping("BOUNCE")
  else
    local a = group:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.15)
    a:SetDuration(0.7)
    group:SetLooping("BOUNCE")
  end
  if motion == "rotate" then group:SetLooping("REPEAT") end
  group:Play()
  return host
end

local function Build()
  local f = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(560, 170)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f.TitleText:SetText("Smart Glo -- spin probe (no secrets anywhere)")

  Tile(f, 20,  "A texture + rotate",    "texture", "rotate")
  Tile(f, 130, "B text + rotate",       "text",    "rotate")
  Tile(f, 240, "C escape + rotate",     "escape",  "rotate")
  Tile(f, 350, "D escape + scale",      "escape",  "scale")
  Tile(f, 460, "E escape + alpha",      "escape",  "alpha")
  return f
end

--- The aura-container half: our OWN texture inside the client's button, rotating, with no
--- FontString and no sink -- so nothing of ours is ever handed a secret.
local function BuildAura()
  local f = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(300, 170)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, -60)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f.TitleText:SetText("Smart Glo -- aura-container spin probe")

  local control = Tile(f, 20, "control (plain frame)", "texture", "rotate")
  control:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -34)

  local host = CreateFrame("Frame", nil, f)
  host:SetSize(SIZE + 20, SIZE + 20)
  host:SetPoint("TOPLEFT", f, "TOPLEFT", 160, -34)
  local caption = Label(host, "inside an AuraButton")
  caption:SetPoint("TOP", host, "BOTTOM", 0, -2)
  caption:SetWidth(SIZE + 60)

  local okLoad = pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
  if not okLoad then ns.Print("probe: Blizzard_AuraContainer would not load."); return f end

  local okNew, container = pcall(CreateFrame, "AuraContainer", nil, host,
    "CustomAuraContainerTemplate")
  if not okNew or container == nil then
    ns.Printf("probe: container refused -- %s", tostring(container))
    return f
  end
  container:SetAllPoints(host)

  local okSlot, slotErr = pcall(container.AddAuraSlot, container, "spin", "HELPFUL", {
    candidateFilters = { includeSpellIDs = { [WILD_IMP] = true }, isFromPlayerOrPlayerPet = true },
    initializeFrame = function(button)
      button:SetSize(SIZE, SIZE)
      button:SetAllPoints(container)
      local tex = button:CreateTexture(nil, "OVERLAY")
      tex:SetTexture(MARK)
      tex:SetSize(SIZE, SIZE)
      tex:SetPoint("CENTER")
      local group = tex:CreateAnimationGroup()
      local a = group:CreateAnimation("Rotation")
      a:SetDegrees(-360)
      a:SetDuration(3)
      group:SetLooping("REPEAT")
      group:Play()
    end,
  })
  if not okSlot then ns.Printf("probe: AddAuraSlot refused -- %s", tostring(slotErr)) end
  local okUnit, unitErr = pcall(container.SetUnit, container, "player")
  if not okUnit then ns.Printf("probe: SetUnit refused -- %s", tostring(unitErr)) end
  pcall(container.UpdateAllAuras, container)
  return f
end

local auraPanel

ns.RegisterCommand{
  name = "probe",
  args = "spin|aura|close",
  desc = "spin probes: plain regions, and one inside an aura button",
  handler = function(rest)
    local which = string.lower(string.match(rest or "", "^(%S*)"))
    if which == "close" then
      if panel then panel:Hide() end
      if auraPanel then auraPanel:Hide() end
      return
    end
    if which == "aura" then
      if auraPanel == nil then auraPanel = BuildAura() end
      auraPanel:Show()
      ns.Print("aura probe: left tile is a plain frame, right tile is our texture INSIDE the "
        .. "client's aura button. Do both turn?")
      return
    end
    if panel == nil then panel = Build() end
    panel:Show()
    ns.Print("spin probe: A texture, B text, C escape+rotate, D escape+scale, E escape+alpha. "
      .. "Which move?")
  end,
}
