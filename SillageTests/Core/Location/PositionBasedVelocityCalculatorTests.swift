//
//  PositionBasedVelocityCalculatorTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-19.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Testing
import Foundation
import CoreLocation
@testable import Sillage

@MainActor
struct PositionBasedVelocityCalculatorTests {

  private let defaultNoiseMultiplier: Double = 1.0
  private let defaultAccuracy = Measurement<UnitLength>(value: 1.0, unit: .meters)

  @Test("Initial fix returns nil velocity estimate")
  func testInitialFixReturnsNil() async {
    let calculator = PositionBasedVelocityCalculator()
    let now = Date()

    let estimate = await calculator.calculate(
      coordinate: CLLocationCoordinate2D(latitude: 46.15, longitude: -1.15),
      horizontalAccuracy: defaultAccuracy,
      timestamp: now,
      noiseMultiplier: defaultNoiseMultiplier
    )

    #expect(estimate.speedOverGround == nil)
    #expect(estimate.courseOverGround == nil)
    #expect(estimate.speedOverGroundAccuracy == nil)
    #expect(estimate.courseOverGroundAccuracy == nil)
  }

  @Test("Identical coordinates return 0 SOG and nil COG")
  func testIdenticalCoordinatesReturnZeroSOGAndNilCOG() async {
    let calculator = PositionBasedVelocityCalculator()
    let t0 = Date()
    let coord = CLLocationCoordinate2D(latitude: 46.15, longitude: -1.15)

    _ = await calculator.calculate(
      coordinate: coord,
      horizontalAccuracy: defaultAccuracy,
      timestamp: t0,
      noiseMultiplier: defaultNoiseMultiplier
    )

    let estimate = await calculator.calculate(
      coordinate: coord,
      horizontalAccuracy: defaultAccuracy,
      timestamp: t0.addingTimeInterval(1.0),
      noiseMultiplier: defaultNoiseMultiplier
    )

    #expect(estimate.speedOverGround?.value == 0.0)
    #expect(estimate.courseOverGround == nil)
    #expect(estimate.speedOverGroundAccuracy != nil)
  }

  @Test("Micro-jitter below dynamic noise floor returns 0 SOG and nil COG")
  func testMicroJitterBelowNoiseFloorReturnsZeroSOGAndNilCOG() async {
    let calculator = PositionBasedVelocityCalculator()
    let t0 = Date()
    // Horizontal accuracy is 3.0m -> sigmaD is sqrt(3^2 + 3^2) = ~4.24m
    let accuracy = Measurement<UnitLength>(value: 3.0, unit: .meters)
    let coord1 = CLLocationCoordinate2D(latitude: 46.150000, longitude: -1.150000)
    // ~1.11 meters displacement (< 4.24m * 1.0)
    let dLatDeg = 1.11 / 111195.0
    let coord2 = CLLocationCoordinate2D(latitude: 46.150000 + dLatDeg, longitude: -1.150000)

    _ = await calculator.calculate(
      coordinate: coord1,
      horizontalAccuracy: accuracy,
      timestamp: t0,
      noiseMultiplier: 1.0
    )

    let estimate = await calculator.calculate(
      coordinate: coord2,
      horizontalAccuracy: accuracy,
      timestamp: t0.addingTimeInterval(1.0),
      noiseMultiplier: 1.0
    )

    #expect(estimate.speedOverGround?.value == 0.0)
    #expect(estimate.courseOverGround == nil)
  }

  @Test("Constant movement North calculates SOG and True North COG (~0°)")
  func testMovementNorth() async {
    let calculator = PositionBasedVelocityCalculator()
    let t0 = Date()
    let coord1 = CLLocationCoordinate2D(latitude: 46.0, longitude: -1.0)
    // Move ~5.56 meters North in 1 second (~10.8 knots)
    let dLatDeg = 5.56 / 111195.0
    let coord2 = CLLocationCoordinate2D(latitude: 46.0 + dLatDeg, longitude: -1.0)

    _ = await calculator.calculate(
      coordinate: coord1,
      horizontalAccuracy: defaultAccuracy,
      timestamp: t0,
      noiseMultiplier: defaultNoiseMultiplier
    )

    let estimate = await calculator.calculate(
      coordinate: coord2,
      horizontalAccuracy: defaultAccuracy,
      timestamp: t0.addingTimeInterval(1.0),
      noiseMultiplier: defaultNoiseMultiplier
    )

    #expect(estimate.speedOverGround != nil)
    if let sog = estimate.speedOverGround {
      let mps = sog.converted(to: .metersPerSecond).value
      #expect(abs(mps - 5.56) < 0.2)
    }

    #expect(estimate.courseOverGround != nil)
    if let cog = estimate.courseOverGround {
      let deg = cog.converted(to: .degrees).value
      #expect(abs(deg - 0.0) < 1.0 || abs(deg - 360.0) < 1.0)
    }
  }

