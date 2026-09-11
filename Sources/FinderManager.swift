// 移植自 OpenInTerminal - OpenInTerminalCore/FinderManager.swift

import Cocoa
import ScriptingBridge

final class FinderManager: Sendable {

    static let shared = FinderManager()

    /// Get path to front Finder window or selected file.
    /// If the selected one is file, return its parent path.
    func getPathToFrontFinderWindowOrSelectedFile() -> String? {
        guard let fullUrl = getFullUrlToFrontFinderWindowOrSelectedFile() else {
            return nil
        }

        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: fullUrl.path, isDirectory: &isDirectory) else {
            return nil
        }

        // if the selected is a file, then delete last path component
        guard isDirectory.boolValue else {
            return fullUrl.deletingLastPathComponent().path
        }

        return fullUrl.path
    }

    /// Get full url to front Finder window or selected file
    func getFullUrlToFrontFinderWindowOrSelectedFile() -> URL? {
        guard let finder = SBApplication(bundleIdentifier: "com.apple.finder") as FinderApplication?,
              let selection = finder.selection,
              let selectionItems = selection.get() as? [AnyObject] else {
            return nil
        }

        let target: FinderItem

        if let firstItem = selectionItems.first as? FinderItem {
            // Files or folders selected
            target = firstItem
        } else {
            // Nothing selected: use the front window's target. `target` is nil
            // for windows that aren't showing a folder (search results, Recents,
            // Trash queries), so never force it — the caller falls back to Desktop.
            guard let windows = finder.FinderWindows?(),
                  let firstWindow = windows.firstObject as? FinderFinderWindow,
                  let windowTarget = firstWindow.target?.get() as? FinderItem else {
                return nil
            }
            target = windowTarget
        }

        guard let targetUrl = target.URL,
              let url = URL(string: targetUrl) else {
            return nil
        }

        return url
    }

    func getDesktopPath() -> String? {
        // URL(string:) returns nil for any home path that needs percent-encoding
        // (a username containing a space); fileURLWithPath takes it literally.
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop").path
    }
}
