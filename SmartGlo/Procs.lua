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

local DIM = 0.25

--- The alert the client would have drawn is taken away whole, and this is what goes back in
--- its place: the same template, the same animation machinery, the atlas pair Blizzard itself
--- swaps in for a one-button alert. A fat rounded square becomes a thin shield outline, so the
--- two never read alike on one icon.
local ALT_START = "OneButton_ProcStart_Flipbook"
local ALT_LOOP = "OneButton_ProcLoop_Flipbook"

--- ⚠ The hue is baked into both flipbooks, so a tint only reaches another colour through
--- `SetDesaturated`. Whether the pair survives the FlipBook animation is not measured;
--- `Procs.Describe` reports our frame too, so a snapshot answers it. If the write does not
--- hold the art is still the shield rather than the square, which is the difference that
--- matters.
local TINT = { 0.45, 0.85, 1.0 }

--- Ours, parented to the row and never entered in the client's `activeAlerts`, so nothing
--- Blizzard runs re-asserts anything on it. Built the way the client builds its second alert
--- frame `[T1 src @12.1.0: ActionButtonSpellAlerts.lua:26-33]`.
local ours = setmetatable({}, { __mode = "k" })

--- Whether the client wanted an alert here, read from its own answer at the moment it decided
--- and remembered because taking the alert away destroys the evidence.
local wanted = setmetatable({}, { __mode = "k" })

local function Manager()
  local mgr = _G["ActionButtonSpellAlertManager"]
  if type(mgr) ~= "table" or type(mgr.HideAlert) ~= "function" then return nil end
  return mgr
end

