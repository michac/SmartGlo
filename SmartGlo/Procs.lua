-- Blizzard's own proc glow on a row we already speak for.
--
-- The Cooldown Manager runs `ActionButtonSpellAlertManager:ShowAlert(item)` out of
-- `CooldownViewerCooldownItemMixin:RefreshOverlayGlow` whenever `IsSpellOverlayed` is true
-- `[T1 src @12.1.0: CooldownViewer.lua:1236-1252]`. That alert is bright, animated and says
-- one thing -- "this spell procced" -- on the same pixels our marks use to say several.
--
-- ⚠ This is the first thing in the addon that touches what the client drew rather than
-- decorating it, and it is off by default for that reason.
--
-- The treatment is SCOPED to subjects that carry a rule. Where we say nothing, Blizzard's
-- alert is the only information on that icon and taking it away would be a straight loss.

local _, ns = ...

local Procs = {}
ns.Procs = Procs

local hooked = false

--- Alpha is the addon's dial, and the template is why it works: every `<Alpha>` in
--- `ActionButtonSpellAlertTemplate` carries a `childKey`, so the animations drive the two
--- flipbook textures and nothing drives the frame's own alpha
--- `[T1 src @12.1.0: ActionButtonSpellAlerts.xml:21-33]`. Frame alpha multiplies down into
--- them and the running animation cannot take it back.
local DIM = 0.25

local function Manager()
  local mgr = _G["ActionButtonSpellAlertManager"]
  if type(mgr) ~= "table" or type(mgr.HideAlert) ~= "function" then return nil end
  return mgr
end

--- What the client's alert on this row is doing right now, in the words `/sg rows` prints
--- and this module logs when it declines to touch one. Blank is not an outcome: every path
--- through here names itself.
function Procs.Describe(item)
  local mgr = Manager()
  if mgr == nil then return "no alert manager" end
  if type(mgr.HasAlert) ~= "function" then return "manager has no HasAlert" end
  local ok, has, kind = pcall(mgr.HasAlert, mgr, item)
  if not ok then return "HasAlert refused -- " .. ns.Capture.Safe(has) end
  if not has then return "no alert" end
  local frame = item.SpellActivationAlert
  if type(frame) ~= "table" or type(frame.GetAlpha) ~= "function" then
    return ("alert type %s, no Default frame parked"):format(tostring(kind))
  end
  local gotAlpha, alpha = pcall(frame.GetAlpha, frame)
  if not gotAlpha then return "GetAlpha refused -- " .. ns.Capture.Safe(alpha) end
  return ("alert type %s, alpha %.2f"):format(tostring(kind), alpha)
end

--- Blizzard parks the frame on the button itself for a Default alert, and a CDM row can only
--- take a Default one: the AssistedCombatRotation branch needs `actionButton.action`, which a
--- cooldown viewer item does not have `[T1 src @12.1.0: ActionButtonSpellAlerts.lua:117-123]`.
local function AlertFrame(item)
  local frame = item.SpellActivationAlert
  if type(frame) ~= "table" or type(frame.SetAlpha) ~= "function" then return nil end
  return frame
end

--- `nil` means leave the client's alert alone. A number is the alpha to hold it at, and zero
--- is the one value handled by hiding instead, so a fully invisible alert stops animating.
function Procs.Alpha()
  local set = ns.Store.Setting("procAlpha")
  if type(set) == "number" then return set end
  -- The setting was a boolean before it was a dial; true meant hide outright.
  if ns.Store.Setting("suppressProcs") == true then return 0 end
  return nil
end

function Procs.Enabled()
  return Procs.Alpha() ~= nil
end

local function ApplyTo(item)
  local alpha = Procs.Alpha()
  if alpha == nil then return end
  if alpha <= 0 then
    local mgr = Manager()
    if mgr == nil then return end
    local ok, err = pcall(mgr.HideAlert, mgr, item)
    if not ok then ns.log:Mark("procs: HideAlert refused -- %s", ns.Capture.Safe(err)) end
    return
  end
  local frame = AlertFrame(item)
  if frame == nil then return end
  local ok, err = pcall(frame.SetAlpha, frame, alpha)
  if not ok then ns.log:Mark("procs: SetAlpha refused -- %s", ns.Capture.Safe(err)) end
end

--- Why this hook did nothing, recorded on CHANGE. `RefreshOverlayGlow` fires many times a
--- second, so a line per call would bury the transition that matters; a line per new reason
--- is the whole story and is what tells a hook that never fires from one that bails.
local lastReason = setmetatable({}, { __mode = "k" })

