-- The remains element: an aura's remaining time the addon never reads, drawn as an OCCLUDER.
--
-- Count's twin at a different sink. `SetApplicationCount` bands the application count;
-- `SetDurationText` hands the same kind of `NumericRuleFormatter` the aura's CLOCK, and the
-- client evaluates our band table against a remaining time we may not read
-- (security-taint-and-restricted-data.md §3.5.2). Everything else is the count element: the
-- band that draws is an inline `|T..|t` escape of the subject's own icon, centre-cropped, and
-- the band that draws NOTHING is the one that reveals our spinning mark underneath.
--
-- ⚠ BANDS ARE IN SECONDS. An unconfigured binding samples `RemainingDuration`, measured by
-- complement: two bands split at 31 drew as exact inverses across a whole DoT, which a percent
-- input starting at 100 could not produce. A rule written as though it were percent is
-- silently wrong rather than refused, so `<n>s` is part of the surface form.
--
-- ⚠ `options.textFormatter` is the ONLY door. `GetDurationTextBinding` is declared on
-- `CustomAuraButtonPrivateMixin`, and calling it from an addon ABORTS the enclosing function
-- with no error and no log line -- a failure that looks exactly like a rule being ignored.
-- Never reach for it.
--
-- ⚠ This sink seals `Text`, `Alpha` AND `VertexColor`, against `SetApplicationCount`'s `Text`
-- and `Shown`. So no static `SetTextColor` at setup and no alpha animation on that region.
-- The spinning mark underneath is ours, as it is for a count.

local _, ns = ...

local Remains = {}
ns.Remains = Remains

local containers = {}
local failed = {}
local wanted = {}
local state = {}
local pending = {}

--- The unit and filter are fixed, not authored. This family answers "is the DoT I am
--- maintaining about to fall off", so the container watches the TARGET for harmful auras the
--- player applied. A `remains` bind on a self-buff matches nothing, arms no occluder, and
--- would leave the mark bright -- the same hazard the count family carries in the mirror
--- direction. `<aura>.up on player` is the bind for a self-buff.
local UNIT, FILTER = "target", "HARMFUL|PLAYER"

--- Which comparisons put the LIT half at the low end. A band table picks the highest
--- threshold at or below the value, so `< n` is the complement of `>= n` and nothing else
--- about the table changes.
--- ⚠ A band boundary is `>=`, so `<` and `<=` compile to the same table, as do `>` and `>=`.
--- The pair differ only at the exact instant the clock reads `n`, on a value that is falling
--- continuously; there is no picture that separates them.
local LOW_IS_LIT = { ["<"] = true, ["<="] = true }

--- The icon and the draw size are baked into the band table's format string, and a formatter
--- is fixed at the moment it is handed over -- so both belong in the key. A rebind to another
--- spell, or a move of the icon-size slider, is a NEW container rather than a re-armed sink.
local function KeyOf(glow, icon, size)
  return ("%d:%d:%s:%s:%d:%d"):format(glow.subject, glow.bind.aura, glow.bind.cmp,
    tostring(glow.bind.seconds), icon, size)
end

function Remains.Owns(glow)
  return type(glow.bind) == "table" and glow.bind.family == "remains"
end

--- Every arm outcome, success and each distinct failure, passes through here -- so this is
--- the one place the log has to watch. A container that fails to arm is left failed until
--- `/sg rearm`, which is exactly the silence the mark exists to break.
local function Note(key, text)
  if state[key] == text then return end
  state[key] = text
  ns.log:Mark("remains %s: %s", ns.Capture.Safe(key), ns.Capture.Safe(text))
end

--- ⚠ Band 0 is the one that DRAWS for a `>=`, and the one that draws NOTHING for a `<` -- and
--- either way the client hides the whole button when the aura is gone. With the occluder gone
--- with it, a `<` rule's mark reads as though the threshold were met (rule-language.md §6.4).
--- Nothing in this file can see that: the sealed half never learns the aura went away.
--- `Rules.Gate` covers it, adding a presence term on this same aura to the readable half,
--- which closes the element's alpha over the occluder and the mark together. An aura that
--- drops is safe BECAUSE of that gate, not on its own.
local function Bands(bind, entry)
  local escape = ns.Look.IconEscape(entry.icon, entry.width)
  if LOW_IS_LIT[bind.cmp] then
    return {
      { threshold = 0, format = "" },
      { threshold = bind.seconds, format = escape },
    }
  end
  return {
    { threshold = 0, format = escape },
    { threshold = bind.seconds, format = "" },
  }
end

