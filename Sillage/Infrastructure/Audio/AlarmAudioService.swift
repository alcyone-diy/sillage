//
//  AlarmAudioService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-07.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import AudioToolbox
import OSLog

/// Orchestrates alarm audio session state, FIFO engine commands, bounded exponential backoff retries,
/// 5-minute safety-bounded system vibrations, and audio interruption / route-change recovery.
@MainActor
final class AlarmAudioService: AlarmAudioServiceProtocol {
  private let audioEngine: any AlarmAudioPlaying
  private let sessionController: any AlarmAudioSessionManaging
  private let clock: any Clock<Duration>
  private let retryDelays: [Duration]
  private let vibrationInterval: Duration
  private let vibrationTimeout: Duration
  private let vibrate: @MainActor @Sendable () -> Void
  private var audioCommandState: (id: UUID, task: Task<Void, Never>)?
  private var activeSessionID: UUID?
  private var isAudioInterrupted = false
  private var retryAttemptIndex = 0
  // Tokenized `(id: UUID, cancellable:)` states prevent a cancelled retry or vibration task from clearing a newer session.
  private var retryState: (id: UUID, cancellable: TaskCancellable)?
  private var vibrationState: (id: UUID, cancellable: TaskCancellable)?
  private var sessionObservers: [TaskCancellable] = []

