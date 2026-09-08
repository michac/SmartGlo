# SmartGlo — addon repo

This is the addon **source of truth** (`michac/SmartGlo`), a separate git repo gitignored by
the parent wow workspace. A plain push does **not** reach the game: ghaddons installs from
the latest GitHub **release**.

## Releasing

Use the one door, from the workspace `tools/` directory:

    uv run python -m wowkb.addon release sg [--patch|--minor|--major]

It refuses a dirty tree, bumps the `.toc` version, warns if `## Interface:` drifts from
`game-version.md`, luacheck- and luaparser-checks the Lua, commits, pushes, cuts a release
tagged with the `.toc` version, then ghaddons-deploys and reads back `ok`.

**Releases do not need asking.** The only oracle for a glow is whether it reads at a glance
mid-pull, so a build that is ready to look at is released. The luacheck and luaparser gates
plus the dirty-tree refusal are what make that cheap; run them, then cut.

## Rules

Blocks stay short and say what the code does now. No dates, versions or "used to" — that is
`git log`. Commands come from a schema table, never a hand-rolled parser, and the verb is
matched at the head of the string rather than searched for inside it. One `pcall` per call
whose failure you want to tell apart, and keep `err`; a discarded error is a fabricated
result. A UI that renders nothing must render why.

The rule predicates read the player's own **secondary** resources, which are never secret.
Every **primary** — Mana, Rage, Focus, Energy, Runic Power, Fury, Pain, Insanity, Maelstrom —
reads secret in every context, so a threshold on one cannot be evaluated and must not be
offered as a rule. The mechanism is
`knowledge/addon-dev/security-taint-and-restricted-data.md` §4.12.
