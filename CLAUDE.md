# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

The build is driven by the **Makefile**, not SPM alone — `swift build` only produces the bare executable; the `.app` bundle, the two FinderSync extensions, and code signing are all assembled by the Makefile.

```bash
make build           # Universal build (arm64 + x86_64) + both extensions + bundle + signing + arch check
make verify          # lipo-check that all three binaries in the bundle carry every arch in ARCHS
make install         # Build, copy to /Applications, lsregister + pluginkit register/enable, restart Finder
make uninstall       # Remove from /Applications (does not clear App Group prefs)
make run             # Build, then run the binary with --show-ui (settings window)
make clean           # swift package clean + rm -rf .build build .swiftpm
make release         # Build + build/go2shell.zip + build/go2shell.zip.sha256 (exactly what CI ships)
make icon-source     # swift generate_icon.swift → Resources/icon.png (HIG squircle)
make icon            # Resources/icon.png → Resources/AppIcon.icns (sips + iconutil)
make reset           # killall Finder
make debug           # Print swift version, target arches, install state + installed arch
```

`make install` hard-fails if `pluginkit -m -v` doesn't list both extension IDs afterwards. If they register but don't appear in Finder's "Customize Toolbar", check for a stale `disabled (unknown)` state in `pluginkit -m -v | grep go2shell`.

### Iterating on an extension without losing Finder windows

`make install` ends in `killall Finder`, which discards every open Finder window. That is unnecessary: the extensions are separate processes that Finder respawns on demand, so killing only those picks up a new binary.

```bash
make build
rm -rf /Applications/go2shell.app && cp -R .build/go2shell.app /Applications/
LS=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
$LS -f /Applications/go2shell.app
pluginkit -a /Applications/go2shell.app/Contents/PlugIns/go2shellTerminal.appex
pluginkit -a /Applications/go2shell.app/Contents/PlugIns/go2shellCopy.appex
pluginkit -e use -i com.solarhell.go2shell.TerminalSync
pluginkit -e use -i com.solarhell.go2shell.CopySync
killall go2shellTerminal go2shellCopy      # NOT killall Finder
```

Verified: the extension processes restart and log from the new binary on the next toolbar click while Finder keeps all its windows.

### Universal binary

`make build` cross-compiles for **both** `arm64` and `x86_64`. `ARCHS` at the top of the Makefile is the only place that list lives.

- The main app goes through `swift build -c release --arch arm64 --arch x86_64`, which relocates the products to **`.build/apple/Products/Release/`** — *not* `.build/release`. `RELEASE_DIR` and the `*.bundle` glob in `create-bundle` both depend on that path, so dropping the `--arch` flags silently breaks bundle assembly.
- The two extensions are compiled once per arch with `swiftc -target <arch>-apple-macosx15.0` into `.build/ext-arch/`, then merged with `lipo -create`. Codesign **after** the lipo — signing thin slices and merging afterwards invalidates the signature.
- `make verify` runs at the end of every `make build` (and again in CI against the unzipped artifact) and fails if any of the three binaries is missing an arch. It exists because v1.1.0 shipped as an x86_64-only zip, hand-built on an Intel Mac, and nothing caught it before it reached the tap.

### Bundle version

The checked-in `Info.plist` files keep a placeholder version — don't bump them by hand. `create-bundle` and both extension targets run `PlistBuddy` over the *copied* plist, writing `CFBundleShortVersionString` from the latest `v*` git tag (`APP_VERSION`) and `CFBundleVersion` from `git rev-list --count HEAD` (`APP_BUILD`). Outside a git checkout it falls back to whatever the source plist says.

All three bundles must get the same version — a container app and an appex that disagree fail App Store validation and make `pluginkit -m -v` output confusing. Each write happens **before** that bundle's `codesign`; reordering them invalidates the signature.

### Target notes

`make run` passes `--show-ui` explicitly — that is the only flag `main.swift` reads. The old `make run-settings` passed `--settings`, which no code has ever read; it and the `run-ui` alias are gone. `make test` just prints a note: `Package.swift` declares no test target and there are no tests in this repo.

Icon regeneration is two steps, both in the Makefile: `make icon-source` runs `generate_icon.swift` to draw the HIG squircle into `Resources/icon.png`, then `make icon` resamples it into the `.icns`. Keep them separate — `icon-source` overwrites `icon.png`, so chaining it into `icon` would clobber a hand-supplied source image.

## Architecture

### Three-binary layout

This is **one app bundle containing three separately-signed executables**:

1. **Main app** (`Sources/`, built by SPM).
2. **TerminalSync extension** (`FinderSyncExtension/TerminalSync/`) — Finder toolbar item "Open in Terminal".
3. **CopySync extension** (`FinderSyncExtension/CopySync/`) — Finder toolbar item "Copy Path".

