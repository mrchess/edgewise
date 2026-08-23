import CoreGraphics
import Foundation

/// Wires hardware to gestures to output, and keeps the screen mapping honest as
/// displays come and go.
public final class Driver {
    public enum Status: Equatable, Sendable {
        case stopped
        case running(displayName: String)
        case failed(String)
    }

    public private(set) var status: Status = .stopped {
        didSet { if status != oldValue { onStatusChange?(status) } }
    }
    public var onStatusChange: ((Status) -> Void)?

    private let monitor: HIDMonitor
    private var recognizer: GestureRecognizer
    private var sink: EventSink
    private var mapper: CoordinateMapper?
    private var configuration: Configuration
    private var tickTimer: DispatchSourceTimer?
    private let clock: () -> TimeInterval

    public init(configuration: Configuration = .load(),
                monitor: HIDMonitor = HIDMonitor(),
                sink: EventSink? = nil,
                clock: @escaping () -> TimeInterval = {
                    Date().timeIntervalSinceReferenceDate
                }) {
        self.configuration = configuration
        self.monitor = monitor
        self.clock = clock
        self.recognizer = GestureRecognizer(configuration: configuration.gesture)
        self.sink = sink ?? Driver.makeSink(for: configuration)
    }

    static func makeSink(for configuration: Configuration) -> EventSink {
        let warp = CGEventSink(restoreCursor: configuration.restoreCursor,
                               hideCursorDuringClick: configuration.hideCursorDuringClick,
                               pinchDelivery: configuration.pinchDelivery)
        switch configuration.deliveryMode {
        case .warp:       return warp
        case .background: return BackgroundEventSink(fallback: warp)
        }
    }

    // MARK: - Lifecycle

    public func start() {
        guard case .stopped = status else { return }

        guard updateMapping() else {
            status = .failed("""
            Could not identify the touch panel among the connected displays. \
            Open Edgewise and pick it manually.
            """)
            return
        }

        monitor.onFrame = { [weak self] frame in self?.handle(frame) }
        monitor.onDisconnect = { [weak self] in self?.handleDisconnect() }

        do {
            try monitor.start()
        } catch {
            status = .failed(String(describing: error))
            return
        }

        // Read calibration from the descriptor when the config does not override it.
        if configuration.logicalMaxX == nil, configuration.logicalMaxY == nil,
           let range = monitor.detectLogicalRange() {
            mapper?.logicalMaxX = range.maxX
            mapper?.logicalMaxY = range.maxY
        }

        startTicking()
        observeDisplayChanges()
        status = .running(displayName: mappedDisplayName ?? "touch panel")
    }

    public func stop() {
        tickTimer?.cancel(); tickTimer = nil
        sink.releaseAll()
        monitor.stop()
        CGDisplayRemoveReconfigurationCallback(Driver.displayChanged,
                                               Unmanaged.passUnretained(self).toOpaque())
        status = .stopped
    }

    public func apply(_ newConfiguration: Configuration) {
        configuration = newConfiguration
        recognizer.configuration = newConfiguration.gesture
        sink.releaseAll()
        sink = Driver.makeSink(for: newConfiguration)
        _ = updateMapping()
    }

    // MARK: - Pipeline

    private func handle(_ frame: TouchFrame) {
        guard let mapper else { return }
        let contacts = frame.activeContacts.map {
            MappedContact(id: $0.contactID, point: mapper.map(rawX: $0.rawX, rawY: $0.rawY))
        }
        let input = GestureInput(contacts: contacts, timestamp: frame.timestamp)
        for event in recognizer.ingest(input) { sink.perform(event) }
    }

    private func handleDisconnect() {
        sink.releaseAll()
        recognizer = GestureRecognizer(configuration: configuration.gesture)
    }

    private func startTicking() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        // Comfortably finer than the shortest long-press anyone would configure.
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            for event in self.recognizer.tick(at: self.clock()) { self.sink.perform(event) }
        }
        timer.resume()
        tickTimer = timer
    }

    // MARK: - Display mapping

    private var mappedDisplayName: String?

    @discardableResult
    private func updateMapping() -> Bool {
        let criteria = DisplayResolver.Criteria(identity: configuration.displayIdentity)
        guard let match = DisplayResolver(criteria: criteria)
                .resolve(among: DisplayProvider.current()) else {
            mapper = nil
            return false
        }
        let panel = TouchPanel.xeneonEdge
        mapper = CoordinateMapper(
            displayBounds: match.display.bounds,
            logicalMaxX: configuration.logicalMaxX ?? panel.fallbackLogicalMaxX,
            logicalMaxY: configuration.logicalMaxY ?? panel.fallbackLogicalMaxY,
            isFlipped: configuration.isFlipped
        )
        mappedDisplayName = match.display.name
        return true
    }

    private func observeDisplayChanges() {
        CGDisplayRegisterReconfigurationCallback(Driver.displayChanged,
                                                 Unmanaged.passUnretained(self).toOpaque())
    }

    /// Re-resolves on any display change, so rearranging monitors or changing
    /// resolution does not leave touches landing at stale coordinates.
    private static let displayChanged: CGDisplayReconfigurationCallBack = {
        _, flags, context in
        guard let context,
              !flags.contains(.beginConfigurationFlag) else { return }
        Unmanaged<Driver>.fromOpaque(context).takeUnretainedValue().updateMapping()
    }
}
