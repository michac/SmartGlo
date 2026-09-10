-- AUTO-GENERATED — do NOT hand-edit.
-- Source: knowledge/classes/_abilities/power-gain.tsv
-- Writer: `uv run python -m wowkb.gen_smartglo_powergain`
--
-- How much of a secondary resource a cast returns, in RAW units — 10 raw per Soul
-- Shard. The scale is not shipped: `UnitPowerDisplayMod` reads it from the client.
--
-- A spell in `varies` returns an amount that depends on a talent or a proc, so no
-- single number is right and `Cast.lua` refuses to project one rather than pick.

local _, ns = ...

local PowerGain = {}
ns.PowerGain = PowerGain

--- A COUNT, not a date: a date would churn `--check` on a regeneration that changed
--- nothing.
PowerGain.count = 124

--- [powerType] = { [castSpellID] = raw units returned }.
PowerGain.raw = {
  [4] = { -- combo_points
    [53] = 1, -- backstab
    [703] = 1, -- garrote
    [1752] = 1, -- sinister_strike
    [1766] = 3, -- kick
    [1776] = 1, -- gouge
    [1822] = 1, -- rake
    [5217] = 3, -- tigers_fury
    [5221] = 1, -- shred
    [5374] = 2, -- mutilate
    [5938] = 1, -- shiv
    [8921] = 1, -- moonfire
    [14161] = 1, -- ruthlessness
    [14190] = 1, -- seal_fate
    [22482] = 1, -- blade_flurry
    [32645] = 1, -- envenom
    [50334] = 1, -- berserk
    [51690] = 1, -- killing_spree
    [51723] = 1, -- fan_of_knives
    [77758] = 1, -- thrash
    [106951] = 1, -- berserk
    [114014] = 1, -- shuriken_toss
    [159286] = 1, -- primal_fury
    [185313] = 4, -- shadow_dance
    [185438] = 2, -- shadowstrike
    [185565] = 1, -- poisoned_knife
    [197835] = 1, -- shuriken_storm
    [200758] = 1, -- gloomblade
    [210722] = 3, -- ashamanes_frenzy
    [213764] = 1, -- swipe
    [274837] = 1, -- feral_frenzy
    [279876] = 1, -- opportunity
    [328085] = 1, -- blindside
    [381828] = 4, -- ace_up_your_sleeve
    [382505] = 2, -- the_first_dance
    [385478] = 2, -- shrouded_suffocation
    [385627] = 1, -- kingsbane
    [391872] = 1, -- tigers_tenacity
    [393991] = 5, -- elunes_guidance
    [426591] = 3, -- goremaws_bite
    [441691] = 5, -- wildpower_surge
    [454419] = 1, -- deal_fate
    [455461] = 1, -- lethal_preservation
    [470669] = 2, -- echoing_reprimand
    [1243807] = 1, -- frantic_frenzy
    [1247227] = 1, -- crimson_tempest
    [1250318] = 1, -- poisoners_drive
    [1265861] = 6, -- gravedigger
  },
  [5] = { -- runes
    [47568] = 6, -- empower_rune_weapon
    [205223] = 2, -- consumption
    [207061] = 1, -- murderous_efficiency
    [220143] = 2, -- apocalypse
    [281238] = 1, -- obliteration
    [316239] = 1, -- rune_strike
    [377073] = 1, -- frigid_executioner
    [444072] = 1, -- a_feast_of_souls
    [1249658] = 2, -- breath_of_sindragosa
    [1263824] = 2, -- consumption
  },
  [7] = { -- soul_shards
    [348] = 1, -- immolate
    [686] = 10, -- shadow_bolt
    [980] = 10, -- agony
    [5740] = 1, -- rain_of_fire
    [6353] = 10, -- soul_fire
    [17962] = 5, -- conflagrate
    [29722] = 2, -- incinerate
    [196277] = 10, -- implosion
    [196586] = 3, -- dimensional_rift
    [264178] = 20, -- demonbolt
    [388667] = 10, -- drain_soul
    [433891] = 30, -- infernal_bolt
    [449620] = 10, -- necrolyte_teachings
    [449638] = 30, -- shadow_of_death
    [449706] = 10, -- feast_of_souls
    [460551] = 10, -- doom
    [1259790] = 10, -- unstable_affliction
    [1276163] = 10, -- dominion_of_argus
  },
  [9] = { -- holy_power
    [20271] = 1, -- judgment
    [20473] = 1, -- holy_shock
    [24275] = 1, -- hammer_of_wrath
    [25912] = 1, -- holy_shock
    [53576] = 1, -- infusion_of_light
    [53595] = 1, -- hammer_of_the_righteous
    [53652] = 1, -- beacon_of_light
    [81297] = 1, -- consecration
    [114165] = 3, -- holy_prism
    [114852] = 3, -- holy_prism
    [184575] = 1, -- blade_of_justice
    [204019] = 1, -- blessed_hammer
    [404542] = 1, -- crusading_strikes
    [431474] = 1, -- second_sunrise
    [432459] = 3, -- holy_bulwark
    [432977] = 1, -- sanctification
    [1263782] = 1, -- walk_into_light
    [1267203] = 1, -- glory_of_the_vanguard
  },
  [12] = { -- chi
    [100784] = 1, -- blackout_kick
    [117952] = 1, -- crackling_jade_lightning
    [121817] = 1, -- combat_wisdom
    [123986] = 1, -- chi_burst
    [130654] = 1, -- chi_burst
    [392958] = 1, -- glory_of_the_dawn
    [451498] = 1, -- energy_burst
    [1217413] = 2, -- slicing_winds
    [1248833] = 1, -- airborne_rhythm
    [1249832] = 1, -- obsidian_spiral
    [1272694] = 2, -- zenith_stomp
  },
  [16] = { -- arcane_charges
    [1449] = 1, -- arcane_explosion
    [30451] = 1, -- arcane_blast
    [153626] = 1, -- arcane_orb
    [321507] = 4, -- touch_of_the_magi
    [383676] = 1, -- impetus
    [449394] = 4, -- glorious_incandescence
    [451038] = 4, -- arcane_soul
    [461248] = 1, -- high_voltage
    [1223798] = 4, -- intuition
    [1241462] = 1, -- arcane_pulse
    [1295923] = 4, -- prismatic_bolt
  },
  [19] = { -- essence
    [411165] = 2, -- eye_of_infinity
  },
}

--- [powerType] = { [castSpellID] = true } for the spells whose gain is not a number.
PowerGain.varies = {
  [4] = { -- combo_points
    [1833] = true, -- cheap_shot
    [8676] = true, -- ambush
    [185763] = true, -- pistol_shot
    [343160] = true, -- premeditation
  },
  [7] = { -- soul_shards
    [17877] = true, -- shadowburn
  },
  [9] = { -- holy_power
    [35395] = true, -- crusader_strike
    [205273] = true, -- wake_of_ashes
    [255937] = true, -- wake_of_ashes
  },
}
