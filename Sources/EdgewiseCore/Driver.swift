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

    /// Whether the panel actually delivers multiple contacts.
    ///
    /// Not a static property of the driver: the Xeneon Edge describes a ten-finger
    /// digitizer but only ever transmits on its mouse-emulation interface, so the
    /// answer is only known once it has reported something. Settings that depend on it
    /// stay hidden until then, rather than offering controls that cannot act.
    public private(set) var supportsMultipleContacts = false
    public var onMultiContactAvailable: (() -> Void)?

    private let monitor: HIDMonitor
    private var recognizer: GestureRecognizer
    private var sink: EventSink
    private var mapper: CoordinateMapper?
    private var configuration: Configuration
    private var tickTimer: DispatchSourceTimer?
    private var momentum = MomentumScroller()
    private var lastMomentumStep: TimeInterval = 0
    private var momentumOrigin: CGPoint = .zero
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
        self.momentum = MomentumScroller(
            deceleration: configuration.gesture.momentumDeceleration)
        self.sink = sink ?? Driver.makeSink(for: configuration)
    }

    static func makeSink(for configuration: Configuration) -> EventSink {
        CGEventSink(restoreCursor: configuration.restoreCursor,
                    pinchDelivery: configuration.pinchDelivery)
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
        monitor.onMultiContactAvailable = { [weak self] in
            guard let self, !self.supportsMultipleContacts else { return }
            self.supportsMultipleContacts = true
            self.onMultiContactAvailable?()
        }
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
        momentum.stop()
        sink.releaseAll()
        monitor.stop()
        CGDisplayRemoveReconfigurationCallback(Driver.displayChanged,
                                               Unmanaged.passUnretained(self).toOpaque())
        status = .stopped
    }

    public func apply(_ newConfiguration: Configuration) {
        configuration = newConfiguration
        recognizer.configuration = newConfiguration.gesture
        momentum.deceleration = newConfiguration.gesture.momentumDeceleration
        momentum.stop()
        sink.releaseAll()
        sink = Driver.makeSink(for: newConfiguration)
        _ = updateMapping()
    }

    // MARK: - Pipeline

    private func handle(_ frame: TouchFrame) {
        guard let mapper else { return }

        // A new touch cancels any glide, the way putting a finger on a phone stops it.
        if momentum.isCoasting, !frame.activeContacts.isEmpty {
            momentum.stop()
            (sink as? CGEventSink)?.endMomentum()
        }

        let contacts = frame.activeContacts.map {
            MappedContact(id: $0.contactID, point: mapper.map(rawX: $0.rawX, rawY: $0.rawY))
        }
        let input = GestureInput(contacts: contacts, timestamp: frame.timestamp)
        for event in recognizer.ingest(input) { deliver(event) }
    }

    /// Routes an event, intercepting the hand-off into momentum.
    private func deliver(_ event: GestureEvent) {
        if case .scrollEnded(let vx, let vy, let at) = event {
            sink.perform(event)
            momentumOrigin = at
            lastMomentumStep = clock()
            momentum.begin(velocityX: vx, velocityY: vy)
            return
        }
        sink.perform(event)
    }

    private func handleDisconnect() {
        sink.releaseAll()
        recognizer = GestureRecognizer(configuration: configuration.gesture)
    }

    private func startTicking() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        // 60Hz: fine enough that a coasting scroll looks smooth, and comfortably
        // finer than the shortest long press anyone would configure.
        timer.schedule(deadline: .now() + 1.0 / 60, repeating: 1.0 / 60)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = self.clock()
            for event in self.recognizer.tick(at: now) { self.deliver(event) }
            self.stepMomentum(at: now)
        }
        timer.resume()
        tickTimer = timer
    }

    /// Advances a coasting scroll. Driven from the same tick as gesture timing so
    /// there is only one timer in the driver.
    private func stepMomentum(at now: TimeInterval) {
        guard momentum.isCoasting else { return }
        let elapsed = min(now - lastMomentumStep, 0.05)
        lastMomentumStep = now
        guard elapsed > 0 else { return }

        if let (dx, dy) = momentum.step(elapsed: elapsed) {
            sink.perform(.scrollMomentum(deltaX: dx, deltaY: dy, at: momentumOrigin))
        }
        if !momentum.isCoasting { (sink as? CGEventSink)?.endMomentum() }
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
            rotation: Int(CGDisplayRotation(match.display.id).rounded())
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
