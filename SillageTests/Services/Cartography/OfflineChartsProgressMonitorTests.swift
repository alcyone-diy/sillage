//
//  OfflineChartsProgressMonitorTests.swift
//  SillageTests
//
//  Created by Alcyone on 2026-11-26.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Testing
@testable import Sillage

@Suite("OfflineChartsProgressMonitor")
@MainActor
struct OfflineChartsProgressMonitorTests {

  private func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @MainActor () -> Bool
  ) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
      if ContinuousClock.now >= deadline {
        return false
      }
      await Task.yield()
      try? await Task.sleep(for: .milliseconds(5))
    }
    return true
  }

  @Test("Initial state is idle")
  func initialStateIsIdle() {
    let monitor = OfflineChartsProgressMonitor()
    #expect(monitor.progress == nil)
    #expect(monitor.isDownloading == false)
  }

  @Test("MapLibre-only progress updates synchronously and returns to idle")
  func mapLibreOnlyProgress() {
    let monitor = OfflineChartsProgressMonitor()

    monitor.updateMapLibreProgress(0.4)
    #expect(monitor.isDownloading == true)
    #expect(monitor.progress == 0.4)

    monitor.updateMapLibreProgress(0.75)
    #expect(monitor.isDownloading == true)
    #expect(monitor.progress == 0.75)

    monitor.updateMapLibreProgress(nil)
    #expect(monitor.isDownloading == false)
    #expect(monitor.progress == nil)
  }

  @Test("GeoGarage-only progress streams and returns to idle")
  func geoGarageOnlyProgress() async {
    let monitor = OfflineChartsProgressMonitor()
    let (stream, continuation) = AsyncStream<Double?>.makeStream()
    defer {
      continuation.finish()
      monitor.stop()
    }

    monitor.start(geoGarageProgressStream: stream)

    continuation.yield(0.25)
    let reachedFirst = await waitUntil { monitor.progress == 0.25 }
    #expect(reachedFirst)
    #expect(monitor.isDownloading == true)

    continuation.yield(0.8)
    let reachedSecond = await waitUntil { monitor.progress == 0.8 }
    #expect(reachedSecond)

    continuation.yield(nil)
    let returnedToIdle = await waitUntil { monitor.progress == nil }
    #expect(returnedToIdle)
    #expect(monitor.isDownloading == false)
  }

  @Test("Parallel MapLibre and GeoGarage progress averages both engines")
  func parallelEnginesAverageProgress() async {
    let monitor = OfflineChartsProgressMonitor()
    let (stream, continuation) = AsyncStream<Double?>.makeStream()
    defer {
      continuation.finish()
      monitor.stop()
    }

    monitor.start(geoGarageProgressStream: stream)
    monitor.updateMapLibreProgress(0.4)
    #expect(monitor.progress == 0.4)

    continuation.yield(0.8)
    let reachedAverage = await waitUntil {
      guard let progress = monitor.progress else { return false }
      return abs(progress - 0.6) < 1e-9
    }
    #expect(reachedAverage)
    #expect(monitor.isDownloading == true)

    // MapLibre finishes while GeoGarage is still downloading.
    monitor.updateMapLibreProgress(nil)
    #expect(monitor.progress == 0.8)
    #expect(monitor.isDownloading == true)

    // GeoGarage finishes too -> idle.
    continuation.yield(nil)
    let returnedToIdle = await waitUntil { monitor.progress == nil }
    #expect(returnedToIdle)
    #expect(monitor.isDownloading == false)
  }

  @Test("Delta filter accumulates small increments and passes boundary values immediately")
  func deltaFilterAccumulationAndBoundaries() {
    let monitor = OfflineChartsProgressMonitor(minPublishDelta: 0.01)

    // Transition nil -> non-nil publishes immediately.
    monitor.updateMapLibreProgress(0.500)
    #expect(monitor.progress == 0.500)

    // Small increments below threshold are suppressed individually...
    monitor.updateMapLibreProgress(0.504)
    #expect(monitor.progress == 0.500)
    monitor.updateMapLibreProgress(0.508)
    #expect(monitor.progress == 0.500)

    // ...but raw values accumulate and publish once delta from last published >= 0.01.
    monitor.updateMapLibreProgress(0.511)
    #expect(monitor.progress == 0.511)

    // Boundary value 1.0 bypasses the delta filter even when delta < 0.01.
    monitor.updateMapLibreProgress(0.996)
    #expect(monitor.progress == 0.996)
    monitor.updateMapLibreProgress(1.0)
    #expect(monitor.progress == 1.0)

    // Boundary value 0.0 bypasses the delta filter even when delta < 0.01.
    monitor.updateMapLibreProgress(0.004)
    #expect(monitor.progress == 0.004)
    monitor.updateMapLibreProgress(0.0)
    #expect(monitor.progress == 0.0)
  }

  @Test("stop() cancels observation, clears GeoGarage state, and preserves MapLibre progress")
  func stopCancelsObservation() async {
    let monitor = OfflineChartsProgressMonitor()
    let (stream, continuation) = AsyncStream<Double?>.makeStream()
    defer { continuation.finish() }

    monitor.start(geoGarageProgressStream: stream)
    monitor.updateMapLibreProgress(0.5)

    continuation.yield(0.3)
    let reachedAverage = await waitUntil {
      guard let progress = monitor.progress else { return false }
      return abs(progress - 0.4) < 1e-9
    }
    #expect(reachedAverage)

    monitor.stop()
    // GeoGarage state is cleared while the parallel MapLibre download remains intact.
    #expect(monitor.progress == 0.5)
    #expect(monitor.isDownloading == true)

    // Yielding after stop() must not mutate progress.
    continuation.yield(0.9)
    try? await Task.sleep(for: .milliseconds(50))
    #expect(monitor.progress == 0.5)

    // Clearing MapLibre too returns to idle.
    monitor.updateMapLibreProgress(nil)
    #expect(monitor.progress == nil)
    #expect(monitor.isDownloading == false)
  }

  @Test("Calling start() again cancels the previous stream and resets GeoGarage state")
  func restartCancelsPreviousStream() async {
    let monitor = OfflineChartsProgressMonitor()
    let (stream1, continuation1) = AsyncStream<Double?>.makeStream()
    let (stream2, continuation2) = AsyncStream<Double?>.makeStream()
    defer {
      continuation1.finish()
      continuation2.finish()
      monitor.stop()
    }

    monitor.start(geoGarageProgressStream: stream1)
    continuation1.yield(0.2)
    let reachedFirst = await waitUntil { monitor.progress == 0.2 }
    #expect(reachedFirst)

    // Switch to stream2: previous GeoGarage progress resets to nil until stream2 emits.
    monitor.start(geoGarageProgressStream: stream2)
    #expect(monitor.progress == nil)
    #expect(monitor.isDownloading == false)

    // Late emissions from stream1 must be ignored.
    continuation1.yield(0.95)
    try? await Task.sleep(for: .milliseconds(30))
    #expect(monitor.progress == nil)

    continuation2.yield(0.6)
    let reachedSecond = await waitUntil { monitor.progress == 0.6 }
    #expect(reachedSecond)
    #expect(monitor.isDownloading == true)
  }

  @Test("Natural stream termination without yielding nil clears progress and returns to idle")
  func naturalStreamTerminationReturnsToIdle() async {
    let monitor = OfflineChartsProgressMonitor()
    let (stream, continuation) = AsyncStream<Double?>.makeStream()

    monitor.start(geoGarageProgressStream: stream)
    continuation.yield(0.45)
    let reachedActive = await waitUntil { monitor.progress == 0.45 }
    #expect(reachedActive)
    #expect(monitor.isDownloading == true)

    // Finish stream without yielding nil beforehand.
    continuation.finish()
    let returnedToIdle = await waitUntil { monitor.progress == nil }
    #expect(returnedToIdle)
    #expect(monitor.isDownloading == false)
  }
}
