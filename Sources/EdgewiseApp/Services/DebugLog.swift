import Foundation

/// Appends to a file so a bundled agent app's launch path can be traced. An agent has
/// no terminal attached, and `print` from one goes nowhere.
enum DebugLog {
    static let url = URL(fileURLWithPath: "/tmp/edgewise-debug.log")

    static func write(_ message: String) {
        guard ProcessInfo.processInfo.environment["EDGEWISE_DEBUG"] != nil else { return }
        let line = "\(Date()) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
