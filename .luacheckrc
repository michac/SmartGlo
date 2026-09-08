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
    -- The loader frame — Core.lua. It holds the PLAYER_LOGIN registration and nothing else.
    "CreateFrame",
  },
  -- The addon's true global writes. Only the slash registration, which has to be global
  -- because that is the interface the client reads it through.
  globals = {
    "SLASH_SMARTGLO1",
    "SlashCmdList",
  },
}
