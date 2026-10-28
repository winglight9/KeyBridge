import SwiftUI
import AppKit
import Combine
import Darwin

private struct PopupSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
private struct PopupRoot: View {
    @ObservedObject var store: BridgeStore
    var onSize: (CGSize) -> Void
    var body: some View {
        BridgePopover(store:store).fixedSize()
            .background(GeometryReader { proxy in Color.clear.preference(key:PopupSizeKey.self,value:proxy.size) })
            .onPreferenceChange(PopupSizeKey.self, perform:onSize)
    }
}

final class KeyBridgeDelegate: NSObject, NSApplicationDelegate {
    private var store: BridgeStore!
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var observer: AnyCancellable?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store = BridgeStore(initialMode:CommandLine.arguments.contains("--bluetooth") ? .bluetooth : CommandLine.arguments.contains("--wired") ? .wired : nil)
        item = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        item.button?.image = BrandAssets.menuIcon()
        item.button?.target = self; item.button?.action = #selector(toggle)
        item.button?.toolTip = "KeyBridge · 键桥"
        DistributedNotificationCenter.default().addObserver(self,selector:#selector(showRequested),name:Notification.Name("org.keybridge.show"),object:nil)
        popover.behavior = .transient; popover.animates = false
        let root = PopupRoot(store:store) { [weak self] size in
            guard let self, size.width > 0, size.height > 0 else { return }
            self.popover.contentSize = size
        }
        popover.contentViewController = NSHostingController(rootView:root)
        observer = store.$forwarding.receive(on:DispatchQueue.main).sink { [weak self] active in
            self?.item?.button?.image = BrandAssets.menuIcon(active:active)
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.4) { [weak self] in self?.show() }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.9) { [weak self] in
            if CommandLine.arguments.contains("--request-input") { self?.store.grantInput() }
            if CommandLine.arguments.contains("--request-control") { self?.store.grantReceive() }
        }
    }
    @objc private func toggle() { if popover.isShown { popover.performClose(nil) } else { show() } }
    @objc private func showRequested(_ notification:Notification) { show() }
    private func show() {
        guard let button = item?.button else { return }
        NSApp.activate(ignoringOtherApps:true)
        popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY)
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) { [weak self] in self?.saveInterfaceSnapshot() }
    }
    private func saveInterfaceSnapshot() {
        guard let view = popover.contentViewController?.view,
              let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) else { return }
        view.cacheDisplay(in:view.bounds,to:bitmap)
        guard let png = bitmap.representation(using:.png,properties:[:]) else { return }
        try? FileManager.default.createDirectory(at:Diagnostics.directory,withIntermediateDirectories:true)
        try? png.write(to:Diagnostics.directory.appendingPathComponent("interface.png"),options:.atomic)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    func applicationWillTerminate(_ notification: Notification) { store?.shutdown() }
}

@main
enum KeyBridgeMain {
    private static var singleton: Int32 = -1
    static func main() {
        if CommandLine.arguments.contains("--diagnostics") { Diagnostics.printHardware(); return }
        try? FileManager.default.createDirectory(at:Diagnostics.directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        singleton = Darwin.open(Diagnostics.directory.appendingPathComponent("application.lock").path,O_CREAT | O_RDWR,mode_t(0o600))
        guard singleton >= 0, flock(singleton,LOCK_EX | LOCK_NB) == 0 else {
            DistributedNotificationCenter.default().postNotificationName(Notification.Name("org.keybridge.show"),object:nil,userInfo:nil,deliverImmediately:true)
            return
        }
        let application = NSApplication.shared
        let delegate = KeyBridgeDelegate(); application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
