-- The in-flight cast, and what it will do to a secondary resource when it lands.
--
-- A rule can ask for the count AFTER the current cast: `soul_shards.after_cast >= 3`. The
-- cost is debited at COMPLETION, not at cast start, so mid-cast the bar still shows the
-- pre-cast count and the projection applies both halves at once -- subtract the cost, add
-- the gain.
--
-- The player's own cast id is READABLE. `SecretWhenUnitSpellCastRestricted` seals a cast
-- field when the unit being asked about is not the player or their pet, which is a test on
-- WHICH UNIT and not on combat (cdm-rider-patterns.md 9.2). A per-spell flag still overrides
-- that in either direction, so every id is guarded before it is used as a key.

local _, ns = ...

local Cast = {}
ns.Cast = Cast

--- Only a HARD cast opens a window: `UNIT_SPELLCAST_START` does not fire for an instant,
--- which is exactly the wanted behaviour -- an instant's result is already in the bar by the
--- time anything could read it, so there is nothing to project.
local OPENS = { UNIT_SPELLCAST_START = true }

--- Every way a cast can end, because the window has to close on all of them. Without the
--- failure edges a cancelled cast keeps projecting its cost for as long as the client stays
--- quiet.
local CLOSES = {
  UNIT_SPELLCAST_SUCCEEDED = true,
  UNIT_SPELLCAST_INTERRUPTED = true,
  UNIT_SPELLCAST_FAILED = true,
  UNIT_SPELLCAST_FAILED_QUIET = true,
  UNIT_SPELLCAST_STOP = true,
}

--- What `Rules.Triggers` asks for on behalf of a projected term. The attach path registers
--- every `UNIT_` trigger against "player", which is the only unit whose id reads plain.
Cast.EVENTS = {
  "UNIT_SPELLCAST_START",
  "UNIT_SPELLCAST_SUCCEEDED",
  "UNIT_SPELLCAST_INTERRUPTED",
  "UNIT_SPELLCAST_FAILED",
  "UNIT_SPELLCAST_FAILED_QUIET",
  "UNIT_SPELLCAST_STOP",
}

local inflight

--- Fed from the one event frame the attach path already owns, so the ledger is current
--- before the rules that read it run. Two frames would have no ordering between them.
function Cast.Observe(event, spellID)
  if not (OPENS[event] or CLOSES[event]) then return end
  if ns.IsSecret(spellID) or type(spellID) ~= "number" then
    -- An unreadable id cannot key the gain table, and a window left open on one would be
    -- projecting some other spell's numbers. Closing is the honest response.
    inflight = nil
    return
  end
  if OPENS[event] then
    inflight = spellID
  elseif inflight == spellID then
    inflight = nil
  end
end

--- The spell in flight, or nil. `/sg why` names it so a projected row says what it is
--- projecting past rather than only what it concluded.
function Cast.InFlight()
  return inflight
end

--- The raw-unit change the in-flight cast will make to `powerType` when it lands, or
--- `nil, why` when that is not a number.
---
--- ⚠ Two worlds, kept apart. "Nothing in flight" is a measured ZERO. "This spell's gain
--- depends on a talent" and "the cost refused" are UNKNOWN, and folding either into a zero
--- would report the plain count as though it were the projection.
function Cast.Delta(powerType)
  local spellID = inflight
  if spellID == nil then return 0 end

  local varies = ns.PowerGain.varies[powerType]
  if varies ~= nil and varies[spellID] then
    return nil, ("%s's gain is talent- or proc-dependent"):format(ns.Rules.Label(spellID))
  end

  local gains = ns.PowerGain.raw[powerType]
  local gain = (gains ~= nil and gains[spellID]) or 0

  local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
  if not ok then
    return nil, ("cost refused -- %s"):format(ns.Capture.Safe(costs))
  end
  -- The call returns nothing for a spell with no resource cost, which is a cost of zero and
  -- not a refusal: the `ok` above is what tells those apart.
  local cost = 0
  if type(costs) == "table" then
    for _, entry in ipairs(costs) do
      if entry.type == powerType then
        if ns.IsSecret(entry.minCost) or type(entry.minCost) ~= "number" then
          return nil, "cost is not a readable number"
        end
        -- `minCost` and not `cost`: the latter folds in optional cost, which the spell may
        -- spend but is not required to, so it overstates the debit.
        cost = entry.minCost
      end
    end
  end
  return gain - cost
end
