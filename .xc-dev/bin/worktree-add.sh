#!/bin/sh
# git xc-worktree-add <path> [<branch> | -b <new-branch> | ...] [--no-warm]
#
# `git worktree add`, then resolves the new worktree's own simulator and runs `xc-dev run` in the
# background so its DerivedData is warm by the time you start. The xc-dev config is committed,
# so there's nothing else to set up.
#
# Register once per clone:
#   git config alias.xc-worktree-add '!sh .xc-dev/bin/worktree-add.sh'
#
# Usage:
#   git xc-worktree-add .worktrees/fix-x -b fix-x
#   git xc-worktree-add .worktrees/fix-x fix-x --no-warm
set -e

# Git aliases run with a minimal PATH that often lacks ~/.cargo/bin.
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

if [ -z "$1" ]; then
    echo "usage: git xc-worktree-add <path> [<branch> | -b <new-branch> | ...] [--no-warm]" >&2
    exit 2
fi
# Aliases run from the worktree's top level; resolve <path> against where it was typed.
DIR="$1"
case "$DIR" in
    /*) ;;
    *) DIR="${GIT_PREFIX:-}$DIR" ;;
esac
shift

WARM=1
for arg do
    shift
    case "$arg" in
        --no-warm) WARM=0 ;;
        *) set -- "$@" "$arg" ;;
    esac
done

git worktree add "$DIR" "$@"
ABS="$(cd "$DIR" && pwd)"
cd "$ABS"

if [ ! -f .xc-dev/tasks.toml ]; then
    echo "This branch predates the committed .xc-dev/ config; skipping simulator setup."
    exit 0
fi
command -v xc-dev >/dev/null 2>&1 || {
    echo "xc-dev not found — cargo install --git https://github.com/yjmeqt/xc-dev xc-dev" >&2
    exit 1
}
echo "Simulator: $(xc-dev :get sim_name) ($(xc-dev :get sim_id))"

if [ "$WARM" -eq 1 ]; then
    LOG="$ABS/.xc-dev/warm-run.log"
    nohup xc-dev run >"$LOG" 2>&1 &
    echo $! >"$ABS/.xc-dev/warm-run.pid"
    echo "Warming in the background: xc-dev run (log: $LOG; skip with --no-warm)"
fi
