# Agent guidelines

## Git workflow

- Never push directly to `main`. Every change goes on a branch and lands through a pull request on `yjmeqt/Attention`.
- The repo is owned by the `yjmeqt` GitHub account; run `gh auth switch --user yjmeqt` before using `gh` if another account is active.
- Commits use `yjmeqt <yjmeqt@gmail.com>`. This is set in the repo's local git config; don't change `user.name` or `user.email`, and don't commit as another account.

## iOS builds and runs: xc-dev

iOS build, run, simulator and clean work goes through [`xc-dev`](https://github.com/yjmeqt/xc-dev) (`cargo install --git https://github.com/yjmeqt/xc-dev xc-dev`). Its config is committed in `.xc-dev/`, so every worktree, including the ones Claude creates under `.claude/worktrees/`, has the same tasks with nothing to set up. Run `xc-dev` from anywhere in the repo to list them.

```sh
xc-dev build                # xcodegen if project.yml changed, then build for the simulator
xc-dev run                  # build, boot this worktree's iPhone sim, install, launch
xc-dev run-ipad             # same on this worktree's iPad sim
xc-dev run-duo              # same on this worktree's iPhone Duo sim
xc-dev run-mac              # build and open the Mac menu bar app
xc-dev stop                 # kill this worktree's xcodebuild, terminate the app on its sims
xc-dev clean                # delete this worktree's sims and its DerivedData
xc-dev prune                # dry run: sims and DerivedData left by removed worktrees
xc-dev prune mode=delete    # delete them
xc-dev run-device <id>      # physical iPhone; ids from `xc-dev devices-iphone`
xc-dev :get sim_id          # any resolved variable: sim_name, bundle_id, git_worktree_slug, ...
```

- Each worktree gets its own simulators, named `Attention-<worktree slug>` (plus `-ipad` and `-duo`), so parallel worktrees never share one. Don't use the `Attention-Shots-*` simulators: `ios/Tools/store-shots/capture.zsh` drives them.
- Builds go to Xcode's own DerivedData folder for the worktree's project path (`~/Library/Developer/Xcode/DerivedData/Attention-<hash>`), the same one Xcode uses when it opens that project. `xc-dev clean` deletes it.
- Add a task to `.xc-dev/tasks.toml` rather than hand-writing an `xcodebuild` call that a task could cover.

### Tests

There's no xc-dev task for tests. Run them with `xcodebuild` directly, on a simulator no one else is using, such as this worktree's own:

```sh
xcodebuild test -project ios/Attention.xcodeproj -scheme Attention \
  -destination "id=$(xc-dev :get sim_id)"
```

The `Attention` scheme runs `AttentionTests` (Swift Testing suites in `ios/Tests/`). Add `-only-testing:AttentionTests/<Suite>` to run one suite.

### Worktrees

Worktrees you create by hand go in `.worktrees/` (git-ignored). Register the helpers once per clone:

```sh
git config alias.xc-worktree-add '!sh .xc-dev/bin/worktree-add.sh'
git config alias.xc-worktree-remove '!sh .xc-dev/bin/worktree-remove.sh'
```

```sh
git xc-worktree-add .worktrees/my-feature -b my-feature   # add, resolve its sim, warm with `xc-dev run` in the background (--no-warm skips)
git xc-worktree-remove .worktrees/my-feature              # stop, delete its sims and DerivedData, remove the worktree; keeps the branch
```

Claude archives the worktrees it creates without running any of this, so run `xc-dev prune` now and then to clean up after them.
