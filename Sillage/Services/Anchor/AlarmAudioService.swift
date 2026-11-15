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
import AVFoundation
import AudioToolbox
import OSLog

@MainActor
public protocol AlarmAudioServiceProtocol: AnyObject, Sendable {
  func prepareAudioSession()
  func startSiren()
  func stopSiren()
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

/// Executes blocking AVAudioSession and two-phase AVAudioPlayer work off the main thread.
private actor AlarmAudioEngine {
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

  private var phase: PlaybackPhase = .idle
  private var activeSessionID: UUID?
  private var escalationPlayer: AVAudioPlayer?
  private var sirenPlayer: AVAudioPlayer?
  private var scheduledSirenDeviceTime: TimeInterval?

  @discardableResult
  private func configureSessionCategory() -> Bool {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [.duckOthers])
      Logger.anchor.info("🔊 AVAudioSession category configured (.playback).")
      return true
    } catch {
      Logger.anchor.error("Failed to configure AVAudioSession category: \(error.localizedDescription, privacy: .public)")
      return false
    }
  }

  @discardableResult
  private func configureAndActivateSession() -> Bool {
    guard configureSessionCategory() else {
      return false
    }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setActive(true)
      Logger.anchor.info("🔊 AVAudioSession activated in .playback mode.")
      return true
    } catch {
      Logger.anchor.error("Failed to activate AVAudioSession: \(error.localizedDescription, privacy: .public)")
      return false
    }
  }

  func prepareAudioSession() {
    _ = configureSessionCategory()
  }

  func startPlayback(sessionID: UUID, delegate: AudioPlayerDelegateProxy) -> Bool {
    if activeSessionID != sessionID {
      resetPlayers()
      activeSessionID = sessionID
      phase = .escalation
    }

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

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      Logger.anchor.error("Failed to deactivate AVAudioSession: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func startOrResumeEscalation(delegate: AudioPlayerDelegateProxy) -> Bool {
    if let existingEscalation = escalationPlayer, existingEscalation.isPlaying {
      return true
    }

    guard configureAndActivateSession() else {
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

    guard configureAndActivateSession() else {
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
    sirenPlayer?.stop()
    sirenPlayer = nil
    scheduledSirenDeviceTime = nil
  }
}

@MainActor
final class AlarmAudioService: AlarmAudioServiceProtocol {
  private let audioEngine = AlarmAudioEngine()
  private lazy var delegateProxy = AudioPlayerDelegateProxy { [weak self] in
    self?.handleEscalationDidFinish()
  }
  private var audioCommandState: (id: UUID, task: Task<Void, Never>)?
  private var activeSessionID: UUID?
  private var vibrationState: (id: UUID, cancellable: TaskCancellable)?
  private var interruptionObserver: TaskCancellable?
  private var routeChangeObserver: TaskCancellable?

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
      startAudioObservers()
    }

    let delegate = delegateProxy
    enqueueAudioOperation { engine in
      _ = await engine.startPlayback(sessionID: sessionID, delegate: delegate)
    }
  }

  func stopSiren() {
    guard activeSessionID != nil else { return }
    activeSessionID = nil
    Logger.anchor.info("🔇 Stopping alarm siren audio.")

    vibrationState?.cancellable.cancel()
    vibrationState = nil

    interruptionObserver?.cancel()
    interruptionObserver = nil
    routeChangeObserver?.cancel()
    routeChangeObserver = nil

    enqueueAudioOperation { engine in
      await engine.stopPlayback()
    }
  }

  fileprivate func handleEscalationDidFinish() {
    guard let sessionID = activeSessionID else { return }
    enqueueAudioOperation { engine in
      _ = await engine.transitionToContinuousSiren(sessionID: sessionID)
    }
  }

  /// Chains audio operations strictly in FIFO order off the main thread.
  private func enqueueAudioOperation(_ operation: @escaping @Sendable (AlarmAudioEngine) async -> Void) {
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
    enqueueAudioOperation { engine in
      await engine.handleInterruptionBegan(sessionID: sessionID)
    }
  }

  private func resumeAudioIfActive() {
    guard let sessionID = activeSessionID else { return }
    let delegate = delegateProxy
    enqueueAudioOperation { engine in
      _ = await engine.startPlayback(sessionID: sessionID, delegate: delegate)
    }
  }

  private func startVibrationLoop() {
    vibrationState?.cancellable.cancel()
    let taskID = UUID()

    let task = Task { @MainActor [weak self] in
      let deadline = ContinuousClock.now + .seconds(300) // 5 minutes maximum

      while !Task.isCancelled {
        if ContinuousClock.now >= deadline {
          Logger.anchor.info("⏰ Vibration loop reached 5-minute safety timeout. Auto-stopping vibration.")
          break
        }

        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

        do {
          try await Task.sleep(for: .seconds(1))
        } catch {
          // Task was cancelled during sleep
          break
        }
      }

      if self?.vibrationState?.id == taskID {
        self?.vibrationState = nil
      }
    }

    vibrationState = (id: taskID, cancellable: TaskCancellable(task))
  }

  private func startAudioObservers() {
    guard interruptionObserver == nil, routeChangeObserver == nil else { return }

    interruptionObserver = observeNotification(AVAudioSession.interruptionNotification) { service, userInfo in
      guard let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
        return
      }

      switch type {
      case .began:
        Logger.anchor.info("🔇 Audio session interruption began during active alarm.")
        service.handleInterruptionBegan()
      case .ended:
        Logger.anchor.info("🔊 Audio session interruption ended; resuming alarm playback.")
        service.resumeAudioIfActive()
      @unknown default:
        break
      }
    }

    routeChangeObserver = observeNotification(AVAudioSession.routeChangeNotification) { service, userInfo in
      guard let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
            reason == .oldDeviceUnavailable else {
        return
      }
      Logger.anchor.info("🔊 Audio output device disconnected; resuming alarm playback.")
      service.resumeAudioIfActive()
    }
  }

  private func observeNotification(
    _ name: Notification.Name,
    handler: @escaping @MainActor (AlarmAudioService, [AnyHashable: Any]) -> Void
  ) -> TaskCancellable {
    let task = Task { @MainActor [weak self] in
      for await notification in NotificationCenter.default.notifications(named: name) {
        guard !Task.isCancelled, let self else { break }
        guard let userInfo = notification.userInfo else { continue }
        handler(self, userInfo)
      }
    }
    return TaskCancellable(task)
  }
}
