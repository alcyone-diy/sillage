//
//  InstrumentDampingService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-23.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation
import Observation
import OSLog

/// Domain layer service responsible for ingesting raw GPS data (`PositioningService`),
/// applying maritime-specific damping/smoothing filters,
/// and emitting a UI-ready state (`InstrumentState`).
///
/// Architectural Choice: Generic Clock Injection.
/// By injecting `<C: Clock>`, we decouple the service from the global system time.
/// This allows injecting a `MockClock` in unit tests to eliminate real wall-clock delays,
/// preventing CI flakiness and drastically speeding up test execution.
@MainActor
@Observable
final class InstrumentDampingService<C: Clock & Sendable> where C.Duration == Duration {
  private(set) var state: InstrumentState?
  
  private let positioningService: PositioningService
  private let clock: C
  private let dateProvider: @Sendable () -> Date
  
  // Architectural Choice: Native Swift 6 Tasks.
  // Propagates CancellationError natively without needing wrappers like TaskCancellable.
  // @ObservationIgnored prevents the @Observable macro from wrapping these internals, saving CPU.
  @ObservationIgnored private var locationUpdatesTask: Task<Void, Never>?
  @ObservationIgnored private var stationaryDataTask: Task<Void, Error>?
  
  @ObservationIgnored private var movementState: MovementState = .stopped
  
  // Algorithmic Choice: Time-based circular buffer.
  // We use an O(N) evaluation instead of a running sum to prevent IEEE 754 floating-point drift
  // on very long navigations. Since N is small (max ~40 elements for 4 seconds at 10Hz),
  // O(N) is negligible and mathematically more stable.
  @ObservationIgnored private var courseOverGroundBuffer: [(timestamp: C.Instant, cosX: Double, sinY: Double)] = []
  
  // Business Rule: Hysteresis Thresholds (Schmitt Trigger).
  // Prevents the UI from flickering between "Moving" and "Stopped" due to GPS micro-variations.
  private let cutOffSpeed = Measurement(value: 0.5, unit: UnitSpeed.knots)
  private let resumeSpeed = Measurement(value: 1.0, unit: UnitSpeed.knots)
  
  // Business Rule: Interface Throttling.
  // Typed constants (Measurement) defining significant change thresholds
  // to preserve SwiftUI CPU/GPU resources.
  private let distanceUpdateThreshold = Measurement(value: 1.0, unit: UnitLength.meters)
  private let speedUpdateThreshold = Measurement(value: 0.1, unit: UnitSpeed.knots)
  private let courseUpdateThreshold = Measurement(value: 1.0, unit: UnitAngle.degrees)
  private let timeUpdateThreshold: TimeInterval = 1.0
  
  @ObservationIgnored private var lastSmoothedCourseOverGround: Measurement<UnitAngle>?
  @ObservationIgnored private var speedOverGround: Measurement<UnitSpeed>?
  
  // Monotonic clock immune to NTP time jumps, mandatory for reliable delta-time checks.
  @ObservationIgnored private var lastUpdateTime: C.Instant?
  
  init(
    positioningService: PositioningService,
    clock: C,
    dateProvider: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.positioningService = positioningService
    self.clock = clock
    self.dateProvider = dateProvider
  }
  
  func start() {
    guard locationUpdatesTask == nil else { return }
    locationUpdatesTask = Task { [weak self] in
      // Stream is extracted locally to avoid strong self capture in the async loop.
      guard let stream = self?.positioningService.locationUpdates else { return }
      
      for await positioningState in stream {
        // Architectural Choice: Break loop if self is deallocated.
        // Prevents the async task from living forever if `stop()` was forgotten.
        guard !Task.isCancelled, let self = self else { break }
        
        switch positioningState {
        case .active(let fix), .degraded(let fix):
          self.processFix(fix)
        case .lost:
          break
        }
      }
    }
  }
  
  func stop() {
    // Concurrency Safety: Actor-isolated tasks must be formally canceled here
    // by the parent (e.g. AppEnvironment), because `deinit` usage is non-isolated in Swift 6.
    locationUpdatesTask?.cancel()
    locationUpdatesTask = nil
    
    stationaryDataTask?.cancel()
    stationaryDataTask = nil
  }
  