local function Formatter(bind, entry)
  local util = C_StringUtil
  if type(util) ~= "table" or type(util.CreateNumericRuleFormatter) ~= "function" then
    return nil, "C_StringUtil.CreateNumericRuleFormatter is absent"
  end
  local okMake, fmt = pcall(util.CreateNumericRuleFormatter)
  if not okMake or fmt == nil then
    return nil, "CreateNumericRuleFormatter refused: " .. tostring(fmt)
  end
  local okSet, err = pcall(fmt.SetBreakpoints, fmt, Bands(bind, entry))
  if not okSet then return nil, "SetBreakpoints refused: " .. tostring(err) end
  return fmt
end

--- One slot, one button, one FontString, one formatter, armed ONCE here and never re-armed.
local function Arm(entry, key)
  local glow = entry.glow
  local host = ns.Overlay.Element(glow)

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
  -- A child frame of the element, so the occluder draws ABOVE that element's own mark and
  -- over nothing else: a second glow on the same subject has its own element and its own mark.
  container:SetAllPoints(host)

  local armed = false
  -- ⚠ THE AURA ID, NOT THE CAST ID. `includeSpellIDs` matches the aura sitting on the unit,
  -- which for a DoT is not always the id of the spell you pressed. `Names.Resolve(..., "aura")`
  -- already yields the right one -- which is why this family resolves in the aura namespace --
  -- but naming the cast id here costs a flight and looks exactly like a dead sink.
  local okSlot, slotErr = pcall(container.AddAuraSlot, container, "remains", FILTER, {
    candidateFilters = {
      includeSpellIDs = { [glow.bind.aura] = true },
    },
    initializeFrame = function(button)
      button:SetSize(entry.width, entry.width)
      button:SetAllPoints(container)

      local fmt, why = Formatter(glow.bind, entry)
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
      local okSink, sinkErr = pcall(button.SetDurationText, button, fs, { textFormatter = fmt })
      if not okSink then
        Note(key, "SetDurationText refused: " .. tostring(sinkErr))
        return
      end
      armed = true
    end,
  })
  if not okSlot then
    Note(key, "AddAuraSlot refused: " .. tostring(slotErr))
    return nil
  end

  local okUnit, unitErr = pcall(container.SetUnit, container, UNIT)
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
    Note(key, "the slot built but the duration sink never armed.")
    return nil
  end
  Note(key, ("armed on aura %d (%s, %s) -- lit %s %ss, icon %d, %d/%d texels drawn at %d "
    .. "units (residual %+.4f), trim %+.2f,%+.2f"):format(glow.bind.aura, UNIT, FILTER,
    glow.bind.cmp, tostring(glow.bind.seconds), entry.icon, entry.crop.half * 2, 64,
    entry.crop.size, entry.crop.residual, ns.Look.OCCLUDE_X, ns.Look.OCCLUDE_Y))
  return container
end

--- Keyed and idempotent, so every flush may call it. Arming needs the row's icon and its
--- width, so a subject with no laid-out row is DEFERRED rather than armed against a guess.
function Remains.Rebuild()
  wanted = {}
  pending = {}
  for _, glow in ipairs(ns.Store.All()) do
    if Remains.Owns(glow) then
      local host = ns.Overlay.Element(glow)
      local icon = ns.Attach.IconOf(glow.subject)
      local width = host:GetWidth()
      if icon == nil or type(width) ~= "number" or width <= 0 then
        pending[glow.subject] = "waiting for a laid-out row -- an occluder is cropped from "
          .. "the icon that row is drawing."
      else
        local crop = ns.Look.ChooseCrop(width)
        local key = KeyOf(glow, icon, crop.size)
        wanted[key] = { glow = glow, icon = icon, width = width, crop = crop }
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
      containers[key]:SetAllPoints(ns.Overlay.Element(entry.glow))
    elseif not failed[key] then
      -- A container cannot be destroyed, so a key that failed to arm is left failed until
      -- `/sg rearm` or until the key itself changes. Retrying on every layout would build a
      -- fresh frame per event, and the report already says what went wrong.
      containers[key] = Arm(entry, key)
      failed[key] = containers[key] == nil
    end
  end
end

function Remains.Describe(subject)
  for key, entry in pairs(wanted) do
    if entry.glow.subject == subject then
      return state[key] or "no report"
    end
  end
  return pending[subject] or "no remains element"
end

function Remains.ReportStatus()
  local any = false
  for key, entry in pairs(wanted) do
    any = true
    ns.Printf("  remains %s: %s |cff999999(on %s)|r", key, state[key] or "no report",
      ns.SpellLabel(entry.glow.subject))
  end
  for subject, why in pairs(pending) do
    any = true
    ns.Printf("  remains on %s: %s", ns.SpellLabel(subject), why)
  end
  if not any then
    ns.Print("  no remains elements.")
  end
end

--- Discards every container and builds again. A formatter is fixed at handover and a button
--- may not be re-armed, so anything that changes what a band DRAWS goes through here.
function Remains.Rearm()
  for key, container in pairs(containers) do
    container:Hide()
    containers[key] = nil
    state[key] = nil
  end
  failed = {}
  Remains.Rebuild()
end
