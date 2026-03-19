# Local Fork Workflow

This repo is a personal Ghostty fork with local product changes. The goal is:

- keep it easy to pull upstream changes from `ghostty-org/ghostty`
- avoid losing local work
- keep a simple build/install path for the macOS app

Related local references:

- [LOCAL_BUILD_OPTIONS.md](/Users/marijn/Projects/ghostty/LOCAL_BUILD_OPTIONS.md)

## Recommended setup

Recommended branches:

- `upstream-main`
  - local mirror of upstream `main`
  - never commit custom work here
- `marijn-workspaces`
  - your custom branch with sidebar/workspace changes

Branch naming note:

- prefer `marijn-workspaces` over `marijn/workspaces`
- if Git errors with `cannot lock ref ... unable to create directory for .git/refs/heads/...`,
  use a non-nested branch name with `-` instead of `/`
- this avoids ref namespace collisions if a plain ref name already exists somewhere in the repo history or refs

Recommended remote setup:

```bash
git remote add upstream git@github.com:ghostty-org/ghostty.git
git fetch upstream
```

## Best option

Best default for a personal app:

1. Update your clean upstream mirror branch.
2. Rebase your custom branch on top of it.

Commands:

```bash
git fetch upstream
git checkout upstream-main
git reset --hard upstream/main
git checkout marijn-workspaces
git rebase upstream-main
```

Why this is the best default:

- keeps history clean
- makes conflicts happen in one predictable place
- makes it easy to see what is truly custom
- easiest for an agent to reason about later

## Lower-stress option

If you want fewer rebases and do not care about a messier history:

```bash
git fetch upstream
git checkout marijn-workspaces
git merge upstream/main
```

Why choose this:

- safer feeling if you dislike rebasing
- less history rewriting

Tradeoff:

- history gets noisy fast
- custom diff against upstream is harder to inspect

## Most upstream-friendly option

Keep the real custom work as a small patch stack:

- `upstream-main` mirrors upstream exactly
- `marijn-workspaces` contains only fork features
- optionally split large custom work into 2-5 focused commits

Then update like this:

```bash
git fetch upstream
git checkout upstream-main
git reset --hard upstream/main
git checkout marijn-workspaces
git rebase upstream-main
```

This is the easiest shape for future cleanup, extraction, or reimplementation.

## What to ask Codex later

Good future prompt:

```text
Please sync this fork with upstream using the documented local fork workflow.
Use upstream-main as the clean mirror branch and rebase marijn-workspaces on top.
If there are conflicts, resolve them without dropping our workspace-sidebar changes.
Then rebuild and reinstall the macOS app.
```

## macOS build/install

Important repo-specific note:

- use `macos/build.nu` for the macOS app
- do not use `zig build` as the main macOS app build path

### Fast install choices

Option 1: safest for side-by-side testing

```bash
bash macos/install_local_app.sh Debug "/Applications/Ghostty Debug.app"
```

- bundle id: `com.mitchellh.ghostty.debug`
- does not replace your normal Ghostty install
- macOS permissions are separate from the normal app

Option 2: best for keeping permissions/settings

```bash
bash macos/install_local_app.sh ReleaseLocal "/Applications/Ghostty.app"
```

- bundle id: `com.mitchellh.ghostty`
- best chance of keeping existing TCC permissions and app identity
- replaces the installed Ghostty app

Why `ReleaseLocal` is preferred for `/Applications/Ghostty.app`:

- same bundle identifier as the normal app
- built for local use
- avoids the debug bundle id mismatch

## Permission note

Nothing can guarantee macOS will preserve every permission forever, but the most reliable path is:

- install `ReleaseLocal`
- keep the target path as `/Applications/Ghostty.app`
- keep the bundle identifier as `com.mitchellh.ghostty`

That keeps app identity as stable as possible.
