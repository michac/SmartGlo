-- Where applied rules live between sessions, and the one door every consumer reads them by.

local _, ns = ...

local Store = {}
ns.Store = Store

local db

--- Profiles live in source and are handed out by value: an applied rule the player then
--- edits must not write back into the table the next `/sg profile` reads.
local function Copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = Copy(v) end
  return out
end

--- A rule set reduced to one number, so "is this still what the profile says" is a comparison
--- and not a walk. Keys are sorted, so two tables with the same content stamp the same however
--- they were built.
local function Stamp(list)
  local parts = {}
  local function write(value)
    if type(value) ~= "table" then
      parts[#parts + 1] = tostring(value)
      return
    end
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    parts[#parts + 1] = "{"
    for _, k in ipairs(keys) do
      parts[#parts + 1] = tostring(k) .. "="
      write(value[k])
      parts[#parts + 1] = ","
    end
    parts[#parts + 1] = "}"
  end
  write(list)
  local text, hash = table.concat(parts), 5381
  for i = 1, #text do
    hash = (hash * 33 + string.byte(text, i)) % 4294967296
  end
  return hash
end

--- The source stamped the way an APPLIED copy would be. `Modernize` rewrites the older rule
--- shapes on the way in, so stamping the raw source and comparing it to a stored rule set that
--- has been through that pass would report drift on every login for a profile nobody touched.
local function ProfileStamp(profile)
  local copy = Copy(profile.glows)
  for _, glow in ipairs(copy) do ns.Rules.Modernize(glow) end
  return Stamp(copy)
end

--- A profile applied from source is a COPY, so a later release changing the source changes
--- nothing already applied. This carries the change across -- but only when the copy is still
--- untouched. Three states, and the middle one is why the stamp is stored rather than just
--- compared: rules that match what was applied are the player's consent to be updated, rules
--- that do not are the player's own work and are never overwritten.
local function Resync()
  local name = db.settings.profile
  if name == nil then return end
  local profile = ns.Profiles.Get(name)
  if profile == nil then
    ns.Printf("profile %q is applied but no longer exists in this build.", tostring(name))
    return
  end
  local source, applied = ProfileStamp(profile), db.settings.profileStamp
  -- ⚠ A copy applied before this tracking existed carries no stamp, and no comparison can
  -- tell an untouched one from a hand-edited one. Adopting whatever is stored as the baseline
  -- is the only safe reading -- it overwrites nothing -- and it is what makes every LATER
  -- change resync by itself. This build's own change is the one that has to be asked for.
  if applied == nil then
    db.settings.profileStamp = Stamp(db.glows)
    if db.settings.profileStamp ~= source then
      ns.Printf("⚠ your %s rules predate update tracking and are OUT OF DATE -- rule fixes "
        .. "in this build are NOT active. `/sg profile %s` to take them (this replaces any "
        .. "edits of your own). From then on updates apply by themselves.",
        profile.label, name)
    end
    return
  end
  if source == applied then return end
  if Stamp(db.glows) ~= applied then
    ns.Printf("⚠ %s has changed and those fixes are NOT active, but your rules differ from "
      .. "the copy you applied -- leaving them alone. `/sg profile %s` to take the new "
      .. "version.", profile.label, name)
    return
  end
  db.glows = Copy(profile.glows)
  db.settings.profileStamp = source
  ns.Printf("%s updated from source (%d glows).", profile.label, #db.glows)
  ns.log:Mark("profile %s resynced -- stamp %s -> %s", ns.Capture.Safe(name),
    tostring(applied), tostring(source))
end

function Store.Load()
  if type(SmartGloDB) ~= "table" then SmartGloDB = {} end
  if type(SmartGloDB.glows) ~= "table" then SmartGloDB.glows = {} end
  if type(SmartGloDB.settings) ~= "table" then SmartGloDB.settings = {} end
  db = SmartGloDB
  ns.db = db
  -- Rules stored before the two bowls carry `show` and `count`; they mean what `when` and a
  -- count `bind` mean now, so they are rewritten on the way in rather than handled twice.
  for _, glow in ipairs(db.glows) do ns.Rules.Modernize(glow) end
  Resync()
  for _, glow in ipairs(db.glows) do ns.Rules.Modernize(glow) end
end

local function glows()
  if db == nil then Store.Load() end
  return db.glows
end

function Store.All()
  return glows()
end

function Store.ForSubject(spellID)
  local out = {}
  for _, glow in ipairs(glows()) do
    if glow.subject == spellID then out[#out + 1] = glow end
  end
  return out
end

function Store.Subjects()
  local seen, out = {}, {}
  for _, glow in ipairs(glows()) do
    if not seen[glow.subject] then
      seen[glow.subject] = true
      out[#out + 1] = glow.subject
    end
  end
  return out
end

--- Replaces every glow on one subject; the checker runs first, and a refusal changes nothing.
function Store.SetForSubject(spellID, list)
  local errs = {}
  for i, glow in ipairs(list) do
    glow.subject = spellID
    local ok, why = ns.Rules.CheckGlow(ns.Rules.Modernize(glow))
    if ok == nil then
      for _, err in ipairs(why) do errs[#errs + 1] = ("glow %d: %s"):format(i, err) end
    end
  end
  if #errs > 0 then return nil, errs end

  local kept = {}
  for _, glow in ipairs(glows()) do
    if glow.subject ~= spellID then kept[#kept + 1] = glow end
  end
  for _, glow in ipairs(list) do kept[#kept + 1] = glow end
  db.glows = kept
  ns.Attach.Refresh()
  ns.Count.Rebuild()
  ns.Presence.Rebuild()
  return true
end

--- Flat per-character switches, beside the rules rather than inside them: a setting is not a
--- rule and must not ride the import/export string a rule set travels in.
function Store.Setting(key)
  return db and db.settings and db.settings[key]
end

function Store.SetSetting(key, value)
  if db == nil then return end
  db.settings[key] = value
end

--- Does any applied rule name this subject? The proc suppression is scoped to rows we speak
--- for, because on a row we say nothing about, Blizzard's alert is the only thing said.
function Store.Speaks(subject)
  for _, glow in ipairs(Store.All()) do
    if glow.subject == subject then return true end
  end
  return false
end

function Store.Replace(list)
  local errs = {}
  for i, glow in ipairs(list) do
    local ok, why = ns.Rules.CheckGlow(ns.Rules.Modernize(glow))
    if ok == nil then
      for _, err in ipairs(why) do errs[#errs + 1] = ("glow %d: %s"):format(i, err) end
    end
  end
  if #errs > 0 then return nil, errs end
  db.glows = list
  ns.Attach.Refresh()
  ns.Count.Rebuild()
  ns.Presence.Rebuild()
  return true
end

ns.RegisterCommand{
  name = "profile",
  args = "<name>",
  desc = "load a built-in rule set from source",
  handler = function(rest)
    local name = string.match(rest or "", "^(%S*)")
    if name == "" then
      ns.Printf("profiles: %s", table.concat(ns.Profiles.Names(), ", "))
      return
    end
    local profile = ns.Profiles.Get(name)
    if profile == nil then
      ns.Printf("no profile %q. Known: %s", name, table.concat(ns.Profiles.Names(), ", "))
      return
    end
    local ok, errs = Store.Replace(Copy(profile.glows))
    if ok == nil then
      ns.Printf("profile %s was refused:", name)
      for _, err in ipairs(errs) do ns.Print("  " .. err) end
      return
    end
    -- What was applied, and what it looked like. A later login compares both: the name says
    -- which source to read, the stamp says whether the copy has been touched since.
    db.settings.profile = string.lower(name)
    db.settings.profileStamp = ProfileStamp(profile)
    ns.Printf("loaded profile %s (%d glows).", profile.label, #profile.glows)
  end,
}

ns.RegisterCommand{
  name = "color",
  args = "<name>",
  desc = "recolour every applied rule",
  handler = function(rest)
    local name = string.lower(string.match(rest or "", "^(%S*)"))
    if name == "" or not ns.Look.IsColor(name) then
      ns.Printf("colours: %s", table.concat(ns.Look.Names(), ", "))
      return
    end
    local list = {}
    for _, glow in ipairs(glows()) do
      glow.color = name
      list[#list + 1] = glow
    end
    local ok, errs = Store.Replace(list)
    if ok == nil then
      for _, err in ipairs(errs) do ns.Print("  " .. err) end
      return
    end
    -- Every mark is our own texture, so both kinds retint in place on the next evaluation.
    ns.Printf("%s.", name)
  end,
}

ns.RegisterCommand{
  name = "list",
  desc = "every rule currently applied",
  handler = function()
    local all = glows()
    if #all == 0 then
      ns.Print("no rules applied. /sg profile demonology loads the built-in set.")
      return
    end
    for i, glow in ipairs(all) do
      local bits = {}
      if glow.when then bits[#bits + 1] = ns.Rules.Describe(glow.when) end
      if glow.bind then bits[#bits + 1] = ns.Rules.DescribeBind(glow.bind) end
      ns.Printf("  %d. %s |cff999999on %s -- %s [%s]|r", i, glow.name or "(unnamed)",
        ns.SpellLabel(glow.subject), table.concat(bits, " + "),
        glow.color or ns.Look.DEFAULT)
    end
  end,
}