  @Test("Constant movement East calculates SOG and True East COG (~90°)")
  func testMovementEast() async {
    let calculator = PositionBasedVelocityCalculator()
    let t0 = Date()
    let coord1 = CLLocationCoordinate2D(latitude: 46.0, longitude: -1.0)
    // Move ~5.56 meters East in 1 second
    let meanLatRad = 46.0 * .pi / 180.0
    let dLonDeg = 5.56 / (111195.0 * cos(meanLatRad))
    let coord2 = CLLocationCoordinate2D(latitude: 46.0, longitude: -1.0 + dLonDeg)

    _ = await calculator.calculate(
      coordinate: coord1,
      horizontalAccuracy: defaultAccuracy,
      timestamp: t0,
      noiseMultiplier: defaultNoiseMultiplier
    )

    let estimate = await calculator.calculate(
      coordinate: coord2,
      horizontalAccuracy: defaultAccuracy,
      timestamp: t0.addingTimeInterval(1.0),
      noiseMultiplier: defaultNoiseMultiplier
    )

    #expect(estimate.speedOverGround != nil)
    if let sog = estimate.speedOverGround {
      let mps = sog.converted(to: .metersPerSecond).value
      #expect(abs(mps - 5.56) < 0.2)
    }

    #expect(estimate.courseOverGround != nil)
    if let cog = estimate.courseOverGround {
      let deg = cog.converted(to: .degrees).value
      #expect(abs(deg - 90.0) < 1.0)
    }
  }

  @Test("Movement South (~180°) and West (~270°)")
  func testMovementSouthAndWest() async {
    let calculator = PositionBasedVelocityCalculator()
    let t0 = Date()
    let coord1 = CLLocationCoordinate2D(latitude: 46.0, longitude: -1.0)
    let dLatDeg = 5.56 / 111195.0

    // South
    _ = await calculator.calculate(coordinate: coord1, horizontalAccuracy: defaultAccuracy, timestamp: t0, noiseMultiplier: defaultNoiseMultiplier)
    let southFix = await calculator.calculate(
      coordinate: CLLocationCoordinate2D(latitude: 46.0 - dLatDeg, longitude: -1.0),
      horizontalAccuracy: defaultAccuracy,
      timestamp: t0.addingTimeInterval(1.0),
      noiseMultiplier: defaultNoiseMultiplier
    )
    if let cog = southFix.courseOverGround {
      #expect(abs(cog.converted(to: .degrees).value - 180.0) < 1.0)
    }

    // West
    await calculator.reset()
    let meanLatRad = 46.0 * .pi / 180.0
    let dLonDeg = 5.56 / (111195.0 * cos(meanLatRad))
    _ = await calculator.calculate(coordinate: coord1, horizontalAccuracy: defaultAccuracy, timestamp: t0, noiseMultiplier: defaultNoiseMultiplier)
    let westFix = await calculator.calculate(
      coordinate: CLLocationCoordinate2D(latitude: 46.0, longitude: -1.0 - dLonDeg),
      horizontalAccuracy: defaultAccuracy,
      timestamp: t0.addingTimeInterval(1.0),
      noiseMultiplier: defaultNoiseMultiplier
    )
    if let cog = westFix.courseOverGround {
      #expect(abs(cog.converted(to: .degrees).value - 270.0) < 1.0)
    }
  }

