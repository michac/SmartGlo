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

--- The two viewers whose item mixins override `ShouldBeActive` to track the aura, so only
--- their frames can be asked whether it is up.
local BUFF_VIEWERS = {
  BuffIconCooldownViewer = true,
  BuffBarCooldownViewer = true,
}

local ALERT_AURA_APPLIED, ALERT_AURA_REMOVED = 5, 6

local hooksInstalled = false
local dirty, flushQueued = false, false
local dirtySources = {}
local editing = false

--- Weak-keyed so nothing of ours lands on a Blizzard frame and nothing of ours pins one.
local alertHooked = setmetatable({}, { __mode = "k" })

--- Rebuilt from scratch on every flush; a cached id-to-frame table survives pool reuse and
--- is then WRONG rather than stale.
local bound = {}
local auraLatch = {}
local auraHeard = {}
local latchWarned = {}
--- [aura] = { {item, isBuffViewer}, ... }. Rebuilt every flush beside `bound`, for the same
--- reason: a frame list that survives pool reuse is wrong rather than stale.
local auraFrames = {}
local lastFlush = { frames = 0, matched = 0 }

local function CountKeys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

--- Each entry is {viewer, isBuffViewer}. The flag rides the NAME, not the position: a viewer
--- that does not exist is skipped, so an index into this list is not an index into
--- VIEWER_NAMES, and a shift would hand the buff viewers' rule to a cooldown viewer.
local function Viewers()
  local out = {}
  for _, name in ipairs(VIEWER_NAMES) do
    local viewer = _G[name]
    if viewer ~= nil then out[#out + 1] = { viewer, BUFF_VIEWERS[name] == true } end
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
    local stack = { ns.Rules.Gate(glow) }
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
        if event == ALERT_AURA_APPLIED or event == ALERT_AURA_REMOVED then
          local was = auraLatch[aura]
          auraLatch[aura] = event == ALERT_AURA_APPLIED and ns.T or ns.F
          if was ~= auraLatch[aura] then
            ns.log:Mark("aura %s %s -> %s", ns.Capture.Safe(ns.Rules.Label(aura)),
              tostring(was), auraLatch[aura])
          end
        end
      end
    end
    Attach.Evaluate()
  end)
end

-- ------------------------------------------------- the aura level, beside the edge
--
-- The edge latch answers "did I hear it go up", which is UNKNOWN until an edge arrives --
-- so a buff already up when we started watching reads as nothing. These two fields are the
-- client's own answer to "is it up NOW", carried on the frame it already laid out, so
-- reading them costs no aura call and is not subject to the per-spell aura allowlist.
--
-- ⚠ `wasSetFromAura` is UNMEASURED: it is named by a third-party addon, not by Blizzard's
-- generated docs (mined-pending-verification.md E2). Nothing here asserts it exists. A frame
-- that answers neither field returns nil and the caller falls back to the edge latch, so on
-- a client without them this whole path is dead weight rather than a wrong answer.

--- true | false | nil, where nil means "this frame cannot say" and never "absent".
---
--- A BUFF viewer item answers properly: `CooldownViewerBuffItemMixin:ShouldBeActive`
--- overrides the base to track the aura -- expiry, the linked-spell fallback and totems --
--- and `IsActive` reads what it set. The base mixin's version is `cooldownID ~= nil`, true
--- for every bound row, so this question may only be put to a buff item.
---
--- ⚠ Being SHOWN is not the same question and must not be substituted: `ShouldBeShown`
--- returns true whenever `hideWhenInactive` is off, which is a user setting, so a shown row
--- says nothing about the aura.
local function ReadBuffActive(item)
  if type(item.IsActive) ~= "function" then return nil end
  local ok, active = pcall(item.IsActive, item)
  if not ok then
    ns.log:Mark("presence: IsActive refused -- %s", ns.Capture.Safe(active))
    return nil
  end
  if ns.IsSecret(active) or type(active) ~= "boolean" then return nil end
  return active
end

