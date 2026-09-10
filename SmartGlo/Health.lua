-- The sealed health bind: the player's health, which the addon decides against and never reads.
--
-- `UnitHealth` is one of the unconditionally-secret functions -- there is no restriction state
-- in which it hands tainted code a number -- so a health threshold can never be a gate. What
-- it can be is a curve: `UnitHealthPercent(unit, usePredicted, curve)` evaluates the curve
-- against the percentage in C and returns the result, itself secret, which goes straight into
-- `Texture:SetAlpha`. Nothing here branches on a magnitude and there is no readback.
--
-- A curve evaluation is a SNAPSHOT, so it is re-applied on a ticker. The ticker draws only --
-- it never evaluates a rule and never writes a capture line.

local _, ns = ...

local Health = {}
ns.Health = Health

local INTERVAL = 0.1

--- The input scale is UNMEASURED. The documentation says "percent of health remaining", and
--- no Blizzard caller passes a curve to this function, so whether full health arrives as 100
--- or as 1 is a guess until an eyeball settles it.
---
--- The curves below are shaped so that the WRONG guess fails DARK. A `<` rule wants alpha at
--- LOW input, which on a 0..1 scale would be every input there is -- permanently bright, the
--- one failure worse than none. The guard point at 1.001 takes that whole range back to 0, so
--- on a 0..1 client the mark simply never lights. It costs the 0..1% band on a 0..100 client,
--- which is a health total nobody survives to look at.
local ZERO_TO_ONE = 1.001

local active = {}
local ticker
local curves = {}

--- Every piece is feature-gated together: on a client missing any of them a sealed bind
--- cannot be drawn at all, and the honest outcome is a dark mark rather than a lit one.
local function Available()
  return C_CurveUtil ~= nil and C_CurveUtil.CreateCurve ~= nil
    and Enum ~= nil and Enum.LuaCurveType ~= nil and UnitHealthPercent ~= nil
end

--- Step is a floor, so `<` and `<=` compile to the same curve, as `>` and `>=` do. The client
--- draws in whole steps and cannot express the open end of an interval.
local function Compile(bind)
  local curve = C_CurveUtil.CreateCurve()
  curve:SetType(Enum.LuaCurveType.Step)
  if bind.cmp == ">" or bind.cmp == ">=" then
    -- Alpha at HIGH input, so a 0..1 scale lands below the threshold and reads dark already.
    curve:AddPoint(0, 0)
    curve:AddPoint(bind.percent, 1)
  else
    curve:AddPoint(0, 0)
    curve:AddPoint(ZERO_TO_ONE, 1)
    curve:AddPoint(bind.percent, 0)
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

--- The health family is a sealed family that owns a mark's ALPHA. `Overlay.SetLit` asks this
--- before writing that channel, so ownership is decided once rather than per frame.
function Health.Owns(glow)
  return type(glow.bind) == "table" and glow.bind.family == "health"
end

--- ⚠ `usePredicted` is false on purpose: incoming heals would otherwise move the mark for a
--- cast that has not landed, and the rule is about the health you have.
local function Apply(entry)
  local ok, value = pcall(UnitHealthPercent, "player", false, CurveFor(entry.glow.bind))
  if not ok then
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
--- The ticker exists only while a sealed health bind is on screen.
function Health.Refresh()
  active = {}
  if Available() then
    for _, glow in ipairs(ns.Store.All()) do
      if Health.Owns(glow) then
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
function Health.Describe(bind)
  if bind.cmp == ">" or bind.cmp == ">=" then
    return ("[sealed] Step (0,0) (%s,1)"):format(bind.percent)
  end
  return ("[sealed] Step (0,0) (%s,1) (%s,0)"):format(ZERO_TO_ONE, bind.percent)
end
