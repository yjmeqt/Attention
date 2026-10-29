#!/bin/sh
# git xc-worktree-remove <path> [--force]
#
# Stops the worktree's build, deletes its simulators and DerivedData, then `git worktree remove`.
# Leaves the branch alone and never removes the main checkout.
#
# Register once per clone:
#   git config alias.xc-worktree-remove '!sh .xc-dev/bin/worktree-remove.sh'
set -e

export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

if [ -z "$1" ]; then
    echo "usage: git xc-worktree-remove <path> [--force]" >&2
    exit 2
fi
DIR="$1"
case "$DIR" in
    /*) ;;
    *) DIR="${GIT_PREFIX:-}$DIR" ;;
esac
shift

if [ -d "$DIR" ]; then
    ABS="$(cd "$DIR" && pwd -P)"
else
    echo "xc-worktree-remove: no such directory: $DIR" >&2
    exit 1
fi

MAIN="$(git worktree list --porcelain | awk '/^worktree / { print $2; exit }')"
if [ "$ABS" = "$(cd "$MAIN" && pwd -P)" ]; then
    echo "xc-worktree-remove: refusing to remove the main checkout: $MAIN" >&2
    exit 1
fi
git worktree list --porcelain | grep -qxF "worktree $ABS" || {
    echo "xc-worktree-remove: not a registered worktree: $ABS (see git worktree list)" >&2
    exit 1
}

# Leave the target before deleting it.
cd "$MAIN"

if [ -f "$ABS/.xc-dev/tasks.toml" ] && command -v xc-dev >/dev/null 2>&1; then
    (
        cd "$ABS"
        xc-dev stop || true
        xc-dev clean || rm -rf "$ABS/.xc-dev/DerivedData"
    ) || true
fi

# xc-dev :clean matches DerivedData by its recorded project path, which Xcode may store through a
# symlink (/tmp vs /private/tmp). Catch those by the resolved path while the worktree still exists.
for pl in "$HOME"/Library/Developer/Xcode/DerivedData/*/info.plist; do
    [ -f "$pl" ] || continue
    ws=$(plutil -extract WorkspacePath raw "$pl" 2>/dev/null) || continue
    [ -e "$ws" ] || continue
    case "$(cd "$(dirname "$ws")" && pwd -P)/" in
        "$ABS"/*) rm -rf "$(dirname "$pl")" && echo "Deleted DerivedData for $ws" ;;
    esac
done

git worktree remove "$ABS" "$@"
echo "Removed worktree $ABS"
