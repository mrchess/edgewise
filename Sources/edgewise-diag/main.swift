import ApplicationServices
import CoreGraphics
import EdgewiseCore
import Foundation
import IOKit
import IOKit.hid

// Diagnostics and QA tool. Everything here is read-only or writes a fixture file —
// it never posts an event, so it is always safe to run.

func usage() -> Never {
    print("""
    edgewise-diag — diagnostics for the Edgewise touch driver

      doctor              Check permissions, panel, and display mapping
      devices             List connected touch panels and their HID ranges
      displays            List displays and show which one resolves as the panel
      record <file> [s]   Record raw HID values to a fixture (default 10s)
      replay <file>       Replay a fixture and print the gestures it produces
      watch               Print live gestures without posting any events
    """)
    exit(0)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { usage() }

// MARK: - displays

func printDisplays() {
    let displays = DisplayProvider.current()
    print("Displays (\(displays.count)):\n")
    for d in displays {
        let tags = [d.isMain ? "main" : nil, d.isBuiltin ? "built-in" : nil]
            .compactMap { $0 }.joined(separator: ", ")
        print("  id \(d.id)  \(d.name ?? "unnamed")")
        print("     \(Int(d.bounds.width))x\(Int(d.bounds.height)) "
              + "@ (\(Int(d.bounds.minX)),\(Int(d.bounds.minY)))"
              + (tags.isEmpty ? "" : "  [\(tags)]"))
        print("     vendor \(d.vendorNumber)  model \(d.modelNumber)  serial \(d.serialNumber)")
    }

    let configuration = Configuration.load()
    let criteria = DisplayResolver.Criteria(identity: configuration.displayIdentity)
    if let match = DisplayResolver(criteria: criteria).resolve(among: displays) {
        print("\n  ✓ Panel resolved to \(match.display.name ?? "id \(match.display.id)") "
              + "by \(match.how)")
    } else {
        print("\n  ✗ Could not identify the panel. Set it manually in Edgewise.")
    }
}

// MARK: - devices

func openManager(seize: Bool) -> IOHIDManager? {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let matches = TouchPanel.known.map {
        [kIOHIDVendorIDKey: $0.vendorID, kIOHIDProductIDKey: $0.productID] as CFDictionary
    }
    IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
    let options = seize ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
                        : IOOptionBits(kIOHIDOptionsTypeNone)
    guard IOHIDManagerOpen(manager, options) == kIOReturnSuccess else { return nil }
    return manager
}

func printDevices() {
    guard let manager = openManager(seize: false) else {
        print("✗ Could not open HID manager. Grant Input Monitoring.")
        exit(1)
    }
    guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
          !devices.isEmpty else {
        print("✗ No supported touch panel found.")
        print("  Looking for:")
        for p in TouchPanel.known {
            print(String(format: "    %@  VID 0x%04x  PID 0x%04x", p.name, p.vendorID, p.productID))
        }
        exit(1)
    }

    for device in devices {
        func string(_ key: String) -> String {
            (IOHIDDeviceGetProperty(device, key as CFString) as? String) ?? "?"
        }
        func number(_ key: String) -> Int {
            (IOHIDDeviceGetProperty(device, key as CFString) as? Int) ?? 0
        }
        print("Panel: \(string(kIOHIDProductKey))  by \(string(kIOHIDManufacturerKey))")
        print(String(format: "  VID 0x%04x  PID 0x%04x  serial %@",
                     number(kIOHIDVendorIDKey), number(kIOHIDProductIDKey),
                     string(kIOHIDSerialNumberKey)))

        guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, 0)
                as? [IOHIDElement] else { continue }
        var seen = Set<String>()
        print("  Reported usages:")
        for element in elements {
            let page = Int(IOHIDElementGetUsagePage(element))
            let usage = Int(IOHIDElementGetUsage(element))
            let lo = Int(IOHIDElementGetLogicalMin(element))
            let hi = Int(IOHIDElementGetLogicalMax(element))
            let key = "\(page):\(usage)"
            guard seen.insert(key).inserted else { continue }
            let name = usageName(page: page, usage: usage)
            let range = hi > 0 ? "  [\(lo)...\(hi)]" : ""
            print(String(format: "    page 0x%02x usage 0x%02x  %@%@", page, usage, name, range))
        }
    }
}

func usageName(page: Int, usage: Int) -> String {
    switch (page, usage) {
    case (HIDUsage.Page.genericDesktop, HIDUsage.x): return "X"
    case (HIDUsage.Page.genericDesktop, HIDUsage.y): return "Y"
    case (HIDUsage.Page.digitizer, HIDUsage.tipSwitch): return "Tip Switch"
    case (HIDUsage.Page.digitizer, HIDUsage.contactID): return "Contact ID"
    case (HIDUsage.Page.digitizer, HIDUsage.contactCount): return "Contact Count"
    case (HIDUsage.Page.button, HIDUsage.button1): return "Button 1"
    default: return ""
    }
}

// MARK: - record

final class Recorder {
    var values: [HIDFixture.Value] = []
    let start = Date().timeIntervalSinceReferenceDate
    var maxX = 0, maxY = 0
}

