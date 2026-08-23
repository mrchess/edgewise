import Combine
import EdgewiseCore
import Foundation

/// Observable wrapper around the core `Driver`, so SwiftUI can show live state.
///
/// The app hosts the driver in-process rather than shipping a separate daemon. That
/// keeps it to a single binary the user grants permissions to exactly once, instead of
/// a helper that needs its own Accessibility and Input Monitoring entries.
@MainActor
final class DriverController: ObservableObject {
    @Published private(set) var status: Driver.Status = .stopped
    @Published var configuration: Configuration {
        didSet {
            // Ignore writes that change nothing.
            //
            // SwiftUI writes back through bindings during view evaluation —
            // `MenuBarExtra(isInserted:)` does it on every pass. Without this guard
            // each of those no-op writes saved the file and republished, which
            // invalidated the view that had just written, and the app live-locked in
            // an endless render loop.
            guard configuration != oldValue else { return }
            applyAndPersist()
        }
    }

    private var driver: Driver?

    init() {
        configuration = Configuration.load()
    }

    var isRunning: Bool { if case .running = status { true } else { false } }

    var statusDescription: String { Self.describe(status) }

    static func describe(_ status: Driver.Status) -> String {
        switch status {
        case .stopped: "Not running"
        case .running(let display): "Running on \(display)"
        case .failed(let message): message
        }
    }

    static func isRunning(_ status: Driver.Status) -> Bool {
        if case .running = status { true } else { false }
    }

    func start() {
        guard driver == nil else { return }
        let driver = Driver(configuration: configuration)
        driver.onStatusChange = { [weak self] status in
            Task { @MainActor in self?.status = status }
        }
        self.driver = driver
        driver.start()
        status = driver.status
    }

    func stop() {
        driver?.stop()
        driver = nil
        status = .stopped
    }

    func restart() {
        stop()
        start()
    }

    /// Remembers the panel's display so it is found again after a replug or reorder.
    func pinDisplay(_ descriptor: DisplayDescriptor) {
        configuration.displayIdentity = DisplayIdentity(descriptor)
        restart()
    }

    var availableDisplays: [DisplayDescriptor] { DisplayProvider.current() }

    private func applyAndPersist() {
        try? configuration.save()
        driver?.apply(configuration)
    }
}