--- The cooldown viewers have no such predicate, so only these two fields can speak there.
--- ⚠ `wasSetFromAura` is UNMEASURED: it is named by a third-party addon, not by Blizzard's
--- generated docs (mined-pending-verification.md E2). Nothing here asserts it exists. A frame
--- answering neither field returns nil and the caller falls back to the edge latch, so on a
--- client without them this path is dead weight rather than a wrong answer.
local function ReadFieldPresence(item)
  local fromAura, instance = item.wasSetFromAura, item.auraInstanceID
  if not ns.IsSecret(fromAura) and fromAura == true then return true end
  if not ns.IsSecret(instance) and instance ~= nil then return true end
  if fromAura ~= nil or instance ~= nil then return false end
  return nil
end

--- The level across every frame carrying the aura, buff viewers first. They hold a real
--- predicate and the cooldown viewers hold two unmeasured fields, so a buff frame that can
--- answer settles it alone rather than being mixed with the weaker source.
local function AuraLevel(auraSpellID)
  local frames = auraFrames[auraSpellID]
  if frames == nil then return nil end
  local buffSpoke, fieldSpoke = false, false
  local fieldUp = false
  for _, entry in ipairs(frames) do
    local item, isBuffViewer = entry[1], entry[2]
    if isBuffViewer then
      local active = ReadBuffActive(item)
      if active == true then return true end
      if active == false then buffSpoke = true end
    else
      local present = ReadFieldPresence(item)
      if present == true then fieldUp = true end
      if present ~= nil then fieldSpoke = true end
    end
  end
  if buffSpoke then return false end
  if fieldSpoke then return fieldUp end
  return nil
end

--- UNKNOWN until an edge has been heard: a row the player never enabled raises none, and
--- that silence must not read as absence.
function Attach.AuraLatch(auraSpellID)
  local level = AuraLevel(auraSpellID)
  if level ~= nil then return level and ns.T or ns.F end
  if not auraHeard[auraSpellID] then
    -- Once per flush: this is read on every evaluation, and the fact worth recording is that
    -- the row is missing, not how many times something asked.
    if not latchWarned[auraSpellID] then
      latchWarned[auraSpellID] = true
      ns.log:Mark("aura %s UNKNOWN -- no bound row raises its alerts, so a Tracked Buffs "
        .. "checkbox is missing", ns.Capture.Safe(ns.Rules.Label(auraSpellID)))
    end
    return ns.UNKNOWN
  end
  return auraLatch[auraSpellID] or ns.UNKNOWN
end

-- ---------------------------------------------------------------- the rebuild

