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
local function Available()
  return C_CurveUtil ~= nil and C_CurveUtil.CreateCurve ~= nil
    and Enum ~= nil and Enum.LuaCurveType ~= nil and Enum.DurationTimeModifier ~= nil
    and C_Spell ~= nil and C_Spell.GetSpellCooldownDuration ~= nil
end

--- Step is a floor, so `>` and `>=` compile to the SAME curve: the client draws in whole
--- steps and cannot express the open end of an interval. Normalising says so rather than
--- pretending to a distinction that would silently not exist.
---
--- `outside lo..hi` is one bind and one curve -- three points, two transitions.
local function Compile(bind)
  local curve = C_CurveUtil.CreateCurve()
  curve:SetType(Enum.LuaCurveType.Step)
  if bind.cmp == "outside" then
    curve:AddPoint(0, 1)
    curve:AddPoint(bind.lo, 0)
    curve:AddPoint(bind.hi, 1)
  elseif bind.cmp == ">" or bind.cmp == ">=" then
    curve:AddPoint(0, 0)
    curve:AddPoint(bind.seconds, 1)
  else
    curve:AddPoint(0, 1)
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

--- The duration family is the sealed family that owns a mark's ALPHA. `Overlay.SetLit` asks
--- this before writing that channel, so ownership is decided once rather than per frame.
function Duration.Owns(glow)
  return type(glow.bind) == "table" and glow.bind.family == "duration"
end

--- ⚠ With the spell READY there is no duration object, and both `<` and `outside` map zero
--- remaining to alpha 1 -- so the absent case is the bright one, which is worse than dark.
--- The checker refuses such a bind unless the rule answers for it; this is where the answer
--- is applied, and the default with no answer is dark.
local function ApplyAbsent(entry)
  entry.element.mark:SetAlpha(entry.glow.bind.absent == "show" and 1 or 0)
end

local function Apply(entry)
  local bind = entry.glow.bind
  local ok, durObj = pcall(C_Spell.GetSpellCooldownDuration, bind.spell, false)
  if not ok or durObj == nil or durObj.EvaluateRemainingDuration == nil then
    ApplyAbsent(entry)
    return
  end
  local okEval, value = pcall(durObj.EvaluateRemainingDuration, durObj, CurveFor(bind),
    Enum.DurationTimeModifier.RealTime)
  if not okEval then
    -- A refused evaluation is not a zero: it is the client declining, and a mark drawn on a
    -- fabricated zero would be a wrong answer rather than a missing one.
    entry.element.mark:SetAlpha(0)
    return
  end
  entry.element.mark:SetAlpha(value)
end

local function Tick()
  for _, entry in ipairs(active) do Apply(entry) end
end

--- Called from the attach evaluation, which is where the set of glows and their gates change.
--- The ticker exists only while a sealed duration is on screen.
function Duration.Refresh()
  active = {}
  if Available() then
    for _, glow in ipairs(ns.Store.All()) do
      if Duration.Owns(glow) then
        active[#active + 1] = { glow = glow, element = ns.Overlay.Element(glow) }
      end
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
  if bind.cmp == "outside" then
    return ("[sealed] Step (0,1) (%s,0) (%s,1)"):format(bind.lo, bind.hi)
  end
  if bind.cmp == ">" or bind.cmp == ">=" then
    return ("[sealed] Step (0,0) (%s,1)"):format(bind.seconds)
  end
  return ("[sealed] Step (0,1) (%s,0)"):format(bind.seconds)
end
