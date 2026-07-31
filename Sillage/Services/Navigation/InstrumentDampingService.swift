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
import OSLog
import Observation

/// Domain layer service responsible for ingesting raw GPS data (`PositioningService`),
/// applying maritime-specific damping/smoothing filters,
/// and emitting a UI-ready state (`InstrumentState`).
// ARCHITECTURE: Domain-Driven Design & Swift 6 Concurrency
// We use a @MainActor @Observable final class.
// This ensures that all UI-bound telemetry mutations occur safely on the main thread,
// satisfying Swift 6 strict concurrency checks without the overhead of an isolated Actor.
@MainActor
@Observable
final class InstrumentDampingService<C: Clock & Sendable> where C.Duration == Duration {
  public private(set) var state: InstrumentState? {
    didSet {
      if let state = state {
        for continuation in continuations.values {
          continuation.yield(state)
        }
      }
    }
  }
  
  // ARCHITECTURE: Multicast AsyncStream Factory
  // We maintain a registry of continuations to allow multiple subscribers (like various ViewModels)
  // to independently observe the same Domain Service without stealing events from one another.
  @ObservationIgnored private var continuations = [UUID: AsyncStream<InstrumentState>.Continuation]()
  
  private let positioningService: PositioningService
  private let clock: C
  private let dateProvider: @Sendable () -> Date
  
  @ObservationIgnored private var locationUpdatesTask: Task<Void, Never>?
  @ObservationIgnored private var stationaryDataTask: Task<Void, Error>?
  @ObservationIgnored private var gpsState: GPSState = .lost
  
  @ObservationIgnored private var courseState: CourseState = .stopped
  
  // Time-based circular buffer to compute a stable vector average.
  @ObservationIgnored private var courseOverGroundBuffer: [(timestamp: C.Instant, cosX: Double, sinY: Double)] = []
  
  private let cutOffSpeed = Measurement(value: 0.5, unit: UnitSpeed.knots)
  private let resumeSpeed = Measurement(value: 1.0, unit: UnitSpeed.knots)
  
  private let distanceUpdateThreshold = Measurement(value: 1.0, unit: UnitLength.meters)
  private let speedUpdateThreshold = Measurement(value: 0.1, unit: UnitSpeed.knots)
  private let courseUpdateThreshold = Measurement(value: 1.0, unit: UnitAngle.degrees)
  private let timeUpdateThreshold: TimeInterval = 1.0
  
  @ObservationIgnored private var lastSmoothedCourseOverGround: Measurement<UnitAngle>?
  @ObservationIgnored private var speedOverGround: Measurement<UnitSpeed>?
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
  
  deinit {
    for continuation in continuations.values {
      continuation.finish()
    }
    continuations.removeAll()
  }
  
  public func observeState() -> AsyncStream<InstrumentState> {
    AsyncStream { continuation in
      let id = UUID()
      self.continuations[id] = continuation
      
      continuation.onTermination = { @Sendable [weak self] _ in
        Task { @MainActor [weak self] in
          self?.continuations.removeValue(forKey: id)
        }
      }
    }
  }
  
  func start() {
    guard locationUpdatesTask == nil else { return }
    locationUpdatesTask = Task { [weak self] in
      guard let stream = self?.positioningService.locationUpdates else { return }
      
      for await positioningState in stream {
        guard !Task.isCancelled, let self = self else { break }
        
        switch positioningState {
        case .active(let fix):
          self.gpsState = .active
          self.processFix(fix)
        case .degraded(let fix):
          self.gpsState = .degraded
          self.processFix(fix)
        case .lost:
          self.gpsState = .lost
          self.handleLostSignal()
        }
      }
    }
  }
  
  func stop() {
    locationUpdatesTask?.cancel()
    locationUpdatesTask = nil
    
    stationaryDataTask?.cancel()
    stationaryDataTask = nil
    
    for continuation in continuations.values {
      continuation.finish()
    }
    continuations.removeAll()
  }
  
