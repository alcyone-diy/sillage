import OSLog

extension Logger {
    private static let subsystem = "com.alcyone.sillage"

    static let storage = Logger(subsystem: subsystem, category: "Storage")
}
