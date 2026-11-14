//
//  SimulatedPositioningService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-14.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

#if DEBUG
import Foundation
import CoreLocation
import OSLog
import os

/// Deterministic positioning service used exclusively in `-screenshot-mode`.
/// Emits synthetic `NavigationFix` states without touching hardware CoreLocation sensors.
@MainActor
final class SimulatedPositioningService: PositioningService {
  private let scenario: ScreenshotScenario

  var currentAuthorizationStatus: CLAuthorizationStatus {
    .authorizedAlways
  }

  private(set) var currentDistanceFilter: Measurement<UnitLength> = Measurement(value: 10.0, unit: .meters)
  private(set) var lastKnownLocation: NavigationFix?

  private var locationContinuations: [UUID: AsyncStream<PositioningState>.Continuation] = [:]
  private var authContinuations: [UUID: AsyncStream<CLAuthorizationStatus>.Continuation] = [:]
  private var activeUpdateTokens = Set<UUID>()
  private var emissionTask: Task<Void, Never>?
  private var hasEmittedLegOrigin = false

  var locationUpdates: AsyncStream<PositioningState> {
    let (stream, continuation) = AsyncStream.makeStream(of: PositioningState.self)
    let id = UUID()
    locationContinuations[id] = continuation

    let initialFix = hasEmittedLegOrigin
      ? makeFix(at: scenario.vesselCoordinate, timestamp: Date.now)
      : makeOriginFix(timestamp: Date.now)
    self.lastKnownLocation = initialFix
    continuation.yield(.active(initialFix))

    continuation.onTermination = { @Sendable [weak self] _ in
      guard let service = self else { return }
      Task { @MainActor in
        service.locationContinuations.removeValue(forKey: id)
      }
    }
    return stream
  }

  var authorizationStatusStream: AsyncStream<CLAuthorizationStatus> {
    let (stream, continuation) = AsyncStream.makeStream(of: CLAuthorizationStatus.self)
    let id = UUID()
    authContinuations[id] = continuation
    continuation.yield(.authorizedAlways)

    continuation.onTermination = { @Sendable [weak self] _ in
      guard let service = self else { return }
      Task { @MainActor in
        service.authContinuations.removeValue(forKey: id)
      }
    }
    return stream
  }

  init(scenario: ScreenshotScenario) {
    self.scenario = scenario
    self.lastKnownLocation = makeOriginFix(timestamp: Date.now)
    Logger.telemetry.info("📸 SimulatedPositioningService initialized for screenshot mode.")
  }

  deinit {
    emissionTask?.cancel()
  }

  func requestAuthorization() {
    for continuation in authContinuations.values {
      continuation.yield(.authorizedAlways)
    }
  }

  @MainActor
  private final class SimulatedToken: LocationUpdateToken, BackgroundLocationToken {
    let id: UUID
    private let onInvalidate: @Sendable (UUID) -> Void
    private let isInvalidated = OSAllocatedUnfairLock(initialState: false)

    init(id: UUID, onInvalidate: @escaping @Sendable (UUID) -> Void) {
      self.id = id
      self.onInvalidate = onInvalidate
    }

    func invalidate() {
      performInvalidationIfNeeded()
    }

    nonisolated deinit {
      performInvalidationIfNeeded()
    }

    nonisolated private func performInvalidationIfNeeded() {
      let shouldInvalidate = isInvalidated.withLock { invalidated in
        guard !invalidated else { return false }
        invalidated = true
        return true
      }
      if shouldInvalidate {
        onInvalidate(id)
      }
    }
  }

  func requestBackgroundLocation() -> any BackgroundLocationToken {
    SimulatedToken(id: UUID()) { _ in }
  }

  func requestLocationUpdates() -> any LocationUpdateToken {
    let tokenID = UUID()
    let token = SimulatedToken(id: tokenID) { @Sendable [weak self] id in
      guard let service = self else { return }
      Task { @MainActor in
        service.releaseUpdateToken(id: id)
      }
    }

    let wasEmpty = activeUpdateTokens.isEmpty
    activeUpdateTokens.insert(tokenID)
    if wasEmpty {
      startEmissionLoop()
    }
    return token
  }

  private func releaseUpdateToken(id: UUID) {
    activeUpdateTokens.remove(id)
    if activeUpdateTokens.isEmpty {
      emissionTask?.cancel()
      emissionTask = nil
    }
  }

  func requestDistanceFilter(_ distance: Measurement<UnitLength>, for identifier: String) {
    currentDistanceFilter = distance
  }

  func removeDistanceFilter(for identifier: String) {
    currentDistanceFilter = Measurement(value: 10.0, unit: .meters)
  }

  private func startEmissionLoop() {
    guard emissionTask == nil else { return }

    let settleDelay = scenario.legOriginSettleDelay
    let swingCoords = scenario.swingCoordinates

    emissionTask = Task { @MainActor [weak self] in
      // 1. Wait `legOriginSettleDelay` after initial leg origin fix so ChartViewModel & WaypointService
      //    lock goToOriginCoordinate, then transition to vesselCoordinate for a non-zero XTE.
      if self?.hasEmittedLegOrigin == false {
        try? await Task.sleep(for: settleDelay)
        guard !Task.isCancelled else { return }
        self?.hasEmittedLegOrigin = true
      }

      // 2. Emit either the anchorage swing sequence or the steady open-water sailing fix.
      if !swingCoords.isEmpty {
        var index = 0
        var step = 1
        while !Task.isCancelled {
          guard let self else { break }
          let coord = swingCoords[index]
          let tangentialCOG: Measurement<UnitAngle>?
          if swingCoords.count > 1 {
            if index + step >= swingCoords.count || index + step < 0 {
              step = -step
            }
            let nextCoord = swingCoords[index + step]
            tangentialCOG = coord.greatCircleBearing(to: nextCoord)
            index += step
          } else {
            tangentialCOG = self.scenario.courseOverGround
          }
          let fix = self.makeFix(at: coord, courseOverGround: tangentialCOG, timestamp: Date.now)
          self.broadcast(fix)

          do {
            try await Task.sleep(for: .milliseconds(1050))
          } catch {
            break
          }
        }
      } else {
        while !Task.isCancelled {
          guard let self else { break }
          let fix = self.makeFix(at: self.scenario.vesselCoordinate, timestamp: Date.now)
          self.broadcast(fix)
          do {
            try await Task.sleep(for: .seconds(2))
          } catch {
            break
          }
        }
      }
    }
  }

  private func broadcast(_ fix: NavigationFix) {
    self.lastKnownLocation = fix
    for continuation in locationContinuations.values {
      continuation.yield(.active(fix))
    }
  }

  private func makeOriginFix(timestamp: Date) -> NavigationFix {
    NavigationFix(
      coordinate: scenario.legOriginCoordinate,
      horizontalAccuracy: scenario.horizontalAccuracy,
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: timestamp
    )
  }

  private func makeFix(
    at coordinate: CLLocationCoordinate2D,
    courseOverGround: Measurement<UnitAngle>? = nil,
    timestamp: Date
  ) -> NavigationFix {
    NavigationFix(
      coordinate: coordinate,
      horizontalAccuracy: scenario.horizontalAccuracy,
      courseOverGround: courseOverGround ?? scenario.courseOverGround,
      courseOverGroundAccuracy: Measurement(value: 2.0, unit: .degrees),
      speedOverGround: scenario.speedOverGround,
      speedOverGroundAccuracy: Measurement(value: 0.1, unit: .metersPerSecond),
      timestamp: timestamp
    )
  }
}
#endif
