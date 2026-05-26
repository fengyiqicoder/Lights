---
name: lights-hooks
description: |
  Install Lights traffic-light status hooks into Claude Code's settings.json.
  Lights is a macOS menu-bar app that shows AI activity as a floating
  traffic light (red=executing, yellow=needs input, green=idle).
  Use this skill when the user mentions Lights, asks how to connect Lights
  to Claude Code, says "set up lights hooks", "install lights skill", or
  installs Lights and asks how to wire it up.
---

# Install Lights Hooks for Claude Code

Lights listens on `http://127.0.0.1:9876` for state signals. When configured
correctly, Claude Code fires curl requests on lifecycle events and the
floating traffic light reflects current activity.

## Step 1 — Verify Lights is running

Run:

```bash
curl -s --max-time 1 http://127.0.0.1:9876/status
```

Expected output: `idle`, `executing`, `permission`, or `off`.

If the curl fails or hangs:
- Tell the user: *"Lights app isn't running. Launch /Applications/Lights.app
  (or `open Lights.app` from the source repo) and then re-invoke this skill."*
- **Stop.** Do not proceed with config changes.

## Step 2 — Back up settings.json

```bash
TS=$(date +%Y%m%d-%H%M%S)
cp ~/.claude/settings.json ~/.claude/settings.json.bak-lights-$TS
```

## Step 3 — Merge the hooks

Read `~/.claude/settings.json` as JSON. Ensure the top-level `hooks` key
exists (create as `{}` if missing). For each of the five events below,
**add** a new hook entry — preserve any existing hooks the user has.

### Idempotency rule

Before adding each hook, scan all existing commands in the target event
array. If any command already contains `9876/<endpoint>` for that
endpoint, **skip** — do not duplicate.

### Hooks to add

All commands share these properties:
- `type: "command"`
- `timeout: 2000`
- Stream output to `/dev/null`, suffix `|| true` so a missing Lights never
  blocks Claude Code

| Event | Matcher | Endpoint |
|---|---|---|
| `UserPromptSubmit` | *(none)* | `/executing` |
| `Notification` | *(none)* | `/permission` |
| `Stop` | *(none)* | `/idle` |
| `PreToolUse` | `AskUserQuestion\|ExitPlanMode` | `/permission` |
| `PostToolUse` | `AskUserQuestion\|ExitPlanMode` | `/executing` |

Command template:
```
curl -s --max-time 1 http://127.0.0.1:9876/<endpoint> >/dev/null 2>&1 || true
```

### Merge structure

Each event in `hooks` is an array of entries. Each entry has:
- optional `matcher` (regex)
- `hooks`: array of `{type, command, timeout}` objects

When adding to an event:
1. If an entry with the same `matcher` already exists → append the new hook
   to that entry's `hooks` array.
2. Otherwise → create a new entry with the matcher + the single hook.

## Step 4 — Write the JSON back

Pretty-print with 2-space indent. Don't sort other keys the user has set.

## Step 5 — Verify

```bash
curl -s http://127.0.0.1:9876/status
```

The user can then:
- Type any prompt in Claude Code → red light
- Wait for a permission prompt → yellow
- See response complete → green

## Uninstall

If the user asks to remove Lights hooks, scan every hook command in
`settings.json` and delete the ones containing any of:
- `9876/executing`
- `9876/permission`
- `9876/idle`
- `9876/off`

Drop entries whose `hooks` array becomes empty. Leave everything else
untouched. Back up first as in Step 2.

## Alternative: Lights app itself

If the user has Lights.app installed, they can also use its built-in
Setup panel (right-click the floating traffic light → "Setup Hooks…")
which does the same merge with a single click. This skill exists for
users who don't run the GUI.
