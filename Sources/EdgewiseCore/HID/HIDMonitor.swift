import CoreGraphics
import Foundation
import IOKit
import IOKit.hid

/// Owns the IOHIDManager and turns raw device values into `TouchFrame`s.
///
/// The device is opened with `kIOHIDOptionsTypeSeizeDevice` so macOS stops interpreting
/// it. That is the whole trick: without seizing, macOS treats an unrecognised digitizer
/// as a *relative* pointing device — which is why an untouched Xeneon Edge behaves like
/// a trackpad, nudging the cursor from wherever it already sits instead of jumping to
/// where you touched.
///
/// Seizing requires Input Monitoring permission.
public final class HIDMonitor {
    public enum StartError: Error, CustomStringConvertible {
        case openFailed(IOReturn)
        case deviceNotFound

        public var description: String {
            switch self {
            case .openFailed(let code):
                return """
                Could not seize the touch panel (IOReturn \(code)). \
                Grant Input Monitoring, and check no other process holds the device.
                """
            case .deviceNotFound:
                return "No supported touch panel is connected."
            }
        }
    }

    private var manager: IOHIDManager?
    private var parser = HIDReportParser()
    private let panels: [TouchPanel]
    private let clock: @Sendable () -> TimeInterval

    /// Called on the main run loop for every meaningful change in touch state.
    public var onFrame: ((TouchFrame) -> Void)?
    /// Called when the panel disappears, so the runtime can drop stale gesture state.
    public var onDisconnect: (() -> Void)?

    public init(panels: [TouchPanel] = TouchPanel.known,
                clock: @escaping @Sendable () -> TimeInterval = {
                    Date().timeIntervalSinceReferenceDate
                }) {
        self.panels = panels
        self.clock = clock
    }

    public func start() throws {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        let matches = panels.map {
            [kIOHIDVendorIDKey: $0.vendorID, kIOHIDProductIDKey: $0.productID] as CFDictionary
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().handle(value)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            guard let context else { return }
            let monitor = Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.parser.reset()
            monitor.onDisconnect?()
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(),
                                        CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else { throw StartError.openFailed(result) }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              !devices.isEmpty else { throw StartError.deviceNotFound }
    }

    public func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(),
                                          CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }

    private func handle(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let intValue = IOHIDValueGetIntegerValue(value)

        if let frame = parser.ingest(usagePage: page, usage: usage,
                                     value: Int(intValue), timestamp: clock()) {
            onFrame?(frame)
        }
    }

    /// Reads the panel's own coordinate range out of its HID descriptor, so
    /// calibration does not have to be hardcoded.
    public func detectLogicalRange() -> (maxX: Int, maxY: Int)? {
        guard let manager,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first,
              let elements = IOHIDDeviceCopyMatchingElements(device, nil, 0)
                as? [IOHIDElement]
        else { return nil }

        var maxX: Int?, maxY: Int?
        for element in elements {
            let page = Int(IOHIDElementGetUsagePage(element))
            let usage = Int(IOHIDElementGetUsage(element))
            guard page == HIDUsage.Page.genericDesktop else { continue }
            let logicalMax = Int(IOHIDElementGetLogicalMax(element))
            guard logicalMax > 0 else { continue }
            if usage == HIDUsage.x { maxX = max(maxX ?? 0, logicalMax) }
            if usage == HIDUsage.y { maxY = max(maxY ?? 0, logicalMax) }
        }
        guard let x = maxX, let y = maxY else { return nil }
        return (x, y)
    }
}
