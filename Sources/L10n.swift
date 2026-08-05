import Foundation

enum L10n {
    private static let bundle = Bundle.main

    static let preferredTerminal = NSLocalizedString("settings.preferred_terminal", bundle: bundle, comment: "")
    static let notInstalled = NSLocalizedString("settings.not_installed", bundle: bundle, comment: "")
    static let fallbackNote = NSLocalizedString("settings.fallback_note", bundle: bundle, comment: "")
    static let finderExtension = NSLocalizedString("settings.finder_extension", bundle: bundle, comment: "")
    static let extensionEnabled = NSLocalizedString("settings.extension_enabled", bundle: bundle, comment: "")
    static let extensionDisabled = NSLocalizedString("settings.extension_disabled", bundle: bundle, comment: "")
    static let manageExtensions = NSLocalizedString("settings.manage_extensions", bundle: bundle, comment: "")
    static let toolbarHint = NSLocalizedString("settings.toolbar_hint", bundle: bundle, comment: "")
}
