-- Spell names in a rule: `summon_demonic_tyrant` -> 265187, and the check against the client.
--
-- `Symbols.lua` is GENERATED from the KB's ability inventory. This file owns what the addon
-- does with it: resolve a name inside a spec scope, refuse an ambiguous one rather than guess,
-- and verify the table against the only authority for id -> name there is, the running client.

local _, ns = ...

local Names = {}
ns.Names = Names

--- Built on first use and kept: 40 specs x ~170 names is a table nobody wants at load time,
--- and in practice a session touches one spec.
local index = { ability = {}, aura = {} }

--- Two namespaces, and the TERM picks which. `on` / `ready()` want something the spec can
--- learn; `aura()` wants something the Cooldown Manager can track. A name in both worlds --
--- consecration, shield_of_the_righteous -- is a different spell in each, so resolving an
--- aura against the ability table is not a near miss, it is a wrong answer that parses.
local TABLES = {
  ability = { specs = "specs", names = "names" },
  aura = { specs = "auraSpecs", names = "auraNames" },
}

local function IndexFor(key, kind)
  local where = TABLES[kind] or TABLES.ability
  local cache = index[kind] or index.ability
  local built = cache[key]
  if built ~= nil then return built end
  local ids = ns.Symbols[where.specs][key]
  if ids == nil then return nil end
  built = {}
  for _, id in ipairs(ids) do
    local name = ns.Symbols[where.names][id]
    if name ~= nil then built[name] = id end
  end
  cache[key] = built
  return built
end

