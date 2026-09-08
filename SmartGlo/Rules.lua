-- The rule AST: the term catalogue, the checker's refusals, and three-valued evaluation.

local _, ns = ...

local Rules = {}
ns.Rules = Rules

--- Secondary resources are never secret, so a threshold on one is a gate at any value.
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

local CMP = {
  [">="] = function(a, b) return a >= b end,
  [">"] = function(a, b) return a > b end,
  ["<="] = function(a, b) return a <= b end,
  ["<"] = function(a, b) return a < b end,
  ["=="] = function(a, b) return a == b end,
}

Rules.SECONDARY = SECONDARY
Rules.PRIMARY = PRIMARY

function Rules.PowerType(name)
  local key = SECONDARY[name]
  if key == nil then return nil end
  if type(Enum) ~= "table" or type(Enum.PowerType) ~= "table" then return nil end
  return Enum.PowerType[key]
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
      table.insert(errs, ("%s is a primary resource and can never be a gate"):format(term.power))
    elseif SECONDARY[term.power] == nil then
      table.insert(errs, ("unknown resource %q"):format(tostring(term.power)))
    end
    if CMP[term.cmp] == nil then
      table.insert(errs, ("unknown comparison %q"):format(tostring(term.cmp)))
    end
    if type(term.value) ~= "number" then
      table.insert(errs, "a resource threshold needs a number")
    end
  elseif term.t == "ready" then
    if type(term.spell) ~= "number" then
      table.insert(errs, "ready() needs a spell id")
    end
  elseif term.t == "aura" then
    if type(term.spell) ~= "number" then
      table.insert(errs, "aura() needs a spell id")
    end
  elseif term.t == "charges" then
    table.insert(errs, "a charge COUNT is neither a gate nor a binding; use ready() instead")
  elseif term.t == "count" then
    table.insert(errs, "a count is a sealed binding and cannot appear inside an expression")
  else
    table.insert(errs, ("unknown term %q"):format(term.t))
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
  if glow.show ~= nil then
    Check(glow.show, errs, 0)
  end
  if glow.count ~= nil then
    if type(glow.count.aura) ~= "number" then
      table.insert(errs, "a count element needs a numeric aura id")
    end
    if type(glow.count.threshold) ~= "number" then
      table.insert(errs, "a count element needs a numeric threshold")
    end
  end
  if glow.show == nil and glow.count == nil then
    table.insert(errs, "a glow needs a `show` expression, a `count` element, or both")
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

local Eval

local function EvalResource(term, trace)
  local pt = Rules.PowerType(term.power)
  if pt == nil then
    trace[#trace + 1] = { text = term.power .. ": unknown resource", verdict = ns.UNKNOWN }
    return ns.UNKNOWN
  end
  local ok, value = pcall(UnitPower, "player", pt)
  if not ok then
    trace[#trace + 1] = { text = term.power .. ": refused (" .. tostring(value) .. ")", verdict = ns.UNKNOWN }
    return ns.UNKNOWN
  end
  if ns.IsSecret(value) or type(value) ~= "number" then
    trace[#trace + 1] = { text = term.power .. ": not a readable number", verdict = ns.UNKNOWN }
    return ns.UNKNOWN
  end
  local verdict = ns.F
  if CMP[term.cmp](value, term.value) then verdict = ns.T end
  trace[#trace + 1] = {
    text = ("%s %s %d (is %d)"):format(term.power, term.cmp, term.value, value),
    verdict = verdict,
  }
  return verdict
end

local function EvalReady(term, trace)
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
  trace[#trace + 1] = { text = "ready(" .. term.spell .. ")", verdict = verdict }
  return verdict
end

--- Aura presence rides the CDM's own alert edges: a row nobody bound raises none, and that
--- is UNKNOWN rather than absent (cooldown-manager.md §5.1).
local function EvalAura(term, trace)
  local verdict = ns.Attach.AuraLatch(term.spell)
  local label = "aura(" .. term.spell .. ")"
  if verdict == ns.UNKNOWN then
    label = label .. ": no Cooldown Manager row is bound to it"
  end
  trace[#trace + 1] = { text = label, verdict = verdict }
  return verdict
end

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
  end
  trace[#trace + 1] = { text = "unknown term " .. tostring(term.t), verdict = ns.UNKNOWN }
  return ns.UNKNOWN
end

--- Evaluates every term: no short-circuit, because `/sg why` needs all of them.
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
    return ("%s %s %s"):format(expr.power, expr.cmp, tostring(expr.value))
  elseif expr.t == "ready" then
    return "ready(" .. tostring(expr.spell) .. ")"
  elseif expr.t == "aura" then
    return "aura(" .. tostring(expr.spell) .. ")"
  end
  return tostring(expr.t)
end

Rules.Describe = Describe
