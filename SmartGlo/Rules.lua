-- The rule AST: the two bowls, the checker's refusals, and three-valued evaluation.
--
-- `when` is the readable bowl and takes as many terms as you like. `bind` is the sealed bowl
-- and holds AT MOST ONE leaf, which is why it is a slot and not a list: at-most-one is then
-- structural rather than something the checker has to remember to say.

local _, ns = ...

local Rules = {}
ns.Rules = Rules

--- Secondary resources are never secret, so a threshold on one is readable at any value.
local SECONDARY = {
  soul_shards = "SoulShards",
  holy_power = "HolyPower",
  combo_points = "ComboPoints",
  chi = "Chi",
  arcane_charges = "ArcaneCharges",
  essence = "Essence",
  runes = "Runes",
}

--- Every primary reads secret in every context, so one can never answer a boolean.
local PRIMARY = {
  mana = true, rage = true, focus = true, energy = true, runic_power = true,
  fury = true, pain = true, insanity = true, maelstrom = true,
}

--- Which resources may carry `.after_cast`. Not every secondary can: the Tier-1 energize
--- rows show Wake of Ashes returning 1, 3 or 5 Holy Power and Ambush 1, 2 or 3 Combo Points
--- depending on talents and procs, so there is no single number to project with. Soul Shards
--- are whole and invariant for every hard cast that generates them, which is what makes the
--- projection honest here and a guess everywhere else.
local PROJECTABLE = { soul_shards = true }

local CMP = {
  [">="] = function(a, b) return a >= b end,
  [">"] = function(a, b) return a > b end,
  ["<="] = function(a, b) return a <= b end,
  ["<"] = function(a, b) return a < b end,
  ["=="] = function(a, b) return a == b end,
}

--- The bowl catalogue: a term named on the wrong side is refused BY NAME in both directions,
--- which is what makes the sorting enforced rather than remembered.
local SEALED_FAMILY = { count = true, duration = true, presence = true }

--- Every readable term that is a call over ONE spell. Named once: the checker, the renderer
--- and the trigger table all ask this, so a new call cannot be half-added.
local SPELL_TERM = {
  ready = true, aura = true, talent = true, at_max_charges = true, no_charges = true,
}

local READABLE_TERM = { resource = true }
for name in pairs(SPELL_TERM) do READABLE_TERM[name] = true end

--- The filter components a presence bind may name. A subset of `AuraUtil.AuraFilters` on
--- purpose: these are the ones the grammar can produce, and the client asserts on the rest.
local FILTER_COMPONENT = { HELPFUL = true, HARMFUL = true, PLAYER = true }

--- `<` and `outside` on a cooldown are also true at zero remaining, and zero remaining means
--- the spell is READY -- so such a bind glows permanently while its subject is up unless the
--- author says otherwise. Bright is worse than dark.
local UNBOUNDED_BELOW = { ["<"] = true, ["<="] = true, outside = true }

function Rules.PowerType(name)
  local key = SECONDARY[name]
  if key == nil then return nil end
  if type(Enum) ~= "table" or type(Enum.PowerType) ~= "table" then return nil end
  return Enum.PowerType[key]
end

--- A rule written before the two bowls: `show` is `when`, and a `count` element is the count
--- family of `bind`. Old wire strings and old SavedVariables still load.
function Rules.Modernize(glow)
  if type(glow) ~= "table" then return glow end
  if glow.when == nil and glow.show ~= nil then glow.when = glow.show end
  glow.show = nil
  if glow.bind == nil and type(glow.count) == "table" then
    glow.bind = { family = "count", aura = glow.count.aura, threshold = glow.count.threshold }
  end
  glow.count = nil
  return glow
end

-- ---------------------------------------------------------------- the checker

local Check

local function CheckList(terms, errs, depth)
  if type(terms) ~= "table" or #terms == 0 then
    table.insert(errs, "a combinator needs at least one term")
    return
  end
  for _, term in ipairs(terms) do
    Check(term, errs, depth + 1)
  end
