//
//  AlarmAudioEngine.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-07.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import AVFoundation
import OSLog

/// Testable playback engine seam separating `AVAudioPlayer` work from `AlarmAudioService` orchestration.
protocol AlarmAudioPlaying: Sendable {
  func prepareAudioSession() async
  func startPlayback(sessionID: UUID, onEscalationDidFinish: @escaping @MainActor @Sendable () -> Void) async -> Bool
  func handleInterruptionBegan(sessionID: UUID) async
  func transitionToContinuousSiren(sessionID: UUID) async -> Bool
  func stopPlayback() async
}

nonisolated private final class AudioPlayerDelegateProxy: NSObject, AVAudioPlayerDelegate, Sendable {
  private let onEscalationDidFinish: @MainActor @Sendable () -> Void

  nonisolated init(onEscalationDidFinish: @escaping @MainActor @Sendable () -> Void) {
    self.onEscalationDidFinish = onEscalationDidFinish
    super.init()
  }

  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    guard flag else { return }
    notifyEscalationFinished()
  }

  nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
    Logger.anchor.error("AVAudioPlayer decode error: \(error?.localizedDescription ?? "unknown", privacy: .public)")
    notifyEscalationFinished()
  }

  nonisolated private func notifyEscalationFinished() {
    let onEscalationDidFinish = self.onEscalationDidFinish
    Task { @MainActor in
      onEscalationDidFinish()
    }
  }
}