The extensions are **not** SPM targets. The Makefile compiles each with a direct `swiftc` invocation linking `-Xlinker -e -Xlinker _NSExtensionMain` (the FinderSync entry point; each extension's `main.swift` is deliberately empty) and embeds the `.appex` under `Contents/PlugIns/`. If you add a Swift file to an extension, add it to that extension's `swiftc` line in the Makefile — SPM will not pick it up.

### Main-app launch routing (`Sources/main.swift`)

Three conditions decide between one-shot launcher and settings UI:

- Shows the **UI** if `--show-ui` is passed, **or** Finder is not frontmost (checked via *both* `frontmostApplication` and `menuBarOwningApplication`), **or** the resolved path is empty / starts with `/Applications`.
- The `/Applications` guard is what makes double-clicking the installed app open settings instead of a terminal at `/Applications`.
- Otherwise it resolves the path via `FinderManager` (ScriptingBridge → Finder), falls back to Desktop, calls `TerminalManager.openTerminal(atPath:)`, and exits.

`LSUIElement` in `Resources/Info.plist` keeps the app dockless; `SettingsAppDelegate` raises the activation policy to `.regular` only when SwiftUI actually boots.

### Two independent terminal-launch implementations

**This is the main thing to know before touching terminal behavior.** The same feature exists twice with *different* AppleScript strategies, and neither imports the other:

| | `Sources/TerminalManager.swift` (main app) | `FinderSyncExtension/TerminalSync/TerminalLauncher.swift` (toolbar) |
|---|---|---|
| Enum | `TerminalManager.Terminal` | `SupportedTerminal` |
| Terminal.app | ScriptingBridge `open([url])` | `tell application id … do script "cd …"` |
| iTerm / Warp / WezTerm | `do shell script "open -a X <path>"` | `tell application id` + session write / `warp://action/new_tab?path=` / bare `activate` |
| Path escaping | `appleScriptString()` + AppleScript `quoted form of` | `singleQuoted()` / `urlEncode()` / `appleScriptString()` |

A fix in one does **not** apply to the other. Known live divergence: the extension's WezTerm case only activates the app without any `cd`, while the main app path passes the directory to `open -a`.

Both sides now build shell commands as `"… " & quoted form of <applescript string>` and let AppleScript do the quoting. The old hand-rolled `String.specialCharEscaped(_:)` is gone and must not come back: it escaped `\` *last*, so backslashes it had just inserted got re-escaped and a path with a space came out with six of them, which the shell then collapsed into a literal `\ ` — every iTerm/Warp/WezTerm launch into a directory with a space silently opened the wrong place.

Ghostty is handled identically on both sides and must stay that way: one unconditional `tell application id` that sets `initial working directory` on a `new surface configuration`, with a `count of windows` check so a fresh launch gets a tab rather than a second window. Do **not** reintroduce an `NSRunningApplication` "is it running?" branch — inside the sandboxed extension that check can report Ghostty as not-running while it is, and the `open -na … --working-directory=` fallback it used to guard forces a *second* instance that restores its saved session and drops the working directory entirely (verified: a cold `open -na` with a unique probe path produced no shell at that path). Read the comment block in `TerminalLauncher.swift` before changing this.

### Sandbox asymmetry

The main app is **not sandboxed** (`app-sandbox = false` in `Resources/go2shell.entitlements`); both extensions **are** (Finder requires it). Consequences that show up in extension code:

- `NSHomeDirectory()` returns the sandbox container, so `TerminalSync` reads the real home via `getpwuid` (`realUserHome()`).
- Every app the extension talks to via AppleScript must be listed in `com.apple.security.temporary-exception.apple-events`. `TerminalSync/FinderSync.entitlements` lists Finder **plus all five terminal bundle IDs**; `CopySync/FinderSync.entitlements` lists Finder only (it just writes the pasteboard). The main app needs no such list.

### Settings flow (App Group)

`PreferredTerminal` is shared between all three binaries via the **`group.com.solarhell.go2shell`** App Group. The main app goes through `Sources/SharedDefaults.swift` (which falls back to `.standard` if the group is unavailable, e.g. an unsigned dev run) and binds it with `@AppStorage(store:)` in `Views.swift`; each extension constructs its own `UserDefaults(suiteName:)`. A new shared key needs all three binaries to agree on the suite name.

On first run only (key unset), `detectDefaultTerminal()` in `main.swift` writes `iTerm` if `/Applications/iTerm.app` exists, else `Terminal`.

App Group defaults live in `~/Library/Group Containers/group.com.solarhell.go2shell/Library/Preferences/`, **not** `~/Library/Preferences/`. `defaults read group.com.solarhell.go2shell PreferredTerminal` reports "does not exist" even when the value is set — `plutil -p` the plist in the Group Container instead.

### Settings window

`Views.swift` is a native `Form` with `.formStyle(.grouped)`, constrained in width and `.fixedSize` vertically so the window sizes to its content instead of scrolling inside a fixed frame. All five terminals render in one fixed-order list; uninstalled ones grey out in place rather than moving to a separate group.

The extension-status row goes through `Sources/ExtensionStatus.swift`, which shells out to `pluginkit`. `FIFinderSyncController.isExtensionEnabled` looks like the right API but only reports for the calling *extension's* own process — in the container app it is always false, which silently renders "not enabled" for a perfectly healthy install. The main app is unsandboxed, so spawning `pluginkit` is allowed. `FIFinderSyncController.showExtensionManagementInterface()` *does* work from the container app; it opens System Settings › Login Items & Extensions — the parent pane, not the Finder Extensions sheet, so don't label the button as if it jumps straight there.

Both calls need `FinderSync.framework`, linked from the main app via `linkerSettings` in `Package.swift`.

### Network-volume fallback

`FIFinderSyncController.targetedURL()` / `selectedItemURLs()` return `nil` on SMB/AFP mounts and some Finder views. Both extension controllers fall back to **AppleScript against `com.apple.finder`** (`frontFinderPathViaAppleScript`, duplicated verbatim in both controllers). This is what the `com.apple.finder` entry in each extension's temporary-exception list is for — don't remove it, and don't add `--deep` to the main-app codesign, which would overwrite the extensions' entitlements with the main app's.

### `menu(for:)` must not block

Finder shows a "waiting" indicator if a FinderSync extension blocks in `menu(for:)`. Both controllers capture URLs synchronously (the FinderSync API is main-thread-only), return `nil` immediately, and dispatch the real work — AppleScript fallback, terminal launch, pasteboard write — to `DispatchQueue.global`. Keep this pattern for any new menu action. Both extensions log to `os.Logger` under subsystem `com.solarhell.go2shell.{TerminalSync,CopySync}`; `log show --predicate 'subsystem BEGINSWITH "com.solarhell.go2shell"'` is the only practical way to debug them.

### Finder/Terminal ScriptingBridge headers

`Sources/Finder.{swift,h}` and `Sources/Terminal.{swift,h}` are **auto-generated from the `Finder.app` / `Terminal.app` sdef definitions** and checked in so SPM compiles without running `sdef`. Treat them as opaque — regenerate rather than hand-edit.

### Adding a new terminal

**Four** places must agree:

1. `Sources/TerminalManager.swift` — `Terminal` enum case + `private static func open<Name>(atPath:)`.
2. `FinderSyncExtension/TerminalSync/TerminalLauncher.swift` — `SupportedTerminal` case + a `case` in the AppleScript switch.
3. `FinderSyncExtension/TerminalSync/FinderSync.entitlements` — add the bundle ID to `com.apple.security.temporary-exception.apple-events`, or the sandboxed extension's AppleScript is silently denied.
4. `appPath` (both enums) and `bundleID` must match the real install location and bundle identifier.

The enums are intentionally not shared — the extension doesn't import the main-app target.

## Code signing

Everything is **ad-hoc signed** (`codesign --sign -`). Order matters: each `.appex` is signed with its own entitlements file at build time *and again* after being copied into the bundle, then the main app is signed **without** `--deep` so the extension signatures and entitlements survive. Follow the same order for any manual re-sign: extensions first (with their entitlements), then the outer app with `Resources/go2shell.entitlements`.

Releases are not notarized — the release notes tell users to run `xattr -d com.apple.quarantine`.

## Localization

`Sources/L10n.swift` wraps `NSLocalizedString` against **`Bundle.main`**, not `Bundle.module`. That only works because `create-bundle` in the Makefile copies `Resources/*.lproj` directly into `Contents/Resources/` (separately from the SPM `.bundle`). Both copy steps must stay. The extensions are **not** localized — their `toolbarItemName` / tooltips are hardcoded English.

`Info.plist` sets `CFBundleDevelopmentRegion` to `zh_CN` while `Package.swift` sets `defaultLocalization: "en"`.

## Distribution

`release.yml` (manual `workflow_dispatch`; auto-increments the patch version if none given) creates the tag and GitHub release, then calls `build.yml`, then `update-homebrew.yml`.

`build.yml` runs `make release` and uploads `build/go2shell.zip` + `build/go2shell.zip.sha256`, so local and CI packaging cannot drift — change packaging in the Makefile only. It then unzips the artifact and prints `lipo -archs` for all three binaries.

Installing from the tap needs a trust step first: Homebrew 6 refuses to load casks from untrusted third-party taps, and without `brew trust --cask <tap>/go2shell` even `brew tap` fails with `invalid syntax in tap!`. Both READMEs document it; keep it there.

`update-homebrew.yml` derives both endpoints from the running workflow: the tap is `${{ github.repository_owner }}/homebrew-tap` and the download URL comes from `${{ github.repository }}`, so it follows forks and account renames without edits. (This repo's origin is still written as `dingtang2008/go2shell`; GitHub redirects that to `ElvisLabs/go2shell`, and likewise `dingtang2008/tap` → `ElvisLabs/homebrew-tap`, which is why the README's `brew install dingtang2008/tap/go2shell` still resolves.) The job overwrites `Casks/go2shell.rb` wholesale, so the `caveats` and `zap trash:` stanzas in the workflow heredoc are the source of truth — edit them there, never in the tap.
