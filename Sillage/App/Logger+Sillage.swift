//
//  Logger+Sillage.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import OSLog

extension Logger {
  private static let subsystem = "com.alcyone.sillage"

  // These loggers are explicitly marked 'nonisolated' to counter the global
  // @MainActor inference imposed by the project. Since 'OSLog.Logger' is
  // inherently 'Sendable', this guarantees direct access from any thread
  // or actor without forcing a context switch (zero-overhead).

  nonisolated static let database = Logger(subsystem: subsystem, category: "Database")
  nonisolated static let network = Logger(subsystem: subsystem, category: "Network")
  nonisolated static let chart = Logger(subsystem: subsystem, category: "Chart")
  nonisolated static let storage = Logger(subsystem: subsystem, category: "Storage")
  nonisolated static let system = Logger(subsystem: subsystem, category: "System")
  nonisolated static let telemetry = Logger(subsystem: subsystem, category: "Telemetry")
  nonisolated static let tracking = Logger(subsystem: subsystem, category: "Tracking")
  nonisolated static let barometer = Logger(subsystem: subsystem, category: "Barometer")
  nonisolated static let anchor = Logger(subsystem: subsystem, category: "Anchor")
  nonisolated static let offline = Logger(subsystem: subsystem, category: "Offline")
  nonisolated static let messaging = Logger(subsystem: subsystem, category: "Messaging")
  nonisolated static let navigation = Logger(subsystem: subsystem, category: "Navigation")
}
