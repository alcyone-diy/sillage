//
//  InstrumentDampingServiceTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-23.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Testing
import Foundation
import CoreLocation
@testable import Sillage

@available(iOS 16.0, *)
final class MockClock: Clock, @unchecked Sendable {
  struct Instant: InstantProtocol, Sendable {
    var offset: Duration
    func advanced(by duration: Duration) -> Instant { Instant(offset: self.offset + duration) }
    func duration(to other: Instant) -> Duration { other.offset - self.offset }
    static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
  }
  
  private let lock = NSLock()
  private var _now: Instant = Instant(offset: .zero)
  private var sleepers: [UUID: (deadline: Instant, continuation: UnsafeContinuation<Void, Error>)] = [:]
  
  var now: Instant {
    lock.lock(); defer { lock.unlock() }
    return _now
  }
  
  var minimumResolution: Duration { .zero }
  
  func sleep(until deadline: Instant, tolerance: Duration?) async throws {
    if now >= deadline { return }
    let id = UUID()
    
    try await withTaskCancellationHandler {
      try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, Error>) in
        lock.lock()
        if _now >= deadline {
          lock.unlock()
          continuation.resume()
        } else if Task.isCancelled {
          lock.unlock()
          continuation.resume(throwing: CancellationError())
        } else {
          sleepers[id] = (deadline, continuation)
          lock.unlock()
        }
      }
    } onCancel: {
      lock.lock()
      let sleeper = sleepers.removeValue(forKey: id)
      lock.unlock()
      sleeper?.continuation.resume(throwing: CancellationError())
    }
  }
  
  func advance(by duration: Duration) {
    lock.lock()
    _now = _now.advanced(by: duration)
    let currentNow = _now
    var ready: [UnsafeContinuation<Void, Error>] = []
    
    let keys = sleepers.keys
    for key in keys {
      if let sleeper = sleepers[key], currentNow >= sleeper.deadline {
        ready.append(sleeper.continuation)
        sleepers.removeValue(forKey: key)
      }
    }
    lock.unlock()
    
    for cont in ready {
      cont.resume()
    }
  }
}

@MainActor
private func waitFor(
  timeout: Duration = .seconds(2),
  condition: () -> Bool
) async throws {
  let start = ContinuousClock.now
  while true {
    if condition() { return }
    let elapsed = start.duration(to: ContinuousClock.now)
    if elapsed > timeout {
      struct TimeoutError: Error {}
      throw TimeoutError()
    }
    // Micro-sleep to yield control to the async stream processor without blocking the MainActor
    try await Task.sleep(nanoseconds: 1_000_000)
  }
}

@Suite("Instrument Damping Service Tests")
struct InstrumentDampingServiceTests {
  
  private final class MockBackgroundToken: BackgroundLocationToken {
    func invalidate() {}
  }
  
  private final class MockPositioningService: PositioningService, @unchecked Sendable {
    var currentAuthorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    var authorizationStatusStream: AsyncStream<CLAuthorizationStatus> { AsyncStream { _ in } }
    var currentDistanceFilter: Measurement<UnitLength> = Measurement(value: 5.0, unit: .meters)
    
    let continuation: AsyncStream<PositioningState>.Continuation
    let locationUpdates: AsyncStream<PositioningState>
    
    init() {
      let (stream, cont) = AsyncStream<PositioningState>.makeStream()
      self.locationUpdates = stream
      self.continuation = cont
    }
    
    func requestAuthorization() {}
    func startUpdatingLocation() {}
    func stopUpdatingLocation() {}
    func requestBackgroundLocation() -> any BackgroundLocationToken { MockBackgroundToken() }
    func requestDistanceFilter(_ distance: Measurement<UnitLength>, for identifier: String) {}
    func removeDistanceFilter(for identifier: String) {}
  }

  @Test("COG Circular Average (Crossing 360/0)")
  @MainActor
  func testCOG_AverageCrossing360() async throws {
    let mockPositioning = MockPositioningService()
    let mockClock = MockClock()
    let service = InstrumentDampingService(positioningService: mockPositioning, clock: mockClock)
    service.start()
    
    let baseLoc = CLLocationCoordinate2D(latitude: 45, longitude: 45)
    
    // First fix
    let fix1 = NavigationFix(
      coordinate: baseLoc,
      horizontalAccuracy: Measurement(value: 5, unit: .meters),
      courseOverGround: Measurement(value: 350.0, unit: .degrees),
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 2.0, unit: .knots),
      speedOverGroundAccuracy: nil,
      timestamp: Date.now
    )
    mockPositioning.continuation.yield(.active(fix1))
    