end

--- Refusals are §6 of rule-language.md: a rule that would author cleanly and never fire.
function Check(term, errs, depth)
  depth = depth or 0
  if depth > 12 then
    table.insert(errs, "expression nested deeper than 12")
    return
  end
  if type(term) ~= "table" or type(term.t) ~= "string" then
    table.insert(errs, "a term needs a string `t`")
    return
  end

  if term.t == "and" or term.t == "or" then
    CheckList(term.terms, errs, depth)
  elseif term.t == "not" then
    Check(term.term, errs, depth + 1)
  elseif term.t == "resource" then
    if PRIMARY[term.power] then
      table.insert(errs, ("%s is a primary resource, which is never readable -- it belongs "
        .. "in `bind` as a percent, not in `when`"):format(term.power))
    elseif SECONDARY[term.power] == nil then
      table.insert(errs, ("unknown resource %q"):format(tostring(term.power)))
    end
    if CMP[term.cmp] == nil then
      table.insert(errs, ("unknown comparison %q"):format(tostring(term.cmp)))
    end
    if type(term.value) ~= "number" then
      table.insert(errs, "a resource threshold needs a number")
    end
    if term.projected and not PROJECTABLE[term.power] then
      table.insert(errs, ("%s cannot be read past the current cast -- what a cast returns "
        .. "depends on talents and procs for every resource but soul_shards, so there is no "
        .. "one number to project with"):format(term.power))
    end
  elseif SPELL_TERM[term.t] then
    if type(term.spell) ~= "number" then
      table.insert(errs, term.t .. "() needs a spell id")
    end
  elseif term.t == "charges" then
    table.insert(errs, "a charge COUNT is neither readable nor sealed; use ready() instead")
  elseif SEALED_FAMILY[term.t] then
    table.insert(errs, ("%s is a sealed term and belongs in `bind`, not in `when`"):format(term.t))
  else
    table.insert(errs, ("unknown term %q"):format(term.t))
  end
end

--- Is `not ready(<spell>)` in the readable half? Only a conjunction counts -- a disjunct
--- leaves a path where the guard is false and the bind still drives the widget.
local function GuardsReady(node, spell)
  if type(node) ~= "table" then return false end
  if node.t == "and" then
    for _, sub in ipairs(node.terms or {}) do
      if GuardsReady(sub, spell) then return true end
    end
    return false
  end
  if node.t == "not" then
    local inner = node.term
    return type(inner) == "table" and inner.t == "ready" and inner.spell == spell
  end
  return false
end