  private func processFix(_ fix: NavigationFix) {
    // ---------------------------------------------------------
    // 1. Movement Hysteresis
    // ---------------------------------------------------------
    if let speed = fix.speedOverGround {
      if movementState == .moving && speed < cutOffSpeed {
        movementState = .stopped
        Logger.navigation.debug("Vessel stopped. Speed \(speed.value, format: .fixed(precision: 1)) below cutoff threshold.")
        courseOverGroundBuffer.removeAll()
      } else if movementState == .stopped && speed >= resumeSpeed {
        movementState = .moving
        Logger.navigation.debug("Vessel moving. Speed \(speed.value, format: .fixed(precision: 1)) above resume threshold.")
      }
    }
    
    var finalCourseOverGround = lastSmoothedCourseOverGround
    
    // ---------------------------------------------------------
    // 2. Course Over Ground (COG) Smoothing via Vector Circular Average
    // ---------------------------------------------------------
    if movementState == .moving {
      let now = clock.now
      
      // Algorithmic Choice: Time-based purge MUST happen unconditionally.
      // Even if the current fix has no COG (temporary sensor loss), we purge elements
      // older than 4 seconds to prevent stale vectors from lingering in the buffer.
      courseOverGroundBuffer.removeAll { $0.timestamp.duration(to: now) > .seconds(4.0) }
      
      if let course = fix.courseOverGround {
        let radians = course.converted(to: .radians).value
        let cosX = cos(radians)
        let sinY = sin(radians)
        
        courseOverGroundBuffer.append((timestamp: now, cosX: cosX, sinY: sinY))
      }
      
      if courseOverGroundBuffer.isEmpty {
        // Edge case safety (e.g., all data purged due to 4s loss of COG)
        finalCourseOverGround = lastSmoothedCourseOverGround
      } else {
        // O(N) evaluation to prevent floating-point drift over time.
        var sumX = 0.0
        var sumY = 0.0
        for item in courseOverGroundBuffer {
          sumX += item.cosX
          sumY += item.sinY
        }
        
        let count = Double(courseOverGroundBuffer.count)
        let avgX = sumX / count
        let avgY = sumY / count
        
        var smoothedAngleOverGround = atan2(avgY, avgX)
        if smoothedAngleOverGround < 0 {
          smoothedAngleOverGround += .pi * 2
        }
        
        finalCourseOverGround = Measurement(value: smoothedAngleOverGround, unit: .radians)
        lastSmoothedCourseOverGround = finalCourseOverGround
      }
    }
    
    speedOverGround = fix.speedOverGround
    
    let newState = InstrumentState(
      rawCoordinate: fix.coordinate,
      rawAccuracy: fix.horizontalAccuracy,
      smoothedSOG: speedOverGround,
      smoothedCOG: finalCourseOverGround,
      movementState: movementState,
      sensorTimestamp: fix.timestamp,
      systemDate: dateProvider()
    )
    
    // ---------------------------------------------------------
    // 3. UI Throttling
    // ---------------------------------------------------------
    // Only impact the UI if a physically significant change occurred.
    if shouldUpdateState(newState) {
      self.state = newState
      self.lastUpdateTime = clock.now
    }
    
    // ---------------------------------------------------------
    // 4. Dynamic Stationary Timeout
    // ---------------------------------------------------------
    // The GPS distance filter suspends updates if there is no movement.
    // We arm a dynamic "watchdog" timer (based on speed) to switch to the Stopped state.
    stationaryDataTask?.cancel()
    stationaryDataTask = nil
    
    let timeoutSeconds: Double
    if let speed = speedOverGround {
      let sogMPS = speed.converted(to: .metersPerSecond).value
      let filterMeters = positioningService.currentDistanceFilter.converted(to: .meters).value
      
      let expectedDelay = filterMeters / max(sogMPS, 0.1)
      timeoutSeconds = min(max(expectedDelay * 1.5, 4.0), 20.0)
    } else {
      // Business Rule: No fake speed (0). We use a static fallback if the data is missing.
      timeoutSeconds = 10.0
    }
    
    // Memory Choice: Extract clock locally to avoid capturing `self` strongly during the `await`.
    // This prevents prolonged asynchronous retention leaks if the parent object is deallocated.
    let currentClock = self.clock
    stationaryDataTask = Task { @MainActor [weak self] in
      do {
        // Let Swift 6 natively propagate cancellation if a new fix arrives before the timer expires.
        try await currentClock.sleep(for: .seconds(timeoutSeconds))
        self?.handleStationaryTimeout(fix: fix)
      } catch is CancellationError {
        // Silent cancellation
      } catch {
        // Architectural Choice: Structured OSLog.
        // We never silently ignore unexpected errors. We log them explicitly to the system console.
        Logger.navigation.error("Stationary task failed with unexpected error: \(error.localizedDescription, privacy: .public)")
      }
    }
  }
  
