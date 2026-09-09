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

function Store.Load()
  if type(SmartGloDB) ~= "table" then SmartGloDB = {} end
  if type(SmartGloDB.glows) ~= "table" then SmartGloDB.glows = {} end
  db = SmartGloDB
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
    local ok, why = ns.Rules.CheckGlow(glow)
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
  return true
end

function Store.Replace(list)
  local errs = {}
  for i, glow in ipairs(list) do
    local ok, why = ns.Rules.CheckGlow(glow)
    if ok == nil then
      for _, err in ipairs(why) do errs[#errs + 1] = ("glow %d: %s"):format(i, err) end
    end
  end
  if #errs > 0 then return nil, errs end
  db.glows = list
  ns.Attach.Refresh()
  ns.Count.Rebuild()
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
      if glow.show then bits[#bits + 1] = ns.Rules.Describe(glow.show) end
      if glow.count then
        bits[#bits + 1] = ("count(%d) >= %d"):format(glow.count.aura, glow.count.threshold)
      end
      ns.Printf("  %d. %s |cff999999on %s -- %s [%s]|r", i, glow.name or "(unnamed)",
        ns.SpellLabel(glow.subject), table.concat(bits, " + "),
        glow.color or ns.Look.DEFAULT)
    end
  end,
}