local function CheckBind(bind, when, errs)
  if type(bind) ~= "table" then
    table.insert(errs, "a bind must be a table")
    return
  end
  if bind.family == "count" then
    if type(bind.aura) ~= "number" then
      table.insert(errs, "a count bind needs a numeric aura id")
    end
    if type(bind.threshold) ~= "number" then
      table.insert(errs, "a count bind needs a numeric threshold")
    end
  elseif bind.family == "duration" then
    if type(bind.spell) ~= "number" then
      table.insert(errs, "a duration bind needs a spell id")
    end
    if bind.cmp == "outside" then
      if type(bind.lo) ~= "number" or type(bind.hi) ~= "number" or bind.hi <= bind.lo then
        table.insert(errs, "`outside` needs two rising bounds")
      end
    elseif CMP[bind.cmp] == nil or bind.cmp == "==" then
      table.insert(errs, ("unknown duration comparison %q"):format(tostring(bind.cmp)))
    elseif type(bind.seconds) ~= "number" then
      table.insert(errs, "a duration bind needs a number of seconds")
    end
    if UNBOUNDED_BELOW[bind.cmp] and bind.absent == nil
        and not GuardsReady(when, bind.spell) then
      table.insert(errs, ("`%s` on a cooldown is also true when the spell is READY, so this "
        .. "would glow permanently while it is up. Add `not ready(...)` to `when`, or set "
        .. "`absent` to \"dark\" or \"show\" on the bind"):format(tostring(bind.cmp)))
    end
  elseif bind.family == "presence" then
    if type(bind.aura) ~= "number" then
      table.insert(errs, "a presence bind needs a numeric aura id")
    end
    if bind.unit ~= "player" and bind.unit ~= "target" then
      table.insert(errs, ("unknown unit %q; a presence bind reads `player` or `target`")
        :format(tostring(bind.unit)))
    end
    -- `AuraUtil.IsValidFilterString` ASSERTS, so a component the client does not know is a
    -- hard error inside `AddAuraSlot` rather than an empty result. Refuse it here instead.
    for component in string.gmatch(tostring(bind.filter), "[^|]+") do
      if not FILTER_COMPONENT[component] then
        table.insert(errs, ("unknown aura filter %q"):format(component))
      end
    end
  elseif bind.family == "health" then
    if CMP[bind.cmp] == nil or bind.cmp == "==" then
      table.insert(errs, ("unknown health comparison %q"):format(tostring(bind.cmp)))
    elseif type(bind.percent) ~= "number" or bind.percent <= 0 or bind.percent >= 100 then
      table.insert(errs, "a health bind needs a percent strictly between 0 and 100")
    end
  elseif READABLE_TERM[bind.family] then
    table.insert(errs, ("%s is readable and belongs in `when`, not in `bind`"):format(bind.family))
  else
    table.insert(errs, ("unknown bind family %q"):format(tostring(bind.family)))
  end
end

--- Returns nil plus the refusal list when the rule could author cleanly and never fire.
function Rules.CheckGlow(glow)
  local errs = {}
  if type(glow) ~= "table" then
    return nil, { "a glow must be a table" }
  end
  if type(glow.subject) ~= "number" then
    table.insert(errs, "a glow needs a numeric subject spell id")
  end
  if glow.when ~= nil then
    Check(glow.when, errs, 0)
  end
  if glow.bind ~= nil then
    CheckBind(glow.bind, glow.when, errs)
  end
  if glow.color ~= nil and not ns.Look.IsColor(glow.color) then
    table.insert(errs, ("unknown colour %q; known: %s"):format(tostring(glow.color),
      table.concat(ns.Look.Names(), ", ")))
  end
  if glow.when == nil and glow.bind == nil then
    table.insert(errs, "a glow needs a `when` expression, a `bind`, or both")
  end
  if #errs > 0 then return nil, errs end
  return glow
end

-- ------------------------------------------------------------- the evaluation

local function Worst(a, b)
  if a == ns.F or b == ns.F then return ns.F end
  if a == ns.UNKNOWN or b == ns.UNKNOWN then return ns.UNKNOWN end
  return ns.T
end

--- `unknown or S` drives from S; `unknown and S` is dark. Never let a negated unknown pass.
local function Best(a, b)
  if a == ns.T or b == ns.T then return ns.T end
  if a == ns.UNKNOWN or b == ns.UNKNOWN then return ns.UNKNOWN end
  return ns.F
end

--- The name a rule would WRITE for a spell, and the id when nothing names it. This feeds
--- `Describe` and `DescribeBind`, whose output has to parse back, so it may only ever return
--- a rule symbol or a bare id -- never a display name, which carries spaces and punctuation
--- the grammar cannot read. `Rules.Pretty` is the one to use for anything a person reads.
function Rules.Label(spellID)
  return ns.Names.Of(spellID) or tostring(spellID)
end

--- The same thing for a HUMAN: the rule symbol when there is one, else the client's own name
--- for the id, else the bare number. `Symbols.lua` carries the KB's ability inventory, so an
--- aura or override id is in no inventory and used to print as a raw number in `/sg why`.
--- The client is Tier 1 for id -> name and knows every id, which is what closes that gap.
--- ⚠ Never route parseable output through this.
function Rules.Pretty(spellID)
  local symbol = ns.Names.Of(spellID)
  if symbol ~= nil then return symbol end
  if C_Spell ~= nil and C_Spell.GetSpellName ~= nil then
    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    if ok and type(name) == "string" and name ~= "" then
      return ("%s (%d)"):format(name, spellID)
    end
  end
  return tostring(spellID)
