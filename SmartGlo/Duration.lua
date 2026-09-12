-- The sealed duration bind: a cooldown the addon decides against and never reads.
--
-- `C_Spell.GetSpellCooldownDuration` hands back an opaque object whose remaining time is a
-- Secret Value. The comparison the rule asks for is compiled into a Step CURVE, the engine
-- evaluates it against the secret internally, and the result -- itself secret -- goes
-- straight into `Texture:SetAlpha`, which is allowed when tainted. Nothing here branches on
-- a magnitude, and there is no readback: `GetAlpha` on that texture throws afterwards.
--
-- A curve evaluation is a SNAPSHOT, not a binding, so it is re-applied on a ticker. The
-- ticker draws only -- it never evaluates a rule and never writes a capture line.

local _, ns = ...

local Duration = {}
ns.Duration = Duration

local INTERVAL = 0.1

local active = {}
local ticker
local curves = {}

--- Every piece is feature-gated together: on a client missing any of them a sealed bind
--- cannot be drawn at all, and the honest outcome is a dark mark rather than a lit one.
---
--- Which piece is absent is NAMED, not folded into a boolean: the mark is built at alpha 0
--- and this module alone raises it, so a bind that never armed and one that armed and
--- evaluated dark are the same dark icon. The log is where they come apart.
local function Missing()
  if C_CurveUtil == nil or C_CurveUtil.CreateCurve == nil then
    return "C_CurveUtil.CreateCurve"
  end
  if Enum == nil or Enum.LuaCurveType == nil then return "Enum.LuaCurveType" end
  if Enum.DurationTimeModifier == nil then return "Enum.DurationTimeModifier" end
  if C_Spell == nil or C_Spell.GetSpellCooldownDuration == nil then
    return "C_Spell.GetSpellCooldownDuration"
  end
  return nil
end

--- A READY spell still hands back a duration object, one reading zero remaining -- readiness
--- is a VALUE here, not an absent object -- so the `absent` tail never fires for it and a band
--- that starts at zero glows permanently while the spell is up. Every curve whose low end
--- lights therefore opens just above zero. ElvUI guards the same edge with the same epsilon.
local READY = 0.001

--- Step is a floor, so `>` and `>=` compile to the SAME curve: the client draws in whole
--- steps and cannot express the open end of an interval. Normalising says so rather than
--- pretending to a distinction that would silently not exist.
---
--- `outside lo..hi` is one bind and one curve -- three points, two transitions.
local function Compile(bind)
  local curve = C_CurveUtil.CreateCurve()
  curve:SetType(Enum.LuaCurveType.Step)
  if bind.cmp == ">" or bind.cmp == ">=" then
    curve:AddPoint(0, 0)
    curve:AddPoint(bind.seconds, 1)
    return curve
  end
  -- A threshold at or under the guard leaves no band to light, and dark is the honest outcome.
  local opens = bind.cmp == "outside" and bind.lo or bind.seconds
  curve:AddPoint(0, 0)
  if opens > READY then curve:AddPoint(READY, 1) end
  if bind.cmp == "outside" then
    curve:AddPoint(bind.lo, 0)
    curve:AddPoint(bind.hi, 1)
  else
    curve:AddPoint(bind.seconds, 0)
  end
  return curve
end

local function CurveFor(bind)
  local key = ns.Rules.DescribeBind(bind)
  local curve = curves[key]
  if curve == nil then
    curve = Compile(bind)
    curves[key] = curve
  end
  return curve
end

--- The duration family is the sealed family that owns the drawn art's ALPHA -- mark and plate
--- together, through `Overlay.SetArt`, because a plate lit without its mark is a false glow.
--- `Overlay.SetLit` asks this before writing that channel, so ownership is decided once
--- rather than per frame.
function Duration.Owns(glow)
  return type(glow.bind) == "table" and glow.bind.family == "duration"
end

--- ⚠ With the spell READY there is no duration object, and both `<` and `outside` map zero
--- remaining to alpha 1 -- so the absent case is the bright one, which is worse than dark.
--- The checker refuses such a bind unless the rule answers for it; this is where the answer
--- is applied, and the default with no answer is dark.
local function ApplyAbsent(entry)
  ns.Overlay.SetArt(entry.element, entry.glow.bind.absent == "show" and 1 or 0)
end

--- The ticker draws and never writes a line, so what reaches the log is the CLASS of what the
--- client handed back -- once, and again only when it changes. `<secret>` means the curve was
--- evaluated and the client owns the alpha; a plain number means it did not seal.
---
--- Keyed by the GLOW and not by the entry: `Refresh` rebuilds every entry from scratch and is
--- called from each attach evaluation, so a memory living on the entry is new every time and
--- dedups nothing. That flooded the capture ring and evicted everything worth reading.
local lastClass = setmetatable({}, { __mode = "k" })
local lastArmed = nil

