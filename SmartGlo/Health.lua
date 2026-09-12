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

--- The curve's input is a FRACTION: full health arrives as 1.0, not as 100. Blizzard ships
--- `CurveConstants.ScaleTo100` to convert it, a Linear curve from (0.0, 0) to (1.0, 100),
--- and its own comment calls that "re-scales any percentage value from [0, 1] to [0, 100]"
--- (`security-taint-and-restricted-data.md` §4.12). A rule states its threshold in percent,
--- so the compile divides by this.
local PERCENT = 100

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
  if UnitHealthPercent == nil then return "UnitHealthPercent" end
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

--- The health family is a sealed family that owns the drawn art's ALPHA -- mark and plate
--- together, through `Overlay.SetArt`, because a plate lit without its mark is a false glow.
--- `Overlay.SetLit` asks this before writing that channel, so ownership is decided once
--- rather than per frame.
function Health.Owns(glow)
  return type(glow.bind) == "table" and glow.bind.family == "health"
end

--- The ticker draws and never writes a line, so what reaches the log is the CLASS of what the
--- client handed back -- once, and again only when it changes. `<secret>` means the curve was
--- evaluated and the client owns the alpha. A plain NUMBER means it did not seal, and then
--- the number says which scale the input is on, which no eyeball can report.
---
--- Keyed by the GLOW and not by the entry: `Refresh` rebuilds every entry from scratch and is
--- called from each attach evaluation, so a memory living on the entry is new every time and
--- dedups nothing. That flooded the capture ring and evicted everything worth reading.
local lastClass = setmetatable({}, { __mode = "k" })
local lastArmed = nil

local function Class(entry, text)
  if lastClass[entry.glow] == text then return end
  lastClass[entry.glow] = text
  ns.log:Mark("health %s %s -> %s", ns.Capture.Safe(ns.Rules.Label(entry.glow.subject)),
    ns.Capture.Safe(ns.Rules.DescribeBind(entry.glow.bind)), text)
end

--- ⚠ `usePredicted` is false on purpose: incoming heals would otherwise move the mark for a
--- cast that has not landed, and the rule is about the health you have.
local function Apply(entry)
  local ok, value = pcall(UnitHealthPercent, "player", false, CurveFor(entry.glow.bind))
  if not ok then
    -- A refused evaluation is not a zero: it is the client declining, and a mark drawn on a
    -- fabricated zero would be a wrong answer rather than a missing one.
    ns.Overlay.SetArt(entry.element, 0)
    Class(entry, "refused -- " .. ns.Capture.Safe(value))
    return
  end
  -- Neither a secret nor a number is not an alpha: writing it raises inside the ticker, and
  -- writing a zero instead would report a health this never read.
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
--- The ticker exists only while a sealed health bind is on screen.
function Health.Refresh()
  active = {}
  local missing, owned = Missing(), 0
  for _, glow in ipairs(ns.Store.All()) do
    if Health.Owns(glow) then
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
      ns.log:Mark("health binds UNAVAILABLE -- %s is absent; %d mark(s) stay dark",
        ns.Capture.Safe(missing), owned)
    elseif owned > 0 then
      ns.log:Mark("health binds armed: %d", owned)
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
  local at = bind.percent / PERCENT
  if bind.cmp == ">" or bind.cmp == ">=" then
    return ("[sealed] Step (0,0) (%s,1)"):format(at)
  end
  return ("[sealed] Step (0,1) (%s,0)"):format(at)
end
