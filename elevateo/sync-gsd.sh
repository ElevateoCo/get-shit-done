#!/usr/bin/env bash
# elevateo/sync-gsd.sh — make the fork canonical on this machine.
#
# Decision (elevate-os docs/internal-workflows): ElevateoCo/get-shit-done (this fork)
# is the canonical source of truth; the local ~/.claude install syncs FROM it.
# This script is the "local syncs from fork" mechanism:
#   pull the fork  ->  back up the current install  ->  run the fork's OFFICIAL installer  ->  verify.
#
# It deliberately WRAPS the official installer (bin/install.js) rather than hand-copying
# files, so the multi-location deploy (workflows + commands + skills + hooks + settings)
# stays correct.
#
# USAGE
#   bash elevateo/sync-gsd.sh                 # pull + backup + install (global, Claude Code)
#   bash elevateo/sync-gsd.sh --dry-run       # print what would happen, change nothing
#   bash elevateo/sync-gsd.sh --no-backup     # skip the pre-install backup (not recommended)
#   bash elevateo/sync-gsd.sh --branch <name> # sync a branch other than main
#
# ENV OVERRIDES
#   GSD_FORK_DIR   fork checkout location   (default: ~/Work/Github/get-shit-done)
#   GSD_FORK_URL   clone URL if missing     (default: https://github.com/ElevateoCo/get-shit-done.git)
#   CLAUDE_DIR     config dir               (default: ~/.claude)
#
# Re-runnable: yes. Idempotent (the installer is; git pull is).

set -euo pipefail

GSD_FORK_DIR="${GSD_FORK_DIR:-$HOME/Work/Github/get-shit-done}"
GSD_FORK_URL="${GSD_FORK_URL:-https://github.com/ElevateoCo/get-shit-done.git}"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
BRANCH="main"
DRY_RUN=0
DO_BACKUP=1

# ---------- argv ----------
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)   DRY_RUN=1 ;;
    --no-backup) DO_BACKUP=0 ;;
    --branch)    BRANCH="${2:?--branch needs a value}"; shift ;;
    -h|--help)   sed -n '2,/^set -e/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf '✗ unknown arg: %s\n' "$1" >&2; exit 1 ;;
  esac
  shift
done