local function Class(entry, text)
  if lastClass[entry.glow] == text then return end
  lastClass[entry.glow] = text
  ns.log:Mark("duration %s %s -> %s", ns.Capture.Safe(ns.Rules.Label(entry.glow.subject)),
    ns.Capture.Safe(ns.Rules.DescribeBind(entry.glow.bind)), text)
end

--- The three ways there is no duration object stay apart: the client refusing the call, the
--- spell having no cooldown running, and an object of a shape this cannot drive are different
--- facts that reach the same dark mark.
local function Apply(entry)
  local bind = entry.glow.bind
  -- `ignoreGCD` TRUE. The GCD-inclusive form hands back a live duration object for a spell
  -- that is merely mid-global-cooldown, so a `<` rung lights for 1.5s after every cast on a
  -- spell that is actually up -- "a GCD-only cooldown must never read as real unavailability"
  -- (cdm-rider-patterns.md).
  local ok, durObj = pcall(C_Spell.GetSpellCooldownDuration, bind.spell, true)
  if not ok then
    Class(entry, "refused -- " .. ns.Capture.Safe(durObj))
    ApplyAbsent(entry)
    return
  end
  if durObj == nil then
    Class(entry, "no duration object -- spell is ready")
    ApplyAbsent(entry)
    return
  end
  if durObj.EvaluateRemainingDuration == nil then
    Class(entry, "object has no EvaluateRemainingDuration")
    ApplyAbsent(entry)
    return
  end
  local okEval, value = pcall(durObj.EvaluateRemainingDuration, durObj, CurveFor(bind),
    Enum.DurationTimeModifier.RealTime)
  if not okEval then
    -- A refused evaluation is not a zero: it is the client declining, and a mark drawn on a
    -- fabricated zero would be a wrong answer rather than a missing one.
    ns.Overlay.SetArt(entry.element, 0)
    Class(entry, "evaluate refused -- " .. ns.Capture.Safe(value))
    return
  end
  -- Neither a secret nor a number is not an alpha: writing it raises inside the ticker, and
  -- writing a zero instead would report a cooldown this never read.
  if not ns.IsSecret(value) and type(value) ~= "number" then
    ns.Overlay.SetArt(entry.element, 0)
    Class(entry, "not an alpha -- " .. ns.Capture.Safe(value))
    return
  end
  Class(entry, ns.Capture.Safe(value))
  ns.Overlay.SetArt(entry.element, value)
end

local function Tick()
  for _, entry in ipairs(active) do Apply(entry) end
end

--- Called from the attach evaluation, which is where the set of glows and their gates change.
--- The ticker exists only while a sealed duration is on screen.
function Duration.Refresh()
  active = {}
  local missing, owned = Missing(), 0
  for _, glow in ipairs(ns.Store.All()) do
    if Duration.Owns(glow) then
      owned = owned + 1
      if missing == nil then
        active[#active + 1] = { glow = glow, element = ns.Overlay.Element(glow) }
      end
    end
  end
  -- Also on change only, and for the same reason: this runs on every evaluation.
  local armed = ("%s/%s"):format(tostring(missing), owned)
  if armed ~= lastArmed then
    lastArmed = armed
    if owned > 0 and missing ~= nil then
      ns.log:Mark("duration binds UNAVAILABLE -- %s is absent; %d mark(s) stay dark",
        ns.Capture.Safe(missing), owned)
    elseif owned > 0 then
      ns.log:Mark("duration binds armed: %d", owned)
    end
  end
  if #active > 0 then
    if ticker == nil then ticker = C_Timer.NewTicker(INTERVAL, Tick) end
    Tick()
  elseif ticker ~= nil then
    ticker:Cancel()
    ticker = nil
  end
end

--- What `/sg why` can honestly say about a sealed bind: the points it compiled to. There is
--- no readback of what the client drew, so the compiled curve is the whole story.
function Duration.Describe(bind)
  if bind.cmp == ">" or bind.cmp == ">=" then
    return ("[sealed] Step (0,0) (%s,1)"):format(bind.seconds)
  end
  local opens = bind.cmp == "outside" and bind.lo or bind.seconds
  local guard = opens > READY and ("(%s,1) "):format(READY) or ""
  if bind.cmp == "outside" then
    return ("[sealed] Step (0,0) %s(%s,0) (%s,1)"):format(guard, bind.lo, bind.hi)
  end
  return ("[sealed] Step (0,0) %s(%s,0)"):format(guard, bind.seconds)
end
