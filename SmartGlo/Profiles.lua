-- Named rule sets carried in source, so a profile can be authored outside the game.
--
-- Not SavedVariables: /reload commits those from memory before reloading, so an edit made
-- while the client is running is overwritten (anatomy-and-runtime.md:955).

local _, ns = ...

local Profiles = {}
ns.Profiles = Profiles

Profiles.list = {
  -- ⚠ Every shard threshold in both Demonology profiles is `projected`: the count as it will
  -- stand once the cast in flight lands. Shards are debited at COMPLETION, so mid-cast the bar
  -- still shows the pre-cast number and a plain threshold answers about a state that is
  -- already gone. Nothing casting projects ZERO, so these read exactly like plain thresholds
  -- while you stand still.
  demonology = {
    label = "Demonology",
    glows = {
      {
        name = "Hand of Gul'dan at three shards",
        subject = 105174,
        when = { t = "resource", power = "soul_shards", cmp = ">=", value = 3, projected = true },
      },
      -- `ready()` covers a hazard of its own: the occluder is a static copy of the icon drawn
      -- above the swipe, so a mark mid-cooldown would show an unswiped patch. The absence case
      -- is not this rule's business -- `Rules.Gate` adds the presence term on 296553 that
      -- rule-language.md §6.4 requires, and `/sg why` prints it as its own row.
      {
        name = "Implosion at six imps",
        subject = 196277,
        when = { t = "ready", spell = 196277 },
        bind = { family = "count", aura = 296553, threshold = 6 },
      },
    },
  },

  -- Transcribed from the simc `diabolist` list. Each glow is one APL line with the terms the
  -- addon cannot read dropped -- so a lit icon means "this line's readable conditions hold",
  -- never "cast this now": priority ORDER is not expressible and is not claimed.
  --
  -- Two subjects are OVERRIDE ids. Ruination replaces Hand of Gul'dan and Infernal Bolt
  -- replaces Shadow Bolt while their proc is up, so each glow attaches only in the window it
  -- is about -- which is why neither carries a gate of its own.
  ["demonology-diabolist"] = {
    label = "Demonology — Diabolist",
    glows = {
      {
        name = "Tyrant at five shards",
        subject = 265187,
        when = { t = "resource", power = "soul_shards", cmp = "==", value = 5, projected = true },
      },
      {
        name = "Hand of Gul'dan capped",
        subject = 105174,
        when = { t = "resource", power = "soul_shards", cmp = "==", value = 5, projected = true },
      },
      -- Dominion of Argus's window IS the Tyrant window -- "Summoning your Demonic Tyrant
      -- leaves open a portal to Argus for 15 sec" -- so this aura is the addon's only way to
      -- ask "is Tyrant out". The id is the row the Cooldown Manager tracks, not the talent
      -- 1276163: the talent id names no tracked row, so a latch on it would read UNKNOWN
      -- forever. It needs a Tracked Buffs checkbox, and `/sg why` says so when it is missing.
      {
        name = "Hand of Gul'dan inside the Argus window",
        subject = 105174,
        when = { t = "aura", spell = 1276166 },
      },
      {
        name = "Demonbolt on a Core below four shards",
        subject = 264178,
        when = { t = "and", terms = {
          { t = "resource", power = "soul_shards", cmp = "<", value = 4, projected = true },
          { t = "aura", spell = 264173 },
        } },
      },
      {
        name = "Infernal Bolt below three shards",
        subject = 433891,
        when = { t = "resource", power = "soul_shards", cmp = "<", value = 3, projected = true },
      },
      {
        name = "Implosion at six imps",
        subject = 196277,
        when = { t = "ready", spell = 196277 },
        bind = { family = "count", aura = 296553, threshold = 6 },
      },
      {
        name = "Ruination",
        subject = 428522,
        when = { t = "ready", spell = 428522 },
      },
      {
        name = "Grimoire: Imp Lord",
        subject = 1276452,
        when = { t = "ready", spell = 1276452 },
      },
      {
        name = "Grimoire: Fel Ravager",
        subject = 1276467,
        when = { t = "ready", spell = 1276467 },
      },
      {
        name = "Summon Doomguard",
        subject = 1276672,
        when = { t = "ready", spell = 1276672 },
      },
      -- Reign of Tyranny banks imps for the Tyrant instead, so the APL only sends
      -- Dreadstalkers on demand when it is NOT taken.
      {
        name = "Call Dreadstalkers without Reign of Tyranny",
        subject = 104316,
        when = { t = "and", terms = {
          { t = "not", term = { t = "talent", spell = 1276748 } },
          { t = "ready", spell = 104316 },
        } },
      },
    },
  },
  -- Transcribed from the simc `retribution` list. Each glow is one APL line with the terms
  -- the addon cannot read dropped -- so a lit icon means "this line's readable conditions
  -- hold", never "cast this now": priority ORDER is not expressible and is not claimed.
  --
  -- Hammer of Light and its `hammer_of_light_ready` gates are absent on purpose: they come
  -- from Light's Deliverance, a TEMPLAR talent, which this tree does not have.
  ["retribution-herald"] = {
    label = "Retribution — Herald of the Sun",
    glows = {
      {
        name = "Wake of Ashes",
        subject = 255937,
        when = { t = "ready", spell = 255937 },
      },
      {
        name = "Divine Toll",
        subject = 375576,
        when = { t = "ready", spell = 375576 },
      },
      {
        name = "Avenging Wrath",
        subject = 31884,
        when = { t = "ready", spell = 31884 },
      },
      {
        name = "Execution Sentence into Wake of Ashes",
        subject = 343527,
        when = { t = "and", terms = {
          { t = "ready", spell = 343527 },
          { t = "ready", spell = 255937 }
        } },
      },
      {
        name = "Templar's Verdict at cap",
        subject = 85256,
        when = { t = "and", terms = {
          { t = "resource", power = "holy_power", cmp = "==", value = 5 },
          { t = "not", term = { t = "ready", spell = 255937 } }
        } },
      },
      {
        name = "Divine Storm on Empyrean Power",
        subject = 53385,
        when = { t = "aura", spell = 326732 },
      },
      {
        name = "Blade of Justice on a proc",
        subject = 184575,
        when = { t = "or", terms = {
          { t = "aura", spell = 406064 },
          { t = "aura", spell = 402912 }
        } },
      },
      {
        name = "Blade of Justice held under Walk Into Light",
        subject = 184575,
        when = { t = "and", terms = {
          { t = "talent", spell = 1263782 },
          { t = "aura", spell = 31884 }
        } },
      },
    },
  },

  -- From the simc `protection` list and Method's 12.1 priority. Same contract as above: a
  -- lit icon is a rung whose readable conditions hold, not an instruction.
  --
  -- No count bind here, though `consecration,if=buff.divine_guidance.stack>=5` is the right
  -- shape for one and `Rules.Gate` now covers the absence case that ruled it out. It is left
  -- out because it is a rotation call, not because it cannot be expressed.
  ["protection-lightsmith"] = {
    label = "Protection — Lightsmith",
    glows = {
      {
        name = "Word of Glory on Shining Light",
        subject = 85673,
        when = { t = "aura", spell = 321136 },
      },
      -- The paid cast, for when you are actually hurt rather than when it is free. Health can
      -- only ever be a BIND: `UnitHealth` is unconditionally secret, so no gate can compare it
      -- and the threshold goes to the client as a curve. The readable half carries the part
      -- that can be read -- 3 Holy Power is the cost, so this is "castable".
      {
        name = "Word of Glory when hurt",
        subject = 85673,
        when = { t = "resource", power = "holy_power", cmp = ">=", value = 3 },
        bind = { cmp = "<", family = "health", percent = 80 },
      },
      -- Not `ready()`: a mark that means "this button is available" says what the icon's own
      -- swipe already says. At the cap the next charge is being thrown away, which is a
      -- decision, and the CDM's own visual-source flags answer it without a charge count.
      {
        name = "Holy Armaments capped",
        subject = 432459,
        when = { t = "at_max_charges", spell = 432459 },
      },
      {
        name = "Avenger's Shield on Glory of the Vanguard",
        subject = 31935,
        when = { t = "aura", spell = 1267203 },
      },
      {
        name = "Avenging Wrath with Divine Toll up",
        subject = 31884,
        when = { t = "and", terms = {
          { t = "ready", spell = 31884 },
          { t = "ready", spell = 375576 }
        } },
      },
      {
        name = "Divine Toll inside Avenging Wrath",
        subject = 375576,
        when = { t = "and", terms = {
          { t = "ready", spell = 375576 },
          { t = "aura", spell = 31884 }
        } },
      },
      -- Avenging Wrath and Sentinel are a CHOICE NODE, so both sides ship and the untalented
      -- one cannot fire: `ready()` reads UNKNOWN for a spell you do not know, and its row is
      -- never laid out. The APL is no guide here -- it names Sentinel nowhere and simply plays
      -- the Avenging Wrath side -- so these two mirror the Wrath rungs onto 389539.
      -- ⚠ The buff Sentinel applies is Divine Resolve, whose id the KB does not carry. If
      -- `aura(389539)` reads `?`, that row does not carry the buff and the id is what to fix.
      {
        name = "Sentinel with Divine Toll up",
        subject = 389539,
        when = { t = "and", terms = {
          { t = "ready", spell = 389539 },
          { t = "ready", spell = 375576 }
        } },
      },
      {
        name = "Divine Toll inside Sentinel",
        subject = 375576,
        when = { t = "and", terms = {
          { t = "ready", spell = 375576 },
          { t = "aura", spell = 389539 }
        } },
      },
      -- The BUILDERS. `judgment,if=full_recharge_time<=gcd*2` is a "you are about to waste a
      -- charge" rung, and at-the-cap is its readable half: strictly later than the APL's, so
      -- it under-marks rather than over-marks. Crusader's Judgment adds the second charge; on
      -- a build without it this reads as plain off-cooldown, which is honest either way.
      {
        name = "Judgment at cap",
        subject = 20271,
        when = { t = "at_max_charges", spell = 20271 },
      },
      -- The filler builder is a CHOICE NODE, so both rungs ship and only the talented one can
      -- ever attach -- the other has no laid-out row and stays dark. Three charges is where a
      -- Protection rotation actually leaks, which makes the cap the rung worth marking.
      {
        name = "Blessed Hammer at cap",
        subject = 204019,
        when = { t = "at_max_charges", spell = 204019 },
      },
      {
        name = "Hammer of the Righteous at cap",
        subject = 53595,
        when = { t = "at_max_charges", spell = 53595 },
      },
      {
        name = "Blessed Hammer on Blessed Assurance",
        subject = 204019,
        when = { t = "aura", spell = 433015 },
      },
      {
        name = "Hammer of the Righteous on Blessed Assurance",
        subject = 53595,
        when = { t = "aura", spell = 433015 },
      },
      {
        name = "Consecration when you are not in it",
        subject = 26573,
        when = { t = "and", terms = {
          { t = "ready", spell = 26573 },
          { t = "not", term = { t = "aura", spell = 188370 } }
        } },
      },
      -- Two rungs on the same button, and the second is the first with its requirement
      -- lowered. At the cap you press regardless, because the next generator overcaps; with
      -- the mitigation buff down it is worth pressing at the castable minimum instead. `>= 5`
      -- rather than `== 5` so a talent that raises the cap cannot step over it.
      {
        name = "Shield of the Righteous at cap",
        subject = 53600,
        when = { t = "resource", power = "holy_power", cmp = ">=", value = 5 },
      },
      {
        name = "Shield of the Righteous with the buff down",
        subject = 53600,
        when = { t = "and", terms = {
          { t = "resource", power = "holy_power", cmp = ">=", value = 3 },
          { t = "not", term = { t = "aura", spell = 132403 } }
        } },
      },
    },
  },

  -- ⚠ AN INSTRUMENT, NOT ADVICE. Four health binds and nothing else, so every mark on screen
  -- is one of these four.
  --
  -- A LADDER: three rising thresholds and the complement of the lowest, read at once. The
  -- COUNT of lit marks is your health band, so the curve is exercised at three points rather
  -- than one, and out of combat your own regeneration sweeps it for you -- nothing here needs
  -- damage taken on purpose, a threshold crossed on cue, or a stopwatch.
  --
  --   Word of Glory lit               >= 80%        all three lit  = 80%+
  --   Shield of the Righteous lit     >= 60%        two lit        = 60-80%
  --   Consecration lit                >= 40%        one lit        = 40-60%
  --   Avenger's Shield lit            <  40%        only AS lit    = under 40%
  --
  -- Consecration and Avenger's Shield are exact complements, so EXACTLY ONE of them is lit at
  -- every health total. Both lit or both dark means the reading is void -- a standing validity
  -- check that costs nothing and exercises the `<` compile path beside the `>=` one.
  ["protection-healthprobe"] = {
    label = "Protection — health-bind ladder",
    glows = {
      {
        name = "LADDER: >= 80% health",
        subject = 85673,
        bind = { cmp = ">=", family = "health", percent = 80 },
      },
      {
        name = "LADDER: >= 60% health",
        subject = 53600,
        bind = { cmp = ">=", family = "health", percent = 60 },
      },
      {
        name = "LADDER: >= 40% health",
        subject = 26573,
        bind = { cmp = ">=", family = "health", percent = 40 },
      },
      {
        name = "LADDER: < 40% health (complement of the rung above)",
        subject = 31935,
        bind = { cmp = "<", family = "health", percent = 40 },
      },
    },
  },

  -- ⚠ AN INSTRUMENT, NOT ADVICE. Four duration binds, all reading ARDENT DEFENDER's cooldown
  -- (31850, ~90s, self-cast, no target, castable out of combat) and glowing four other icons.
  -- Subject and bound spell are independent, so one press lights a ladder somewhere else.
  --
  -- The question is the curve's INPUT UNIT, which `Duration.lua` assumes is seconds and which
  -- nothing has measured. Right after casting, remaining is ~90 seconds -- so the input is ~90
  -- on a seconds domain, ~90000 on milliseconds, ~1.0 on a [0, 1] fraction. Points at 30 and
  -- 1000 straddle all three.
  --
  --   Consecration vs Avenger's Shield are exact complements -- which one is lit is the answer:
  --     Avenger's Shield lit   input is seconds or a fraction
  --     Consecration lit       input is MILLISECONDS
  --   Shield of the Righteous then separates the first pair:
  --     lit                    input is SECONDS -- the shipped assumption holds
  --     dark                   input is a [0, 1] FRACTION
  --   Word of Glory dark with a cooldown running means nothing drives alpha at all.
  --
  -- `< 1000s` carries `absent dark` because `<` on a cooldown is also true at zero remaining,
  -- which would glow permanently while the spell is up.
  ["protection-durationprobe"] = {
    label = "Protection — duration-bind probe",
    glows = {
      {
        name = "DPROBE: Ardent Defender cooldown > 0.5s (anything at all)",
        subject = 85673,
        bind = { family = "duration", spell = 31850, cmp = ">", seconds = 0.5 },
      },
      {
        name = "DPROBE: > 30s (lit on seconds or ms, dark on a fraction)",
        subject = 53600,
        bind = { family = "duration", spell = 31850, cmp = ">", seconds = 30 },
      },
      {
        name = "DPROBE: > 1000s (lit ONLY on milliseconds)",
        subject = 26573,
        bind = { family = "duration", spell = 31850, cmp = ">", seconds = 1000 },
      },
      {
        name = "DPROBE: < 1000s (complement of the rung above)",
        subject = 31935,
        bind = { family = "duration", spell = 31850, cmp = "<", seconds = 1000,
                 absent = "dark" },
      },
      -- The `outside` form, which is the only compile shape with two transitions and has
      -- never run. On Divine Toll, off Ardent Defender's ~90s cooldown, one icon shows all
      -- three edges in one press: LIT from the cast down to 60s, DARK through 60..30, LIT
      -- again under 30, then DARK when the spell comes up.
      {
        name = "DPROBE: outside 30s..60s (three edges on one icon)",
        subject = 375576,
        bind = { family = "duration", spell = 31850, cmp = "outside", lo = 30, hi = 60,
                 absent = "dark" },
      },
    },
  },
}

function Profiles.Names()
  local names = {}
  for name in pairs(Profiles.list) do names[#names + 1] = name end
  table.sort(names)
  return names
end

function Profiles.Get(name)
  local profile = Profiles.list[string.lower(name or "")]
  if profile == nil then return nil end
  return profile
end