log()  { printf '\033[36m·\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m▲\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[31m✗\033[0m %s\n' "$*" >&2; }
# run: execute, or just print in dry-run. Call with separate args (no eval).
run()  { if [ "$DRY_RUN" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else "$@"; fi; }

# ---------- pre-flight ----------
command -v git  >/dev/null 2>&1 || { err "git not found";  exit 1; }
command -v node >/dev/null 2>&1 || { err "node not found"; exit 1; }

# ---------- 1. get/refresh the fork checkout ----------
log "fork: $GSD_FORK_DIR (branch $BRANCH)"
if [ ! -d "$GSD_FORK_DIR/.git" ]; then
  warn "fork checkout missing — cloning $GSD_FORK_URL"
  run git clone "$GSD_FORK_URL" "$GSD_FORK_DIR"
fi
if [ "$DRY_RUN" = 1 ]; then
  printf '  [dry-run] git -C %s fetch origin && checkout %s && pull --ff-only\n' "$GSD_FORK_DIR" "$BRANCH"
else
  git -C "$GSD_FORK_DIR" fetch origin
  # refuse to clobber local fork edits
  if [ -n "$(git -C "$GSD_FORK_DIR" status --porcelain)" ]; then
    err "fork checkout has uncommitted changes — commit/stash them before syncing"
    exit 1
  fi
  git -C "$GSD_FORK_DIR" checkout "$BRANCH"
  git -C "$GSD_FORK_DIR" pull --ff-only origin "$BRANCH"
fi
INSTALLER="$GSD_FORK_DIR/bin/install.js"
[ "$DRY_RUN" = 1 ] || [ -f "$INSTALLER" ] || { err "installer not found at $INSTALLER"; exit 1; }
ok "fork up to date"

# ---------- 2. back up the current install (rollback safety) ----------
if [ "$DO_BACKUP" = 1 ]; then
  STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
  BACKUP_DIR="$CLAUDE_DIR/.gsd-backups/$STAMP"
  log "backing up current GSD install → $BACKUP_DIR"
  run mkdir -p "$BACKUP_DIR"
  # back up everything the installer may overwrite: the runtime, the gsd commands, the gsd skills,
  # settings.json and hooks (both mutated by the installer).
  for SRC in "$CLAUDE_DIR/get-shit-done" "$CLAUDE_DIR/commands/gsd" "$CLAUDE_DIR/settings.json" "$CLAUDE_DIR/hooks"; do
    if [ -e "$SRC" ]; then
      run cp -R "$SRC" "$BACKUP_DIR/" || warn "backup of $SRC failed"
    fi
  done
  if [ "$DRY_RUN" = 1 ]; then
    printf '  [dry-run] cp -R %s/skills/source-command-gsd-* %s/skills-gsd/\n' "$CLAUDE_DIR" "$BACKUP_DIR"
  else
    if ls -d "$CLAUDE_DIR"/skills/source-command-gsd-* >/dev/null 2>&1; then
      mkdir -p "$BACKUP_DIR/skills-gsd"
      cp -R "$CLAUDE_DIR"/skills/source-command-gsd-* "$BACKUP_DIR/skills-gsd/"
    fi
  fi
  ok "backup complete (rollback: restore from $BACKUP_DIR)"
else
  warn "--no-backup: skipping pre-install backup"
fi

# ---------- 2.7 build SDK + hooks (git-clone installs need generated artifacts) ----------
# The SDK (sdk/dist/cli.js — powers /gsd-* commands) and built hooks are generated at
# npm-publish time, NOT committed. Installing from this git clone needs them built first.
if [ ! -f "$GSD_FORK_DIR/sdk/dist/cli.js" ] || [ "${FORCE_BUILD:-0}" = 1 ]; then
  log "building GSD SDK + hooks (required when installing from a git clone)"
  if [ "$DRY_RUN" = 1 ]; then
    printf '  [dry-run] (cd %s && npm install && npm run build:hooks && npm run build:sdk)\n' "$GSD_FORK_DIR"
  else
    ( cd "$GSD_FORK_DIR" && npm install --no-fund --no-audit && npm run build:hooks && npm run build:sdk ) \
      || { err "SDK/hooks build failed — run: cd $GSD_FORK_DIR && npm install && npm run build:hooks && npm run build:sdk"; exit 1; }
  fi
  ok "SDK + hooks built"
else
  log "SDK already built (set FORCE_BUILD=1 to rebuild)"
fi

# ---------- 3. run the fork's official installer ----------
log "installing fork into $CLAUDE_DIR (global, Claude Code)"
# First sync from an old install runs a one-time baseline migration that asks keep/remove
# for stale GSD files. Non-interactive (this script) → set GSD_INSTALLER_MIGRATION_RESOLVE.
# Default to 'remove' (clears stale orphans); override with GSD_INSTALLER_MIGRATION_RESOLVE=keep.
export GSD_INSTALLER_MIGRATION_RESOLVE="${GSD_INSTALLER_MIGRATION_RESOLVE:-remove}"
log "installer migration resolve = $GSD_INSTALLER_MIGRATION_RESOLVE (one-time; override with =keep)"
run node "$INSTALLER" --global --claude --config-dir "$CLAUDE_DIR"
ok "installer finished"

# ---------- 4. verify ----------
if [ "$DRY_RUN" = 1 ]; then
  printf '  [dry-run] verify: node %s/get-shit-done/bin/gsd-tools.cjs --help\n' "$CLAUDE_DIR"
else
  if node "$CLAUDE_DIR/get-shit-done/bin/gsd-tools.cjs" --help >/dev/null 2>&1 \
     || node "$CLAUDE_DIR/get-shit-done/bin/gsd-sdk.js" --help >/dev/null 2>&1; then
    ok "gsd-tools loads"
  else
    warn "could not verify gsd-tools — check the install"
  fi
  FORK_SHA="$(git -C "$GSD_FORK_DIR" rev-parse --short HEAD)"
  ok "synced to fork @ $FORK_SHA"
fi

printf '\n\033[1m== done ==\033[0m\n'
log "fork is now deployed to $CLAUDE_DIR. Re-run anytime to pull the latest."
[ "$DO_BACKUP" = 1 ] && log "rollback: copy the dirs from $CLAUDE_DIR/.gsd-backups/<stamp>/ back into place."
