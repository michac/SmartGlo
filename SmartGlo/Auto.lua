-- Which profile this character wants, decided from the spec it is playing.
--
-- The rules are account-wide; the switch is not. `SmartGloCharDB.auto` is what makes a login
-- on one character load that character's profile without touching what another character
-- asked for -- there is one applied rule set, and an enabled character claims it on the way in.

local _, ns = ...

local Auto = {}
ns.Auto = Auto

--- The spec as a scope key (`warlock.demonology`), which is the word profiles and rules both
--- name a spec by. Goes through the id, never the localised name.
--- `[T1 src @12.1.0: PaperDollFrame.lua:2108]` for the index -> id read.
local function CurrentSpec()
  if type(C_SpecializationInfo) ~= "table" then return nil, "the spec API is absent" end
  local ok, index = pcall(C_SpecializationInfo.GetSpecialization)
  if not ok or type(index) ~= "number" then return nil, "your spec is unreadable" end
  local okInfo, id = pcall(C_SpecializationInfo.GetSpecializationInfo, index)
  if not okInfo or type(id) ~= "number" then return nil, "your spec id is unreadable" end
  local key = ns.Symbols.specIDs[id]
  if key == nil then return nil, ("spec %d is not in the symbol table"):format(id) end
  return key
end

--- Is the player in the hero tree a profile was transcribed for? Three-valued, and the middle
--- value matters: `talent()` rests on a `C_Traits` read that can refuse, and a refusal must
--- read as "cannot tell" rather than as "wrong tree" -- refusing to load on an unreadable
--- talent would leave a player with no rules and no explanation.
local function HeroMatch(profile)
  if profile.hero == nil then return true end
  local selected = ns.Rules.Talent(profile.hero.talent)
  if selected == nil then return nil end
  return selected == true
end

--- What `/sg enable` would load, for the spec currently being played. Returns the profile
--- name, its profile, and whether the hero tree could be confirmed; or nil plus one line
--- saying what stopped it. It never guesses between two candidates.
function Auto.Match()
  local key, why = CurrentSpec()
  if key == nil then return nil, why end
  local names = ns.Profiles.ForSpec(key)
  if #names == 0 then
    return nil, ("no profile ships for %s yet -- `/sg profile` lists what does."):format(key)
  end
  -- More than one profile for a spec is the hero tree deciding, and only a confirmed tree
  -- may decide it: an unreadable talent leaves two candidates and no grounds, which is a
  -- question for the player rather than a coin toss.
  if #names > 1 then
    local kept = {}
    for _, name in ipairs(names) do
      if HeroMatch(ns.Profiles.Get(name)) ~= false then kept[#kept + 1] = name end
    end
    if #kept ~= 1 then
      return nil, ("%d profiles ship for %s and nothing here picks between them: %s. "
        .. "`/sg profile <name>` takes one."):format(#names, key, table.concat(names, ", "))
    end
    names = kept
  end
  local name = names[1]
  local profile = ns.Profiles.Get(name)
  local hero = HeroMatch(profile)
  if hero == false then
    return nil, ("%s is the only %s profile and it is written for %s, which you are not "
      .. "talented into. `/sg profile %s` takes it anyway."):format(
      profile.label, key, profile.hero.tree, name)
  end
  return name, profile, hero
end

--- Take the matched profile, unless it is already what is applied. The three no-ops are as
--- important as the apply: the same profile already loaded, a copy the player has since
--- edited, and a spec nothing ships for. None of them may quietly replace rules.
--- `announce` is false for a login, where silence is the report that nothing changed.
function Auto.Apply(announce)
  local name, profile, hero = Auto.Match()
  if name == nil then
    if announce then ns.Print(profile) end
    ns.log:Mark("auto: no match -- %s", ns.Capture.Safe(profile))
    return false
  end
  if ns.Store.Setting("profile") == name then
    -- Already applied. `Store.Load`'s resync owns source drift; an edit of the player's own
    -- on the right profile is theirs and is not something a login undoes.
    if announce then
      ns.Printf("auto: %s is already applied.", profile.label)
    end
    return false
  end
  if ns.Store.Edited() == true then
    ns.Printf("⚠ auto: this character wants %s, but the applied rules have been edited since "
      .. "they were taken from %s -- leaving them alone. `/sg profile %s` takes the new one "
      .. "(your edits go), `/sg disable` stops asking.",
      profile.label, tostring(ns.Store.Setting("profile")), name)
    ns.log:Mark("auto: withheld %s -- applied rules edited", ns.Capture.Safe(name))
    return false
  end
  local applied, errs = ns.Store.ApplyProfile(name)
  if applied == nil then
    ns.Printf("auto: %s was refused:", name)
    for _, err in ipairs(errs) do ns.Print("  " .. err) end
    return false
  end
  ns.Printf("auto: loaded %s (%d glows).", applied.label, #applied.glows)
  if hero == nil then
    ns.Printf("  (%s is a %s set; your talents could not be read to confirm the tree.)",
      applied.label, applied.hero.tree)
  end
  -- Nothing re-evaluates here: `Store.Replace` already went through `Attach.Refresh`, which
  -- re-primes the talents the new rules name and marks the overlay dirty.
  ns.log:Mark("auto: applied %s", ns.Capture.Safe(name))
  return true
end

--- Login, after the store has loaded. Silent when it changes nothing.
function Auto.OnLogin()
  if ns.Store.CharSetting("auto") ~= true then return end
  Auto.Apply(false)
end

--- A spec change is the same question asked again, and it is out of combat by definition.
local watch = CreateFrame("Frame")
watch:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
watch:SetScript("OnEvent", function()
  if ns.Store.CharSetting("auto") ~= true then return end
  Auto.Apply(false)
end)

ns.RegisterCommand{
  name = "enable",
  desc = "load this character's spec profile now, and at every login",
  handler = function()
    local name, profile = Auto.Match()
    if name == nil then
      ns.Print(profile)
      ns.Print("not enabled -- nothing would load.")
      return
    end
    ns.Store.SetCharSetting("auto", true)
    -- `Apply` says what happened to the rules -- loaded, already there, or withheld. This
    -- says what the switch now does, which is true in all three cases.
    Auto.Apply(true)
    ns.Printf("auto-load is ON for this character -- %s loads at every login.", profile.label)
  end,
}

ns.RegisterCommand{
  name = "disable",
  desc = "stop loading a profile at login on this character",
  handler = function()
    if ns.Store.CharSetting("auto") ~= true then
      ns.Print("auto-load is already off for this character.")
      return
    end
    ns.Store.SetCharSetting("auto", false)
    -- The rules stay. Turning the switch off is a statement about logins, not a request to
    -- be left with nothing -- `/sg list` still shows what is applied.
    ns.Print("auto-load is OFF for this character. The rules already applied stay; "
      .. "`/sg list` shows them.")
  end,
}

--- What `/sg status` says about the switch: on or off, and what it would take -- including
--- the refusal, which is the whole answer when a spec ships no profile.
function Auto.ReportStatus()
  local on = ns.Store.CharSetting("auto") == true
  local name, profile = Auto.Match()
  local wants
  if name == nil then
    wants = profile
  else
    wants = ("%s (`%s`)"):format(profile.label, name)
  end
  if on then
    ns.Printf("auto-load: ON for this character -- %s", wants)
  else
    ns.Printf("auto-load: off. `/sg enable` would load %s", wants)
  end
end