  @Test("Time gap exceeding max resets history cleanly")
  func testTimeGapResetsHistory() async {
    let calculator = PositionBasedVelocityCalculator(maxGapDuration: 10.0)
    let t0 = Date()
    let coord1 = CLLocationCoordinate2D(latitude: 46.0, longitude: -1.0)
    let coord2 = CLLocationCoordinate2D(latitude: 46.0001, longitude: -1.0)

    _ = await calculator.calculate(coordinate: coord1, horizontalAccuracy: defaultAccuracy, timestamp: t0, noiseMultiplier: defaultNoiseMultiplier)

    // Gap of 15 seconds (> 10s max gap)
    let gapEstimate = await calculator.calculate(
      coordinate: coord2,
      horizontalAccuracy: defaultAccuracy,
      timestamp: t0.addingTimeInterval(15.0),
      noiseMultiplier: defaultNoiseMultiplier
    )

    // Must return nil as it becomes the new baseline
    #expect(gapEstimate.speedOverGround == nil)
    #expect(gapEstimate.courseOverGround == nil)

    // Next fix 1s later computes velocity properly from new baseline
    let coord3 = CLLocationCoordinate2D(latitude: 46.0002, longitude: -1.0)
    let followUp = await calculator.calculate(
      coordinate: coord3,
      horizontalAccuracy: defaultAccuracy,
      timestamp: t0.addingTimeInterval(16.0),
      noiseMultiplier: defaultNoiseMultiplier
    )

    #expect(followUp.speedOverGround != nil)
    #expect(followUp.courseOverGround != nil)
  }

  @Test("Negative or zero delta time returns nil and drops anomaly")
  func testNonPositiveDeltaTime() async {
    let calculator = PositionBasedVelocityCalculator()
    let t0 = Date()
    let coord = CLLocationCoordinate2D(latitude: 46.0, longitude: -1.0)

    _ = await calculator.calculate(coordinate: coord, horizontalAccuracy: defaultAccuracy, timestamp: t0, noiseMultiplier: defaultNoiseMultiplier)

    let duplicateTime = await calculator.calculate(
      coordinate: CLLocationCoordinate2D(latitude: 46.0001, longitude: -1.0),
      horizontalAccuracy: defaultAccuracy,
      timestamp: t0,
      noiseMultiplier: defaultNoiseMultiplier
    )

    #expect(duplicateTime.speedOverGround == nil)
    #expect(duplicateTime.courseOverGround == nil)
  }

  @Test("Dynamic noise multiplier rejects displacement below sigmaD * multiplier")
  func testDynamicNoiseMultiplier() async {
    let calculator = PositionBasedVelocityCalculator()
    let t0 = Date()
    // accuracy = 2.0m -> sigmaD = sqrt(2^2 + 2^2) = ~2.83m
    let accuracy = Measurement<UnitLength>(value: 2.0, unit: .meters)
    let coord1 = CLLocationCoordinate2D(latitude: 46.0, longitude: -1.0)
    // Displacement of ~3.33 meters North
    let dLatDeg = 3.33 / 111195.0
    let coord2 = CLLocationCoordinate2D(latitude: 46.0 + dLatDeg, longitude: -1.0)

    // With multiplier 1.5: sigmaD * 1.5 = 2.83 * 1.5 = 4.24m. 3.33m < 4.24m -> rejected (stationary)
    _ = await calculator.calculate(coordinate: coord1, horizontalAccuracy: accuracy, timestamp: t0, noiseMultiplier: 1.5)
    let estimateRejected = await calculator.calculate(
      coordinate: coord2,
      horizontalAccuracy: accuracy,
      timestamp: t0.addingTimeInterval(1.0),
      noiseMultiplier: 1.5
    )
    #expect(estimateRejected.speedOverGround?.value == 0.0)
    #expect(estimateRejected.courseOverGround == nil)

    // With multiplier 0.8: sigmaD * 0.8 = 2.83 * 0.8 = 2.26m. 3.33m > 2.26m -> accepted (valid movement)
    await calculator.reset()
    _ = await calculator.calculate(coordinate: coord1, horizontalAccuracy: accuracy, timestamp: t0, noiseMultiplier: 0.8)
    let estimateAccepted = await calculator.calculate(
      coordinate: coord2,
      horizontalAccuracy: accuracy,
      timestamp: t0.addingTimeInterval(1.0),
      noiseMultiplier: 0.8
    )
    if let sog = estimateAccepted.speedOverGround {
      #expect(sog.value > 0.0)
    } else {
      Issue.record("Expected non-nil speedOverGround")
    }
    #expect(estimateAccepted.courseOverGround != nil)
  }

