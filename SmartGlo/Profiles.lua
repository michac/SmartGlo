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
      -- No gate: at zero imps and below the threshold the correct output is the same
      -- nothing, so there is no absence case for a readable term to cover.
      {
        name = "Implosion at six imps",
        subject = 196277,
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
