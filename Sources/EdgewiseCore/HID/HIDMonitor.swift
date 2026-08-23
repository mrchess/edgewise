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
    /// Cache of which devices are the digitizer, keyed by device pointer. Looking the
    /// properties up per value would mean two IOKit calls on every coordinate.
    private var isDigitizerCache: [UnsafeMutableRawPointer: Bool] = [:]
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

        // Match interface by interface rather than by VID/PID alone. Matching the
        // whole device would also seize the vendor command pipe, needlessly locking
        // out anything that wants to control the panel's brightness or settings.
        let matches = panels.flatMap { panel in
            HIDInterface.claimed.map { interface in
                [
                    kIOHIDVendorIDKey: panel.vendorID,
                    kIOHIDProductIDKey: panel.productID,
                    kIOHIDDeviceUsagePageKey: interface.usagePage,
                    kIOHIDDeviceUsageKey: interface.usage,
                ] as CFDictionary
            }
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
            monitor.isDigitizerCache.removeAll()
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

    /// True for the panel's multi-touch digitizer interface, false for its
    /// mouse-emulation one.
    ///
    /// The panel exposes both. We seize both — the mouse interface has to be claimed
    /// or macOS keeps using it to drive the cursor — but only the digitizer's reports
    /// are worth reading. The mouse interface describes a single pointer and sends no
    /// Contact ID, so its reports land in contact slot 0 and overwrite whatever the
    /// digitizer put there. Two fingers then collapse into one, which is why every
    /// multi-finger gesture behaved like a single drag.
    private func isDigitizer(_ device: IOHIDDevice) -> Bool {
        let key = Unmanaged.passUnretained(device).toOpaque()
        if let cached = isDigitizerCache[key] { return cached }

        let page = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString)
                    as? Int) ?? 0
        let usage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString)
                     as? Int) ?? 0
        let result = page == HIDInterface.digitizer.usagePage
                  && usage == HIDInterface.digitizer.usage
        isDigitizerCache[key] = result
        return result
    }

    private func handle(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        guard isDigitizer(IOHIDElementGetDevice(element)) else { return }
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
