import Foundation

/// Whether the bundled FinderSync extensions are enabled.
///
/// `FIFinderSyncController.isExtensionEnabled` only reports for the calling
/// extension's own process — in the container app it is always false — so ask
/// pluginkit, which is what `make install` uses as the source of truth. The
/// main app is not sandboxed, so spawning it is allowed.
enum ExtensionStatus {
    static let identifiers = [
        "com.solarhell.go2shell.TerminalSync",
        "com.solarhell.go2shell.CopySync",
    ]

    static func allEnabled() -> Bool {
        identifiers.allSatisfy(isEnabled)
    }

    private static func isEnabled(_ identifier: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = ["-m", "-v", "-i", identifier]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        // Column 1 carries the state flag; `+` is enabled, `-` disabled.
        guard let output = String(data: data, encoding: .utf8) else { return false }
        return output.split(separator: "\n").contains {
            $0.hasPrefix("+") && $0.contains(identifier)
        }
    }
}
