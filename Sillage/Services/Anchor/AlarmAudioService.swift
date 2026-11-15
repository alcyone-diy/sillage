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

/// Executes blocking AVAudioSession and AVAudioPlayer work off the main thread.
private actor AlarmAudioEngine {
  private var audioPlayer: AVAudioPlayer?

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

  func startPlayback() -> Bool {
    if let existingPlayer = audioPlayer, existingPlayer.isPlaying {
      return true
    }

    guard configureAndActivateSession() else {
      return false
    }

    if let existingPlayer = audioPlayer {
      if beginLoop(on: existingPlayer) {
        Logger.anchor.info("🔊 AVAudioPlayer resumed SirenAlarm.wav loop successfully.")
        return true
      }
      audioPlayer = nil
    }

    guard let soundURL = Bundle.main.url(forResource: "SirenAlarm", withExtension: "wav") else {
      Logger.anchor.error("⚠️ SirenAlarm.wav resource file not found in main bundle.")
      return false
    }

    do {
      let player = try AVAudioPlayer(contentsOf: soundURL)
      guard beginLoop(on: player) else {
        Logger.anchor.error("AVAudioPlayer.play() returned false for SirenAlarm.wav.")
        return false
      }

      audioPlayer = player
      Logger.anchor.info("🔊 AVAudioPlayer started SirenAlarm.wav loop successfully.")
      return true
    } catch {
      Logger.anchor.error("Failed to initialize AVAudioPlayer for SirenAlarm.wav: \(error.localizedDescription, privacy: .public)")
      return false
    }
  }

  private func beginLoop(on player: AVAudioPlayer) -> Bool {
    player.numberOfLoops = -1 // Infinite loop until stopped
    player.volume = 1.0
    player.prepareToPlay()
    return player.play()
  }

  func stopPlayback() {
    audioPlayer?.stop()
    audioPlayer = nil

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      Logger.anchor.error("Failed to deactivate AVAudioSession: \(error.localizedDescription, privacy: .public)")
    }
  }
}

@MainActor
final class AlarmAudioService: AlarmAudioServiceProtocol {
  private let audioEngine = AlarmAudioEngine()
  private var audioCommandState: (id: UUID, task: Task<Void, Never>)?
  private var isSirenActive = false
  private var vibrationState: (id: UUID, cancellable: TaskCancellable)?
  private var interruptionObserver: TaskCancellable?
  private var routeChangeObserver: TaskCancellable?

  init() {}

  func prepareAudioSession() {
    enqueueAudioOperation { engine in
      await engine.prepareAudioSession()
    }
  }

  func startSiren() {
    if !isSirenActive {
      isSirenActive = true
      Logger.anchor.fault("🚨 Starting continuous loud alarm siren audio!")
      startVibrationLoop()
      startAudioObservers()
    }

    enqueueAudioOperation { engine in
      _ = await engine.startPlayback()
    }
  }

  func stopSiren() {
    guard isSirenActive else { return }
    isSirenActive = false
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

  private func resumeAudioIfActive() {
    guard isSirenActive else { return }
    enqueueAudioOperation { engine in
      _ = await engine.startPlayback()
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
            let type = AVAudioSession.InterruptionType(rawValue: typeValue),
            type == .ended else {
        return
      }
      Logger.anchor.info("🔊 Audio session interruption ended; resuming siren playback.")
      service.resumeAudioIfActive()
    }

    routeChangeObserver = observeNotification(AVAudioSession.routeChangeNotification) { service, userInfo in
      guard let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
            reason == .oldDeviceUnavailable else {
        return
      }
      Logger.anchor.info("🔊 Audio output device disconnected; resuming siren playback.")
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
