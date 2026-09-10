-- Blizzard's own proc glow on a row we already speak for.
--
-- The Cooldown Manager runs `ActionButtonSpellAlertManager:ShowAlert(item)` out of
-- `CooldownViewerCooldownItemMixin:RefreshOverlayGlow` whenever `IsSpellOverlayed` is true
-- `[T1 src @12.1.0: CooldownViewer.lua:1236-1252]`. That alert is bright, animated and says
-- one thing -- "this spell procced" -- on the same pixels our marks use to say several.
--
-- ⚠ This is the first thing in the addon that REMOVES what the client drew rather than
-- decorating it, and it is off by default for that reason. `README.md`'s "decorate, never
-- replace" is a statement about drawing surface, and this trims one.
--
-- The suppression is SCOPED to subjects that carry a rule. Where we say nothing, Blizzard's
-- alert is the only information on that icon and taking it away would be a straight loss.

local _, ns = ...

local Procs = {}
ns.Procs = Procs

local hooked = false

local function Manager()
  local mgr = _G["ActionButtonSpellAlertManager"]
  if type(mgr) ~= "table" or type(mgr.HideAlert) ~= "function" then return nil end
  return mgr
end

function Procs.Enabled()
  return ns.Store.Setting("suppressProcs") == true
end

--- Post-hooks run AFTER `ShowAlert`, so this is a re-assert rather than a prevention: the
--- alert is shown and taken away in the same frame. There is no earlier seam -- the show is
--- an unconditional call inside a method we do not own.
local function Suppress(item)
  if not Procs.Enabled() then return end
  local mgr = Manager()
  if mgr == nil then return end
  local subject = ns.Attach.SubjectOf(item)
  if subject == nil or not ns.Store.Speaks(subject) then return end
  local ok, err = pcall(mgr.HideAlert, mgr, item)
  if not ok then
    ns.log:Mark("procs: HideAlert refused -- %s", ns.Capture.Safe(err))
  end
end

--- Hooked once, on the mixins rather than the frames: an item frame is pooled and a hook on
--- one dies with its acquire, while the mixin is the table every frame inherits.
function Procs.InstallHooks(mixinNames)
  if hooked then return end
  hooked = true
  for _, name in ipairs(mixinNames) do
    local mixin = _G[name]
    if type(mixin) == "table" and type(mixin.RefreshOverlayGlow) == "function" then
      hooksecurefunc(mixin, "RefreshOverlayGlow", Suppress)
    end
  end
end

--- Sweep every laid-out row, for the moment the setting changes rather than the moment a
--- proc fires. Turning it back ON cannot restore an alert we hid -- the client re-shows one
--- on its next refresh, and `/reload` is the honest answer for the rest.
function Procs.Refresh()
  local mgr = Manager()
  if mgr == nil or not Procs.Enabled() then return end
  for subject, item in pairs(ns.Attach.Bound()) do
    if ns.Store.Speaks(subject) then pcall(mgr.HideAlert, mgr, item) end
  end
end

ns.RegisterCommand{
  name = "procs",
  args = "[on|off]",
  desc = "Blizzard's proc glow on rows this addon already speaks for",
  handler = function(rest)
    local word = string.lower(string.match(rest or "", "^(%S*)"))
    if word == "" then
      ns.Printf("Blizzard proc glows are %s on rows with a rule. `/sg procs off` hides them.",
        Procs.Enabled() and "HIDDEN" or "shown")
      return
    end
    if word ~= "on" and word ~= "off" then
      ns.Print("`/sg procs on` shows them, `/sg procs off` hides them.")
      return
    end
    ns.Store.SetSetting("suppressProcs", word == "off")
    Procs.Refresh()
    ns.Printf("Blizzard proc glows are now %s on rows with a rule%s.",
      Procs.Enabled() and "HIDDEN" or "shown",
      Procs.Enabled() and "" or " -- /reload to bring back any already hidden")
  end,
}
