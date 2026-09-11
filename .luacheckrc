-- .luacheckrc — static analysis for Smart Glo.
--
-- The rung above the release flow's luaparser SYNTAX gate: luacheck catches undefined
-- globals, dead locals, shadowing and typos that parse fine but are bugs. `wowkb.addon
-- release sg` runs it because this file exists — its absence is what silently switches
-- the gate off — and it aborts the cut on a hit. By hand, from this repo root:
--
--     luacheck SmartGlo/
--
-- DOCTRINE: curate this config, never inline-suppress. A real catch gets FIXED; a WoW API
-- name the addon legitimately calls goes in the `read_globals` std below, grouped by the
-- file that calls it — a claim a reader can check with one grep. A name nothing calls
-- silences the warning that would have caught the day someone typo'd a real one.

std = "lua51+wow"

stds.wow = {
  read_globals = {
    -- Core.lua — the loader frame, the secret-value class check, spell names for chat.
    "CreateFrame",
    "issecretvalue",
    "C_Spell",

    -- Names.lua — the symbol table is slugged from English spell names, so the client's
    -- locale decides whether checking it against the client can mean anything.
    "GetLocale",

    -- Rules.lua — the readable vocabulary: secondary resources, the cooldown info table,
    -- and the trait config, which is how `talent()` asks whether a node is purchased.
    -- `C_SpellBook` is how `ready()` screens out a spell the player does not have, which
    -- reports "nothing running" exactly like one off cooldown.
    "UnitPower",
    "UnitPowerDisplayMod",
    "UnitHealthPercent",
    "Enum",
    "C_Traits",
    "C_ClassTalents",
    "C_SpellBook",
    "InCombatLockdown",

    -- Look.lua — the shipped escape builder, so no format string is hand-rolled here, and
    -- the clock the colour cycle's phase is taken from.
    "CreateTextureMarkup",
    "GetTime",

    -- Core.lua — the session stamps the capture log carries: which spec it was taken on, and
    -- the reader that tells an unbound key apart from one another binding swallows.
    "C_SpecializationInfo",
    "GetBindingKey",

    -- Overlay.lua / Config.lua — our own frames hang off the screen, never off a CDM icon.
    "UIParent",

    -- Attach.lua — riding the Cooldown Manager: the viewers, the item mixins, the hooks.
    "hooksecurefunc",
    "C_Timer",
    "C_CooldownViewer",
    "EventRegistry",

    -- Procs.lua — the client's own read of whether a spell is procced, asked before we
    -- decide whether to draw the replacement glow.
    "C_SpellActivationOverlay",

    -- Capture.lua — the readability classes and the session timestamp.
    "issecrettable",
    "date",

    -- Count.lua — the managed aura container and the authored numeric formatter.
    "C_AddOns",
    "C_StringUtil",

    -- Duration.lua — the engine-curve read: a decision taken against a secret magnitude
    -- without ever reading it.
    "C_CurveUtil",

    -- Wire.lua — serialize, compress and base64, all three shipped by the client.
    "C_EncodingUtil",

    -- Config.lua — the four viewer globals the subject dropdown enumerates.
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
  },
  -- The addon's true global writes: the slash registration, which has to be global because
  -- that is the interface the client reads it through, and the SavedVariables table.
  globals = {
    "SLASH_SMARTGLO1",
    -- The Key Bindings UI reads these by name; Bindings.xml supplies the binding itself.
    "BINDING_HEADER_SMARTGLO",
    "BINDING_NAME_SMARTGLO_WHY_LOG",
    "SlashCmdList",
    "SmartGloDB",
  },
}

-- Capture.lua is vendored verbatim and opens `local ADDON, ns = ...`, WoW's
-- (addonName, addonTable) vararg. It uses only `ns`, so `ADDON` reads dead — but renaming a
-- vendored file's locals is how a diff against the other copies stops showing divergence.
ignore = { "211/ADDON" }