/// Executes blocking two-phase `AVAudioPlayer` escalation and looping siren playback off the main thread.
actor AlarmAudioEngine: AlarmAudioPlaying {
  private enum SoundResource {
    static let escalationName = "AnchorAlarm_CleanEscalation_27s"
    static let sirenName = "SirenAlarm"
    static let fileExtension = "wav"
  }

  private enum PlaybackPhase {
    case idle
    case escalation
    case continuousSiren
  }

  private let sessionController: any AlarmAudioSessionManaging
  private var phase: PlaybackPhase = .idle
  private var activeSessionID: UUID?
  private var delegateProxy: AudioPlayerDelegateProxy?
  private var escalationPlayer: AVAudioPlayer?
  private var sirenPlayer: AVAudioPlayer?
  private var scheduledSirenDeviceTime: TimeInterval?

  init(sessionController: any AlarmAudioSessionManaging = SystemAlarmAudioSessionController()) {
    self.sessionController = sessionController
  }

  /// Pre-configures the playback category while armed without activating the session so other audio apps keep playing uninterrupted.
  func prepareAudioSession() {
    _ = sessionController.configurePlaybackCategory()
  }

  func startPlayback(
    sessionID: UUID,
    onEscalationDidFinish: @escaping @MainActor @Sendable () -> Void
  ) -> Bool {
    if activeSessionID != sessionID {
      resetPlayers()
      activeSessionID = sessionID
      phase = .escalation
    }

    // Always instantiate a fresh delegate proxy so callers passing an updated closure are never silently ignored.
    let delegate = AudioPlayerDelegateProxy(onEscalationDidFinish: onEscalationDidFinish)
    delegateProxy = delegate

    promoteToContinuousIfScheduledElapsed()

    switch phase {
    case .continuousSiren:
      return startOrResumeContinuousSiren()
    case .escalation, .idle:
      phase = .escalation
      return startOrResumeEscalation(delegate: delegate)
    }
  }

  func handleInterruptionBegan(sessionID: UUID) {
    guard activeSessionID == sessionID else { return }
    promoteToContinuousIfScheduledElapsed()

    if phase == .escalation {
      // Cancel scheduled Phase 2 playback while keeping escalationPlayer paused at its offset.
      sirenPlayer?.stop()
      scheduledSirenDeviceTime = nil
    }
  }

  func transitionToContinuousSiren(sessionID: UUID) -> Bool {
    guard activeSessionID == sessionID, phase != .idle else { return false }

    phase = .continuousSiren
    escalationPlayer?.delegate = nil
    escalationPlayer = nil
    scheduledSirenDeviceTime = nil

    return startOrResumeContinuousSiren()
  }

  func stopPlayback() {
    resetPlayers()
    activeSessionID = nil
    phase = .idle
    sessionController.deactivatePlaybackSession()
  }

  private func startOrResumeEscalation(delegate: AudioPlayerDelegateProxy) -> Bool {
    if let existingEscalation = escalationPlayer, existingEscalation.isPlaying {
      existingEscalation.delegate = delegate
      return true
    }

    guard sessionController.activatePlaybackSession() else {
      return false
    }

    if let pausedEscalation = escalationPlayer {
      let remaining = pausedEscalation.duration - pausedEscalation.currentTime
      if remaining <= 0.05 {
        return transitionToContinuousSiren(sessionID: activeSessionID ?? UUID())
      }

      // Clear any stale future schedule before re-arming the seamless handoff.
      sirenPlayer?.stop()
      scheduledSirenDeviceTime = nil

      let preparedSiren = prepareSirenPlayer()
      pausedEscalation.delegate = delegate
      guard beginLoop(on: pausedEscalation, loops: 0) else {
        Logger.anchor.error("Failed to resume AnchorAlarm_CleanEscalation_27s.wav; falling back to SirenAlarm.wav.")
        phase = .continuousSiren
        escalationPlayer = nil
        return startOrResumeContinuousSiren()
      }

      if let preparedSiren {
        scheduleSiren(
          preparedSiren,
          after: pausedEscalation.duration - pausedEscalation.currentTime,
          referenceDeviceTime: pausedEscalation.deviceCurrentTime
        )
      }
      Logger.anchor.info("🔊 Resumed progressive escalation alarm (phase 1).")
      return true
    }

    guard let escalation = makePlayer(named: SoundResource.escalationName) else {
      Logger.anchor.error("⚠️ AnchorAlarm_CleanEscalation_27s.wav unavailable; starting SirenAlarm.wav directly.")
      phase = .continuousSiren
      return startOrResumeContinuousSiren()
    }

    let preparedSiren = prepareSirenPlayer()
    escalation.delegate = delegate
    guard beginLoop(on: escalation, loops: 0) else {
      Logger.anchor.error("AVAudioPlayer.play() returned false for AnchorAlarm_CleanEscalation_27s.wav; falling back to SirenAlarm.wav.")
      phase = .continuousSiren
      return startOrResumeContinuousSiren()
    }

    escalationPlayer = escalation
    if let preparedSiren {
      scheduleSiren(
        preparedSiren,
        after: escalation.duration,
        referenceDeviceTime: escalation.deviceCurrentTime
      )
    }
    Logger.anchor.info("🔊 AVAudioPlayer started AnchorAlarm_CleanEscalation_27s.wav (phase 1).")
    return true
  }

  private func startOrResumeContinuousSiren() -> Bool {
    if let existingSiren = sirenPlayer, existingSiren.isPlaying {
      return true
    }

    guard sessionController.activatePlaybackSession() else {
      return false
    }

    if let existingSiren = sirenPlayer, beginLoop(on: existingSiren, loops: -1) {
      Logger.anchor.info("🔊 AVAudioPlayer started/resumed SirenAlarm.wav loop (phase 2).")
      return true
    }

    guard let player = makePlayer(named: SoundResource.sirenName) else {
      sirenPlayer = nil
      return false
    }

    guard beginLoop(on: player, loops: -1) else {
      Logger.anchor.error("AVAudioPlayer.play() returned false for SirenAlarm.wav.")
      sirenPlayer = nil
      return false
    }

    sirenPlayer = player
    Logger.anchor.info("🔊 AVAudioPlayer started SirenAlarm.wav loop (phase 2).")
    return true
  }

  private func prepareSirenPlayer() -> AVAudioPlayer? {
    if let existingSiren = sirenPlayer {
      existingSiren.numberOfLoops = -1
      existingSiren.volume = 1.0
      existingSiren.currentTime = 0
      existingSiren.prepareToPlay()
      return existingSiren
    }

    guard let player = makePlayer(named: SoundResource.sirenName) else {
      return nil
    }
    player.numberOfLoops = -1
    player.volume = 1.0
    player.prepareToPlay()
    sirenPlayer = player
    return player
  }

  private func scheduleSiren(
    _ siren: AVAudioPlayer,
    after delay: TimeInterval,
    referenceDeviceTime: TimeInterval
  ) {
    siren.numberOfLoops = -1
    siren.volume = 1.0
    siren.currentTime = 0
    siren.prepareToPlay()
    let startTime = referenceDeviceTime + max(0.0, delay)
    scheduledSirenDeviceTime = siren.play(atTime: startTime) ? startTime : nil
  }

  private func promoteToContinuousIfScheduledElapsed() {
    guard phase == .escalation,
           let scheduledTime = scheduledSirenDeviceTime,
           let referencePlayer = sirenPlayer ?? escalationPlayer,
           referencePlayer.isPlaying,
           referencePlayer.deviceCurrentTime >= scheduledTime else {
      return
    }

    phase = .continuousSiren
    escalationPlayer?.delegate = nil
    escalationPlayer = nil
    scheduledSirenDeviceTime = nil
  }

  private func makePlayer(named name: String) -> AVAudioPlayer? {
    guard let url = resourceURL(named: name, withExtension: SoundResource.fileExtension) else {
      Logger.anchor.error("⚠️ \(name, privacy: .public).wav resource file not found in main bundle.")
      return nil
    }

    do {
      return try AVAudioPlayer(contentsOf: url)
    } catch {
      Logger.anchor.error("Failed to initialize AVAudioPlayer for \(name, privacy: .public).wav: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  private func resourceURL(named name: String, withExtension ext: String) -> URL? {
    Bundle.main.url(forResource: name, withExtension: ext)
      ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Sounds")
  }

  private func beginLoop(on player: AVAudioPlayer, loops: Int) -> Bool {
    player.numberOfLoops = loops
    player.volume = 1.0
    player.prepareToPlay()
    return player.play()
  }

  private func resetPlayers() {
    escalationPlayer?.delegate = nil
    escalationPlayer?.stop()
    escalationPlayer = nil
    delegateProxy = nil
    sirenPlayer?.stop()
    sirenPlayer = nil
    scheduledSirenDeviceTime = nil
  }
}
