# lights-hooks

Claude Code skill that wires the [Lights](https://github.com/fengyiqicoder/Lights)
macOS traffic-light app into `~/.claude/settings.json` so Claude Code's
lifecycle events drive the lights' color.

## Install

```bash
npx skillsadd fengyiqicoder/lights-hooks
```

Then in Claude Code, ask: *"set up lights hooks"* — the skill activates
on description match and walks Claude through the JSON merge.

## Prerequisites

- macOS with Lights.app running (`http://127.0.0.1:9876` must respond)
- Claude Code installed

## What it does

Adds these hooks to `~/.claude/settings.json` (preserving any existing
hooks you have):

| Claude Code event | → endpoint | Light |
|---|---|---|
| UserPromptSubmit | `/executing` | 🔴 red |
| Notification | `/permission` | 🟡 yellow |
| Stop | `/idle` | 🟢 green |
| PreToolUse on AskUserQuestion/ExitPlanMode | `/permission` | 🟡 yellow |
| PostToolUse on AskUserQuestion/ExitPlanMode | `/executing` | 🔴 red |

A backup of your existing `settings.json` is saved as
`settings.json.bak-lights-YYYYMMDD-HHMMSS` before any change.

## Uninstall

Tell Claude: *"uninstall lights hooks"* — the skill removes only the
9876-port curl entries; everything else stays intact.

## See also

- [Lights.app source](https://github.com/fengyiqicoder/Lights) — built-in
  Setup panel does the same install with one click via the GUI
- [skills.sh](https://skills.sh) — the Claude Code skills directory