--- Why a bare name is not in the aura table: it may name two tracked rows rather than none,
--- and then the ids are what the author has to choose between.
local function AuraRefusal(key, bare)
  local by_spec = ns.Symbols.auraAmbiguous and ns.Symbols.auraAmbiguous[key]
  local ids = by_spec and by_spec[bare]
  if ids == nil then
    return ("%s tracks no aura called %q -- an aura() term reads through a Cooldown Manager "
      .. "row, so a buff with no tracked row cannot be named here"):format(key, bare)
  end
  local parts = {}
  for _, id in ipairs(ids) do parts[#parts + 1] = tostring(id) end
  return ("%q names %d tracked rows in %s (%s); write the id you mean"):format(
    bare, #ids, key, table.concat(parts, ", "))
end

--- A scope word: `demonology`, or `warlock.demonology` when the bare word names two specs.
--- Returns nil plus the refusal, never a guess.
function Names.Scope(word)
  word = string.lower(word or "")
  if word == "" then return nil, "a spec name is required" end
  if ns.Symbols.specs[word] ~= nil then return word end
  local key = ns.Symbols.specAlias[word]
  if key ~= nil then return key end
  if string.find(word, ".", 1, true) then
    return nil, ("no spec %q"):format(word)
  end
  -- Absent from specAlias and not a full key: either it is not a spec at all, or it names
  -- more than one and the generator deliberately left it out.
  local matches = {}
  for full in pairs(ns.Symbols.specs) do
    if string.sub(full, -#word - 1) == "." .. word then matches[#matches + 1] = full end
  end
  if #matches > 1 then
    table.sort(matches)
    return nil, ("%q names %d specs; write one of %s"):format(word, #matches,
      table.concat(matches, ", "))
  end
  return nil, ("no spec %q"):format(word)
end

--- A spell reference: a raw id, `class.spec.name`, or a bare name inside `scope`.
--- The refusal names what would have made it resolvable; it never falls back to a guess.
--- `kind` is "ability" (the default) or "aura". A raw id passes through either way: the
--- table is how a NAME is found, never a gate on what a rule may name.
function Names.Resolve(text, scope, kind)
  kind = kind or "ability"
  text = string.lower(text or "")
  local number = tonumber(text)
  if number ~= nil then
    if number ~= math.floor(number) or number <= 0 then
      return nil, ("%q is not a spell id"):format(text)
    end
    return number
  end
  if text == "" then return nil, "a spell name or id is required" end

  local class, spec, bare = string.match(text, "^([%a_]+)%.([%a_]+)%.([%a%d_]+)$")
  if class ~= nil then
    local key, why = Names.Scope(class .. "." .. spec)
    if key == nil then return nil, why end
    local by_name = IndexFor(key, kind)
    local id = by_name and by_name[bare]
    if id == nil then
      if kind == "aura" then return nil, AuraRefusal(key, bare) end
      return nil, ("%s has no %q"):format(key, bare)
    end
    return id
  end

  if string.find(text, ".", 1, true) then
    return nil, ("%q is not a name; write <class>.<spec>.<name>, a bare name, or an id"):format(text)
  end
  if scope == nil then
    return nil, ("%q needs a scope -- put `spec demonology` above the rules, or write "
      .. "warlock.demonology.%s, or a raw spell id"):format(text, text)
  end
  local by_name = IndexFor(scope, kind)
  local id = by_name and by_name[text]
  if id == nil then
    if kind == "aura" then return nil, AuraRefusal(scope, text) end
    return nil, ("%s has no %q"):format(scope, text)
  end
  return id
end

--- The name to print for an id. Nil for one the inventory does not carry -- an override id
--- or a raw number a rule spelled out -- and the caller prints the number instead.
function Names.Of(spellID)
  return ns.Symbols.names[spellID]
end

--- The spec whose inventory carries an id, or nil. An id in several specs answers the first
--- by sort order, which is all a `spec` header needs: it only decides which names print bare.
local owner
function Names.SpecOf(spellID)
  if spellID == nil then return nil end
  if owner == nil then
    local keys = {}
    for key in pairs(ns.Symbols.specs) do keys[#keys + 1] = key end
    table.sort(keys)
    owner = {}
    for _, key in ipairs(keys) do
      for _, id in ipairs(ns.Symbols.specs[key]) do
        if owner[id] == nil then owner[id] = key end
      end
    end
  end
  return owner[spellID]
end

--- How a rule should WRITE an id: bare inside `scope`, qualified when it belongs to another
--- spec, and the raw number when the inventory does not name it at all.
function Names.Write(spellID, scope)
  local name = ns.Symbols.names[spellID]
  if name == nil then return tostring(spellID) end
  local key = Names.SpecOf(spellID)
  if key == nil then return tostring(spellID) end
  if key == scope then return name end
  return key .. "." .. name
end

-- ------------------------------------------------------------------- the check

--- The client is Tier 1 for id -> name. Every mismatch here is a patch rename or a KB drift,
--- and catching it costs no flight -- only a login.
---
--- Spread over frames rather than swept in one: ~4000 `GetSpellName` calls in a single frame
--- is a visible hitch at exactly the moment the player is loading in.
local CHUNK = 250

local function Slug(name)
  if type(name) ~= "string" then return nil end
  name = string.lower(name)
  name = string.gsub(name, "'", "")
  name = string.gsub(name, "[^a-z0-9]+", "_")
  return (string.gsub(name, "^_*(.-)_*$", "%1"))
end

local function Matches(id, want)
  local ok, name = pcall(C_Spell.GetSpellName, id)
  if not ok or type(name) ~= "string" then return nil end   -- nil = the client has no name
  local got = Slug(name)
  if got == want then return true end
  if got == ns.Symbols.alsoNamed[id] then return true end
  return false, got
end

--- `report` nil runs silently and prints only on a mismatch; true always prints a summary.
function Names.Check(report)
  local ids = {}
  for id in pairs(ns.Symbols.names) do ids[#ids + 1] = id end
  table.sort(ids)

  local at, ok, unknown, wrong = 1, 0, 0, {}
  local ticker
  ticker = C_Timer.NewTicker(0, function()
    local stop = math.min(at + CHUNK - 1, #ids)
    for i = at, stop do
      local id = ids[i]
      local matched, got = Matches(id, ns.Symbols.names[id])
      if matched == nil then
        unknown = unknown + 1
      elseif matched then
        ok = ok + 1
      elseif #wrong < 20 then
        wrong[#wrong + 1] = ("%d: KB says %s, the client says %s"):format(
          id, ns.Symbols.names[id], got)
      else
        wrong.more = (wrong.more or 0) + 1
      end
    end
    at = stop + 1
    if at > #ids then
      ticker:Cancel()
      if #wrong == 0 and not report then return end
      ns.Printf("symbols: %d of %d spells match the client, %d unknown to it, %d disagree "
        .. "|cff999999(%s)|r", ok, #ids, unknown, #wrong + (wrong.more or 0), ns.Symbols.source)
      for _, line in ipairs(wrong) do ns.Print("  " .. line) end
      if wrong.more then ns.Printf("  ... and %d more", wrong.more) end
      if #wrong > 0 then
        ns.Print("  a disagreement is a patch rename or KB drift -- regenerate with "
          .. "`wowkb.gen_smartglo_symbols`.")
      end
    end
  end)
end

ns.RegisterCommand{
  name = "symbols",
  args = "[spec]",
  desc = "check the generated spell-name table against the client",
  handler = function(rest)
    local word = string.match(rest or "", "^(%S*)")
    if word ~= "" then
      local key, why = Names.Scope(word)
      if key == nil then
        ns.Print(why)
        return
      end
      local names = IndexFor(key)
      local n = 0
      for _ in pairs(names) do n = n + 1 end
      ns.Printf("%s: %d names. Bare names in a rule resolve here under `spec %s`.",
        key, n, word)
      return
    end
    ns.Printf("%d spells across %d specs, from %s. Checking against the client...",
      ns.Symbols.count, ns.Symbols.specCount, ns.Symbols.source)
    Names.Check(true)
  end,
}
