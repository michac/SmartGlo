-- The sealed power bind: a PRIMARY resource, which the addon decides against and never reads.
--
-- `UnitPower` is `SecretWhenUnitPowerRestricted`, so a Fury threshold can never be a gate.
-- What it can be is a curve: `UnitPowerPercent(unit, powerType, usePredicted, curve)` is the
-- documented sibling of the `UnitHealthPercent` next door -- same prose, same polymorphic
-- `LuaCurveEvaluatedResult` -- and it evaluates the curve in C, returning a secret that goes
-- straight into `Texture:SetAlpha`. Nothing here branches on a magnitude and there is no
-- readback. `security-taint-and-restricted-data.md` §4.8.0's worked example is a mana bar.
--
-- ⚠ The READABLE question about a primary is `affordable(<spell>)`, not a threshold, and it is
-- the one most rules want. This family exists for the question that one cannot answer:
-- `insufficientPower` is binary, false at 40 Fury and at 170 alike, so overcap and pooling are
-- reachable only from here.
--
-- A curve evaluation is a SNAPSHOT, so it is re-applied on a ticker. The ticker draws only --
-- it never evaluates a rule and never writes a capture line.

local _, ns = ...

local Power = {}
ns.Power = Power

local INTERVAL = 0.1

--- The curve's input is a FRACTION, as health's is: a full bar arrives as 1.0, not as 100.
--- Blizzard ships `CurveConstants.ScaleTo100` to convert the other way, and its own comment
--- calls that "re-scales any percentage value from [0, 1] to [0, 100]". A rule states its
--- threshold in percent, so the compile divides by this.
--- ⚠ Getting this wrong INVERTS the result rather than degrading it: a threshold written in
--- percent sits up to a hundred times above the top of the domain, so `>=` never lights and
--- `<` lights always.
local PERCENT = 100

local active = {}
local ticker
local curves = {}

--- Feature-gated as one piece, and the absent piece is NAMED rather than folded into a
--- boolean: the mark is built at alpha 0 and this module alone raises it, so a bind that never
--- armed and one that armed and evaluated dark are the same dark icon. The log separates them.
local function Missing()
  if C_CurveUtil == nil or C_CurveUtil.CreateCurve == nil then
    return "C_CurveUtil.CreateCurve"
  end
  if Enum == nil or Enum.LuaCurveType == nil then return "Enum.LuaCurveType" end
  if Enum.PowerType == nil then return "Enum.PowerType" end
  if UnitPowerPercent == nil then return "UnitPowerPercent" end
  return nil
end

--- Step is a floor, so `<` and `<=` compile to the same curve, as `>` and `>=` do. The client
--- draws in whole steps and cannot express the open end of an interval.
local function Compile(bind)
  local curve = C_CurveUtil.CreateCurve()
  curve:SetType(Enum.LuaCurveType.Step)
  local at = bind.percent / PERCENT
  if bind.cmp == ">" or bind.cmp == ">=" then
    curve:AddPoint(0, 0)
    curve:AddPoint(at, 1)
  else
    curve:AddPoint(0, 1)
    curve:AddPoint(at, 0)
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

--- The power family owns the drawn art's ALPHA -- mark and plate together, through
--- `Overlay.SetArt`, because a plate lit without its mark is a false glow. `Overlay.SetLit`
--- asks this before writing that channel, so ownership is decided once rather than per frame.
function Power.Owns(glow)
  return type(glow.bind) == "table" and glow.bind.family == "power"
end

--- What reaches the log is the CLASS of what the client handed back -- once, and again only
--- when it changes. `<secret>` means the curve was evaluated and the client owns the alpha.
---
--- ⚠ A plain NUMBER here is the useful diagnostic, and it has two causes worth telling apart:
--- the domain is not [0, 1] after all, or the player HAS NO SUCH BAR -- a `fury%` rule on a
--- Paladin. Both draw dark, which is the right answer for either, and the number in the log is
--- how the second one is recognised. That is why no class check is compiled in: a table of
--- class-to-power would be one more thing to drift against a patch, and the honest outcome is
--- already a dark mark that says why.
---
--- Keyed by the GLOW and not by the entry: `Refresh` rebuilds every entry from scratch, so a
--- memory living on the entry is new every time and dedups nothing.
local lastClass = setmetatable({}, { __mode = "k" })
local lastArmed = nil

local function Class(entry, text)
  if lastClass[entry.glow] == text then return end
  lastClass[entry.glow] = text
  ns.log:Mark("power %s %s -> %s", ns.Capture.Safe(ns.Rules.Label(entry.glow.subject)),
    ns.Capture.Safe(ns.Rules.DescribeBind(entry.glow.bind)), text)
end

--- ⚠ `usePredicted` is false for the same reason health's is: the rule is about the resource
--- you have, not the one a cast in flight will leave you.
local function Apply(entry)
  local pt = ns.Rules.PrimaryPowerType(entry.glow.bind.power)
  if pt == nil then
    ns.Overlay.SetArt(entry.element, 0)
    Class(entry, "no Enum.PowerType for " .. tostring(entry.glow.bind.power))
    return
  end
  local ok, value = pcall(UnitPowerPercent, "player", pt, false, CurveFor(entry.glow.bind))
  if not ok then
    -- A refused evaluation is not a zero: it is the client declining, and a mark drawn on a
    -- fabricated zero would be a wrong answer rather than a missing one.
    ns.Overlay.SetArt(entry.element, 0)
    Class(entry, "refused -- " .. ns.Capture.Safe(value))
    return
  end
  -- Neither a secret nor a number is not an alpha: writing it raises inside the ticker, and
  -- writing a zero instead would report a resource this never read.
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
--- The ticker exists only while a sealed power bind is on screen.
function Power.Refresh()
  active = {}
  local missing, owned = Missing(), 0
  for _, glow in ipairs(ns.Store.All()) do
    if Power.Owns(glow) then
      owned = owned + 1
      if missing == nil then
        active[#active + 1] = { glow = glow, element = ns.Overlay.Element(glow) }
      end
    end
  end
  local armed = ("%s/%s"):format(tostring(missing), owned)
  if armed ~= lastArmed then
    lastArmed = armed
    if owned > 0 and missing ~= nil then
      ns.log:Mark("power binds UNAVAILABLE -- %s is absent; %d mark(s) stay dark",
        ns.Capture.Safe(missing), owned)
    elseif owned > 0 then
      ns.log:Mark("power binds armed: %d", owned)
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
function Power.Describe(bind)
  local at = bind.percent / PERCENT
  if bind.cmp == ">" or bind.cmp == ">=" then
    return ("[sealed] Step (0,0) (%s,1)"):format(at)
  end
  return ("[sealed] Step (0,1) (%s,0)"):format(at)
end
