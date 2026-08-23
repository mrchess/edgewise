import CoreGraphics
import Foundation
import IOKit
import IOKit.hid

/// Writes driver diagnostics to a file when EDGEWISE_DEBUG is set. An agent app has no
/// terminal, so `print` from one goes nowhere.
public enum HIDTrace {
    nonisolated(unsafe) private static var counts: [String: Int] = [:]
    public nonisolated(unsafe) static var url = URL(fileURLWithPath: "/tmp/edgewise-debug.log")

    public static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["EDGEWISE_DEBUG"] != nil
    }

    public static func log(_ message: String) {
        guard isEnabled else { return }
        let line = "\(Date()) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    /// Logs only every 50th occurrence, so a 100Hz report stream stays readable.
    public static func sampled(_ key: String) {
        guard isEnabled else { return }
        counts[key, default: 0] += 1
        if counts[key]! % 50 == 1 { log("\(key) count=\(counts[key]!)") }
    }
}

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
    /// Set once the digitizer sends anything, after which the mouse interface — which
    /// describes the same finger as a single pointer — is ignored as a duplicate.
    private var hasSeenDigitizerData = false

    /// Called the first time the digitizer reports, i.e. when multi-finger gestures
    /// become possible. On a panel stuck in mouse emulation it never fires.
    public var onMultiContactAvailable: (() -> Void)?
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
            monitor.hasSeenDigitizerData = false
            monitor.onDisconnect?()
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(),
                                        CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else { throw StartError.openFailed(result) }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              !devices.isEmpty else { throw StartError.deviceNotFound }

        HIDTrace.log("open: \(devices.count) interface(s) matched")
        for device in devices {
            let page = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString)
                        as? Int) ?? -1
            let usage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString)
                         as? Int) ?? -1
            HIDTrace.log("  interface page=\(page) usage=\(usage) digitizer=\(isDigitizer(device))")
            if isDigitizer(device) { enableMultiTouch(on: device) }
        }
    }
    /// Switches the panel out of mouse emulation and into multi-touch reporting.
    ///
    /// This panel powers up in mouse mode: its digitizer interface is present and fully
    /// described, but reports nothing, while a mouse-emulation interface sends a single
    /// pointer. That is why it looks single-touch on a Mac, and why its multi-touch is
    /// widely assumed to be a hardware limitation. Corsair specify five-point touch, so
    /// the capability is there; it simply is never switched on.
    ///
    /// The digitizer declares a Device Configuration feature report (usage 0x0D/0x0E,
    /// report ID 0x21) holding Device Mode and Device Identifier. Linux's
    /// `hid-multitouch` writes that field during probe, which is what makes panels of
    /// this class work there. macOS has no equivalent, so it stays in mouse mode.
    ///
    /// Following that driver: 0x02 selects touchscreen and 0x03 touchpad, and it carries
    /// a quirk for devices that only accept the write once the report has been read.
    /// Both values and that ordering are tried here, and the result is verified by
    /// reading back rather than by trusting the return code — this panel returns success
    /// for a write it then ignores.
    @discardableResult
    private func enableMultiTouch(on device: IOHIDDevice) -> Bool {
        let reportID: CFIndex = 0x21
        /// Matches `MT_INPUTMODE_TOUCHSCREEN` and `MT_INPUTMODE_TOUCHPAD`.
        let modes: [UInt8] = [0x02, 0x03]

        // Read first: some devices refuse the write until the report has been read once.
        HIDTrace.log("  device mode initial: \(describe(readFeature(device, reportID)))")

        for mode in modes {
            var payload: [UInt8] = [mode, 0x00]
            let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, reportID,
                                              &payload, payload.count)
            let readBack = readFeature(device, reportID)
            HIDTrace.log(String(format: "  set mode 0x%02x -> ret=%d, reads back %@",
                                mode, result, describe(readBack)))
            if let readBack, readBack.first == mode { return true }
        }
        return false
    }

    /// Reads the Device Configuration feature report.
    ///
    /// The buffer is sized to the two bytes the descriptor declares. An oversized one
    /// comes back holding the control-transfer setup packet rather than report data,
    /// which reads as plausible nonsense — that is how an earlier attempt convinced
    /// itself it had read a device mode it never saw.
    private func readFeature(_ device: IOHIDDevice, _ reportID: CFIndex) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: 2)
        var length = buffer.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, reportID,
                                          &buffer, &length)
        guard result == kIOReturnSuccess, length > 0 else { return nil }
        return Array(buffer.prefix(length))
    }

    private func describe(_ bytes: [UInt8]?) -> String {
        guard let bytes else { return "unreadable" }
        return bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
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
        let device = IOHIDElementGetDevice(element)

        // Prefer the digitizer once it starts reporting. Until then accept the
        // mouse interface, so a panel whose mode switch was refused still taps —
        // single touch is a poor outcome, no touch at all is a broken one.
        let digitizer = isDigitizer(device)
        HIDTrace.sampled("hid digitizer=\(digitizer)")
        if digitizer {
            if !hasSeenDigitizerData {
                HIDTrace.log("digitizer is now reporting")
                onMultiContactAvailable?()
            }
            hasSeenDigitizerData = true
        } else if hasSeenDigitizerData {
            return
        }
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
