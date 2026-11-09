import ApplicationServices

public enum AccessibilityPermission {
    /// Value of `kAXTrustedCheckOptionPrompt`; the imported C global is a mutable `var` that Swift 6 rejects.
    private static let trustedCheckOptionPrompt = "AXTrustedCheckOptionPrompt"

    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to System Settings › Privacy & Security › Accessibility.
    public static func request() {
        let options = [trustedCheckOptionPrompt: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
