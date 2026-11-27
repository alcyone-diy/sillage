//
//  AlarmAudioSessionController.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import AVFoundation
import OSLog

/// Domain-safe audio session lifecycle events emitted from iOS `AVAudioSession` notifications.
enum AlarmAudioSessionEvent: Sendable, Equatable {
  case interruptionBegan
  case interruptionEnded
  case oldDeviceUnavailable
}

/// Adapter seam isolating `AVAudioSession` configuration and system notification parsing.
nonisolated protocol AlarmAudioSessionManaging: Sendable {
  @discardableResult func configurePlaybackCategory() -> Bool
  @discardableResult func activatePlaybackSession() -> Bool
  func deactivatePlaybackSession()
  @MainActor func observeEvents(
    handler: @escaping @MainActor (AlarmAudioSessionEvent) -> Void
  ) -> [TaskCancellable]
}

private struct NotificationObserverBox: @unchecked Sendable {
  let tokens: [any NSObjectProtocol]
}

/// Default `AVAudioSession` adapter used in production by `AlarmAudioEngine` and `AlarmAudioService`.
nonisolated struct SystemAlarmAudioSessionController: AlarmAudioSessionManaging {

  @discardableResult
  func configurePlaybackCategory() -> Bool {
    do {
      let session = AVAudioSession.sharedInstance()
      // `.duckOthers` takes effect only once `setActive(true)` is called when the alarm sounds, so preparing
      // this category while armed leaves background music untouched while still ducking audio during an active siren.
      try session.setCategory(.playback, mode: .default, options: [.duckOthers])
      Logger.anchor.info("🔊 AVAudioSession category configured (.playback).")
      return true
    } catch {
      Logger.anchor.error("Failed to configure AVAudioSession category: \(error.localizedDescription, privacy: .public)")
      return false
    }
  }

  @discardableResult
  func activatePlaybackSession() -> Bool {
    guard configurePlaybackCategory() else {
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

  func deactivatePlaybackSession() {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      Logger.anchor.error("Failed to deactivate AVAudioSession: \(error.localizedDescription, privacy: .public)")
    }
  }

  @MainActor
  func observeEvents(
    handler: @escaping @MainActor (AlarmAudioSessionEvent) -> Void
  ) -> [TaskCancellable] {
    // Register NotificationCenter observers synchronously via AsyncStream's builder closure
    // so notifications posted immediately after `startSiren()` are buffered and never dropped.
    let stream = Self.makeEventStream()
    let consumerTask = Task { @MainActor in
      for await event in stream {
        guard !Task.isCancelled else { break }
        handler(event)
      }
    }
    return [TaskCancellable(consumerTask)]
  }

  private static func makeEventStream() -> AsyncStream<AlarmAudioSessionEvent> {
    AsyncStream { continuation in
      let center = NotificationCenter.default

      let interruptionToken = center.addObserver(
        forName: AVAudioSession.interruptionNotification,
        object: nil,
        queue: nil
      ) { notification in
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
          return
        }

        switch type {
        case .began:
          Logger.anchor.info("🔇 Audio session interruption began during active alarm.")
          continuation.yield(.interruptionBegan)
        case .ended:
          Logger.anchor.info("🔊 Audio session interruption ended; resuming alarm playback.")
          continuation.yield(.interruptionEnded)
        @unknown default:
          break
        }
      }

      let routeChangeToken = center.addObserver(
        forName: AVAudioSession.routeChangeNotification,
        object: nil,
        queue: nil
      ) { notification in
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
              reason == .oldDeviceUnavailable else {
          return
        }
        Logger.anchor.info("🔊 Audio output device disconnected; resuming alarm playback.")
        continuation.yield(.oldDeviceUnavailable)
      }

      let box = NotificationObserverBox(tokens: [interruptionToken, routeChangeToken])
      continuation.onTermination = { _ in
        for token in box.tokens {
          NotificationCenter.default.removeObserver(token)
        }
      }
    }
  }
}
