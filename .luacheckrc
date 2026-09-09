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

    -- Rules.lua — the readable vocabulary: secondary resources and the cooldown info table.
    "UnitPower",
    "Enum",

    -- Look.lua — the shipped escape builder, so no format string is hand-rolled here.
    "CreateTextureMarkup",

    -- Overlay.lua / Config.lua — our own frames hang off the screen, never off a CDM icon.
    "UIParent",

    -- Attach.lua — riding the Cooldown Manager: the viewers, the item mixins, the hooks.
    "hooksecurefunc",
    "C_Timer",
    "C_CooldownViewer",
    "EventRegistry",

    -- Count.lua — the managed aura container and the authored numeric formatter.
    "C_AddOns",
    "C_StringUtil",

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
    "SlashCmdList",
    "SmartGloDB",
  },
}
