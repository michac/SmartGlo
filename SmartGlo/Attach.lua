-- The attach path: which live CDM icon each subject is on right now, and what lights it.

local _, ns = ...

local Attach = {}
ns.Attach = Attach

local VIEWER_NAMES = {
  "EssentialCooldownViewer", "UtilityCooldownViewer",
  "BuffIconCooldownViewer", "BuffBarCooldownViewer",
}

local MIXIN_NAMES = {
  "CooldownViewerEssentialItemMixin", "CooldownViewerUtilityItemMixin",
  "CooldownViewerBuffIconItemMixin", "CooldownViewerBuffBarItemMixin",
}

local ALERT_AURA_APPLIED, ALERT_AURA_REMOVED = 5, 6

local hooksInstalled = false
local dirty, flushQueued = false, false
local editing = false

--- Weak-keyed so nothing of ours lands on a Blizzard frame and nothing of ours pins one.
local alertHooked = setmetatable({}, { __mode = "k" })

--- Rebuilt from scratch on every flush; a cached id-to-frame table survives pool reuse and
--- is then WRONG rather than stale.
local bound = {}
local auraLatch = {}
local auraHeard = {}
local lastFlush = { frames = 0, matched = 0 }

local function Viewers()
  local out = {}
  for _, name in ipairs(VIEWER_NAMES) do
    local viewer = _G[name]
    if viewer ~= nil then out[#out + 1] = viewer end
  end
  return out
end

local function ActiveFrames(viewer)
  local pool = viewer.itemFramePool
  if pool == nil or type(pool.EnumerateActive) ~= "function" then return nil end
  return pool:EnumerateActive()
end

--- `IsVisible` carries a secret Shown aspect, so an unreadable answer fails closed to hidden:
--- an inactive row hides in place and keeps its grid cell.
local function IsShowing(item)
  local ok, visible = pcall(item.IsVisible, item)
  if not ok then return false end
  if ns.IsSecret(visible) then return false end
  return visible == true
end

local function CooldownIDOf(item)
  local ok, id = pcall(item.GetCooldownID, item)
  if ok and type(id) == "number" then return id end
  if type(item.cooldownID) == "number" then return item.cooldownID end
  return nil
end

local function InfoFor(cooldownID)
  if type(C_CooldownViewer) ~= "table" then return nil end
  local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
  if not ok or type(info) ~= "table" then return nil end
  return info
end

--- A subject is the spell the icon is SHOWING, override included -- what the player sees.
local function BoundSpell(info)
  if type(info.overrideSpellID) == "number" and info.overrideSpellID ~= 0 then
    return info.overrideSpellID
  end
  if type(info.spellID) == "number" then return info.spellID end
  return nil
end

local function InfoCarriesAura(info, auraSpellID)
  if info.spellID == auraSpellID or info.overrideSpellID == auraSpellID then return true end
  if type(info.linkedSpellIDs) == "table" then
    for _, id in ipairs(info.linkedSpellIDs) do
      if id == auraSpellID then return true end
    end
  end
  return info.linkedSpellID == auraSpellID
end

-- ------------------------------------------------------------- the aura latch

local function WantedAuras()
  local wanted = {}
  for _, glow in ipairs(ns.Store.All()) do
    local expr = glow.show
    local stack = { expr }
    while #stack > 0 do
      local term = table.remove(stack)
      if type(term) == "table" then
        if term.t == "aura" then wanted[term.spell] = true end
        if type(term.terms) == "table" then
          for _, sub in ipairs(term.terms) do stack[#stack + 1] = sub end
        end
        if term.term ~= nil then stack[#stack + 1] = term.term end
      end
    end
  end
  return wanted
end

--- Observing a CALL is not reading a value, so an up/down latch off the alert edges is
--- readable where the aura itself is not (cooldown-manager.md §5.1).
local function HookAlerts(item, auraSpellID)
  auraHeard[auraSpellID] = true
  if alertHooked[item] then return end
  alertHooked[item] = true
  hooksecurefunc(item, "TriggerAlertEvent", function(self, event)
    local id = CooldownIDOf(self)
    if id == nil then return end
    local info = InfoFor(id)
    if info == nil then return end
    for aura in pairs(auraLatch) do
      if InfoCarriesAura(info, aura) then
        if event == ALERT_AURA_APPLIED then
          auraLatch[aura] = ns.T
        elseif event == ALERT_AURA_REMOVED then
          auraLatch[aura] = ns.F
        end
      end
    end
    Attach.Evaluate()
  end)
end

--- UNKNOWN until an edge has been heard: a row the player never enabled raises none, and
--- that silence must not read as absence.
function Attach.AuraLatch(auraSpellID)
  if not auraHeard[auraSpellID] then return ns.UNKNOWN end
  return auraLatch[auraSpellID] or ns.UNKNOWN
end

-- ---------------------------------------------------------------- the rebuild

local function Detach()
  for _, f in pairs(ns.Overlay.Existing()) do
    ns.Overlay.Detach(f)
  end
  bound = {}
end

local function Flush()
  flushQueued = false
  if not dirty then return end
  dirty = false

  Detach()
  local wanted = WantedAuras()
  auraHeard = {}
  for aura in pairs(wanted) do
    if auraLatch[aura] == nil then auraLatch[aura] = ns.UNKNOWN end
  end

  local subjects = {}
  for _, subject in ipairs(ns.Store.Subjects()) do subjects[subject] = true end

  local seen, matched = 0, 0
  for _, viewer in ipairs(Viewers()) do
    local iter = ActiveFrames(viewer)
    if iter ~= nil then
      for item in iter do
        seen = seen + 1
        local id = CooldownIDOf(item)
        if id ~= nil then
          local info = InfoFor(id)
          if info ~= nil then
            local spell = BoundSpell(info)
            if spell ~= nil and subjects[spell] and bound[spell] == nil then
              bound[spell] = item
              ns.Overlay.Anchor(ns.Overlay.For(spell), item)
              matched = matched + 1
            end
            for aura in pairs(wanted) do
              if InfoCarriesAura(info, aura) then HookAlerts(item, aura) end
            end
          end
        end
      end
    end
  end

  lastFlush = { frames = seen, matched = matched }
  ns.Count.Reanchor()
  Attach.Evaluate()
end

function Attach.MarkDirty()
  dirty = true
  if flushQueued then return end
  flushQueued = true
  C_Timer.After(0, Flush)
end

-- -------------------------------------------------------------- the evaluation

function Attach.Evaluate()
  local lit = {}
  for _, glow in ipairs(ns.Store.All()) do
    local item = bound[glow.subject]
    local open = false
    if item ~= nil and not editing and IsShowing(item) then
      open = ns.Rules.Evaluate(glow.show) == ns.T
    end
    if glow.count ~= nil then
      ns.Count.SetGate(glow, open)
    elseif open then
      lit[glow.subject] = true
    end
  end
  for subject in pairs(bound) do
    local f = ns.Overlay.For(subject)
    f:SetShown(not editing)
    ns.Overlay.SetLit(f, lit[subject] == true)
  end
end

-- ------------------------------------------------------------------ the wiring

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function() Attach.Evaluate() end)

local function RegisterTriggers()
  events:UnregisterAllEvents()
  local wanted = {}
  for _, glow in ipairs(ns.Store.All()) do
    ns.Rules.Triggers(glow.show, wanted)
  end
  for event in pairs(wanted) do
    if string.sub(event, 1, 5) == "UNIT_" then
      pcall(events.RegisterUnitEvent, events, event, "player")
    else
      pcall(events.RegisterEvent, events, event)
    end
  end
end

--- The viewer globals do not exist until Blizzard_CooldownViewer has loaded, so this
--- refuses rather than latching `installed` on an empty sweep.
local function InstallHooks()
  if hooksInstalled then return true end
  if #Viewers() == 0 then return false end
  hooksInstalled = true

  for _, viewer in ipairs(Viewers()) do
    hooksecurefunc(viewer, "Layout", Attach.MarkDirty)
    hooksecurefunc(viewer, "RefreshLayout", Attach.MarkDirty)
  end
  for _, name in ipairs(MIXIN_NAMES) do
    local mixin = _G[name]
    if type(mixin) == "table" and type(mixin.OnCooldownIDSet) == "function" then
      hooksecurefunc(mixin, "OnCooldownIDSet", Attach.MarkDirty)
    end
  end

  EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", Attach.MarkDirty)
  EventRegistry:RegisterCallback("EditMode.Enter", function()
    editing = true
    Attach.Evaluate()
  end)
  EventRegistry:RegisterCallback("EditMode.Exit", function()
    editing = false
    Attach.MarkDirty()
  end)
  return true
end

local waiting = CreateFrame("Frame")
waiting:SetScript("OnEvent", function(self, _, name)
  if name ~= "Blizzard_CooldownViewer" then return end
  if InstallHooks() then
    self:UnregisterAllEvents()
    Attach.MarkDirty()
  end
end)

function Attach.Start()
  if not InstallHooks() then
    waiting:RegisterEvent("ADDON_LOADED")
  end
  RegisterTriggers()
  Attach.MarkDirty()
end

function Attach.Refresh()
  RegisterTriggers()
  Attach.MarkDirty()
end

function Attach.Bound()
  return bound
end

function Attach.ReportStatus()
  local viewers = #Viewers()
  if viewers == 0 then
    ns.Print("no Cooldown Manager viewers exist yet -- nothing to attach to.")
    return
  end
  ns.Printf("%d viewers, %d item frames swept, %d subjects attached.",
    viewers, lastFlush.frames, lastFlush.matched)
  if #ns.Store.All() > 0 and lastFlush.matched == 0 then
    ns.Print("rules are applied but none of their subjects has a laid-out row.")
  end
end

ns.RegisterCommand{
  name = "why",
  args = "[spellID]",
  desc = "per-term T/F/? for every applied rule",
  handler = function(rest)
    local only = tonumber(string.match(rest or "", "^(%S*)"))
    local all = ns.Store.All()
    if #all == 0 then
      ns.Print("no rules applied.")
      return
    end
    for _, glow in ipairs(all) do
      if only == nil or glow.subject == only then
        local verdict, trace = ns.Rules.Evaluate(glow.show)
        local attached = "no laid-out row"
        if bound[glow.subject] ~= nil then attached = "attached" end
        ns.Printf("%s |cff999999on %s -- %s, %s|r", glow.name or "(unnamed)",
          ns.SpellLabel(glow.subject), verdict, attached)
        for _, row in ipairs(trace) do
          ns.Printf("    [%s] %s", row.verdict, row.text)
        end
        if glow.count ~= nil then
          ns.Printf("    [sealed] count(%d) >= %d -- %s", glow.count.aura,
            glow.count.threshold, ns.Count.Describe(glow.subject))
        end
      end
    end
  end,
}
