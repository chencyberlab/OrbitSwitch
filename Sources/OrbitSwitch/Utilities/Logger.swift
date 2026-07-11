import OSLog

enum Log {
    static let app = Logger(subsystem: "dev.orbitswitch.app", category: "application")
    static let shortcuts = Logger(subsystem: "dev.orbitswitch.app", category: "shortcuts")
    static let windows = Logger(subsystem: "dev.orbitswitch.app", category: "windows")
}
