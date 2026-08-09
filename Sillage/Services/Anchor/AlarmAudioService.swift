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
final class AlarmAudioService {
  
  private var audioPlayer: AVAudioPlayer?
  private var isPlaying = false
  private var vibrationTask: Task<Void, Never>?
  
  init() {}
  
  func prepareAudioSession() {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [.duckOthers])
      try session.setActive(true)
      Logger.anchor.info("🔊 AVAudioSession prepared in .playback mode.")
    } catch {
      Logger.anchor.error("Failed to prepare AVAudioSession: \(error.localizedDescription)")
    }
  }

  func startSiren() {
    guard !isPlaying else { return }
    isPlaying = true
    Logger.anchor.fault("🚨 Starting continuous loud alarm siren audio!")
    
    prepareAudioSession()
    setupAndStartAudioPlayer()
    startVibrationLoop()
  }
  
  func stopSiren() {
    guard isPlaying else { return }
    isPlaying = false
    Logger.anchor.info("🔇 Stopping alarm siren audio.")
    
    vibrationTask?.cancel()
    vibrationTask = nil
    
    audioPlayer?.stop()
    audioPlayer = nil
    
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      Logger.anchor.error("Failed to deactivate AVAudioSession: \(error.localizedDescription)")
    }
  }
  
  private func setupAndStartAudioPlayer() {
    guard let soundURL = Bundle.main.url(forResource: "SirenAlarm", withExtension: "wav") else {
      Logger.anchor.error("⚠️ SirenAlarm.wav resource file not found in main bundle.")
      return
    }
    
    do {
      let player = try AVAudioPlayer(contentsOf: soundURL)
      player.numberOfLoops = -1 // Infinite loop until stopped
      player.volume = 1.0
      player.prepareToPlay()
      player.play()
      self.audioPlayer = player
      Logger.anchor.info("🔊 AVAudioPlayer started SirenAlarm.wav loop successfully.")
    } catch {
      Logger.anchor.error("Failed to initialize AVAudioPlayer for SirenAlarm.wav: \(error.localizedDescription)")
    }
  }
  
  private func startVibrationLoop() {
    vibrationTask?.cancel()
    vibrationTask = Task { @MainActor [weak self] in
      let startTime = Date()
      let maxDuration: TimeInterval = 300.0 // 5 minutes maximum
      
      while !Task.isCancelled {
        if Date().timeIntervalSince(startTime) >= maxDuration {
          Logger.anchor.info("⏰ Vibration loop reached 5-minute safety timeout. Auto-stopping vibration.")
          break
        }
        
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        
        do {
          try await Task.sleep(nanoseconds: 1_000_000_000)
        } catch {
          // Task was cancelled during sleep
          break
        }
      }
      self?.vibrationTask = nil
    }
  }
}
