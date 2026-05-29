# elevateo/

Elevateo-specific additions to this GSD fork, kept in their own directory so upstream
merges don't conflict.

## Canonical model
`ElevateoCo/get-shit-done` (this fork) is the **canonical source of truth** for GSD.
The local `~/.claude/get-shit-done/` install is a **deployment** that syncs FROM the fork.
All GSD edits — catalog-side and process-side — land as **PRs to this fork**; nothing is
edited directly in the un-versioned local install.

## sync-gsd.sh
Makes the fork canonical on a machine: pull the fork → back up the current install →
run the fork's official installer (`bin/install.js`) → verify.

```bash
bash elevateo/sync-gsd.sh --dry-run   # see exactly what it will do
bash elevateo/sync-gsd.sh             # pull + backup + install (global, Claude Code)
```

- Wraps the official installer (correct multi-location deploy: workflows + commands + skills + hooks).
- Backs up `~/.claude/get-shit-done`, `~/.claude/commands/gsd`, and the `source-command-gsd-*` skills to `~/.claude/.gsd-backups/<timestamp>/` before installing (rollback safety).
- First sync from the old 1.22.4 install may prompt for migration — answer interactively.
- Env overrides: `GSD_FORK_DIR`, `GSD_FORK_URL`, `CLAUDE_DIR`.
