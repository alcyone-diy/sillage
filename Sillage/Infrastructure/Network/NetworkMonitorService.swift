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

@MainActor
protocol NetworkMonitorServiceProtocol: AnyObject {
  var isConnected: Bool { get }
  func connectionStream() -> AsyncStream<Bool>
}

@Observable
@MainActor
final class NetworkMonitorService: NetworkMonitorServiceProtocol, @unchecked Sendable {
  private let monitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "NetworkMonitor")
  
  private(set) var isConnected: Bool = true
  
  @ObservationIgnored
  private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]
  
  init() {
    monitor.pathUpdateHandler = { [weak self] path in
      let connected = path.status == .satisfied
      Task { @MainActor [weak self] in
        guard let self = self else { return }
        if self.isConnected != connected {
          self.isConnected = connected
          Logger.network.info("Network status changed. Is connected: \(connected, privacy: .public)")
          
          for continuation in self.continuations.values {
            continuation.yield(connected)
          }
          
          if connected {
            NotificationCenter.default.post(name: NSNotification.Name("NetworkDidReconnect"), object: nil)
          }
        }
      }
    }
    monitor.start(queue: queue)
  }
  
  func connectionStream() -> AsyncStream<Bool> {
    let id = UUID()
    return AsyncStream { [weak self] continuation in
      guard let self = self else {
        continuation.finish()
        return
      }
      continuation.yield(self.isConnected)
      self.continuations[id] = continuation
      continuation.onTermination = { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.continuations.removeValue(forKey: id)
        }
      }
    }
  }
  
  deinit {
    monitor.cancel()
    for continuation in continuations.values {
      continuation.finish()
    }
    continuations.removeAll()
  }
}

