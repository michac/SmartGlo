-- Named rule sets carried in source, so a profile can be authored outside the game.
--
-- Not SavedVariables: /reload commits those from memory before reloading, so an edit made
-- while the client is running is overwritten (anatomy-and-runtime.md:955).

local _, ns = ...

local Profiles = {}
ns.Profiles = Profiles

Profiles.list = {
  demonology = {
    label = "Demonology",
    glows = {
      {
        name = "Hand of Gul'dan at three shards",
        subject = 105174,
        show = { t = "resource", power = "soul_shards", cmp = ">=", value = 3 },
      },
      -- ⚠ The gate is not optional here. A count draws an OCCLUDER below the threshold, so
      -- band 0 draws, so rule-language.md §6.4's absence case applies: with the aura gone the
      -- client hides the button, the occluder goes with it, and the mark reads as six. Wild
      -- Imps' Cooldown Manager buff is continuously present, which is what makes this safe.
      -- `ready()` covers a separate hazard: the occluder is a static copy of the icon drawn
      -- above the swipe, so a mark mid-cooldown would show an unswiped patch.
      {
        name = "Implosion at six imps",
        subject = 196277,
        show = { t = "ready", spell = 196277 },
        count = { aura = 296553, threshold = 6 },
      },
    },
  },
}

function Profiles.Names()
  local names = {}
  for name in pairs(Profiles.list) do names[#names + 1] = name end
  table.sort(names)
  return names
end

function Profiles.Get(name)
  local profile = Profiles.list[string.lower(name or "")]
  if profile == nil then return nil end
  return profile
end
