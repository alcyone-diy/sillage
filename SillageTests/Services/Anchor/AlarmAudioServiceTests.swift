//
//  AlarmAudioServiceTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-15.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import AVFoundation
import Clocks
import os
@testable import Sillage

private final class MockAlarmAudioEngine: AlarmAudioPlaying, @unchecked Sendable {
  private struct State {
    var startResults: [Bool]
    var startCalls: [UUID] = []
    var transitionResults: [Bool] = [true]
    var transitionCalls: [UUID] = []
    var interruptionBeganCalls: [UUID] = []
    var stopCallCount = 0
    var prepareCallCount = 0
    var latestEscalationCallback: (@MainActor @Sendable () -> Void)?
  }

  private let stateLock: OSAllocatedUnfairLock<State>

  init(startResults: [Bool] = [true]) {
    self.stateLock = OSAllocatedUnfairLock(initialState: State(startResults: startResults))
  }

  var startCallCount: Int {
    stateLock.withLock { $0.startCalls.count }
  }

  var transitionCallCount: Int {
    stateLock.withLock { $0.transitionCalls.count }
  }

  var interruptionBeganCallCount: Int {
    stateLock.withLock { $0.interruptionBeganCalls.count }
  }

  var stopCallCount: Int {
    stateLock.withLock { $0.stopCallCount }
  }

  @MainActor
  func triggerEscalationFinished() {
    let callback = stateLock.withLock { $0.latestEscalationCallback }
    callback?()
  }

  func prepareAudioSession() async {
    stateLock.withLock { $0.prepareCallCount += 1 }
  }

  func startPlayback(
    sessionID: UUID,
    onEscalationDidFinish: @escaping @MainActor @Sendable () -> Void
  ) async -> Bool {
    stateLock.withLock { state in
      state.startCalls.append(sessionID)
      state.latestEscalationCallback = onEscalationDidFinish
      if state.startResults.isEmpty {
        return true
      }
      return state.startResults.removeFirst()
    }
  }

  func handleInterruptionBegan(sessionID: UUID) async {
    stateLock.withLock { $0.interruptionBeganCalls.append(sessionID) }
  }

  func transitionToContinuousSiren(sessionID: UUID) async -> Bool {
    stateLock.withLock { state in
      state.transitionCalls.append(sessionID)
      if state.transitionResults.isEmpty {
        return true
      }
      return state.transitionResults.removeFirst()
    }
  }

  func stopPlayback() async {
    stateLock.withLock { $0.stopCallCount += 1 }
  }
}

@MainActor
final class AlarmAudioServiceTests: XCTestCase {

  func testBundleAudioResources_existInBundleRootAndArePlayable() throws {
    let requiredSoundFiles = ["AnchorAlarm_CleanEscalation_27s", "SirenAlarm"]

    for name in requiredSoundFiles {
      let rootURL = Bundle.main.url(forResource: name, withExtension: "wav")
      XCTAssertNotNil(
        rootURL,
        "Expected \(name).wav at app bundle root for AVAudioPlayer and UNNotificationSound"
      )
      guard let rootURL else { continue }
      let player = try AVAudioPlayer(contentsOf: rootURL)
      XCTAssertGreaterThan(player.duration, 0, "Expected non-empty audio duration for \(name).wav")
    }
  }

  func testStartSiren_retriesWhenPlaybackFailsAndStopsRetryingOnSuccess() async throws {
    let engine = MockAlarmAudioEngine(startResults: [false, false, true])
    let clock = TestClock()
    var vibrateCount = 0
    let service = AlarmAudioService(
      audioEngine: engine,
      clock: clock,
      retryDelays: [.seconds(1), .seconds(2), .seconds(4)],
      vibrationInterval: .seconds(1),
      vibrate: { vibrateCount += 1 }
    )

    service.startSiren()

    try await waitFor { engine.startCallCount == 1 && service.hasPendingPlaybackRetry }
    await clock.advance(by: .seconds(1))
    try await waitFor { engine.startCallCount == 2 && service.hasPendingPlaybackRetry }
    await clock.advance(by: .seconds(2))
    try await waitFor { engine.startCallCount == 3 }
    await clock.advance(by: .seconds(10))

    XCTAssertEqual(engine.startCallCount, 3)
    XCTAssertFalse(service.hasPendingPlaybackRetry)
    XCTAssertGreaterThanOrEqual(vibrateCount, 1)

    service.stopSiren()
    try await waitFor { engine.stopCallCount == 1 }
  }

