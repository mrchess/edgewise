import EdgewiseCore
import Foundation

/// Headless driver process. The menu bar app registers this as a login item;
/// it is also runnable directly for debugging.
let arguments = CommandLine.arguments

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    edgewised — Edgewise touch driver

      --config <path>          Use an alternate configuration file
      --version                Print version and exit
    """)
    exit(0)
}

if arguments.contains("--version") {
    print(EdgewiseVersion.current)
    exit(0)
}

let configuration: Configuration = {
    if let index = arguments.firstIndex(of: "--config"), index + 1 < arguments.count {
        return Configuration.load(from: URL(fileURLWithPath: arguments[index + 1]))
    }
    return Configuration.load()
}()

let driver = Driver(configuration: configuration)
driver.onStatusChange = { status in
    switch status {
    case .running(let display): print("edgewised: running on \(display)")
    case .failed(let message):  FileHandle.standardError.write(Data("edgewised: \(message)\n".utf8))
    case .stopped:              print("edgewised: stopped")
    }
}

signal(SIGINT)  { _ in driver.stop(); exit(0) }
signal(SIGTERM) { _ in driver.stop(); exit(0) }

driver.start()
if case .failed = driver.status { exit(1) }
CFRunLoopRun()
