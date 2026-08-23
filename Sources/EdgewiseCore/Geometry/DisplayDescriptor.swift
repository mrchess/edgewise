import CoreGraphics
import Foundation

/// A snapshot of one display, decoupled from CoreGraphics so it can be built in tests.
public struct DisplayDescriptor: Equatable, Sendable {
    public let id: UInt32
    public let vendorNumber: UInt32
    public let modelNumber: UInt32
    public let serialNumber: UInt32
    /// Quartz global coordinates: origin top-left of the main display.
    public let bounds: CGRect
    public let isBuiltin: Bool
    public let isMain: Bool
    public let name: String?

    public init(id: UInt32, vendorNumber: UInt32, modelNumber: UInt32, serialNumber: UInt32,
                bounds: CGRect, isBuiltin: Bool, isMain: Bool, name: String?) {
        self.id = id
        self.vendorNumber = vendorNumber
        self.modelNumber = modelNumber
        self.serialNumber = serialNumber
        self.bounds = bounds
        self.isBuiltin = isBuiltin
        self.isMain = isMain
        self.name = name
    }
}

/// A stable way to name one physical display across reboots and replugs.
public struct DisplayIdentity: Equatable, Hashable, Codable, Sendable {
    public let vendorNumber: UInt32
    public let modelNumber: UInt32
    public let serialNumber: UInt32

    public init(vendorNumber: UInt32, modelNumber: UInt32, serialNumber: UInt32) {
        self.vendorNumber = vendorNumber
        self.modelNumber = modelNumber
        self.serialNumber = serialNumber
    }

    public init(_ d: DisplayDescriptor) {
        self.init(vendorNumber: d.vendorNumber,
                  modelNumber: d.modelNumber,
                  serialNumber: d.serialNumber)
    }

    public func matches(_ d: DisplayDescriptor) -> Bool {
        d.vendorNumber == vendorNumber
            && d.modelNumber == modelNumber
            && d.serialNumber == serialNumber
    }
}