  init(
    audioEngine: (any AlarmAudioPlaying)? = nil,
    sessionController: any AlarmAudioSessionManaging = SystemAlarmAudioSessionController(),
    clock: any Clock<Duration> = ContinuousClock(),
    retryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(15)],
    vibrationInterval: Duration = .seconds(1),
    vibrationTimeout: Duration = .seconds(300),
    vibrate: @escaping @MainActor @Sendable () -> Void = { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }
  ) {
    self.sessionController = sessionController
    self.audioEngine = audioEngine ?? AlarmAudioEngine(sessionController: sessionController)
    self.clock = clock
    self.retryDelays = retryDelays
    self.vibrationInterval = vibrationInterval
    self.vibrationTimeout = vibrationTimeout
    self.vibrate = vibrate
  }

  func prepareAudioSession() {
    enqueueAudioOperation { engine in
      await engine.prepareAudioSession()
    }
  }

  func startSiren() {
    let sessionID: UUID
    if let existingSessionID = activeSessionID {
      sessionID = existingSessionID
    } else {
      sessionID = UUID()
      activeSessionID = sessionID
      Logger.anchor.fault("🚨 Starting progressive anchor alarm (escalation -> continuous siren)!")
      startVibrationLoop()
      startSessionObservers()
    }

    isAudioInterrupted = false
    cancelPlaybackRetry()
    retryAttemptIndex = 0
    enqueuePlaybackStart(sessionID: sessionID)
  }

  func stopSiren() {
    guard activeSessionID != nil else { return }
    activeSessionID = nil
    isAudioInterrupted = false
    Logger.anchor.info("🔇 Stopping alarm siren audio.")

    cancelPlaybackRetry()
    retryAttemptIndex = 0

    vibrationState?.cancellable.cancel()
    vibrationState = nil

    sessionObservers.forEach { $0.cancel() }
    sessionObservers.removeAll()

    enqueueAudioOperation { engine in
      await engine.stopPlayback()
    }
  }

  var hasPendingPlaybackRetry: Bool {
    retryState != nil
  }

  private func handleEscalationDidFinish() {
    guard let sessionID = activeSessionID else { return }
    enqueueAudioOperation { [weak self] engine in
      let started = await engine.transitionToContinuousSiren(sessionID: sessionID)
      await self?.handlePlaybackAttemptResult(started: started, sessionID: sessionID)
    }
  }

  private func enqueuePlaybackStart(sessionID: UUID) {
    let onEscalationDidFinish: @MainActor @Sendable () -> Void = { [weak self] in
      self?.handleEscalationDidFinish()
    }
    enqueueAudioOperation { [weak self] engine in
      let started = await engine.startPlayback(
        sessionID: sessionID,
        onEscalationDidFinish: onEscalationDidFinish
      )
      await self?.handlePlaybackAttemptResult(started: started, sessionID: sessionID)
    }
  }

  /// Schedules bounded exponential backoff retries when playback or session activation fails transiently in the background.
  private func handlePlaybackAttemptResult(started: Bool, sessionID: UUID) {
    guard activeSessionID == sessionID else { return }

    if started {
      cancelPlaybackRetry()
      retryAttemptIndex = 0
      return
    }

    guard !isAudioInterrupted else { return }

    guard retryAttemptIndex < retryDelays.count else {
      Logger.anchor.fault("🚨 Exhausted in-app alarm audio playback retries; relying on system notifications.")
      return
    }

    let delay = retryDelays[retryAttemptIndex]
    retryAttemptIndex += 1
    let attemptNumber = retryAttemptIndex
    Logger.anchor.error("⚠️ Alarm audio playback failed; scheduling retry #\(attemptNumber, privacy: .public).")

    cancelPlaybackRetry()
    let retryID = UUID()
    let clock = self.clock
    let task = Task { @MainActor [weak self] in
      do {
        try await clock.sleep(for: delay)
      } catch {
        return
      }
      guard let self,
            !Task.isCancelled,
            self.activeSessionID == sessionID else {
        return
      }
      if self.retryState?.id == retryID {
        self.retryState = nil
      }
      self.enqueuePlaybackStart(sessionID: sessionID)
    }
    retryState = (id: retryID, cancellable: TaskCancellable(task))
  }

  private func cancelPlaybackRetry() {
    retryState?.cancellable.cancel()
    retryState = nil
  }

  /// Chains audio operations strictly in FIFO order off the main thread.
  private func enqueueAudioOperation(_ operation: @escaping @Sendable (any AlarmAudioPlaying) async -> Void) {
    let previousTask = audioCommandState?.task
    let engine = audioEngine
    let operationID = UUID()

    let task = Task.detached(priority: .userInitiated) { [weak self] in
      await previousTask?.value
      await operation(engine)
      await self?.clearAudioCommandIfMatching(id: operationID)
    }

    audioCommandState = (id: operationID, task: task)
  }

  private func clearAudioCommandIfMatching(id: UUID) {
    if audioCommandState?.id == id {
      audioCommandState = nil
    }
  }

  private func handleInterruptionBegan() {
    guard let sessionID = activeSessionID else { return }
    isAudioInterrupted = true
    cancelPlaybackRetry()
    enqueueAudioOperation { engine in
      await engine.handleInterruptionBegan(sessionID: sessionID)
    }
  }

  private func resumeAudioIfActive() {
    guard let sessionID = activeSessionID else { return }
    isAudioInterrupted = false
    cancelPlaybackRetry()
    retryAttemptIndex = 0
    enqueuePlaybackStart(sessionID: sessionID)
  }

  private func startVibrationLoop() {
    vibrationState?.cancellable.cancel()
    let taskID = UUID()
    let clock = self.clock
    let interval = vibrationInterval
    let timeout = vibrationTimeout
    let vibrateAction = vibrate

    let task = Task { @MainActor [weak self] in
      await AlarmAudioService.runVibrationLoop(
        using: clock,
        interval: interval,
        timeout: timeout,
        vibrateAction: vibrateAction
      )

      if self?.vibrationState?.id == taskID {
        self?.vibrationState = nil
      }
    }

    vibrationState = (id: taskID, cancellable: TaskCancellable(task))
  }

  // Generic helper opens the `any Clock<Duration>` existential so `clock.now >= deadline` can compare concrete `Instant`s.
  private static func runVibrationLoop<C: Clock>(
    using clock: C,
    interval: Duration,
    timeout: Duration,
    vibrateAction: @MainActor @Sendable () -> Void
  ) async where C.Duration == Duration {
    let deadline = clock.now.advanced(by: timeout)

    while !Task.isCancelled {
      if clock.now >= deadline {
        Logger.anchor.info("⏰ Vibration loop reached 5-minute safety timeout. Auto-stopping vibration.")
        break
      }

      vibrateAction()

      do {
        try await clock.sleep(for: interval)
      } catch {
        break
      }
    }
  }

  private func startSessionObservers() {
    guard sessionObservers.isEmpty else { return }

    sessionObservers = sessionController.observeEvents { [weak self] event in
      guard let self else { return }
      switch event {
      case .interruptionBegan:
        self.handleInterruptionBegan()
      case .interruptionEnded, .oldDeviceUnavailable:
        self.resumeAudioIfActive()
      }
    }
  }
}
