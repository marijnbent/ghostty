# Local Build Options

Quick reference for building, running, and installing this fork later.

## Main choices

### Update shared core only

Use this when code outside `macos/` changed and you only need to refresh the underlying Ghostty library first:

```bash
zig build -Demit-macos-app=false
```

### Build the macOS app

Preferred repo-specific build path:

```bash
macos/build.nu --scheme Ghostty --configuration Debug --action build
```

Other useful configurations:

```bash
macos/build.nu --scheme Ghostty --configuration ReleaseLocal --action build
macos/build.nu --scheme Ghostty --configuration Release --action build
```

Output location:

```text
macos/build/<configuration>/Ghostty.app
```

## Best day-to-day options

### Debug build

Good for development and side-by-side testing:

```bash
macos/build.nu --scheme Ghostty --configuration Debug --action build
```

- app path: `macos/build/Debug/Ghostty.app`
- bundle id: `com.mitchellh.ghostty.debug`

### ReleaseLocal build

Best for actually installing over your normal Ghostty while keeping app identity as stable as possible:

```bash
macos/build.nu --scheme Ghostty --configuration ReleaseLocal --action build
```

- app path: `macos/build/ReleaseLocal/Ghostty.app`
- bundle id: `com.mitchellh.ghostty`

## Install helpers

### Install debug build side-by-side

```bash
bash macos/install_local_app.sh Debug "/Applications/Ghostty Debug.app"
```

### Install release-local build over the normal app

```bash
bash macos/install_local_app.sh ReleaseLocal "/Applications/Ghostty.app"
```

If you want the shortest safe default for daily use, use:

```bash
bash macos/install_local_app.sh ReleaseLocal "/Applications/Ghostty.app"
```

## Running

### Launch the built debug app directly

```bash
osascript -e 'tell application "'"$PWD"'/macos/build/Debug/Ghostty.app" to activate'
```

### Launch the installed app

```bash
open -a /Applications/Ghostty.app
```

## Testing

### Swift/macOS tests

```bash
macos/build.nu --scheme Ghostty --configuration Debug --action test
```

### Zig tests

```bash
zig build test
zig build test -Dtest-filter=<name>
```

## What to ask Codex later

Good future prompts:

```text
Use LOCAL_BUILD_OPTIONS.md and build a ReleaseLocal app, then install it to /Applications/Ghostty.app.
```

```text
Use LOCAL_BUILD_OPTIONS.md and build a Debug app for side-by-side testing.
```
