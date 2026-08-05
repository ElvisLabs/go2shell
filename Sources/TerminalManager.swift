// 移植自 OpenInTerminal - OpenInTerminalCore/App.swift (Terminal 部分)

import Cocoa
import ScriptingBridge

class TerminalManager {
    enum Terminal: String, CaseIterable {
        case terminal = "Terminal"
        case iterm = "iTerm"
        case warp = "Warp"
        case ghostty = "Ghostty"
        case wezterm = "WezTerm"

        var displayName: String {
            switch self {
            case .terminal: return "Terminal.app"
            case .iterm: return "iTerm2"
            case .warp: return "Warp"
            case .ghostty: return "Ghostty"
            case .wezterm: return "WezTerm"
            }
        }

        var appPath: String {
            switch self {
            case .terminal: return "/System/Applications/Utilities/Terminal.app"
            case .iterm: return "/Applications/iTerm.app"
            case .warp: return "/Applications/Warp.app"
            case .ghostty: return "/Applications/Ghostty.app"
            case .wezterm: return "/Applications/WezTerm.app"
            }
        }

        var isInstalled: Bool {
            FileManager.default.fileExists(atPath: appPath)
        }
    }

    static func openTerminal(atPath path: String, override: String? = nil) {
        let terminalName = override
            ?? SharedDefaults.shared.string(forKey: "PreferredTerminal")
            ?? "Terminal"
        var terminal = Terminal(rawValue: terminalName) ?? .terminal
        if !terminal.isInstalled {
            terminal = .terminal
        }

        switch terminal {
        case .terminal:
            openAppleTerminal(atPath: path)
        case .iterm:
            openITerm(atPath: path)
        case .warp:
            openWarp(atPath: path)
        case .ghostty:
            openGhostty(atPath: path)
        case .wezterm:
            openWezTerm(atPath: path)
        }
    }

    /// Terminal.app — 移植自 OpenInTerminal 的 ScriptingBridge 方式
    private static func openAppleTerminal(atPath path: String) {
        let url = URL(fileURLWithPath: path)
        guard let terminal = SBApplication(bundleIdentifier: "com.apple.Terminal") as TerminalApplication?,
              let open = terminal.open else {
            return
        }
        open([url])
        terminal.activate()
    }

    /// iTerm2 — 移植自 OpenInTerminal 的 shell 命令方式
    private static func openITerm(atPath path: String) {
        let source = """
        do shell script "open -a iTerm " & quoted form of \(appleScriptString(path))
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }

    /// Warp
    private static func openWarp(atPath path: String) {
        let source = """
        do shell script "open -a Warp " & quoted form of \(appleScriptString(path))
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }

    /// Ghostty — uses Ghostty 1.x's AppleScript dictionary to add a tab carrying
    /// the initial working directory. `tell application id` launches Ghostty when
    /// needed, so there is no cold-start branch: `open -na` would force a second
    /// instance that restores its saved session and drops --working-directory.
    /// See the FinderSync extension's TerminalLauncher.swift for the full reasoning.
    private static func openGhostty(atPath path: String) {
        let source = """
        tell application id "com.mitchellh.ghostty"
            activate
            set cfg to new surface configuration
            set initial working directory of cfg to \(appleScriptString(path))
            if (count of windows) > 0 then
                new tab in front window with configuration cfg
            else
                new window with configuration cfg
            end if
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }

    private static func appleScriptString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// WezTerm
    private static func openWezTerm(atPath path: String) {
        let source = """
        do shell script "open -a WezTerm " & quoted form of \(appleScriptString(path))
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }
}