end

local Eval

--- The number the threshold is compared against, in DISPLAY units, or `nil, why`.
---
--- Plain: whatever the bar shows. Projected: the same count with the in-flight cast's cost
--- and gain applied, which has to be done in RAW units -- ten raw per Soul Shard -- and then
--- floored the way the bar floors it, or the fragments left over from a partial shard would
--- read as a whole one. `UnitPowerDisplayMod` supplies the scale so nothing here ships it.
local function Current(term, pt)
  if not term.projected then
    local ok, value = pcall(UnitPower, "player", pt)
    if not ok then return nil, "refused (" .. tostring(value) .. ")" end
    if ns.IsSecret(value) or type(value) ~= "number" then return nil, "not a readable number" end
    return value
  end

  local delta, why = ns.Cast.Delta(pt)
  if delta == nil then return nil, why end

  local ok, raw = pcall(UnitPower, "player", pt, true)
  if not ok then return nil, "refused (" .. tostring(raw) .. ")" end
  if ns.IsSecret(raw) or type(raw) ~= "number" then return nil, "not a readable number" end

  local okMod, mod = pcall(UnitPowerDisplayMod, pt)
  if not okMod or ns.IsSecret(mod) or type(mod) ~= "number" or mod <= 0 then
    return nil, "no display scale"
  end
  return math.floor((raw + delta) / mod)
end

