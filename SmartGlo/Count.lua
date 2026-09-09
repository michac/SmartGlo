-- The count element: an aura application count the addon never reads, drawn as an OCCLUDER.
--
-- The polarity is inverted. Below the threshold the client draws the subject's own icon,
-- centre-cropped, over our spinning mark; at the threshold it draws nothing and the mark is
-- revealed. That inversion is what buys motion: an inline `|T..|t` escape takes a FontString's
-- alpha and none of its geometric transforms, so a mark drawn AS an escape can never turn
-- (security-taint-and-restricted-data.md §3.5). A mark our own Texture draws always can.
--
-- The addon supplies the bands and the client evaluates them against the sealed count
-- (§3.5.2). It still never learns the count.

local _, ns = ...

local Count = {}
ns.Count = Count

local containers = {}
local failed = {}
local wanted = {}
local keyFor = {}
local state = {}
local pending = {}

--- The icon and the draw size are baked into the band table's format string, and a formatter
--- is fixed at the moment it is handed over -- so both belong in the key. A rebind to another
--- spell, or a move of the icon-size slider, is a NEW container rather than a re-armed sink.
local function KeyOf(glow, icon, size)
  return ("%d:%d:%d:%d:%d"):format(glow.subject, glow.count.aura, glow.count.threshold,
    icon, size)
end

local function Note(key, text)
  state[key] = text
end

--- The COMPLEMENT: the occluder at band 0 and nothing at the threshold
--- (`{{0,"%d"},{2,""}}` is the measured shape, §3.5.2).
---
--- ⚠ Band 0 draws, so this is rule-language.md §6.4's absence case: the client hides the
--- button whenever the aura is gone, no button means no occluder, and the mark then reads as
--- though the threshold were met. It is only correct for an aura that is CONTINUOUSLY
--- PRESENT. Do not point a count element at one that drops.
local function Bands(threshold, entry)
  local escape = ns.Look.IconEscape(entry.icon, entry.width)
  return {
    { threshold = 0, format = escape },
    { threshold = threshold, format = "" },
  }
end

local function Formatter(threshold, entry)
  local util = C_StringUtil
  if type(util) ~= "table" or type(util.CreateNumericRuleFormatter) ~= "function" then
    return nil, "C_StringUtil.CreateNumericRuleFormatter is absent"
  end
  local okMake, fmt = pcall(util.CreateNumericRuleFormatter)
  if not okMake or fmt == nil then
    return nil, "CreateNumericRuleFormatter refused: " .. tostring(fmt)
  end
  local okSet, err = pcall(fmt.SetBreakpoints, fmt, Bands(threshold, entry))
  if not okSet then return nil, "SetBreakpoints refused: " .. tostring(err) end
  return fmt
end

--- One slot, one button, one FontString, one formatter, armed ONCE here and never re-armed.
local function Arm(entry, key)
  local glow = entry.glow
  local host = ns.Overlay.For(glow.subject)

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
  -- A child frame of the overlay, so the occluder draws ABOVE the overlay's own mark.
  container:SetAllPoints(host)

  local armed = false
  local okSlot, slotErr = pcall(container.AddAuraSlot, container, "count", "HELPFUL", {
    candidateFilters = {
      includeSpellIDs = { [glow.count.aura] = true },
      isFromPlayerOrPlayerPet = true,
    },
    initializeFrame = function(button)
      button:SetSize(entry.width, entry.width)
      button:SetAllPoints(container)

      local fmt, why = Formatter(glow.count.threshold, entry)
      if fmt == nil then
        Note(key, why)
        return
      end
      -- Centred is safe here where it would not be for a numeral: the string has one
      -- non-empty state, so its width never varies under the player.
      local fs = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
      -- Sub-unit trim lives HERE rather than in the escape: the escape's offsets are integers
      -- and the residual this corrects is a fraction of a unit.
      fs:SetPoint("CENTER", button, "CENTER", ns.Look.OCCLUDE_X, ns.Look.OCCLUDE_Y)
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
  Note(key, ("armed on aura %d -- icon %d, %d/%d texels drawn at %d units (residual %+.4f), "
    .. "trim %+.2f,%+.2f"):format(glow.count.aura, entry.icon, entry.crop.half * 2,
    64, entry.crop.size, entry.crop.residual, ns.Look.OCCLUDE_X, ns.Look.OCCLUDE_Y))
  container:SetAlpha(0)
  return container
end

--- Keyed and idempotent, so every flush may call it. Arming needs the row's icon and its
--- width, so a subject with no laid-out row is DEFERRED rather than armed against a guess.
function Count.Rebuild()
  wanted = {}
  keyFor = {}
  pending = {}
  for _, glow in ipairs(ns.Store.All()) do
    if glow.count ~= nil then
      local host = ns.Overlay.For(glow.subject)
      local icon = ns.Attach.IconOf(glow.subject)
      local width = host:GetWidth()
      if icon == nil or type(width) ~= "number" or width <= 0 then
        pending[glow.subject] = "waiting for a laid-out row -- an occluder is cropped from "
          .. "the icon that row is drawing."
      else
        local crop = ns.Look.ChooseCrop(width)
        local key = KeyOf(glow, icon, crop.size)
        wanted[key] = { glow = glow, icon = icon, width = width, crop = crop }
        keyFor[glow] = key
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
      containers[key]:SetAllPoints(ns.Overlay.For(entry.glow.subject))
    elseif not failed[key] then
      -- A container cannot be destroyed, so a key that failed to arm is left failed until
      -- `/sg rearm` or until the key itself changes. Retrying on every layout would build a
      -- fresh frame per event, and the report already says what went wrong.
      containers[key] = Arm(entry, key)
      failed[key] = containers[key] == nil
    end
  end
end

--- A gate over a binding closes the widget before the client draws it. Through ALPHA on our
--- own container frame: the button's own `Shown` is the client's, and a hide here would be
--- one more thing anchored above it to reason about.
function Count.SetGate(glow, open)
  local key = keyFor[glow]
  local container = key and containers[key]
  if container == nil then return end
  if open then container:SetAlpha(1) else container:SetAlpha(0) end
end

function Count.Describe(subject)
  for key, entry in pairs(wanted) do
    if entry.glow.subject == subject then
      return state[key] or "no report"
    end
  end
  return pending[subject] or "no count element"
end

function Count.Start()
  Count.Rebuild()
end

function Count.ReportStatus()
  local any = false
  for key, entry in pairs(wanted) do
    any = true
    ns.Printf("  count %s: %s |cff999999(on %s)|r", key, state[key] or "no report",
      ns.SpellLabel(entry.glow.subject))
  end
  for subject, why in pairs(pending) do
    any = true
    ns.Printf("  count on %s: %s", ns.SpellLabel(subject), why)
  end
  if not any then
    ns.Print("  no count elements.")
  end
end

--- Discards every container and builds again. A formatter is fixed at handover and a button
--- may not be re-armed, so anything that changes what a band DRAWS goes through here.
function Count.Rearm()
  for key, container in pairs(containers) do
    container:Hide()
    containers[key] = nil
    state[key] = nil
  end
  failed = {}
  Count.Rebuild()
end

ns.RegisterCommand{
  name = "rearm",
  desc = "discard every count element and build it again",
  handler = function()
    Count.Rearm()
    Count.ReportStatus()
  end,
}