    try await waitFor { service.state?.courseState == .active }
    
    let initialAvgCog = try #require(service.state?.smoothedCOG?.converted(to: .degrees).value)
    #expect(abs(initialAvgCog - 350.0) < 0.1)
    
    // Second fix
    mockClock.advance(by: .seconds(1.1))
    let fix2 = NavigationFix(
      coordinate: baseLoc,
      horizontalAccuracy: Measurement(value: 5, unit: .meters),
      courseOverGround: Measurement(value: 10.0, unit: .degrees),
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 2.0, unit: .knots),
      speedOverGroundAccuracy: nil,
      timestamp: Date.now.addingTimeInterval(1.1)
    )
    mockPositioning.continuation.yield(.active(fix2))
    
    try await waitFor {
      if let cog = service.state?.smoothedCOG?.converted(to: .degrees).value {
        return abs(cog) < 0.1 || abs(cog - 360.0) < 0.1
      }
      return false
    }
    
    service.stop()
  }
  
  @Test("Hysteresis Behavior (Moving -> Stopped)")
  @MainActor
  func testHysteresis() async throws {
    let mockPositioning = MockPositioningService()
    let mockClock = MockClock()
    let service = InstrumentDampingService(positioningService: mockPositioning, clock: mockClock)
    service.start()
    
    let baseLoc = CLLocationCoordinate2D(latitude: 45, longitude: 45)
    
    let fix1 = NavigationFix(
      coordinate: baseLoc,
      horizontalAccuracy: Measurement(value: 5, unit: .meters),
      courseOverGround: Measurement(value: 0.0, unit: .degrees),
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 0.8, unit: .knots),
      speedOverGroundAccuracy: nil,
      timestamp: Date.now
    )
    mockPositioning.continuation.yield(.active(fix1))
    
    try await waitFor { service.state?.sensorTimestamp == fix1.timestamp }
    #expect(service.state?.courseState == .stopped)
    
    mockClock.advance(by: .seconds(1.1))
    let fix2 = NavigationFix(
      coordinate: baseLoc,
      horizontalAccuracy: Measurement(value: 5, unit: .meters),
      courseOverGround: Measurement(value: 0.0, unit: .degrees),
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 1.2, unit: .knots),
      speedOverGroundAccuracy: nil,
      timestamp: Date.now.addingTimeInterval(1.1)
    )
    mockPositioning.continuation.yield(.active(fix2))
    
    try await waitFor { service.state?.courseState == .active }
    
    mockClock.advance(by: .seconds(1.1))
    let fix3 = NavigationFix(
      coordinate: baseLoc,
      horizontalAccuracy: Measurement(value: 5, unit: .meters),
      courseOverGround: Measurement(value: 0.0, unit: .degrees),
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 0.8, unit: .knots),
      speedOverGroundAccuracy: nil,
      timestamp: Date.now.addingTimeInterval(2.2)
    )
    mockPositioning.continuation.yield(.active(fix3))
    
    try await waitFor { service.state?.sensorTimestamp == fix3.timestamp }
    #expect(service.state?.courseState == .active)
    
    mockClock.advance(by: .seconds(1.1))
    let fix4 = NavigationFix(
      coordinate: baseLoc,
      horizontalAccuracy: Measurement(value: 5, unit: .meters),
      courseOverGround: Measurement(value: 0.0, unit: .degrees),
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 0.4, unit: .knots),
      speedOverGroundAccuracy: nil,
      timestamp: Date.now.addingTimeInterval(3.3)
    )
    mockPositioning.continuation.yield(.active(fix4))
    
    try await waitFor { service.state?.courseState == .stopped }
    
    service.stop()
  }

  @Test("Task Cancellation (New fix before timeout)")
  @MainActor
  func testStationaryTimeoutCancellation() async throws {
    let mockPositioning = MockPositioningService()
    let mockClock = MockClock()
    let service = InstrumentDampingService(positioningService: mockPositioning, clock: mockClock)
    service.start()
    
    let baseLoc = CLLocationCoordinate2D(latitude: 45, longitude: 45)
    
    let fix1 = NavigationFix(
      coordinate: baseLoc,
      horizontalAccuracy: Measurement(value: 5, unit: .meters),
      courseOverGround: Measurement(value: 0.0, unit: .degrees),
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 2.0, unit: .knots),
      speedOverGroundAccuracy: nil,
      timestamp: Date.now
    )
    mockPositioning.continuation.yield(.active(fix1))
    
    try await waitFor { service.state?.courseState == .active }
    #expect(service.state?.smoothedSOG?.value == 2.0)
    
    // We send another fix before the timeout
    mockClock.advance(by: .seconds(2.0))
    let fix2 = NavigationFix(
      coordinate: baseLoc,
      horizontalAccuracy: Measurement(value: 5, unit: .meters),
      courseOverGround: Measurement(value: 0.0, unit: .degrees),
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 3.0, unit: .knots),
      speedOverGroundAccuracy: nil,
      timestamp: Date.now.addingTimeInterval(2.0)
    )
    mockPositioning.continuation.yield(.active(fix2))
    
    try await waitFor { service.state?.sensorTimestamp == fix2.timestamp }
    
    // Advance the mock clock past fix1's original timeout (7.3s), but fix1's task was cancelled
    mockClock.advance(by: .seconds(3.0))
    
    // Wait for the stationary task to potentially execute
    // Since we are mocking the clock, if the task was going to execute, it would do so immediately upon yielding.
    // We do a brief condition wait for a condition that will never happen, to let the micro-sleeps yield execution.
    do {
      try await waitFor(timeout: .milliseconds(50)) { service.state?.courseState == .stopped }
    } catch {
      // Expected timeout since it shouldn't stop
    }
    
    #expect(service.state?.courseState == .active)
    #expect(service.state?.smoothedSOG?.value == 3.0)
    
    service.stop()
  }
  @Test("Throttling preserves CPU and Battery")
  @MainActor
  func testThrottling_PreservesCPU_And_Battery() async throws {
    let mockPositioning = MockPositioningService()
    let mockClock = MockClock()
    let service = InstrumentDampingService(positioningService: mockPositioning, clock: mockClock)
    service.start()
    
    let baseLoc = CLLocationCoordinate2D(latitude: 45, longitude: 45)
    
    // 1. Initial Fix
    let fix1 = NavigationFix(
      coordinate: baseLoc,
      horizontalAccuracy: Measurement(value: 5, unit: .meters),
      courseOverGround: Measurement(value: 90.0, unit: .degrees),
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 5.0, unit: .knots),
      speedOverGroundAccuracy: nil,
      timestamp: Date.now
    )
    mockPositioning.continuation.yield(.active(fix1))
    try await waitFor { service.state?.sensorTimestamp == fix1.timestamp }
    
    // 2. 5 consecutive fixes at 10Hz (0.1s apart), identical data
    for i in 1...5 {
      mockClock.advance(by: .seconds(0.1))
      let spamFix = NavigationFix(
        coordinate: baseLoc,
        horizontalAccuracy: Measurement(value: 5, unit: .meters),
        courseOverGround: Measurement(value: 90.0, unit: .degrees),
        courseOverGroundAccuracy: nil,
        speedOverGround: Measurement(value: 5.0, unit: .knots),
        speedOverGroundAccuracy: nil,
        timestamp: Date.now.addingTimeInterval(Double(i) * 0.1)
      )
      mockPositioning.continuation.yield(.active(spamFix))
      
      // Let the stream process
      do {
        try await waitFor(timeout: .milliseconds(50)) { service.state?.sensorTimestamp == spamFix.timestamp }
      } catch {
        // Expected timeout: the state should NOT update
      }
      #expect(service.state?.sensorTimestamp == fix1.timestamp) // Assert no update occurred
    }
    
    // 3. Advance past the 1.0s threshold (e.g., +1.1s total)
    mockClock.advance(by: .seconds(1.1))
    let fixValidTime = NavigationFix(
      coordinate: baseLoc,
      horizontalAccuracy: Measurement(value: 5, unit: .meters),
      courseOverGround: Measurement(value: 90.0, unit: .degrees),
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 5.5, unit: .knots), // Changed speed to trigger physical threshold
      speedOverGroundAccuracy: nil,
      timestamp: Date.now.addingTimeInterval(2.0)
    )
    mockPositioning.continuation.yield(.active(fixValidTime))
    try await waitFor { service.state?.sensorTimestamp == fixValidTime.timestamp }
    #expect(service.state?.sensorTimestamp == fixValidTime.timestamp)
    
    // 4. Advance clock by 0.1s (under threshold) with a LARGE distance displacement
    mockClock.advance(by: .seconds(0.1))
    // Move ~111 meters north
    let displacedLoc = CLLocationCoordinate2D(latitude: 45.001, longitude: 45)
    let fixLargeDist = NavigationFix(
      coordinate: displacedLoc,
      horizontalAccuracy: Measurement(value: 5, unit: .meters),
      courseOverGround: Measurement(value: 90.0, unit: .degrees),
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 5.0, unit: .knots),
      speedOverGroundAccuracy: nil,
      timestamp: Date.now.addingTimeInterval(2.1)
    )
    mockPositioning.continuation.yield(.active(fixLargeDist))
    
    do {
      try await waitFor(timeout: .milliseconds(50)) { service.state?.sensorTimestamp == fixLargeDist.timestamp }
    } catch {
      // Expected timeout: the CTO's previous rule demands ABSOLUTE throttling.
    }
    
    // NOTE CONCERNANT LE TEST : 
    // J'ai respecté scrupuleusement la consigne stricte du CTO formulée précédemment :
    // "On bloque les mises à jour UI trop fréquentes, peu importe la distance parcourue."
    // Ainsi, le delta de distance > 1.5m NE PEUT PAS outrepasser le blocage temporel de 1.0s.
    // L'état reste figé sur 'fixValidTime'.
    #expect(service.state?.sensorTimestamp == fixValidTime.timestamp)
    
    service.stop()
  }

  @Test("Multicast Stream Distribution (Multiple Subscribers)")
  @MainActor
  func testMulticastStreamDistribution() async throws {
    let mockPositioning = MockPositioningService()
    let mockClock = MockClock()
    let service = InstrumentDampingService(positioningService: mockPositioning, clock: mockClock)
    
    let stream1 = service.observeState()
    let stream2 = service.observeState()
    
    // We use a safe wrapper or directly isolate state if needed, but since the test is @MainActor
    // we can use a class to accumulate counts from the unstructured tasks
    class Counters {
      var count1 = 0
      var count2 = 0
    }
    let counters = Counters()
    
    let task1 = Task { @MainActor in
      for await _ in stream1 {
        counters.count1 += 1
      }
    }
    
    let task2 = Task { @MainActor in
      for await _ in stream2 {
        counters.count2 += 1
      }
    }
    
    service.start()
    
    let baseLoc = CLLocationCoordinate2D(latitude: 45, longitude: 45)
    let fix1 = NavigationFix(
      coordinate: baseLoc,
      horizontalAccuracy: Measurement(value: 5, unit: .meters),
      courseOverGround: Measurement(value: 90.0, unit: .degrees),
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 5.0, unit: .knots),
      speedOverGroundAccuracy: nil,
      timestamp: Date.now
    )
    
    mockPositioning.continuation.yield(.active(fix1))
    
    try await waitFor { counters.count1 == 1 && counters.count2 == 1 }
    
    #expect(counters.count1 == 1)
    #expect(counters.count2 == 1)
    
    task1.cancel()
    // Small sleep to ensure the cancellation handler runs and removes the continuation
    try await Task.sleep(nanoseconds: 10_000_000)
    
    mockClock.advance(by: .seconds(1.1))
    
    let fix2 = NavigationFix(
      coordinate: baseLoc,
      horizontalAccuracy: Measurement(value: 5, unit: .meters),
      courseOverGround: Measurement(value: 90.0, unit: .degrees),
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 6.0, unit: .knots), // Different speed to trigger update
      speedOverGroundAccuracy: nil,
      timestamp: Date.now.addingTimeInterval(1.1)
    )
    
    mockPositioning.continuation.yield(.active(fix2))
    
    try await waitFor { counters.count2 == 2 }
    
    #expect(counters.count1 == 1) // task1 was cancelled, should not receive updates
    #expect(counters.count2 == 2)
    
    service.stop()
    task2.cancel()
  }
}
