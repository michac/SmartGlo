-- The presence element: an aura the addon never reads, drawn by the fact that it EXISTS.
--
-- Revealing polarity, and that is what makes absence safe here. The container creates a button
-- only while an aura matches, so our mark rides the button and an absent aura draws nothing.
-- The count element had to invert -- a threshold needs the client to pick a band, and band 0
-- draws -- but a presence has no threshold and needs no occluder.
--
-- Not limited to a Cooldown Manager row. The container reads through
-- `C_UnitAuras.GetUnitAuraInstanceIDs(unit, filter)` in untainted Blizzard code, so the unit is
-- whatever we name and the bound is the filter string
-- (security-taint-and-restricted-data.md §3.5).

local _, ns = ...

local Presence = {}
ns.Presence = Presence

local containers, failed, wanted, state = {}, {}, {}, {}

--- The filter and the unit are fixed when the slot is added, so both belong in the key: a
--- change to either is a NEW container rather than a re-armed one.
local function KeyOf(glow)
  local bind = glow.bind
  return ("%d:%d:%s:%s"):format(glow.subject, bind.aura, bind.unit, bind.filter)
end

function Presence.Owns(glow)
  return type(glow.bind) == "table" and glow.bind.family == "presence"
end

--- Every arm outcome passes through here, so the log has one place to watch. A container that
--- fails to arm stays failed until `/sg rearm` -- retrying per layout would build a frame an
--- event, and the report already says what went wrong.
local function Note(key, text)
  if state[key] == text then return end
  state[key] = text
  ns.log:Mark("presence %s: %s", ns.Capture.Safe(key), ns.Capture.Safe(text))
end

local function Arm(entry, key)
  local glow, host = entry.glow, entry.host
  local size = entry.width * ns.Look.FRACTION
  local plate = size * ns.Look.PLATE_SCALE
  local rgb = ns.Look.Rgb(glow.color or ns.Look.DEFAULT)
  local plateRgb = ns.Look.PLATE_RGB

  local okFrame, container = pcall(CreateFrame, "AuraContainer", nil, host,
    "CustomAuraContainerTemplate")
  if not okFrame or container == nil then
    Note(key, "CreateFrame refused -- " .. ns.Capture.Safe(container))
    return nil
  end
  container:SetAllPoints(host)

  -- The container creates and anchors its own buttons; `initializeFrame` is the only hook
  -- into construction, so the mark is built here and never afterwards.
  local okSlot, slotErr = pcall(container.AddAuraSlot, container, "presence", glow.bind.filter, {
    candidateFilters = { includeSpellIDs = { [glow.bind.aura] = true } },
    initializeFrame = function(button)
      button:SetSize(entry.width, entry.width)
      -- The plate, same as the gate sink draws, turning with the mark: the mark's dark phase
      -- needs a known ground. Colour in three -- PLATE_ALPHA is baked into the file, and a
      -- fourth argument would be the same channel `SetAlpha` writes (Overlay.lua, BuildElement).
      local ground = button:CreateTexture(nil, "ARTWORK")
      ground:SetTexture(ns.Look.PLATE)
      ground:SetVertexColor(plateRgb[1], plateRgb[2], plateRgb[3])
      ground:SetSize(plate, plate)
      ground:SetPoint("CENTER")
      ns.Look.Spin(ground)
      local mark = button:CreateTexture(nil, "OVERLAY")
      mark:SetTexture(ns.Look.MASTER)
      mark:SetSize(size, size)
      mark:SetPoint("CENTER")
      mark:SetVertexColor(rgb[1], rgb[2], rgb[3])
      ns.Look.Spin(mark)
    end,
  })
  if not okSlot then
    Note(key, "AddAuraSlot refused -- " .. ns.Capture.Safe(slotErr))
    return nil
  end

  local okUnit, unitErr = pcall(container.SetUnit, container, glow.bind.unit)
  if not okUnit then
    Note(key, "SetUnit refused -- " .. ns.Capture.Safe(unitErr))
    return nil
  end

  Note(key, ("armed on aura %d, unit %s, filter %s"):format(
    glow.bind.aura, glow.bind.unit, glow.bind.filter))
  return container
end

--- Keyed and idempotent, so every flush may call it. Unlike a count, arming needs no icon --
--- nothing is cropped -- so a subject with no laid-out row still arms and simply has nothing
--- to anchor over until one arrives.
function Presence.Rebuild()
  wanted = {}
  for _, glow in ipairs(ns.Store.All()) do
    if Presence.Owns(glow) then
      local host = ns.Overlay.Element(glow)
      local width = host:GetWidth()
      if type(width) == "number" and width > 0 then
        wanted[KeyOf(glow)] = { glow = glow, host = host, width = width }
      end
    end
  end

  for key, container in pairs(containers) do
    if wanted[key] == nil then
      container:Hide()
      containers[key] = nil
      state[key] = nil
    end
  end
  for key in pairs(failed) do
    if wanted[key] == nil then failed[key] = nil end
  end

  for key, entry in pairs(wanted) do
    if containers[key] ~= nil then
      containers[key]:SetAllPoints(entry.host)
    elseif not failed[key] then
      containers[key] = Arm(entry, key)
      failed[key] = containers[key] == nil
    end
  end
end

--- What `/sg why` can say about a presence bind: nothing was read, so the arm report is the
--- whole story -- which unit and which filter the client was asked about.
function Presence.Describe(glow)
  return state[KeyOf(glow)] or "not armed"
end

function Presence.Rearm()
  failed = {}
  for key, container in pairs(containers) do
    container:Hide()
    containers[key] = nil
    state[key] = nil
  end
  Presence.Rebuild()
end