--- Every region the alert frame actually draws with, ENUMERATED rather than named. The
--- template's three flipbook keys were assumed and dimming them changed nothing, which a
--- name-based list cannot tell apart from "those keys are not on this frame".
local function Regions(frame)
  local out = {}
  if type(frame.GetRegions) ~= "function" then return out end
  local ok, regions = pcall(function() return { frame:GetRegions() } end)
  if ok then
    for _, region in ipairs(regions) do out[#out + 1] = region end
  end
  -- Child FRAMES too. A glow drawn one level down would survive every write aimed at this
  -- frame's own regions, and look exactly like a write that did not land.
  local gotKids, kids = pcall(function() return { frame:GetChildren() } end)
  if gotKids then
    for _, kid in ipairs(kids) do out[#out + 1] = kid end
  end
  return out
end

--- A region's identity as the log prints it: its parent key if it has one, else its type.
local function NameOf(frame, region)
  for key, value in pairs(frame) do
    if value == region and type(key) == "string" then return key end
  end
  local ok, kind = pcall(region.GetObjectType, region)
  return ok and tostring(kind) or "?"
end

--- Alpha as the frame reports it, as it lands after the parent chain, and whether the region
--- has opted out of that chain. The three together are what separate "the write was refused"
--- from "the write took and something downstream ignores it".
local function AlphaOf(region)
  local gotOwn, own = pcall(region.GetAlpha, region)
  if not gotOwn then return "alpha refused -- " .. ns.Capture.Safe(own) end
  local gotEff, eff = pcall(region.GetEffectiveAlpha, region)
  if not gotEff then eff = "?" end
  local gotIgn, ign = pcall(region.IsIgnoringParentAlpha, region)
  if not gotIgn then ign = "?" end
  return ("a=%s eff=%s ignoreParent=%s"):format(ns.Capture.Safe(own), ns.Capture.Safe(eff),
    ns.Capture.Safe(ign))
end

--- Every region of one alert frame, with the two things a capture has to tell apart: whether
--- a write landed, and whether anything downstream is dropping it.
local function Chain(frame)
  local regions = Regions(frame)
  local parts = { ("%d region(s), frame %s"):format(#regions, AlphaOf(frame)) }
  for _, region in ipairs(regions) do
    local gotShown, shown = pcall(region.IsShown, region)
    local atlas = ""
    if type(region.GetAtlas) == "function" then
      local gotAtlas, name = pcall(region.GetAtlas, region)
      if gotAtlas and name ~= nil then atlas = " " .. ns.Capture.Safe(name) end
    end
    local tint = ""
    if type(region.GetVertexColor) == "function" then
      local gotTint, r, g, b = pcall(region.GetVertexColor, region)
      if gotTint and r ~= nil then
        tint = (" rgb=%.2f/%.2f/%.2f"):format(r, g or 0, b or 0)
      end
    end
    parts[#parts + 1] = ("%s%s%s %s shown=%s"):format(NameOf(frame, region), atlas, tint,
      AlphaOf(region), gotShown and ns.Capture.Safe(shown) or "?")
  end
  return table.concat(parts, "; ")
end

--- Both alerts on this row: the client's, and the one we put in its place. Blank is not an
--- outcome -- every path through here names itself, and "ours: none" on a row the client
--- wanted to alert is a different bug from "ours: drawn at 0".
function Procs.Describe(item)
  local mgr = Manager()
  if mgr == nil then return "no alert manager" end
  if type(mgr.HasAlert) ~= "function" then return "manager has no HasAlert" end
  local ok, has, kind = pcall(mgr.HasAlert, mgr, item)
  if not ok then return "HasAlert refused -- " .. ns.Capture.Safe(has) end
  local parts = {}
  if not has then
    parts[#parts + 1] = "client: no alert"
  else
    local frame = item.SpellActivationAlert
    if type(frame) ~= "table" or type(frame.GetAlpha) ~= "function" then
      parts[#parts + 1] = ("client: alert type %s, no Default frame parked"):format(
        tostring(kind))
    else
      parts[#parts + 1] = ("client: alert type %s, %s"):format(tostring(kind), Chain(frame))
    end
  end
  local mine = ours[item]
  if mine == nil then
    parts[#parts + 1] = "ours: none built"
  else
    local gotShown, shown = pcall(mine.IsShown, mine)
    parts[#parts + 1] = ("ours: shown=%s %s"):format(
      gotShown and ns.Capture.Safe(shown) or "?", Chain(mine))
  end
  parts[#parts + 1] = ("client wanted an alert: %s"):format(tostring(wanted[item] == true))
  return table.concat(parts, " | ")
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

local function OurAlert(item)
  local frame = ours[item]
  if frame ~= nil then return frame end
  local made, built = pcall(CreateFrame, "Frame", nil, item, "ActionButtonSpellAlertTemplate")
  if not made then
    ns.log:Mark("procs: our alert frame refused -- %s", ns.Capture.Safe(built))
    return nil
  end
  local sized, why = pcall(function()
    local w, h = item:GetSize()
    built:SetSize(w * 1.4, h * 1.4)
    built:SetPoint("CENTER", item, "CENTER", 0, 0)
  end)
  if not sized then ns.log:Mark("procs: our alert sizing refused -- %s", ns.Capture.Safe(why)) end
  for key, atlas in pairs({ ProcStartFlipbook = ALT_START, ProcLoopFlipbook = ALT_LOOP }) do
    local tex = built[key]
    if type(tex) == "table" then
      local ok, err = pcall(tex.SetAtlas, tex, atlas)
      if not ok then ns.log:Mark("procs: %s atlas refused -- %s", key, ns.Capture.Safe(err)) end
      local gotDes, desErr = pcall(tex.SetDesaturated, tex, true)
      if not gotDes then
        ns.log:Mark("procs: %s desaturate refused -- %s", key, ns.Capture.Safe(desErr))
      end
      local gotTint, tintErr = pcall(tex.SetVertexColor, tex, TINT[1], TINT[2], TINT[3])
      if not gotTint then
        ns.log:Mark("procs: %s tint refused -- %s", key, ns.Capture.Safe(tintErr))
      end
    end
  end
  ours[item] = built
  return built
end

--- The loop is played by hand, and the birth is skipped outright. `ProcLoopFlipbook` ships at
--- alpha 0 and only the loop's own first element raises it, so a frame that is merely shown
--- draws NOTHING -- and the mixin's replay cannot be relied on, because the template registers
--- its `OnShow` handler against the `OnHide` script `[T1 src @12.1.0:
--- ActionButtonSpellAlerts.xml:13, 22-26, 34-38]`. Skipping the birth is also the quieter
--- reading, and it is what the Cooldown Manager itself asks for on a refresh
--- `[T1 src @12.1.0: CooldownViewer.lua:1237-1238]`.
local function ShowOurs(item, alpha)
  local frame = OurAlert(item)
  if frame == nil then return end
  local set, why = pcall(frame.SetAlpha, frame, alpha)
  if not set then ns.log:Mark("procs: our alpha refused -- %s", ns.Capture.Safe(why)) end
  local gotShown, shown = pcall(frame.IsShown, frame)
  if not (gotShown and shown) then
    local ok, err = pcall(frame.Show, frame)
    if not ok then ns.log:Mark("procs: our alert show refused -- %s", ns.Capture.Safe(err)) end
  end
  local gotLoop, playing = pcall(frame.ProcLoop.IsPlaying, frame.ProcLoop)
  if gotLoop and playing then return end
  local ok, err = pcall(frame.ProcLoop.Play, frame.ProcLoop)
  if not ok then ns.log:Mark("procs: our loop refused -- %s", ns.Capture.Safe(err)) end
end

local function HideOurs(item)
  local frame = ours[item]
  if frame == nil then return end
  local gotShown, shown = pcall(frame.IsShown, frame)
  if gotShown and not shown then return end
  local ok, err = pcall(function()
    frame.ProcLoop:Stop()
    frame:Hide()
  end)
  if not ok then ns.log:Mark("procs: our alert hide refused -- %s", ns.Capture.Safe(err)) end
end

--- Whether the client wants a proc glow here, asked of the client. This is the same read
--- `RefreshOverlayGlow` makes before it decides `[T1 src @12.1.0: CooldownViewer.lua:1241-1242]`,
--- so it stays true while the proc is up and does not go dark the moment we take the alert
--- away. The remembered answer is the fallback for a refused read, never the primary.
local function Overlayed(item, subject)
  local id = subject
  if type(item.GetSpellID) == "function" then
    local gotID, own = pcall(item.GetSpellID, item)
    if gotID and type(own) == "number" then id = own end
  end
  if type(id) ~= "number" then return wanted[item] == true end
  local ok, on = pcall(C_SpellActivationOverlay.IsSpellOverlayed, id)
  if not ok then
    ns.log:Mark("procs: IsSpellOverlayed refused -- %s", ns.Capture.Safe(on))
    return wanted[item] == true
  end
  return on == true
end

--- ⚠ The hide is UNCONDITIONAL whenever the dial is set. It is the one channel that has
--- always worked, it runs from the evaluation pass rather than from the hook, and putting any
--- remembered flag in front of it is what broke `off`. `HideAlert` on a row with no alert is
--- already a no-op, so there is nothing to guard against.
local function ApplyTo(item, subject)
  local alpha = Procs.Alpha()
  if alpha == nil then
    HideOurs(item)
    return
  end
  local mgr = Manager()
  if mgr ~= nil then
    local ok, err = pcall(mgr.HideAlert, mgr, item)
    if not ok then ns.log:Mark("procs: HideAlert refused -- %s", ns.Capture.Safe(err)) end
  end
  if alpha <= 0 or not Overlayed(item, subject) then
    HideOurs(item)
    return
  end
  ShowOurs(item, alpha)
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
  local mgr = Manager()
  if mgr ~= nil then
    -- Read BEFORE `ApplyTo`, which hides the alert and with it the answer.
    local ok, has = pcall(mgr.HasAlert, mgr, item)
    if not ok then
      ns.log:Mark("procs: HasAlert refused -- %s", ns.Capture.Safe(has))
    else
      wanted[item] = has == true
    end
  end
  Reason(item, ("applying to %s"):format(ns.SpellLabel(subject)))
  ApplyTo(item, subject)
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

--- Ours goes away; the client's own alert comes back on its next `RefreshOverlayGlow`,
--- because taking it out of `activeAlerts` is exactly what makes the next `ShowAlert` fire.
local function RestoreAll()
  for subject, item in pairs(ns.Attach.Bound()) do
    if ns.Store.Speaks(subject) then HideOurs(item) end
  end
end

--- Sweeps for the moment the setting changes rather than the moment a proc fires.
function Procs.Refresh()
  if not Procs.Enabled() then return end
  for subject, item in pairs(ns.Attach.Bound()) do
    if ns.Store.Speaks(subject) then ApplyTo(item, subject) end
  end
end

--- The DIAL, in words. `Procs.Describe` answers about one row's alert; this answers about the
--- setting that governs all of them, and a snapshot needs both.
function Procs.Setting()
  local alpha = Procs.Alpha()
  if alpha == nil then return "shown" end
  if alpha <= 0 then return "HIDDEN" end
  return string.format("REPLACED at %d%%", math.floor(alpha * 100 + 0.5))
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
  desc = "Blizzard's proc glow on rows this addon already speaks for -- hide it, or replace it",
  handler = function(rest)
    local word = string.lower(string.match(rest or "", "^(%S*)"))
    if word == "" then
      ns.Printf("Blizzard proc glows are %s on rows with a rule. `/sg procs dim` swaps in "
        .. "a quieter mark of our own, `/sg procs off` hides them outright.", Procs.Setting())
      return
    end
    local alpha
    if word == "on" then alpha = false
    elseif word == "dim" then alpha = DIM
    elseif word == "off" then alpha = 0
    else alpha = AlphaFrom(word) end
    if alpha == nil then
      ns.Print("`/sg procs on|dim|off`, or a level for the replacement: `/sg procs 40`.")
      return
    end
    if alpha == false then
      RestoreAll()
      ns.Store.SetSetting("procAlpha", nil)
      ns.Store.SetSetting("suppressProcs", nil)
      ns.Print("Blizzard proc glows are now shown on rows with a rule.")
      return
    end
    ns.Store.SetSetting("procAlpha", alpha)
    ns.Store.SetSetting("suppressProcs", nil)
    Procs.Refresh()
    ns.Printf("Blizzard proc glows are now %s on rows with a rule.", Procs.Setting())
  end,
}