  private func processFix(_ fix: NavigationFix) {
    // 1. Movement Hysteresis
    if let speed = fix.speedOverGround {
      if courseState == .active && speed < cutOffSpeed {
        courseState = .stopped
        Logger.navigation.debug("Vessel stopped. Speed \(speed.value, format: .fixed(precision: 1)) below cutoff threshold.")
        courseOverGroundBuffer.removeAll()
      } else if courseState == .stopped && speed >= resumeSpeed {
        courseState = .active
        Logger.navigation.debug("Vessel moving. Speed \(speed.value, format: .fixed(precision: 1)) above resume threshold.")
      }
    }
    
    var finalCourseOverGround = lastSmoothedCourseOverGround
    
    // 2. Course Over Ground (COG) Smoothing via Vector Circular Average
    if courseState == .active {
      let now = clock.now
      
      courseOverGroundBuffer.removeAll { $0.timestamp.duration(to: now) > .seconds(4.0) }
      
      if let course = fix.courseOverGround {
        let radians = course.converted(to: .radians).value
        courseOverGroundBuffer.append((timestamp: now, cosX: cos(radians), sinY: sin(radians)))
      }
      
      if courseOverGroundBuffer.isEmpty {
        finalCourseOverGround = lastSmoothedCourseOverGround
      } else {
        var sumX = 0.0
        var sumY = 0.0
        for item in courseOverGroundBuffer {
          sumX += item.cosX
          sumY += item.sinY
        }
        
        let count = Double(courseOverGroundBuffer.count)
        var smoothedAngle = atan2(sumY / count, sumX / count)
        if smoothedAngle < 0 { smoothedAngle += .pi * 2 }
        
        finalCourseOverGround = Measurement(value: smoothedAngle, unit: .radians)
        lastSmoothedCourseOverGround = finalCourseOverGround
      }
    }
    
    speedOverGround = fix.speedOverGround
    
    let finalCourseState: CourseState = finalCourseOverGround != nil ? courseState : .invalid
    
    let newState = InstrumentState(
      coordinate: fix.coordinate,
      horizontalAccuracy: fix.horizontalAccuracy,
      smoothedSOG: speedOverGround,
      smoothedCOG: finalCourseOverGround,
      courseState: finalCourseState,
      gpsState: self.gpsState,
      sensorTimestamp: fix.timestamp,
      systemDate: dateProvider()
    )
    
    // 3. UI Throttling
    if shouldUpdateState(newState) {
      self.state = newState
      self.lastUpdateTime = clock.now
    }
    
    // 4. Dynamic Stationary Timeout
    stationaryDataTask?.cancel()
    let timeoutSeconds: Double
    if let speed = speedOverGround {
      let sogMPS = speed.converted(to: .metersPerSecond).value
      let filterMeters = positioningService.currentDistanceFilter.converted(to: .meters).value
      timeoutSeconds = min(max((filterMeters / max(sogMPS, 0.1)) * 1.5, 4.0), 20.0)
    } else {
      timeoutSeconds = 10.0
    }
    
    let currentClock = self.clock
    stationaryDataTask = Task { @MainActor [weak self] in
      do {
        try await currentClock.sleep(for: .seconds(timeoutSeconds))
        self?.handleStationaryTimeout(fix: fix)
      } catch is CancellationError {
        // Silent cancellation
      } catch {
        Logger.navigation.error("Stationary task failed with unexpected error: \(error.localizedDescription, privacy: .public)")
      }
    }
  }
  
  private func shouldUpdateState(_ newState: InstrumentState) -> Bool {
    guard let currentState = state else { return true }
    if currentState.courseState != newState.courseState { return true }
    if let lastUpdate = lastUpdateTime, lastUpdate.duration(to: clock.now) < .seconds(timeUpdateThreshold) { return false }
    
    if let curCoord = currentState.coordinate, let newCoord = newState.coordinate {
      let currentLoc = CLLocation(latitude: curCoord.latitude, longitude: curCoord.longitude)
      let newLoc = CLLocation(latitude: newCoord.latitude, longitude: newCoord.longitude)
      if Measurement(value: newLoc.distance(from: currentLoc), unit: UnitLength.meters) >= distanceUpdateThreshold { return true }
    } else if currentState.coordinate?.latitude != newState.coordinate?.latitude || currentState.coordinate?.longitude != newState.coordinate?.longitude {
      return true
    }
    
    if let newSOG = newState.smoothedSOG, let currentSOG = currentState.smoothedSOG {
      if abs((newSOG - currentSOG).converted(to: .knots).value) >= speedUpdateThreshold.value { return true }
    } else if newState.smoothedSOG != currentState.smoothedSOG { return true }
    
    if let newCOG = newState.smoothedCOG, let currentCOG = currentState.smoothedCOG {
      let diffValue = abs((newCOG - currentCOG).converted(to: .degrees).value).truncatingRemainder(dividingBy: 360)
      if (diffValue > 180 ? 360 - diffValue : diffValue) >= courseUpdateThreshold.value { return true }
    } else if newState.smoothedCOG != currentState.smoothedCOG { return true }
    
    return false
  }
  
  private func handleLostSignal() {
    Logger.navigation.info("GPS Signal lost. Nullifying telemetry and forcing vessel to stopped state.")
    self.speedOverGround = nil
    self.courseState = .stopped
    
    let newState = InstrumentState(
      coordinate: self.state?.coordinate,
      horizontalAccuracy: self.state?.horizontalAccuracy,
      smoothedSOG: nil,
      smoothedCOG: self.lastSmoothedCourseOverGround,
      courseState: .stopped,
      gpsState: self.gpsState,
      sensorTimestamp: self.state?.sensorTimestamp ?? dateProvider(),
      systemDate: dateProvider()
    )
    
    self.state = newState
    self.lastUpdateTime = clock.now
  }

  private func handleStationaryTimeout(fix: NavigationFix) {
    Logger.navigation.info("Stationary timeout triggered. Forcing vessel to stopped state.")
    self.speedOverGround = nil
    self.courseState = .stopped
    
    let newState = InstrumentState(
      coordinate: fix.coordinate,
      horizontalAccuracy: fix.horizontalAccuracy,
      smoothedSOG: nil,
      smoothedCOG: self.lastSmoothedCourseOverGround,
      courseState: self.courseState,
      gpsState: self.gpsState,
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
