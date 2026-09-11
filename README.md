# go2shell

[中文文档](README_zh.md)

Quickly open a terminal from the current Finder directory.

![macOS](https://img.shields.io/badge/macOS-Sequoia%2015%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)

![settings](screenshots/settings.jpg)

> This is a personal fork of [solarhell/go2shell](https://github.com/solarhell/go2shell) with extra polish. See [Fork changes](#fork-changes).

## Features

- **One-click launch** — Open a terminal right from the Finder toolbar
- **Copy path** — Copy the current directory or selected items' paths with one click
- **Network-volume aware** — Works on SMB/AFP mounts and other views where FinderSync normally goes silent
- **Smart detection** — Automatically detects installed terminal apps
- **Native icons** — Displays each terminal's real app icon
- Pure Swift, lightweight and fast
- Simple to use, no complex configuration needed

## Fork changes

Changes in this fork versus upstream:

- **HIG-compliant app icon** — Redesigned to match Apple's Launchpad icon grid (824×824 content area on a dark squircle with subtle gradient). No more size mismatch next to other Launchpad apps.
- **Two Finder toolbar extensions** — A dedicated *Open in Terminal* button plus a new *Copy Path* button, each bundled as a FinderSync extension.
- **Works on network drives** — When FinderSync's URL API returns `nil` (common on SMB/AFP mounts, server browsers, etc.), both extensions fall back to asking Finder via AppleScript. The apple-events entitlement is scoped to `com.apple.finder`.
- **No more "waiting" indicator** — Menu callbacks dispatch the actual work to a background queue so Finder's toolbar stays responsive.
- **Shared preferences across app and extensions** — The preferred-terminal setting is stored in the `group.com.solarhell.go2shell` app group.

### Supported Terminals

The app auto-detects the following terminals. Uninstalled ones are greyed out:

- **Terminal.app** (built-in)
- **iTerm2**
- **Warp**
- **Ghostty**
- **WezTerm**

> If the preferred terminal is uninstalled, it automatically falls back to the built-in Terminal.app.

## Install

### Homebrew (recommended)

```bash
brew install --cask ElvisLabs/tap/go2shell

# Upgrade
brew upgrade --cask ElvisLabs/tap/go2shell
```

Homebrew won't load casks from untrusted third-party taps, but naming the cask
in full counts as explicit consent: brew taps the repo, records the trust and
installs, all from that one command. Only if you want to `brew tap ElvisLabs/tap`
on its own do you need `brew trust ElvisLabs/tap` first — a bare tap names no
cask, so there is nothing for Homebrew to take as consent.

The app is ad-hoc signed rather than notarized, so clear the quarantine flag once:

```bash
xattr -d com.apple.quarantine /Applications/go2shell.app
```

Or go to System Settings > Privacy & Security and click "Open Anyway".

> Upstream builds are at `solarhell/tap/solarhell-go2shell` if you prefer the original.

### Build from source

```bash
make install

# Then drag go2shell.app from /Applications to the Finder toolbar
# (hold ⌘ while dragging)

# Done! Click the toolbar icon to open a terminal in the current directory.
```

## Usage

### Step 1: Add to Finder Toolbar

1. Open the Applications folder
2. Hold **⌘ (Command)**
3. Drag `go2shell.app` onto any Finder window's toolbar
4. Done!

### Step 3: Use

- Click the go2shell icon in any Finder window's toolbar
- A terminal opens at the current directory automatically

### Change Settings

**Option 1: Hold Option key**
- Hold **Option (⌥)** and click go2shell in the Finder toolbar
- Or hold Option and double-click the app icon in Finder
- Select your preferred terminal in the settings UI

**Option 2: Command line**
```bash
open /Applications/go2shell.app --args --show-ui
```

**Option 3: Defaults**
```bash
# Set to Terminal.app (default)
defaults write com.solarhell.go2shell PreferredTerminal Terminal

# Set to iTerm2
defaults write com.solarhell.go2shell PreferredTerminal iTerm

# Set to Warp / Ghostty / WezTerm
defaults write com.solarhell.go2shell PreferredTerminal Warp
defaults write com.solarhell.go2shell PreferredTerminal Ghostty
defaults write com.solarhell.go2shell PreferredTerminal WezTerm
```

## System Requirements

- macOS Sequoia 15.0+
- Apple Silicon or Intel — the release zip is a universal binary
- Xcode 16+ (for building)

## Build

Built with **Swift Package Manager** and **Makefile**.

### Using Makefile (recommended)

```bash
make help      # Show all commands
make build     # Build the app
make install   # Install to /Applications
make clean     # Clean build files
make debug     # Show debug info
```

### Using SPM directly

```bash
swift build -c release
.build/release/go2shell
```

> **Note**: SPM alone only compiles the binary. Use `make build` to create a full App Bundle.

## How It Works

1. Uses Apple Events (AppleScript) to get the frontmost Finder window's path
2. Falls back to the Desktop path if no Finder window is open
3. Opens the preferred terminal at that path via AppleScript
4. Exits automatically after launching the terminal

## Project Structure

```
go2shell/
├── Package.swift              # SPM configuration
├── Makefile                   # Build automation
├── Sources/
│   ├── main.swift             # Entry point
│   ├── Views.swift            # SwiftUI interface
│   ├── TerminalManager.swift  # Terminal launch logic
│   ├── Terminal.swift         # Terminal.app ScriptingBridge
│   ├── Finder.swift           # Finder ScriptingBridge
│   └── FinderManager.swift    # Finder path retrieval
├── Resources/
│   ├── Info.plist             # App configuration
│   ├── go2shell.entitlements  # App entitlements
│   └── AppIcon.icns           # App icon
└── .build/                    # Build output (generated)
```

## Roadmap

- [x] Support Terminal.app, iTerm2, Warp, Ghostty, WezTerm
- [x] Native app icons
- [x] Grey out uninstalled terminals, auto-fallback on uninstall
- [ ] Open in new tab or new window
- [ ] Keyboard shortcuts
- [ ] Custom terminal commands (e.g., run a script after cd)

## License

MIT
