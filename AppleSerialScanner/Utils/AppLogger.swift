import Foundation
import OSLog

enum AppLogger {
    static let subsystem: String = Bundle.main.bundleIdentifier ?? "com.appleserialscanner"

    static let network = Logger(subsystem: subsystem, category: "network")
    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let vision = Logger(subsystem: subsystem, category: "vision")
    static let power = Logger(subsystem: subsystem, category: "power")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let storage = Logger(subsystem: subsystem, category: "storage")
}

