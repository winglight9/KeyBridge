import Foundation
import CoreGraphics
import IOKit
import IOKit.hid
import IOKit.hidsystem
import KeyBridgeCore

struct HIDEndpoint {
    enum Kind { case keyboard, trackpad }
    let device: IOHIDDevice
    let kind: Kind
    let product: String
}
enum HIDCatalog {
    static func scan() -> [HIDEndpoint] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var found: [HIDEndpoint] = []
        while true {
            let service = IOIteratorNext(iterator); if service == 0 { break }
            defer { IOObjectRelease(service) }
            guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { continue }
            let page = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue ?? 0
            let usage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? NSNumber)?.intValue ?? 0
            let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "HID device"
            let builtIn = (IOHIDDeviceGetProperty(device, "Built-In" as CFString) as? NSNumber)?.boolValue == true
            let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
            if page == 1, usage == 6, builtIn || product.lowercased().contains("keyboard") {
                found.append(HIDEndpoint(device: device, kind: .keyboard, product: product))
            }
            if page == 1, usage == 2, builtIn, transport == "SPI", product.lowercased().contains("trackpad") {
                found.append(HIDEndpoint(device: device, kind: .trackpad, product: product))
            }
        }
        return found
    }
    static var allowed: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }
    static func requestPermission() { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
}