func record(to path: String, seconds: Double) {
    guard let manager = openManager(seize: false) else {
        print("✗ Could not open HID manager. Grant Input Monitoring.")
        exit(1)
    }
    let recorder = Recorder()
    let context = Unmanaged.passUnretained(recorder).toOpaque()

    IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
        guard let context else { return }
        let recorder = Unmanaged<Recorder>.fromOpaque(context).takeUnretainedValue()
        let element = IOHIDValueGetElement(value)
        let page = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let hi = Int(IOHIDElementGetLogicalMax(element))
        if page == HIDUsage.Page.genericDesktop {
            if usage == HIDUsage.x { recorder.maxX = max(recorder.maxX, hi) }
            if usage == HIDUsage.y { recorder.maxY = max(recorder.maxY, hi) }
        }
        recorder.values.append(.init(
            usagePage: page, usage: usage, value: Int(IOHIDValueGetIntegerValue(value)),
            offset: Date().timeIntervalSinceReferenceDate - recorder.start))
    }, context)

    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(),
                                    CFRunLoopMode.defaultMode.rawValue)

    print("Recording for \(Int(seconds))s — perform the gesture on the panel now…")
    CFRunLoopRunInMode(.defaultMode, seconds, false)

    let panel = TouchPanel.xeneonEdge
    let fixture = HIDFixture(
        name: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
        panel: panel.name,
        logicalMaxX: recorder.maxX > 0 ? recorder.maxX : panel.fallbackLogicalMaxX,
        logicalMaxY: recorder.maxY > 0 ? recorder.maxY : panel.fallbackLogicalMaxY,
        values: recorder.values)
    do {
        try fixture.write(to: URL(fileURLWithPath: path))
        print("✓ Recorded \(recorder.values.count) values to \(path)")
        if recorder.values.isEmpty {
            print("  (nothing captured — check Input Monitoring, and touch the panel)")
        }
    } catch {
        print("✗ Could not write fixture: \(error)")
        exit(1)
    }
}

// MARK: - replay

func replay(_ path: String) {
    do {
        let fixture = try HIDFixture.load(from: URL(fileURLWithPath: path))
        print("Fixture: \(fixture.name)  (\(fixture.values.count) values, "
              + "range \(fixture.logicalMaxX)x\(fixture.logicalMaxY))\n")
        let player = FixturePlayer()
        let summary = player.summarize(fixture)
        print("What the hardware reported:")
        print("  frames:              \(summary.frames)")
        print("  max simultaneous:    \(summary.maximumSimultaneousContacts) contact(s)")
        print("  contact IDs seen:    \(summary.contactIDsSeen.sorted())")
        if summary.maximumSimultaneousContacts < 2 {
            print("  → only one contact ever reported; multi-finger gestures cannot work")
        }
        print("\nGestures recognised:")

        let events = player.play(fixture)
        if events.isEmpty {
            print("  (no gestures produced)")
        }
        for event in events { print("  \(describe(event))") }
    } catch {
        print("✗ Could not read fixture: \(error)")
        exit(1)
    }
}

func describe(_ event: GestureEvent) -> String {
    func p(_ point: CGPoint) -> String { "(\(Int(point.x)), \(Int(point.y)))" }
    switch event {
    case .click(let a):      return "click       \(p(a))"
    case .rightClick(let a): return "right-click \(p(a))"
    case .dragBegan(let a):  return "drag began  \(p(a))"
    case .dragMoved(let a):  return "drag moved  \(p(a))"
    case .dragEnded(let a):  return "drag ended  \(p(a))"
    case .scroll(let dx, let dy, let a):
        return "scroll      d(\(Int(dx)), \(Int(dy))) at \(p(a))"
    case .pinch(let magnification, let a):
        return String(format: "pinch       %+.3f at %@", magnification, p(a))
    case .scrollMomentum(let dx, let dy, let a):
        return "momentum    d(\(Int(dx)), \(Int(dy))) at \(p(a))"
    case .scrollEnded(let vx, let vy, let a):
        return "scroll end  v(\(Int(vx)), \(Int(vy)))/s at \(p(a))"
    }
}

// MARK: - doctor

func doctor() {
    var problems = 0
    func check(_ label: String, _ ok: Bool, _ remedy: String) {
        print(ok ? "  ✓ \(label)" : "  ✗ \(label)\n      → \(remedy)")
        if !ok { problems += 1 }
    }
    print("Edgewise \(EdgewiseVersion.current)\n")

    let manager = openManager(seize: false)
    check("Input Monitoring permission", manager != nil,
          "System Settings → Privacy & Security → Input Monitoring")

    let devices = manager.flatMap { IOHIDManagerCopyDevices($0) as? Set<IOHIDDevice> }
    check("Touch panel connected", !(devices?.isEmpty ?? true),
          "Connect the panel over USB-C")

    check("Accessibility permission", AXIsProcessTrusted(),
          "System Settings → Privacy & Security → Accessibility")

    let displays = DisplayProvider.current()
    let configuration = Configuration.load()
    let criteria = DisplayResolver.Criteria(identity: configuration.displayIdentity)
    let match = DisplayResolver(criteria: criteria).resolve(among: displays)
    check("Panel display identified", match != nil,
          "Open Edgewise and choose the display manually")

    if let match {
        print("      \(match.display.name ?? "id \(match.display.id)") — "
              + "\(Int(match.display.bounds.width))x\(Int(match.display.bounds.height)) "
              + "(matched by \(match.how))")
    }
    print(problems == 0 ? "\nAll checks passed." : "\n\(problems) problem(s) found.")
    exit(problems == 0 ? 0 : 1)
}

// MARK: - dispatch

switch command {
case "displays": printDisplays()
case "devices":  printDevices()
case "doctor":   doctor()
case "record":
    guard arguments.count >= 2 else { usage() }
    record(to: arguments[1], seconds: arguments.count > 2 ? Double(arguments[2]) ?? 10 : 10)
case "replay":
    guard arguments.count >= 2 else { usage() }
    replay(arguments[1])
default: usage()
}
