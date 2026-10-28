import AppKit

enum BrandAssets {
    static func menuIcon(active: Bool = false) -> NSImage? {
        let name = active ? "MenuBarActive" : "MenuBar"
        let image = Bundle.main.url(forResource: name, withExtension: "pdf")
            .flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: "KeyBridge")
        image?.size = NSSize(width: 20, height: 20)
        image?.isTemplate = true
        image?.accessibilityDescription = active ? "KeyBridge · Forwarding" : "KeyBridge"
        return image
    }

    static var appIcon: NSImage {
        Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            .flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: "KeyBridge")!
    }
}