  func testStopSiren_cancelsPendingPlaybackRetry() async throws {
    let engine = MockAlarmAudioEngine(startResults: [false, false])
    let clock = TestClock()
    let service = AlarmAudioService(
      audioEngine: engine,
      clock: clock,
      retryDelays: [.seconds(1), .seconds(2)],
      vibrationInterval: .seconds(10),
      vibrate: {}
    )

    service.startSiren()
    try await waitFor { engine.startCallCount == 1 && service.hasPendingPlaybackRetry }

    service.stopSiren()
    try await waitFor { engine.stopCallCount == 1 }
    await clock.advance(by: .seconds(10))

    XCTAssertEqual(engine.startCallCount, 1)
    XCTAssertFalse(service.hasPendingPlaybackRetry)
  }

  func testAudioInterruptionAndRouteChange_pauseAndResumeActiveAlarm() async throws {
    let engine = MockAlarmAudioEngine(startResults: [true, true, true])
    let clock = TestClock()
    let service = AlarmAudioService(
      audioEngine: engine,
      clock: clock,
      retryDelays: [.seconds(1)],
      vibrationInterval: .seconds(10),
      vibrate: {}
    )

    service.startSiren()
    try await waitFor { engine.startCallCount == 1 }

    NotificationCenter.default.post(
      name: AVAudioSession.interruptionNotification,
      object: nil,
      userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
    )
    try await waitFor { engine.interruptionBeganCallCount == 1 }

    NotificationCenter.default.post(
      name: AVAudioSession.interruptionNotification,
      object: nil,
      userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue]
    )
    try await waitFor { engine.startCallCount == 2 }

    NotificationCenter.default.post(
      name: AVAudioSession.routeChangeNotification,
      object: nil,
      userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue]
    )
    try await waitFor { engine.startCallCount == 3 }

    service.stopSiren()
    try await waitFor { engine.stopCallCount == 1 }
  }

  func testEscalationDidFinish_transitionsToContinuousSiren() async throws {
    let engine = MockAlarmAudioEngine(startResults: [true])
    let clock = TestClock()
    let service = AlarmAudioService(
      audioEngine: engine,
      clock: clock,
      retryDelays: [.seconds(1)],
      vibrationInterval: .seconds(10),
      vibrate: {}
    )

    service.startSiren()
    try await waitFor { engine.startCallCount == 1 }

    engine.triggerEscalationFinished()
    try await waitFor { engine.transitionCallCount == 1 }

    service.stopSiren()
    try await waitFor { engine.stopCallCount == 1 }
  }

  func testRapidRestart_doesNotLetCancelledVibrationTaskClearNewVibrationLoop() async throws {
    let engine = MockAlarmAudioEngine(startResults: [true, true])
    let clock = TestClock()
    var vibrateCount = 0
    let service = AlarmAudioService(
      audioEngine: engine,
      clock: clock,
      retryDelays: [.seconds(1)],
      vibrationInterval: .seconds(1),
      vibrate: { vibrateCount += 1 }
    )

    service.startSiren()
    try await waitFor { vibrateCount >= 1 }
    service.stopSiren()
    let countAfterStop = vibrateCount

    service.startSiren()
    try await waitFor { vibrateCount >= countAfterStop + 1 }
    await clock.advance(by: .seconds(1))
    try await waitFor { vibrateCount >= countAfterStop + 2 }
    await clock.advance(by: .seconds(1))
    try await waitFor { vibrateCount >= countAfterStop + 3 }

    service.stopSiren()
    try await waitFor { engine.stopCallCount == 2 }
  }
}