  @Test("Adaptive baseline picks shortest valid time interval to minimize latency")
  func testAdaptiveBaselinePicksShortestValidInterval() async {
    let calculator = PositionBasedVelocityCalculator(windowDuration: 6.0)
    let t0 = Date()
    let coord0 = CLLocationCoordinate2D(latitude: 46.0, longitude: -1.0)
    let dLat1 = 5.0 / 111195.0
    let coord1 = CLLocationCoordinate2D(latitude: 46.0 + dLat1, longitude: -1.0)
    let dLat2 = 10.0 / 111195.0
    let coord2 = CLLocationCoordinate2D(latitude: 46.0 + dLat2, longitude: -1.0)

    _ = await calculator.calculate(coordinate: coord0, horizontalAccuracy: defaultAccuracy, timestamp: t0, noiseMultiplier: defaultNoiseMultiplier)
    _ = await calculator.calculate(coordinate: coord1, horizontalAccuracy: defaultAccuracy, timestamp: t0.addingTimeInterval(1.0), noiseMultiplier: defaultNoiseMultiplier)

    // At t2, both coord1 (dt=1.0s, dist=5m) and coord0 (dt=2.0s, dist=10m) exceed noise floor (1.414m).
    // Adaptive baseline should pick coord1 (most recent valid prior fix, dt=1.0s), yielding ~5 m/s.
    let estimate = await calculator.calculate(
      coordinate: coord2,
      horizontalAccuracy: defaultAccuracy,
      timestamp: t0.addingTimeInterval(2.0),
      noiseMultiplier: defaultNoiseMultiplier
    )

    #expect(estimate.speedOverGround != nil)
    if let sog = estimate.speedOverGround {
      let mps = sog.converted(to: .metersPerSecond).value
      #expect(abs(mps - 5.0) < 0.2)
    }
  }

  @Test("Single transient noisy fix during active motion coasts with nil rather than dropping to 0")
  func testTransientNoisyFixCoastsDuringMotion() async {
    let calculator = PositionBasedVelocityCalculator()
    let t0 = Date()
    let coord1 = CLLocationCoordinate2D(latitude: 46.0, longitude: -1.0)
    let dLatDeg = 5.56 / 111195.0
    let coord2 = CLLocationCoordinate2D(latitude: 46.0 + dLatDeg, longitude: -1.0)

    // Moving fix: 5.56m North in 1s
    _ = await calculator.calculate(coordinate: coord1, horizontalAccuracy: defaultAccuracy, timestamp: t0, noiseMultiplier: defaultNoiseMultiplier)
    let movingEst = await calculator.calculate(
      coordinate: coord2,
      horizontalAccuracy: defaultAccuracy,
      timestamp: t0.addingTimeInterval(1.0),
      noiseMultiplier: defaultNoiseMultiplier
    )
    if let sog = movingEst.speedOverGround {
      #expect(sog.value > 0)
    } else {
      Issue.record("Expected non-nil speedOverGround")
    }

    // Transient noisy fix: accuracy spikes to 50m, displacement is small
    let badAccuracy = Measurement<UnitLength>(value: 50.0, unit: .meters)
    let coastingEst = await calculator.calculate(
      coordinate: coord2,
      horizontalAccuracy: badAccuracy,
      timestamp: t0.addingTimeInterval(2.0),
      noiseMultiplier: defaultNoiseMultiplier
    )

    // First rejected fix during motion coasts (nil, not 0.0)
    #expect(coastingEst.speedOverGround == nil)
    #expect(coastingEst.courseOverGround == nil)

    // Second consecutive rejected fix confirms stationary (0.0)
    let stationaryEst = await calculator.calculate(
      coordinate: coord2,
      horizontalAccuracy: badAccuracy,
      timestamp: t0.addingTimeInterval(3.0),
      noiseMultiplier: defaultNoiseMultiplier
    )
    #expect(stationaryEst.speedOverGround?.value == 0.0)
  }