  private func shouldUpdateState(_ newState: InstrumentState) -> Bool {
    guard let currentState = state else { return true }
    
    if currentState.movementState != newState.movementState { return true }
    
    if let lastUpdate = lastUpdateTime {
      let timeElapsed = lastUpdate.duration(to: clock.now)
      // Architectural Choice: Absolute Throttling (Gatekeeper).
      // The timeUpdateThreshold is the absolute gatekeeper. We short-circuit and return `false` 
      // if the time delta is under the threshold, guaranteeing a strict frequency cap (e.g. 1Hz).
      // This protects SwiftUI and the iPad battery even on multihulls sailing at 30+ knots.
      if timeElapsed < .seconds(timeUpdateThreshold) { return false }
    }
    
    // Business Rule: Physical thresholds do NOT accelerate updates.
    // Distance, speed, and course thresholds are used to CANCEL updates (eventually returning false)
    // if the vessel hasn't moved significantly, thus saving battery even after time has elapsed.
    
    // Mathematical Rule: Native WGS84 model usage via CLLocation instead of spherical approximation
    // because maritime navigation requires ellipsoidal geodetic precision.
    let currentLoc = CLLocation(latitude: currentState.rawCoordinate.latitude, longitude: currentState.rawCoordinate.longitude)
    let newLoc = CLLocation(latitude: newState.rawCoordinate.latitude, longitude: newState.rawCoordinate.longitude)
    let distMeasurement = Measurement(value: newLoc.distance(from: currentLoc), unit: UnitLength.meters)
    
    if distMeasurement >= distanceUpdateThreshold { return true }
    
    if let newSOG = newState.smoothedSOG, let currentSOG = currentState.smoothedSOG {
      // Architectural Choice: Measurement Native Operators.
      // Utilize Foundation's overloaded operators to guarantee unit safety during arithmetic.
      let speedDiff = newSOG - currentSOG
      if abs(speedDiff.converted(to: .knots).value) >= speedUpdateThreshold.value { return true }
    } else if newState.smoothedSOG != currentState.smoothedSOG {
      return true
    }
    
    if let newCOG = newState.smoothedCOG, let currentCOG = currentState.smoothedCOG {
      let angleDiff = newCOG - currentCOG
      let diffValue = abs(angleDiff.converted(to: .degrees).value).truncatingRemainder(dividingBy: 360)
      let shortestDiffValue = diffValue > 180 ? 360 - diffValue : diffValue
      if shortestDiffValue >= courseUpdateThreshold.value { return true }
    } else if newState.smoothedCOG != currentState.smoothedCOG {
      return true
    }
    
    return false
  }
  
  private func handleStationaryTimeout(fix: NavigationFix) {
    Logger.navigation.info("Stationary timeout triggered. Forcing vessel to stopped state.")
    self.speedOverGround = nil
    self.movementState = .stopped
    
    // Business Rule: Timestamp integrity.
    // The emitted state replicates the last sensor timestamp instead of fabricating a fake Date(),
    // and formally nullifies the SOG (nil) instead of asserting 0 knots.
    let newState = InstrumentState(
      rawCoordinate: fix.coordinate,
      rawAccuracy: fix.horizontalAccuracy,
      smoothedSOG: nil,
      smoothedCOG: self.lastSmoothedCourseOverGround,
      movementState: self.movementState,
      sensorTimestamp: fix.timestamp,
      systemDate: dateProvider()
    )
    
    self.state = newState
    self.lastUpdateTime = clock.now
  }
}

extension InstrumentDampingService where C == ContinuousClock {
  convenience init(positioningService: PositioningService) {
    self.init(positioningService: positioningService, clock: ContinuousClock())
  }
}
