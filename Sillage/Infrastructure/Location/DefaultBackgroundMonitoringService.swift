//
//  DefaultBackgroundMonitoringService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import OSLog

@MainActor
final class DefaultBackgroundMonitoringService: BackgroundMonitoringService {
  private let positioningService: PositioningService
  private let notificationService: NotificationService

  private var activeSessions: [UUID: SessionState] = [:]

  private struct SessionState {
    let ownerIdentifier: String
    let backgroundLocationToken: any BackgroundLocationToken
    let locationUpdateToken: any LocationUpdateToken
    let watchdog: WatchdogConfiguration?
  }

  private var gpsUpdateTask: Task<Void, Never>?

  init(positioningService: PositioningService, notificationService: NotificationService) {
    self.positioningService = positioningService
    self.notificationService = notificationService
  }

  func startMonitoring(
    ownerIdentifier: String,
    distanceFilter: Measurement<UnitLength>,
    watchdog: WatchdogConfiguration?
  ) -> any BackgroundMonitoringToken {
    let tokenID = UUID()
    let bgToken = positioningService.requestBackgroundLocation()
    let updateToken = positioningService.requestLocationUpdates()
    positioningService.requestDistanceFilter(distanceFilter, for: ownerIdentifier)
    
    activeSessions[tokenID] = SessionState(
      ownerIdentifier: ownerIdentifier,
      backgroundLocationToken: bgToken,
      locationUpdateToken: updateToken,
      watchdog: watchdog
    )
    
    if gpsUpdateTask == nil {
      startGPSLoop()
    }
    
    return MonitoringToken(id: tokenID) { @Sendable [weak self] id in
      guard let self = self else { return }
      Task { @MainActor in
        self.invalidateToken(id: id)
      }
    }
  }

  private func invalidateToken(id: UUID) {
    guard let session = activeSessions.removeValue(forKey: id) else { return }
    
    session.backgroundLocationToken.invalidate()
    session.locationUpdateToken.invalidate()
    positioningService.removeDistanceFilter(for: session.ownerIdentifier)
    
    if let watchdog = session.watchdog {
      Task {
        await notificationService.cancelWatchdog(identifier: watchdog.identifier)
      }
    }
    
    if activeSessions.isEmpty {
      stopGPSLoop()
    }
  }

  private func startGPSLoop() {
    gpsUpdateTask?.cancel()
    gpsUpdateTask = Task { [weak self] in
      guard let self = self else { return }
      for await state in self.positioningService.locationUpdates {
        guard !Task.isCancelled else { break }
        
        switch state {
        case .active, .degraded:
          await self.pingWatchdogs()
        case .lost:
          break
        }
      }
    }
  }

  private func stopGPSLoop() {
    gpsUpdateTask?.cancel()
    gpsUpdateTask = nil
  }

  private func pingWatchdogs() async {
    for session in activeSessions.values {
      if let watchdog = session.watchdog {
        await notificationService.checkIn(
          identifier: watchdog.identifier,
          title: watchdog.title,
          body: watchdog.body,
          timeout: watchdog.timeout
        )
      }
    }
  }
}

@MainActor
private final class MonitoringToken: BackgroundMonitoringToken {
  private let id: UUID
  private let onDeinit: @Sendable (UUID) -> Void
  private var isInvalidated = false

  init(id: UUID, onDeinit: @escaping @Sendable (UUID) -> Void) {
    self.id = id
    self.onDeinit = onDeinit
  }

  func invalidate() {
    guard !isInvalidated else { return }
    isInvalidated = true
    onDeinit(id)
  }

  nonisolated deinit {
    onDeinit(id)
  }
}
