//
//  NetworkMonitorService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-18.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

//
//  NetworkMonitorService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-18.
//

import Foundation
import Network
import MapLibre
import OSLog
import Observation

@Observable
@MainActor
final class NetworkMonitorService {
  private let monitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "NetworkMonitor")
  
  private(set) var isConnected: Bool = true
  
  init() {
    monitor.pathUpdateHandler = { [weak self] path in
      let connected = path.status == .satisfied
      Task { @MainActor [weak self] in
        guard let self = self else { return }
        if self.isConnected != connected {
          self.isConnected = connected
          Logger.network.info("Network status changed. Is connected: \(connected, privacy: .public)")
          
          if connected {
            NotificationCenter.default.post(name: NSNotification.Name("NetworkDidReconnect"), object: nil)
          }
        }
      }
    }
    monitor.start(queue: queue)
  }
}
