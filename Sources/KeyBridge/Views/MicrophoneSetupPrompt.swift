import AppKit

/// Setup appears only following an explicit microphone sharing request.
/// No settings, installer approval, or restart is performed on the user's behalf.
enum MicrophoneSetupPrompt {
    static func show(title: String, message: String, action: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title; alert.informativeText = message
            alert.addButton(withTitle: action)
            alert.addButton(withTitle: Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "取消" : "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            completion(alert.runModal() == .alertFirstButtonReturn)
        }
    }
}
