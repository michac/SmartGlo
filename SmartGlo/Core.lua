-- Rule-driven glows on Cooldown Manager icons: namespace, chat surface, command dispatch.

local ADDON, ns = ...

--- A capture session names the build it was taken on, so `ns.version` is read, not derived.
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata
  and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "?"

local PREFIX = "|cff00ccffSmartGlo|r: "

function ns.Print(msg)
  print(PREFIX .. tostring(msg))
end

function ns.Printf(fmt, ...)
  ns.Print(string.format(fmt, ...))
end

--- Three-valued throughout: a read that refuses is UNKNOWN and must never collapse to false.
ns.T, ns.F, ns.UNKNOWN = "T", "F", "?"

--- `issecretvalue` is absent on builds without the secret-value system; treat that as "plain".
function ns.IsSecret(v)
  if type(issecretvalue) ~= "function" then return false end
  local ok, secret = pcall(issecretvalue, v)
  if not ok then return true end
  return secret == true
end

--- A spell's name for chat and the config list; the id alone is unreadable to a player.
function ns.SpellLabel(spellID)
  if type(spellID) ~= "number" then return "(no subject)" end
  local ok, name = pcall(C_Spell.GetSpellName, spellID)
  if ok and type(name) == "string" then
    return ("%s (%d)"):format(name, spellID)
  end
  return tostring(spellID)
end

ns.Commands = {}
local order = {}

--- Verbs are declared by the module that owns them; this table drives dispatch and `help`.
function ns.RegisterCommand(spec)
  ns.Commands[spec.name] = spec
  table.insert(order, spec.name)
  table.sort(order)
end

local function Help()
  ns.Print("commands:")
  for _, name in ipairs(order) do
    local spec = ns.Commands[name]
    local args = ""
    if spec.args then args = " " .. spec.args end
    ns.Printf("  /sg %s%s  |cff999999%s|r", name, args, spec.desc)
  end
end

--- Matching only the leading word keeps a verb from being found inside an argument.
local function Dispatch(msg)
  local verb, rest = string.match(msg or "", "^(%S*)%s*(.-)%s*$")
  verb = string.lower(verb or "")
  if verb == "" or verb == "help" then
    Help()
    return
  end
  local spec = ns.Commands[verb]
  if spec == nil then
    ns.Printf("no such command %q.", verb)
    Help()
    return
  end
  spec.handler(rest)
end

ns.RegisterCommand{
  name = "status",
  desc = "what is loaded, and what is attached right now",
  handler = function()
    ns.Print("loaded.")
    ns.Attach.ReportStatus()
    ns.Count.ReportStatus()
  end,
}

ns.RegisterCommand{
  name = "help",
  desc = "list the commands",
  handler = Help,
}

--- The one stream. Every edge case Smart Glo has is SILENT -- the glow simply does not
--- appear -- so the log is the only instrument that says which one happened. Six sessions
--- because a `/reload` burns one and the interesting pull is usually two back.
---
--- ⚠ No game value reaches a line except through `ns.Capture.Safe`, and the duration
--- ticker never writes: only edges do, or the ring fills in under a minute.
ns.log = ns.Capture.Open("attach", { sessions = 6, cap = 600, dedup = true })

local combat = CreateFrame("Frame")
combat:RegisterEvent("PLAYER_REGEN_DISABLED")
combat:RegisterEvent("PLAYER_REGEN_ENABLED")
combat:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
combat:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_SPECIALIZATION_CHANGED" then
    local spec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
    ns.log:Mark("spec change -> %s", ns.Capture.Safe(spec))
    ns.log:Meta("spec", spec)
    return
  end
  ns.log:Mark(event == "PLAYER_REGEN_DISABLED" and "combat enter" or "combat exit")
end)

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
  SLASH_SMARTGLO1 = "/sg"
  SlashCmdList.SMARTGLO = Dispatch
  ns.Store.Load()
  -- Before the attach path asks, and while we are as close to certainly out of combat as a
  -- login gets. `PLAYER_REGEN_ENABLED` repairs it if this one landed inside a fight.
  ns.Rules.PrimeTalents()
  ns.Attach.Start()
  ns.Count.Start()
  ns.Print("loaded -- /sg help")
  ns.log:Mark("login -- SmartGlo %s", ns.Capture.Safe(ns.version))
  -- The generated symbol table against the client, which is the only authority for id -> name.
  -- Silent unless a row disagrees; `/sg symbols` is the same sweep with a summary.
  ns.Names.Check()
end)
