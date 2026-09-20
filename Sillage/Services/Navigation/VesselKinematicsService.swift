//
//  VesselKinematicsService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-19.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation
import OSLog

/// Domain service responsible for computing vessel kinematic telemetry (COG and SOG).
///
/// Architecture:
/// Positioned downstream from the hardware positioning service (`CoreLocationPositioningService`),
/// it decouples raw GPS ingestion from mathematical velocity estimation.
/// Depending on the configured `COGSOGCalculationSource`, it either calculates COG/SOG
/// strictly from successive GPS positions via `PositionBasedVelocityCalculator` or
/// transparently preserves native values provided by Apple CoreLocation.
@MainActor
final class VesselKinematicsService: PositioningService {

  private let positioningService: PositioningService
  private let developerSettingsService: DeveloperSettingsService
  private let calculator: PositionBasedVelocityCalculator

  public private(set) var lastKnownLocation: NavigationFix?

  private var upstreamToken: (any LocationUpdateToken)?
  private var pipelineTask: Task<Void, Never>?
  private var activeUpdateTokens = Set<UUID>()
  private var locationContinuations: [UUID: AsyncStream<PositioningState>.Continuation] = [:]
  private var lastObservedSource: COGSOGCalculationSource?

  var currentAuthorizationStatus: CLAuthorizationStatus {
    positioningService.currentAuthorizationStatus
  }

  var currentDistanceFilter: Measurement<UnitLength> {
    positioningService.currentDistanceFilter
  }

  var authorizationStatusStream: AsyncStream<CLAuthorizationStatus> {
    positioningService.authorizationStatusStream
  }

  var locationUpdates: AsyncStream<PositioningState> {
    let (stream, continuation) = AsyncStream.makeStream(of: PositioningState.self)
    let id = UUID()
    locationContinuations[id] = continuation

    continuation.onTermination = { @Sendable [weak self] _ in
      guard let service = self else { return }
      Task { @MainActor in
        service.locationContinuations.removeValue(forKey: id)
      }
    }
    return stream
  }

  init(
    positioningService: PositioningService,
    developerSettingsService: DeveloperSettingsService,
    calculator: PositionBasedVelocityCalculator? = nil
  ) {
    self.positioningService = positioningService
    self.developerSettingsService = developerSettingsService
    self.calculator = calculator ?? PositionBasedVelocityCalculator()
  }

  deinit {
    pipelineTask?.cancel()
  }

  // MARK: - Token Management

  @MainActor
  private final class KinematicsUpdateToken: LocationUpdateToken {
    let id: UUID
    private let onInvalidate: @MainActor (UUID) -> Void
    private var isInvalidated = false

    init(id: UUID, onInvalidate: @escaping @MainActor (UUID) -> Void) {
      self.id = id
      self.onInvalidate = onInvalidate
    }

    func invalidate() {
      guard !isInvalidated else { return }
      isInvalidated = true
      onInvalidate(id)
    }

    nonisolated deinit {
      let id = self.id
      let callback = self.onInvalidate
      Task { @MainActor in
        callback(id)
      }
    }
  }

  func requestLocationUpdates() -> any LocationUpdateToken {
    let tokenID = UUID()
    let token = KinematicsUpdateToken(id: tokenID) { [weak self] id in
      self?.releaseUpdateToken(id: id)
    }

    let wasEmpty = activeUpdateTokens.isEmpty
    activeUpdateTokens.insert(tokenID)

    if wasEmpty {
      startPipeline()
    }

    return token
  }

  private func releaseUpdateToken(id: UUID) {
    activeUpdateTokens.remove(id)
    if activeUpdateTokens.isEmpty {
      stopPipeline()
    }
  }

  private func startPipeline() {
    guard pipelineTask == nil else { return }
    Logger.navigation.info("[KinematicsService] Starting positioning pipeline.")
    upstreamToken = positioningService.requestLocationUpdates()

    pipelineTask = Task { [weak self] in
      guard let self = self else { return }
      for await rawState in self.positioningService.locationUpdates {
        guard !Task.isCancelled else { break }
        await self.processPositioningState(rawState)
      }
    }
  }

  private func stopPipeline() {
    Logger.navigation.info("[KinematicsService] Stopping positioning pipeline.")
    pipelineTask?.cancel()
    pipelineTask = nil
    upstreamToken?.invalidate()
    upstreamToken = nil
    Task { [calculator] in
      await calculator.reset()
    }
  }

  // MARK: - Kinematics Processing

  private func processPositioningState(_ rawState: PositioningState) async {
    let currentSource = developerSettingsService.cogSogCalculationSource
    if lastObservedSource != currentSource {
      Logger.navigation.notice("[KinematicsService] Calculation source switched to '\(currentSource.rawValue, privacy: .public)'. Resetting kinematics buffer.")
      await calculator.reset()
      lastObservedSource = currentSource
    }

    switch rawState {
    case .active(let rawFix):
      let enrichedFix = await processFix(rawFix, source: currentSource)
      self.lastKnownLocation = enrichedFix
      yieldState(.active(enrichedFix))

    case .degraded(let rawFix):
      let enrichedFix = await processFix(rawFix, source: currentSource)
      self.lastKnownLocation = enrichedFix
      yieldState(.degraded(enrichedFix))

    case .lost(let error):
      Logger.navigation.warning("[KinematicsService] GPS signal lost. Reason: \(error.localizedDescription, privacy: .public)")
      await calculator.reset()
      self.lastKnownLocation = nil
      yieldState(.lost(error))
    }
  }

  private func processFix(_ rawFix: NavigationFix, source: COGSOGCalculationSource) async -> NavigationFix {
    switch source {
    case .iOS:
      return rawFix

    case .sillage:
      let estimate = await calculator.calculate(
        coordinate: rawFix.coordinate,
        horizontalAccuracy: rawFix.horizontalAccuracy,
        timestamp: rawFix.timestamp,
        noiseMultiplier: developerSettingsService.noiseMultiplier,
        windowDuration: developerSettingsService.velocityWindowDuration
      )

      return NavigationFix(
        coordinate: rawFix.coordinate,
        horizontalAccuracy: rawFix.horizontalAccuracy,
        courseOverGround: estimate.courseOverGround,
        courseOverGroundAccuracy: estimate.courseOverGroundAccuracy,
        speedOverGround: estimate.speedOverGround,
        speedOverGroundAccuracy: estimate.speedOverGroundAccuracy,
        timestamp: rawFix.timestamp
      )
    }
  }

  private func yieldState(_ state: PositioningState) {
    for continuation in locationContinuations.values {
      continuation.yield(state)
    }
  }

  // MARK: - Forwarding PositioningService Methods

  func requestAuthorization() {
    positioningService.requestAuthorization()
  }

  func requestBackgroundLocation() -> any BackgroundLocationToken {
    positioningService.requestBackgroundLocation()
  }

  func requestDistanceFilter(_ distance: Measurement<UnitLength>, for identifier: String) {
    positioningService.requestDistanceFilter(distance, for: identifier)
  }

  func removeDistanceFilter(for identifier: String) {
    positioningService.removeDistanceFilter(for: identifier)
  }
}
