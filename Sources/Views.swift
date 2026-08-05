import Cocoa
import FinderSync
import SwiftUI

// MARK: - SwiftUI App（不带 @main，由 main.swift 手动调用）

struct Go2ShellApp: App {
    @NSApplicationDelegateAdaptor(SettingsAppDelegate.self) var appDelegate

    var body: some Scene {
        Window("go2shell", id: "main") {
            MainView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

class SettingsAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// MARK: - Views

struct MainView: View {
    @AppStorage("PreferredTerminal", store: SharedDefaults.shared)
    private var preferredTerminal = "Terminal"

    @State private var extensionEnabled = ExtensionStatus.allEnabled()

    var body: some View {
        Form {
            Section {
                ForEach(TerminalManager.Terminal.allCases, id: \.rawValue) { terminal in
                    terminalRow(terminal)
                }
            } header: {
                Text(L10n.preferredTerminal)
            } footer: {
                Text(L10n.fallbackNote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(L10n.manageExtensions) {
                    FIFinderSyncController.showExtensionManagementInterface()
                }
            } header: {
                HStack {
                    Text(L10n.finderExtension)
                    Spacer()
                    Label(
                        extensionEnabled ? L10n.extensionEnabled : L10n.extensionDisabled,
                        systemImage: extensionEnabled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(extensionEnabled ? Color.green : Color.orange)
                }
            } footer: {
                Text(L10n.toolbarHint)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        // Re-read on activation so toggling the extension in System Settings
        // shows up without relaunching.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            extensionEnabled = ExtensionStatus.allEnabled()
        }
    }

    /// Hand-rolled radio row: uninstalled terminals must keep their position and
    /// grey out, which per-item `.disabled()` inside a `Picker` doesn't do on macOS.
    private func terminalRow(_ terminal: TerminalManager.Terminal) -> some View {
        let selected = preferredTerminal == terminal.rawValue
        return HStack(spacing: 8) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            if let icon = appIcon(for: terminal.appPath) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "questionmark.app.dashed")
                    .foregroundStyle(.tertiary)
                    .frame(width: 16, height: 16)
            }
            Text(terminal.displayName)
            Spacer()
            if !terminal.isInstalled {
                Text(L10n.notInstalled)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .opacity(terminal.isInstalled ? 1 : 0.5)
        .onTapGesture {
            if terminal.isInstalled { preferredTerminal = terminal.rawValue }
        }
    }

    private func appIcon(for appPath: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: appPath) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: appPath)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}