local TakeSources

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
  latchWarned = {}
  auraFrames = {}
  for aura in pairs(wanted) do
    if auraLatch[aura] == nil then auraLatch[aura] = ns.UNKNOWN end
  end

  local subjects = {}
  for _, subject in ipairs(ns.Store.Subjects()) do subjects[subject] = true end

  local seen, matched = 0, 0
  for _, entry in ipairs(Viewers()) do
    local viewer, isBuffViewer = entry[1], entry[2]
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
              if InfoCarriesAura(info, aura) then
                HookAlerts(item, aura)
                local frames = auraFrames[aura]
                if frames == nil then frames = {}; auraFrames[aura] = frames end
                frames[#frames + 1] = { item, isBuffViewer }
              end
            end
          end
        end
      end
    end
  end

  lastFlush = { frames = seen, matched = matched }
  ns.log:Mark("flush <- %s: %d frames, %d of %d subjects bound",
    TakeSources(), seen, matched, CountKeys(subjects))
  for subject in pairs(subjects) do
    if bound[subject] == nil then
      ns.log:Mark("  no frame for %s -- the Cooldown Manager is not laying that row out",
        ns.Capture.Safe(ns.Rules.Label(subject)))
    end
  end
  -- REBUILD, not re-anchor: an occluder is cropped from the icon the row is drawing and
  -- sized in that row's own units, so a rebind or a resize needs a new container rather
  -- than a moved one. Rebuild is keyed and idempotent, so an unchanged row costs nothing.
  ns.Count.Rebuild()
  Attach.Evaluate()
end

--- `source` names what announced the change, and every caller passes one -- a hooksecurefunc
--- callback receives the hooked function's own arguments, which is why each hook below wraps
--- this rather than being it.
---
--- Sources ACCUMULATE and the flush reports the set. Layout fires in bursts that coalesce into
--- one rebuild, so marking each arrival would bury the one that matters -- which announcement
--- preceded a rebind -- under fifty identical lines.
function Attach.MarkDirty(source)
  dirty = true
  dirtySources[source or "?"] = true
  if flushQueued then return end
  flushQueued = true
  C_Timer.After(0, Flush)
end

function TakeSources()
  local out = {}
  for name in pairs(dirtySources) do out[#out + 1] = name end
  table.sort(out)
  dirtySources = {}
  return table.concat(out, "+")
end

-- -------------------------------------------------------------- the evaluation

--- Why a glow is dark, recorded at the moment it goes dark. `/sg why` answers the same
--- question but only while you are looking; a verdict change is over before you can type.
local lastVerdict = setmetatable({}, { __mode = "k" })

local function Note(glow, verdict, trace)
  if lastVerdict[glow] == verdict then return end
  lastVerdict[glow] = verdict
  local parts = {}
  for _, entry in ipairs(trace) do
    parts[#parts + 1] = ("%s %s"):format(entry.verdict, entry.text)
  end
  ns.log:Line("%s [%s] %s", ns.Capture.Safe(glow.name or "(unnamed)"), verdict,
    #parts > 0 and table.concat(parts, ", ") or "no terms")
end

--- Both sealed families write the mark's alpha themselves, so `Overlay.SetLit` must leave
--- that channel alone for either of them.
local function SealsAlpha(glow)
  return ns.Duration.Owns(glow) or ns.Health.Owns(glow)
end

function Attach.Evaluate()
  local live = {}
  for _, glow in ipairs(ns.Store.All()) do
    local item = bound[glow.subject]
    local open = false
    if item == nil then
      Note(glow, "-", {})
    elseif editing then
      Note(glow, "edit", {})
    elseif not IsShowing(item) then
      Note(glow, "hidden", {})
    else
      local verdict, trace = ns.Rules.Evaluate(ns.Rules.Gate(glow))
      Note(glow, verdict, trace)
      open = verdict == ns.T
    end
    -- Both kinds light the same mark. A gate glow shows it outright; a count glow shows it
    -- with the occluder over it, and lets the client take the occluder away at the
    -- threshold. So `open` means the same thing in both: the rule's readable half passed.
    local element = ns.Overlay.Element(glow)
    live[element] = true
    ns.Overlay.SetLit(element, open, glow.color or ns.Look.DEFAULT, SealsAlpha(glow))
  end
  ns.Overlay.DarkenStale(live)
  for subject in pairs(bound) do
    ns.Overlay.SetVisible(ns.Overlay.For(subject), not editing)
  end
  ns.Duration.Refresh()
  ns.Health.Refresh()
end

-- ------------------------------------------------------------------ the wiring

local override = CreateFrame("Frame")
override:SetScript("OnEvent", function() Attach.MarkDirty("SpellOverrideUpdated") end)

local events = CreateFrame("Frame")
-- The cast ledger is fed here rather than from a frame of its own: a projected
-- threshold is read during the evaluation below, so the ledger has to be current
-- first, and two frames have no ordering between them.
events:SetScript("OnEvent", function(_, event, _, _, spellID)
  ns.Cast.Observe(event, spellID)
  Attach.Evaluate()
end)

local function RegisterTriggers()
  events:UnregisterAllEvents()
  local wanted = {}
  for _, glow in ipairs(ns.Store.All()) do
    ns.Rules.Triggers(ns.Rules.Gate(glow), wanted)
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

  for _, entry in ipairs(Viewers()) do
    local viewer = entry[1]
    hooksecurefunc(viewer, "Layout", function() Attach.MarkDirty("Layout") end)
    hooksecurefunc(viewer, "RefreshLayout", function() Attach.MarkDirty("RefreshLayout") end)
  end
  for _, name in ipairs(MIXIN_NAMES) do
    local mixin = _G[name]
    if type(mixin) == "table" and type(mixin.OnCooldownIDSet) == "function" then
      hooksecurefunc(mixin, "OnCooldownIDSet", function() Attach.MarkDirty("OnCooldownIDSet") end)
    end
  end

  EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged",
    function() Attach.MarkDirty("OnDataChanged") end)

  -- A proc that swaps a row's spell keeps its cooldownID, so OnCooldownIDSet is silent for it
  -- and the bound map would go on naming the base spell. This event is what writes the
  -- override, and the bind of a glow whose subject IS the override id depends on it:
  -- Ruination over Hand of Gul'dan, Infernal Bolt over Shadow Bolt.
  override:RegisterEvent("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
  EventRegistry:RegisterCallback("EditMode.Enter", function()
    editing = true
    ns.log:Mark("edit mode enter")
    Attach.Evaluate()
  end)
  EventRegistry:RegisterCallback("EditMode.Exit", function()
    editing = false
    ns.log:Mark("edit mode exit")
    Attach.MarkDirty("EditModeExit")
  end)
  return true
end

local waiting = CreateFrame("Frame")
waiting:SetScript("OnEvent", function(self, _, name)
  if name ~= "Blizzard_CooldownViewer" then return end
  if InstallHooks() then
    self:UnregisterAllEvents()
    Attach.MarkDirty("CooldownViewerLoaded")
  end
end)

function Attach.Start()
  if not InstallHooks() then
    waiting:RegisterEvent("ADDON_LOADED")
  end
  RegisterTriggers()
  Attach.MarkDirty("Start")
end

--- Every write to the rule set changes which events can change a verdict, so a store that
--- only marked dirty would evaluate once and then freeze.
function Attach.Refresh()
  -- New rules may name talents nothing has read yet, and a rule set only changes out of
  -- combat or by paste -- either way this is the moment to read them.
  ns.Rules.PrimeTalents()
  RegisterTriggers()
  Attach.MarkDirty("RulesChanged")
end

--- The fileID the row is DRAWING, which is not `C_Spell.GetSpellTexture(subject)`:
--- `CooldownViewerItemDataMixin:GetSpellTexture` walks a ladder -- a spell-category icon, a
--- live aura's own icon, an equip-slot texture, a linked spell, an override -- before it
--- reaches the base spell. Reading the fileID back off the Icon region is that whole ladder's
--- answer, so an occluder cropped from it matches whatever the player is looking at.
function Attach.IconOf(subject)
  local item = bound[subject]
  if item == nil then return nil end
  local okIcon, icon = pcall(item.GetIconTexture, item)
  if okIcon and icon ~= nil then
    local okID, id = pcall(icon.GetTextureFileID, icon)
    if okID and not ns.IsSecret(id) and type(id) == "number" and id ~= 0 then return id end
  end
  local okTex, tex = pcall(item.GetSpellTexture, item)
  if okTex and not ns.IsSecret(tex) and type(tex) == "number" and tex ~= 0 then return tex end
  return nil
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
        local verdict, trace = ns.Rules.Evaluate(ns.Rules.Gate(glow))
        local attached = "no laid-out row"
        if bound[glow.subject] ~= nil then attached = "attached" end
        ns.Printf("%s |cff999999on %s -- %s, %s|r", glow.name or "(unnamed)",
          ns.SpellLabel(glow.subject), verdict, attached)
        for _, row in ipairs(trace) do
          ns.Printf("    [%s] %s", row.verdict, row.text)
        end
        -- A sealed bind has no verdict to print: nothing here read it. What can be shown is
        -- what was handed to the client -- the count element's arm report, or the curve the
        -- duration bind compiled to.
        if ns.Count.Owns(glow) then
          ns.Printf("    [sealed] %s -- %s", ns.Rules.DescribeBind(glow.bind),
            ns.Count.Describe(glow.subject))
        elseif ns.Duration.Owns(glow) then
          ns.Printf("    %s -- %s", ns.Duration.Describe(glow.bind),
            ns.Rules.DescribeBind(glow.bind))
        elseif ns.Health.Owns(glow) then
          ns.Printf("    %s -- %s", ns.Health.Describe(glow.bind),
            ns.Rules.DescribeBind(glow.bind))
        elseif glow.bind ~= nil then
          ns.Printf("    [sealed] %s", ns.Rules.DescribeBind(glow.bind))
        end
      end
    end
  end,
}
