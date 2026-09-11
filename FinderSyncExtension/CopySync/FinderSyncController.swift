import Cocoa
import FinderSync
import os

@objc(FinderSyncController)
final class FinderSyncController: FIFinderSync {

    private static let logger = Logger(subsystem: "com.solarhell.go2shell.CopySync", category: "main")

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func beginObservingDirectory(at url: URL) {}
    override func endObservingDirectory(at url: URL) {}
    override func requestBadgeIdentifier(for url: URL) {}

    override var toolbarItemName: String { "Copy Path" }
    override var toolbarItemToolTip: String {
        "Copy current directory, or full paths of selected items"
    }
    override var toolbarItemImage: NSImage {
        let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Copy Path") ?? NSImage()
        image.isTemplate = true
        return image
    }

    // Capture URLs synchronously (FinderSync API is main-thread-only), then
    // do the AppleScript fallback + pasteboard write on a background queue so
    // the menu callback returns immediately. Blocking in `menu(for:)` makes
    // Finder show a "waiting" indicator.
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        log("menu(for:) called kind=\(menuKind.rawValue)")
        guard menuKind == .toolbarItemMenu else { return nil }
        let controller = FIFinderSyncController.default()
        let selected = controller.selectedItemURLs() ?? []
        let targeted = controller.targetedURL()
        DispatchQueue.global(qos: .userInitiated).async {
            Self.copyPathToPasteboard(selected: selected, targeted: targeted)
        }
        return nil
    }

    private static func copyPathToPasteboard(selected: [URL], targeted: URL?) {
        let urls: [URL]
        if !selected.isEmpty {
            urls = selected
        } else if let t = targeted, t.isFileURL, !t.path.isEmpty {
            urls = [t]
        } else {
            // URL(fileURLWithPath:) also strips the trailing slash AppleScript
            // puts on folder paths, so output matches the FinderSync branches.
            urls = frontFinderPathsViaAppleScript().map { URL(fileURLWithPath: $0) }
        }
        let text = urls.map { $0.path }.joined(separator: "\n")
        logger.log("selected=\(selected.count, privacy: .public) targeted=\(targeted?.path ?? "nil", privacy: .public) text=\(text, privacy: .public)")
        guard !text.isEmpty else { return }
        DispatchQueue.main.async {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
    }

    /// Fallback for when the FinderSync API returns nil URLs — network mounts,
    /// iCloud Drive, some Finder views. Ask for the selection *first*: in those
    /// locations `selectedItemURLs()` is empty too, so falling straight through
    /// to the window target silently copies the parent folder of whatever the
    /// user actually selected. Requires the com.apple.finder apple-events
    /// exception in the extension's entitlements.
    private static func frontFinderPathsViaAppleScript() -> [String] {
        let source = """
        tell application "Finder"
            try
                set sel to selection as alias list
                if (count of sel) > 0 then
                    set out to {}
                    repeat with anItem in sel
                        set end of out to POSIX path of anItem
                    end repeat
                    return out
                end if
                return {POSIX path of ((target of front window) as alias)}
            on error
                return {}
            end try
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return [] }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if let error = error {
            logger.error("Finder AppleScript failed: \(error, privacy: .public)")
            return []
        }
        // An AppleScript list comes back as a descriptor list (1-based); a bare
        // string has numberOfItems == 0.
        if descriptor.numberOfItems > 0 {
            return (1...descriptor.numberOfItems).compactMap {
                descriptor.atIndex($0)?.stringValue
            }.filter { !$0.isEmpty }
        }
        if let single = descriptor.stringValue, !single.isEmpty { return [single] }
        return []
    }

    private func log(_ message: String) {
        Self.logger.log("\(message, privacy: .public)")
    }
}
