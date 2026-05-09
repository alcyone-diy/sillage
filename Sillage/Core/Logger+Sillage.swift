import OSLog

extension Logger {
  private static let subsystem = "com.alcyone.sillage"

  // These loggers are explicitly marked 'nonisolated' to counter the global
  // @MainActor inference imposed by the project. Since 'OSLog.Logger' is
  // inherently 'Sendable', this guarantees direct access from any thread
  // or actor without forcing a context switch (zero-overhead).

  nonisolated static let storage = Logger(subsystem: subsystem, category: "Storage")
  nonisolated static let network = Logger(subsystem: subsystem, category: "Network")
  nonisolated static let map = Logger(subsystem: subsystem, category: "Map")
  nonisolated static let telemetry = Logger(subsystem: subsystem, category: "Telemetry")
}
