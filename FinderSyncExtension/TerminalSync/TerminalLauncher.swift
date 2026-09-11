import AppKit
import Foundation
import os

enum SupportedTerminal: String, CaseIterable {
    case terminal = "Terminal"
    case iterm = "iTerm"
    case warp = "Warp"
    case ghostty = "Ghostty"
    case wezterm = "WezTerm"

    var bundleID: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iterm: return "com.googlecode.iterm2"
        case .warp: return "dev.warp.Warp-Stable"
        case .ghostty: return "com.mitchellh.ghostty"
        case .wezterm: return "com.github.wez.wezterm"
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

    var isInstalled: Bool { FileManager.default.fileExists(atPath: appPath) }
}

enum TerminalLauncher {
    private static let groupDefaults = UserDefaults(suiteName: "group.com.solarhell.go2shell")
    private static let logger = Logger(subsystem: "com.solarhell.go2shell.TerminalSync", category: "launcher")

    static func open(path: String) {
        let name = groupDefaults?.string(forKey: "PreferredTerminal") ?? "Terminal"
        var terminal = SupportedTerminal(rawValue: name) ?? .terminal
        if !terminal.isInstalled { terminal = .terminal }

        // Use `tell application id "..."`: AppleScript resolves via LaunchServices,
        // launches the app if needed, and waits until AppleEvents are ready —
        // much more reliable than name-based tell plus a manual delay.
        let source: String
        switch terminal {
        case .terminal:
            source = """
            tell application id "\(terminal.bundleID)"
                activate
                do script "cd " & quoted form of \(appleScriptString(path))
            end tell
            """
        case .iterm:
            source = """
            tell application id "\(terminal.bundleID)"
                activate
                try
                    tell current window to create tab with default profile
                on error
                    create window with default profile
                end try
                tell current session of current window
                    write text "cd " & quoted form of \(appleScriptString(path))
                end tell
            end tell
            """
        case .warp:
            source = """
            tell application id "\(terminal.bundleID)" to activate
            do shell script "open " & quoted form of "warp://action/new_tab?path=\(urlEncode(path))"
            """
        case .ghostty:
            // Ghostty 1.x ships an AppleScript dictionary (`new tab` / `new
            // window` with a `surface configuration` carrying the initial
            // working directory). When Ghostty is already running, that's how
            // we reuse the existing process instead of spawning a new app
            // instance. When it's NOT running, AppleScript would activate it
            // and Ghostty would auto-open its default window at the user's
            // home dir, then a second `new window` for our path — two
            // windows — but the `count of windows` check below already handles
            // that by adding a tab to whatever window the launch opened.
            //
            // Do NOT reintroduce an NSRunningApplication branch here: in the
            // sandboxed extension it can report Ghostty as not-running while
            // it is, and the `open -na … --working-directory=` fallback it
            // used to guard forces a *second* instance that restores its saved
            // session and silently drops the working directory — the terminal
            // then lands in an unrelated old tab. Note: `new tab` requires an
            // explicit `in <window>` even though the sdef marks it optional.
            source = """
            tell application id "\(terminal.bundleID)"
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
        case .wezterm:
            source = """
            tell application id "\(terminal.bundleID)" to activate
            """
        }

        logger.log("terminal=\(terminal.rawValue, privacy: .public) path=\(path, privacy: .public)")

        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if result == nil {
            logger.error("AppleScript failed: \(error?.description ?? "nil", privacy: .public)")
        }
    }

    /// Percent-encoding for Warp's `path=` query value. `.urlPathAllowed`
    /// keeps sub-delimiters like `&` and `+`, which would truncate the query
    /// for a directory whose name contains one.
    private static func urlEncode(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~/"))
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// AppleScript string literal, with backslash and double-quote escaped.
    private static func appleScriptString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