  @Test("Continuous slow movement at 1 knot accumulates signal over buffer and calculates SOG/COG")
  func testContinuousOneKnotMovementCalculatesSOGAndCOG() async {
    let calculator = PositionBasedVelocityCalculator(windowDuration: 10.0, maxGapDuration: 10.0)
    let t0 = Date()
    let speedMps = 0.5144 // 1.0 knot
    let dLatPerSec = speedMps / 111195.0
    let accuracy = Measurement<UnitLength>(value: 5.0, unit: .meters)
    let noiseMultiplier = 0.35 // threshold is sqrt(5^2 + 5^2) * 0.35 = ~2.47m

    var lastEstimate: PositionBasedVelocityCalculator.VelocityEstimate?
    // Simulate 10 seconds of continuous movement at 1 knot North (0.514m each second)
    for second in 0...10 {
      let coord = CLLocationCoordinate2D(
        latitude: 46.0 + Double(second) * dLatPerSec,
        longitude: -1.0
      )
      lastEstimate = await calculator.calculate(
        coordinate: coord,
        horizontalAccuracy: accuracy,
        timestamp: t0.addingTimeInterval(Double(second)),
        noiseMultiplier: noiseMultiplier,
        windowDuration: 10.0
      )
    }

    // At 10 seconds, total displacement is 5.14m > 2.47m threshold.
    // Must yield ~1.0 knot and ~0° (North) COG!
    #expect(lastEstimate?.speedOverGround != nil)
    if let sog = lastEstimate?.speedOverGround {
      let knots = sog.converted(to: .knots).value
      #expect(abs(knots - 1.0) < 0.2)
    }

    #expect(lastEstimate?.courseOverGround != nil)
    if let cog = lastEstimate?.courseOverGround {
      let deg = cog.converted(to: .degrees).value
      #expect(abs(deg - 0.0) < 2.0 || abs(deg - 360.0) < 2.0)
    }
  }

  @Test("Window duration parameter strictly limits baseline search to specified duration")
  func testWindowDurationLimitsBaselineSearch() async {
    let calculator = PositionBasedVelocityCalculator(windowDuration: 10.0)
    let t0 = Date()
    let accuracy = Measurement<UnitLength>(value: 5.0, unit: .meters)
    let noiseMultiplier = 0.35 // threshold is ~2.47m

    // Fix at t=0
    _ = await calculator.calculate(
      coordinate: CLLocationCoordinate2D(latitude: 46.0, longitude: -1.0),
      horizontalAccuracy: accuracy,
      timestamp: t0,
      noiseMultiplier: noiseMultiplier,
      windowDuration: 2.0
    )

    // Moving slowly North: 1.0m at t=1s, 2.0m at t=2s, 3.0m at t=3s
    // With windowDuration = 2.0s, at t=3s the t=0s fix (3.0m away) has been pruned.
    // The only prior fixes available are t=2s (1.0m away < 2.47m) and t=1s (2.0m away < 2.47m).
    // None clear the 2.47m threshold -> COG must be nil.
    let dLat1m = 1.0 / 111195.0
    _ = await calculator.calculate(
      coordinate: CLLocationCoordinate2D(latitude: 46.0 + dLat1m, longitude: -1.0),
      horizontalAccuracy: accuracy,
      timestamp: t0.addingTimeInterval(1.0),
      noiseMultiplier: noiseMultiplier,
      windowDuration: 2.0
    )
    _ = await calculator.calculate(
      coordinate: CLLocationCoordinate2D(latitude: 46.0 + 2.0 * dLat1m, longitude: -1.0),
      horizontalAccuracy: accuracy,
      timestamp: t0.addingTimeInterval(2.0),
      noiseMultiplier: noiseMultiplier,
      windowDuration: 2.0
    )
    let estimateAt3s = await calculator.calculate(
      coordinate: CLLocationCoordinate2D(latitude: 46.0 + 3.0 * dLat1m, longitude: -1.0),
      horizontalAccuracy: accuracy,
      timestamp: t0.addingTimeInterval(3.0),
      noiseMultiplier: noiseMultiplier,
      windowDuration: 2.0
    )

    // With 2.0s window, max displacement in window is 2.0m < 2.47m threshold -> no SOG/COG
    #expect(estimateAt3s.courseOverGround == nil)

    // Now send fix at t=4s with larger windowDuration = 5.0s and 5.0m total displacement
    // Now the window retains enough history to clear the 2.47m threshold!
    let estimateAt4s = await calculator.calculate(
      coordinate: CLLocationCoordinate2D(latitude: 46.0 + 5.0 * dLat1m, longitude: -1.0),
      horizontalAccuracy: accuracy,
      timestamp: t0.addingTimeInterval(4.0),
      noiseMultiplier: noiseMultiplier,
      windowDuration: 5.0
    )
    #expect(estimateAt4s.speedOverGround != nil)
    #expect(estimateAt4s.courseOverGround != nil)
  }
}
