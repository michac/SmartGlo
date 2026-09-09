-- The count element: an aura application count the addon never reads, drawn as a mark.
--
-- The only sink for a count is text, so the mark is an inline texture escape inside a band's
-- format string. The addon supplies the bands and the client evaluates them against the
-- sealed count (security-taint-and-restricted-data.md §3.5.2).

local _, ns = ...

local Count = {}
ns.Count = Count

local CELL = 50

local containers = {}
local wanted = {}
local state = {}
local spins = {}

--- The colour is part of the key: a band's hue is baked into the file it names, so changing
--- it means a new container rather than a re-armed sink.
local function KeyOf(glow)
  return ("%d:%d:%d:%s"):format(glow.subject, glow.count.aura, glow.count.threshold,
    glow.color or ns.Look.DEFAULT)
end

local function Note(key, text)
  state[key] = text
end

--- The band carries the escape ALONE: a rotation turns about the run's centre, and a numeral
--- beside the mark would move that centre off the mark.
local function Bands(threshold, size, color)
  local escape = ("|T%s:%d:%d|t"):format(ns.Look.File(color), size, size)
  return {
    { threshold = 0, format = "" },
    { threshold = threshold, format = escape },
  }
end

local function Formatter(threshold, size, color)
  local util = C_StringUtil
  if type(util) ~= "table" or type(util.CreateNumericRuleFormatter) ~= "function" then
    return nil, "C_StringUtil.CreateNumericRuleFormatter is absent"
  end
  local okMake, fmt = pcall(util.CreateNumericRuleFormatter)
  if not okMake or fmt == nil then
    return nil, "CreateNumericRuleFormatter refused: " .. tostring(fmt)
  end
  local okSet, err = pcall(fmt.SetBreakpoints, fmt, Bands(threshold, size, color))
  if not okSet then return nil, "SetBreakpoints refused: " .. tostring(err) end
  return fmt
end

--- One slot, one button, one FontString, one formatter, armed ONCE here and never re-armed.
local function Arm(host, glow, key)
  local okLoad, loadErr = pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
  if not okLoad then
    Note(key, "Blizzard_AuraContainer would not load: " .. tostring(loadErr))
    return nil
  end

  local okNew, container = pcall(CreateFrame, "AuraContainer", nil, host,
    "CustomAuraContainerTemplate")
  if not okNew or container == nil then
    Note(key, "the container was refused: " .. tostring(container))
    return nil
  end
  container:SetAllPoints(host)

  local width = host:GetWidth()
  if type(width) ~= "number" or width <= 0 then width = CELL end
  local size = math.floor(width * ns.Look.FRACTION)

  local armed = false
  local spin
  local okSlot, slotErr = pcall(container.AddAuraSlot, container, "count", "HELPFUL", {
    candidateFilters = {
      includeSpellIDs = { [glow.count.aura] = true },
      isFromPlayerOrPlayerPet = true,
    },
    initializeFrame = function(button)
      button:SetSize(width, width)
      button:SetAllPoints(container)

      local fmt, why = Formatter(glow.count.threshold, size, glow.color)
      if fmt == nil then
        Note(key, why)
        return
      end
      -- Centred is safe here where it would not be for a numeral: the string has one
      -- non-empty state, so its width never varies under the player.
      local fs = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
      fs:SetPoint("CENTER", button, "CENTER", 0, 0)
      spin = ns.Look.Spin(fs)
      local okSink, sinkErr = pcall(button.SetApplicationCount, button, fs, { formatter = fmt })
      if not okSink then
        Note(key, "SetApplicationCount refused: " .. tostring(sinkErr))
        return
      end
      armed = true
    end,
  })
  if not okSlot then
    Note(key, "AddAuraSlot refused: " .. tostring(slotErr))
    return nil
  end

  local okUnit, unitErr = pcall(container.SetUnit, container, "player")
  if not okUnit then
    Note(key, "SetUnit refused: " .. tostring(unitErr))
    return nil
  end
  local okUpdate, updateErr = pcall(container.UpdateAllAuras, container)
  if not okUpdate then
    Note(key, "UpdateAllAuras refused: " .. tostring(updateErr))
    return nil
  end

  if not armed then
    Note(key, "the slot built but the count sink never armed.")
    return nil
  end
  Note(key, "armed on aura " .. glow.count.aura)
  spins[key] = spin
  container:SetAlpha(0)
  return container
end

--- Arming needs an aura container built out of combat, so a rule with a count must be armed
--- before the pull.
function Count.Rebuild()
  wanted = {}
  for _, glow in ipairs(ns.Store.All()) do
    if glow.count ~= nil then
      local key = KeyOf(glow)
      wanted[key] = glow
    end
  end

  -- Hide is correct HERE and nowhere else in this file: a container being discarded is
  -- never coming back, so stopping its spin costs nothing.
  for key, container in pairs(containers) do
    if wanted[key] == nil then
      container:Hide()
      containers[key] = nil
      state[key] = nil
      spins[key] = nil
    end
  end

  for key, glow in pairs(wanted) do
    if containers[key] == nil then
      if InCombatLockdown() then
        Note(key, "not armed: aura containers can only be built out of combat.")
      else
        containers[key] = Arm(ns.Overlay.For(glow.subject), glow, key)
      end
    end
  end
end

--- A gate over a binding closes the widget before the client draws it -- through ALPHA, not
--- Hide, because the mark's motion was armed before the handover and cannot be restarted.
function Count.SetGate(glow, open)
  local container = containers[KeyOf(glow)]
  if container == nil then return end
  if open then container:SetAlpha(1) else container:SetAlpha(0) end
end

function Count.Reanchor()
  for key, glow in pairs(wanted) do
    local container = containers[key]
    if container ~= nil then
      container:SetAllPoints(ns.Overlay.For(glow.subject))
    end
  end
end

function Count.Describe(subject)
  for key, glow in pairs(wanted) do
    if glow.subject == subject then
      return state[key] or "no report"
    end
  end
  return "no count element"
end

function Count.Start()
  Count.Rebuild()
end

function Count.ReportStatus()
  local any = false
  for key in pairs(wanted) do
    any = true
    local spin = "no spin group"
    if spins[key] ~= nil then
      -- The group is forbidden to us once the sink has taken its FontString, so this
      -- reports what the read DID rather than a state it cannot obtain.
      local ok, playing = pcall(spins[key].IsPlaying, spins[key])
      if not ok then
        spin = "spin armed; group is forbidden to read back"
      elseif ns.IsSecret(playing) then
        spin = "spin armed; IsPlaying is secret"
      else
        spin = "spin armed; playing=" .. tostring(playing)
      end
    end
    ns.Printf("  count %s: %s |cff999999(%s, combat=%s)|r", key, state[key] or "no report",
      spin, tostring(InCombatLockdown()))
  end
  if not any then
    ns.Print("  no count elements.")
  end
end

ns.RegisterCommand{
  name = "rearm",
  desc = "rebuild count elements (out of combat)",
  handler = function()
    if InCombatLockdown() then
      ns.Print("not out of combat -- aura containers can only be built before the pull.")
      return
    end
    for key, container in pairs(containers) do
      container:Hide()
      containers[key] = nil
      state[key] = nil
      spins[key] = nil
    end
    Count.Rebuild()
    Count.ReportStatus()
  end,
}