local function Reason(item, why)
  if lastReason[item] == why then return end
  lastReason[item] = why
  ns.log:Mark("procs: %s -- %s", why, ns.Capture.Safe(Procs.Describe(item)))
end

--- Post-hooks run AFTER `ShowAlert`, so this is a re-assert rather than a prevention. There is
--- no earlier seam -- the show is an unconditional call inside a method we do not own.
local function OnRefresh(item)
  if not Procs.Enabled() then
    Reason(item, "off")
    return
  end
  local subject = ns.Attach.SubjectOf(item)
  if subject == nil then
    Reason(item, "row not bound to any subject")
    return
  end
  if not ns.Store.Speaks(subject) then
    Reason(item, ("no rule on %s"):format(ns.SpellLabel(subject)))
    return
  end
  Reason(item, ("applying to %s"):format(ns.SpellLabel(subject)))
  ApplyTo(item)
end

--- Hooked once, on the mixins rather than the frames: an item frame is pooled and a hook on
--- one dies with its acquire, while the mixin is the table every frame inherits. A frame
--- copies the mixin's methods when it is created, so a hook only reaches frames made after
--- it -- which is why the count is logged rather than assumed.
function Procs.InstallHooks(mixinNames)
  if hooked then return end
  hooked = true
  local names = {}
  for _, name in ipairs(mixinNames) do
    local mixin = _G[name]
    if type(mixin) == "table" and type(mixin.RefreshOverlayGlow) == "function" then
      hooksecurefunc(mixin, "RefreshOverlayGlow", OnRefresh)
      names[#names + 1] = name
    end
  end
  ns.log:Mark("procs: RefreshOverlayGlow hooked on %d of %d mixins -- %s",
    #names, #mixinNames, #names > 0 and table.concat(names, ", ") or "none")
end

--- Put every alert back to full. A dimmed one restores exactly; a HIDDEN one cannot be
--- re-shown from here, and the client puts it back on its next refresh.
local function RestoreAll()
  for subject, item in pairs(ns.Attach.Bound()) do
    if ns.Store.Speaks(subject) then
      local frame = AlertFrame(item)
      if frame ~= nil then
        local ok, err = pcall(frame.SetAlpha, frame, 1)
        if not ok then ns.log:Mark("procs: restore refused -- %s", ns.Capture.Safe(err)) end
      end
    end
  end
end

--- Sweeps for the moment the setting changes rather than the moment a proc fires.
function Procs.Refresh()
  if not Procs.Enabled() then return end
  for subject, item in pairs(ns.Attach.Bound()) do
    if ns.Store.Speaks(subject) then ApplyTo(item) end
  end
end

local function Describe()
  local alpha = Procs.Alpha()
  if alpha == nil then return "shown" end
  if alpha <= 0 then return "HIDDEN" end
  return string.format("DIMMED to %d%%", math.floor(alpha * 100 + 0.5))
end

--- `<n>` takes either a percent or a fraction, because both readings of "25" are things a
--- person means and only one of them is a legal alpha.
local function AlphaFrom(word)
  local n = tonumber(word)
  if n == nil then return nil end
  if n > 1 then n = n / 100 end
  if n < 0 or n > 1 then return nil end
  return n
end

ns.RegisterCommand{
  name = "procs",
  args = "[on|dim|off|<n>]",
  desc = "Blizzard's proc glow on rows this addon already speaks for",
  handler = function(rest)
    local word = string.lower(string.match(rest or "", "^(%S*)"))
    if word == "" then
      ns.Printf("Blizzard proc glows are %s on rows with a rule. "
        .. "`/sg procs dim` fades them, `/sg procs off` hides them.", Describe())
      return
    end
    local alpha
    if word == "on" then alpha = false
    elseif word == "dim" then alpha = DIM
    elseif word == "off" then alpha = 0
    else alpha = AlphaFrom(word) end
    if alpha == nil then
      ns.Print("`/sg procs on|dim|off`, or a level: `/sg procs 40`.")
      return
    end
    if alpha == false then
      -- Only a HIDDEN alert needs the client to put it back; a dimmed one restores here.
      local wasHidden = (Procs.Alpha() or 1) <= 0
      RestoreAll()
      ns.Store.SetSetting("procAlpha", nil)
      ns.Store.SetSetting("suppressProcs", nil)
      ns.Printf("Blizzard proc glows are now shown on rows with a rule%s.",
        wasHidden and " -- /reload to bring back any already hidden" or "")
      return
    end
    ns.Store.SetSetting("procAlpha", alpha)
    ns.Store.SetSetting("suppressProcs", nil)
    Procs.Refresh()
    ns.Printf("Blizzard proc glows are now %s on rows with a rule.", Describe())
  end,
}