local function EvalResource(term, trace)
  local label = term.power .. (term.projected and ".after_cast" or "")
  local pt = Rules.PowerType(term.power)
  if pt == nil then
    trace[#trace + 1] = { text = label .. ": unknown resource", verdict = ns.UNKNOWN }
    return ns.UNKNOWN
  end
  local value, why = Current(term, pt)
  if value == nil then
    trace[#trace + 1] = { text = label .. ": " .. tostring(why), verdict = ns.UNKNOWN }
    return ns.UNKNOWN
  end
  local verdict = ns.F
  if CMP[term.cmp](value, term.value) then verdict = ns.T end
  local text = ("%s %s %d (is %d)"):format(label, term.cmp, term.value, value)
  if term.projected then
    local inflight = ns.Cast.InFlight()
    text = text .. (inflight and (" past " .. Rules.Label(inflight)) or ", nothing casting")
  end
  trace[#trace + 1] = { text = text, verdict = verdict }
  return verdict
end

--- A spell the player does not have has no cooldown running, so `GetSpellCooldown` answers
--- READY for it as confidently as for one off cooldown, and a rule naming a talent from
--- another build reads T forever.
---
--- `IsSpellKnown` asks about the PLAYER. Its neighbour `IsSpellInSpellBook` asks about the
--- BOOK and returns true for spells that are not known, including override spells granted by
--- a talent aura -- so a base ability a talent replaces answers true through its replacement.
local function Known(spell)
  if C_SpellBook == nil or C_SpellBook.IsSpellKnown == nil
    or Enum == nil or Enum.SpellBookSpellBank == nil then
    return nil
  end
  local ok, known = pcall(C_SpellBook.IsSpellKnown, spell, Enum.SpellBookSpellBank.Player)
  if not ok or type(known) ~= "boolean" then return nil end
  return known
end

local function EvalReady(term, trace)
  if Known(term.spell) == false then
    trace[#trace + 1] = { text = "ready(" .. Rules.Pretty(term.spell)
      .. "): you do not know this spell", verdict = ns.UNKNOWN }
    return ns.UNKNOWN
  end
  local ok, info = pcall(C_Spell.GetSpellCooldown, term.spell)
  if not ok or type(info) ~= "table" then
    trace[#trace + 1] = { text = "ready(" .. term.spell .. "): no cooldown info", verdict = ns.UNKNOWN }
    return ns.UNKNOWN
  end
  local active, enabled = info.isActive, info.isEnabled
  if ns.IsSecret(active) or type(active) ~= "boolean" then
    trace[#trace + 1] = { text = "ready(" .. term.spell .. "): isActive not readable", verdict = ns.UNKNOWN }
    return ns.UNKNOWN
  end
  local verdict = ns.F
  if not active and enabled ~= false then verdict = ns.T end
  trace[#trace + 1] = { text = "ready(" .. Rules.Pretty(term.spell) .. ")", verdict = verdict }
  return verdict
end

--- Charge STATE off the Cooldown Manager's own verdict, without reading a charge count.
---
--- `CheckCacheCooldownValuesFromCharges` sets `wasSetFromCharges` iff a recharge is running
--- AND at least one charge is banked, and Blizzard's comment says why: charge values take
--- precedence over the spell's own cooldown "until the charges are spent", after which
--- `wasSetFromCooldown` drives instead. So the two flags separate all three states, and the
--- secret `currentCharges` never has to be read -- Blizzard branches on it in untainted code
--- and assigns a literal, so the seal does not travel.
---
--- ⚠ `wasSetFromAura` is deliberately not consulted: an aura may drive the dial while the
--- spell sits at full charges, so requiring the dial to be hidden would read a capped spell
--- as uncapped. The two flags below are the whole question.
--- ⚠ On a spell with ONE charge these degenerate to off-cooldown / on-cooldown, which is
--- honest rather than wrong, and `ready()` says the same thing more plainly.
local function ReadFlag(item, field)
  local ok, value = pcall(function() return item[field] end)
  if not ok then return nil, ("%s refused"):format(field) end
  if ns.IsSecret(value) then return nil, ("%s is secret"):format(field) end
  if value == nil then return nil end
  if type(value) ~= "boolean" then return nil, ("%s is not a boolean"):format(field) end
  return value
end

local function EvalCharges(term, trace, wantMax)
  local label = ("%s(%s)"):format(term.t, Rules.Pretty(term.spell))
  local item = ns.Attach.ItemFor(term.spell)
  if item == nil then
    trace[#trace + 1] = { text = label .. ": no Cooldown Manager row is laid out for it",
      verdict = ns.UNKNOWN }
    return ns.UNKNOWN
  end
  local charges, chargesWhy = ReadFlag(item, "wasSetFromCharges")
  local cooldown, cooldownWhy = ReadFlag(item, "wasSetFromCooldown")
  local why = chargesWhy or cooldownWhy
  if why ~= nil then
    trace[#trace + 1] = { text = label .. ": " .. why, verdict = ns.UNKNOWN }
    return ns.UNKNOWN
  end
  -- Both nil is a row that has not refreshed since its sources were cleared, which is not
  -- the same as both false and must not be reported as "at max".
  if charges == nil and cooldown == nil then
    trace[#trace + 1] = { text = label .. ": the row has set no visual data source yet",
      verdict = ns.UNKNOWN }
    return ns.UNKNOWN
  end
  charges, cooldown = charges == true, cooldown == true
  local verdict
  if wantMax then
    verdict = (not charges and not cooldown) and ns.T or ns.F
  else
    verdict = (cooldown and not charges) and ns.T or ns.F
  end
  trace[#trace + 1] = { text = label, verdict = verdict }
  return verdict
end

--- Aura presence rides the CDM's own alert edges: a row nobody bound raises none, and that
--- is UNKNOWN rather than absent (cooldown-manager.md §5.1).
local function EvalAura(term, trace)
  local verdict = ns.Attach.AuraLatch(term.spell)
  local label = "aura(" .. Rules.Pretty(term.spell) .. ")"
  if verdict == ns.UNKNOWN then
    label = label .. ": no Cooldown Manager row is bound to it"
  end
  trace[#trace + 1] = { text = label, verdict = verdict }
  return verdict
end

-- ------------------------------------------------------------------ talent()
--
-- A talent is a static load condition, so it is an ordinary readable gate -- but it is read
-- off the TRAIT CONFIG, never off the spell book. `C_SpellBook.IsSpellKnown` answers about a
-- spell rather than about a node: it stands in for the talent instead of being it, and a
-- proxy that diverges does so silently. The rule keys off what the APL keys off.

--- Is one node purchased, and is the declared entry the selected one?
---
--- Three values, and the third is the point. `true` = purchased AND the entry matches.
--- `false` = genuinely not taken. `nil` = the read refused or answered in a shape we do not
--- recognise, which is NOT "not taken" -- and under a `not` a wrong `false` reads as a
--- confident true, which is the failure this whole shape exists to prevent.
local function NodeSelected(info, entryID)
  if type(info) ~= "table" then return nil end
  local ranks = info.ranksPurchased
  if ns.IsSecret(ranks) or type(ranks) ~= "number" then return nil end
  if ranks <= 0 then return false end
  -- Entry 0 means the generated table could not say which half of a choice node this is, so
  -- ranks alone decide rather than an entry check that would compare against nothing.
  if entryID == 0 then return true end
  local active = info.activeEntry
  if type(active) ~= "table" then return nil end
  local id = active.entryID
  if ns.IsSecret(id) or type(id) ~= "number" then return nil end
  return id == entryID
end

--- A talent cannot change during a fight and a spec cannot either, so a value read before
--- the pull stays true through it: every moment the answer can CHANGE is a moment we are out
--- of combat, and each of those is a prime point. In combat the cache is served.
--- The one way in is a `/reload` mid-pull, which starts the addon with nothing primed. That
--- costs the rest of that pull -- the gate reads UNKNOWN and the glow stays dark -- and
--- leaving combat repairs it.
local talentCache, talentConfig = {}, nil

local function ActiveConfig()
  if type(C_ClassTalents) ~= "table" or type(C_ClassTalents.GetActiveConfigID) ~= "function"
      or type(C_Traits) ~= "table" or type(C_Traits.GetNodeInfo) ~= "function" then
    return nil
  end
  local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
  if not ok or type(configID) ~= "number" then return nil end
  return configID
end

--- ⚠ `C_Traits.GetNodeInfo` is UNMEASURED -- `knowledge/addon-dev/` records neither its shape
--- nor whether `ranksPurchased` / `activeEntry` survive combat restriction. Nothing here
--- asserts that they do: every read is pcall'ed and every unrecognised answer becomes UNKNOWN,
--- so an unmeasured read that refuses costs a glow and can never invent one.
---
--- A spell may name a different node in another spec, so the table carries every candidate.
--- The node that is not in the player's own tree refuses, which is the client arbitrating
--- rather than the table guessing.
local function ReadTalent(spellID)
  local configID = ActiveConfig()
  if configID == nil then return nil, "the trait config is unreadable" end
  if talentConfig ~= configID then
    talentCache, talentConfig = {}, configID
  end
  local hit = talentCache[spellID]
  if hit ~= nil then return hit.value, hit.why end
  -- A miss in combat is the priming having failed, not a value that moved. Read anyway --
  -- it can only improve on UNKNOWN -- but do not CACHE a combat answer, so the next
  -- out-of-combat prime is what fills the slot.
  local cache = not InCombatLockdown()

  local pairs_ = ns.Symbols.talentNodes[spellID]
  if pairs_ == nil then
    talentCache[spellID] = { why = "no talent node grants it" }
    return nil, "no talent node grants it"
  end
  for i = 1, #pairs_, 2 do
    local ok, info = pcall(C_Traits.GetNodeInfo, configID, pairs_[i])
    if ok then
      local selected = NodeSelected(info, pairs_[i + 1])
      if selected ~= nil then
        if cache then talentCache[spellID] = { value = selected } end
        return selected
      end
    end
  end
  local why = cache and "no candidate node answered"
    or "not read before combat, and a talent is not re-read during one"
  if cache then talentCache[spellID] = { why = why } end
  return nil, why
end

local function EvalTalent(term, trace)
  local selected, why = ReadTalent(term.spell)
  if selected == nil then
    trace[#trace + 1] = { verdict = ns.UNKNOWN,
      text = ("talent(%s): %s"):format(Rules.Pretty(term.spell), why) }
    return ns.UNKNOWN
  end
  local verdict = selected and ns.T or ns.F
  trace[#trace + 1] = {
    text = ("talent(%s) by the trait config"):format(Rules.Pretty(term.spell)),
    verdict = verdict,
  }
  return verdict
end

--- Read every talent the applied rules name, now, while we are certainly out of combat.
--- Called on each of the three edges below and once the store has loaded.
function Rules.PrimeTalents()
  talentCache, talentConfig = {}, nil
  if ns.Store == nil then return end
  for _, glow in ipairs(ns.Store.All()) do
    local stack = { glow.when }
    while #stack > 0 do
      local term = table.remove(stack)
      if type(term) == "table" then
        if term.t == "talent" then ReadTalent(term.spell) end
        for _, sub in ipairs(term.terms or {}) do stack[#stack + 1] = sub end
        if term.term ~= nil then stack[#stack + 1] = term.term end
      end
    end
  end
end

--- ⚠ Frame dispatch order for one event is observably variable, so priming cannot rely on
--- running before the attach path's own handler for the same event. It announces itself
--- instead: a verdict that was UNKNOWN through the fight becomes readable the moment the
--- prime lands, and nothing else would have asked again.
function Rules.PrimedEvaluate()
  Rules.PrimeTalents()
  if ns.Attach ~= nil then ns.Attach.Evaluate() end
end

--- The three edges where the answer can move, and all three are out of combat by definition:
--- a config commit and a spec swap are both barred during a fight, and leaving one is the
--- unambiguous moment to repair a prime that could not happen at login.
local traitWatch = CreateFrame("Frame")
traitWatch:RegisterEvent("TRAIT_CONFIG_UPDATED")
traitWatch:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
traitWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
traitWatch:SetScript("OnEvent", Rules.PrimedEvaluate)

function Eval(term, trace)
  if term.t == "and" then
    local acc = ns.T
    for _, sub in ipairs(term.terms) do acc = Worst(acc, Eval(sub, trace)) end
    return acc
  elseif term.t == "or" then
    local acc = ns.F
    for _, sub in ipairs(term.terms) do acc = Best(acc, Eval(sub, trace)) end
    return acc
  elseif term.t == "not" then
    local inner = Eval(term.term, trace)
    if inner == ns.T then return ns.F end
    if inner == ns.F then return ns.T end
    return ns.UNKNOWN
  elseif term.t == "resource" then
    return EvalResource(term, trace)
  elseif term.t == "ready" then
    return EvalReady(term, trace)
  elseif term.t == "aura" then
    return EvalAura(term, trace)
  elseif term.t == "at_max_charges" then
    return EvalCharges(term, trace, true)
  elseif term.t == "no_charges" then
    return EvalCharges(term, trace, false)
  elseif term.t == "talent" then
    return EvalTalent(term, trace)
  end
  trace[#trace + 1] = { text = "unknown term " .. tostring(term.t), verdict = ns.UNKNOWN }
  return ns.UNKNOWN
end

--- Evaluates every term: no short-circuit, because `/sg why` needs all of them.
--- The expression a glow is actually evaluated on: its `when`, plus -- for a count -- an
--- implicit presence term on the aura the occluder rides.
---
--- A count's band 0 DRAWS, so the client hiding the button takes the occluder away and the
--- mark reads as though the threshold were met (rule-language.md 6.4). Absence is the one
--- case the sealed half gets wrong in the bright direction, and the readable half is where it
--- can be caught: this term reads F when the aura is gone and UNKNOWN when nothing can say,
--- and either one closes the element's alpha over the occluder and the mark together.
---
--- It is built here rather than folded into `when` at decode so the authored rule stays the
--- rule -- `/sg export` and the checker still see what the author wrote, and the term shows up
--- in `/sg why` as the extra row it is.
function Rules.Gate(glow)
  if glow == nil then return nil end
  local bind = glow.bind
  if type(bind) ~= "table" or bind.family ~= "count" or type(bind.aura) ~= "number" then
    return glow.when
  end
  local present = { t = "aura", spell = bind.aura }
  if glow.when == nil then return present end
  return { t = "and", terms = { glow.when, present } }
end

function Rules.Evaluate(expr)
  local trace = {}
  if expr == nil then return ns.T, trace end
  return Eval(expr, trace), trace
end

--- The events that can change a term's answer; a glow's trigger set is the union.
local TRIGGERS = {
  resource = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" },
  ready = { "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "SPELL_UPDATE_CHARGES" },
  aura = {},
  at_max_charges = { "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES" },
  no_charges = { "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES" },
  -- ⚠ NOT the events that make a talent readable -- those are handled by the prime above,
  -- out of combat. These are here so a glow carrying a talent term still re-evaluates when
  -- the trigger union is what drives the attach path.
  talent = { "TRAIT_CONFIG_UPDATED", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_REGEN_ENABLED" },
}

function Rules.Triggers(expr, into)
  into = into or {}
  if type(expr) ~= "table" then return into end
  if expr.t == "and" or expr.t == "or" then
    for _, sub in ipairs(expr.terms) do Rules.Triggers(sub, into) end
  elseif expr.t == "not" then
    Rules.Triggers(expr.term, into)
  else
    for _, event in ipairs(TRIGGERS[expr.t] or {}) do into[event] = true end
    -- A projected threshold also moves when a cast opens or ends, and no power event
    -- announces that: the bar has not changed yet, which is the whole point.
    if expr.t == "resource" and expr.projected then
      for _, event in ipairs(ns.Cast.EVENTS) do into[event] = true end
    end
  end
  return into
end

local function Describe(expr)
  if type(expr) ~= "table" then return "?" end
  if expr.t == "and" or expr.t == "or" then
    local parts = {}
    for _, sub in ipairs(expr.terms) do parts[#parts + 1] = Describe(sub) end
    return "(" .. table.concat(parts, " " .. expr.t .. " ") .. ")"
  elseif expr.t == "not" then
    return "not " .. Describe(expr.term)
  elseif expr.t == "resource" then
    return ("%s%s %s %s"):format(expr.power, expr.projected and ".after_cast" or "",
      expr.cmp, tostring(expr.value))
  elseif SPELL_TERM[expr.t] then
    return expr.t .. "(" .. Rules.Label(expr.spell) .. ")"
  end
  return tostring(expr.t)
end

Rules.Describe = Describe

function Rules.DescribeBind(bind)
  if type(bind) ~= "table" then return "?" end
  if bind.family == "count" then
    return ("%s.stacks >= %s"):format(Rules.Label(bind.aura), tostring(bind.threshold))
  end
  if bind.family == "health" then
    return ("health%% %s %s"):format(bind.cmp, bind.percent)
  end
  if bind.family == "presence" then
    local body = ("%s.up"):format(Rules.Label(bind.aura))
    if bind.unit ~= "player" then body = body .. " on " .. bind.unit end
    if string.find(bind.filter, "PLAYER", 1, true) then body = body .. " mine" end
    return body
  end
  if bind.family == "duration" then
    local body
    if bind.cmp == "outside" then
      body = ("%s.cooldown outside %ss..%ss"):format(Rules.Label(bind.spell), bind.lo, bind.hi)
    else
      body = ("%s.cooldown %s %ss"):format(Rules.Label(bind.spell), bind.cmp, bind.seconds)
    end
    if bind.absent then body = body .. " absent " .. bind.absent end
    return body
  end
  return tostring(bind.family)
end
