//
//  AnchorViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-04.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation
import Observation
import OSLog

@Observable
@MainActor
final class AnchorViewModel {
  
  private let anchorService: AnchorService
  
  // MARK: - UI Properties
  
  private(set) var currentDistance: Measurement<UnitLength>?
  private(set) var sog: Measurement<UnitSpeed>?
  private(set) var gpsAccuracy: Measurement<UnitLength>?
  private(set) var status: AnchorStatus = .inactive
  private(set) var isAlertSilenced: Bool = false
  
  private(set) var configuredRadius: Measurement<UnitLength>
  private(set) var anchorDropError: String?
  
  var isSetupModeActive: Bool = false
  
  var isAnchorDropped: Bool {
    anchorCoordinate != nil
  }
  
  // MARK: - Internal State
  
  private(set) var anchorCoordinate: CLLocationCoordinate2D?
  
  private final class TaskCancellable: @unchecked Sendable {
    var task: Task<Void, Never>?
    deinit { task?.cancel() }
  }
  private let stateUpdateTask = TaskCancellable()
  
  // MARK: - Initialization
  
  init(anchorService: AnchorService) {
    self.anchorService = anchorService
    
    if let watch = anchorService.activeWatch {
      self.configuredRadius = watch.radius
      self.anchorCoordinate = watch.coordinate
    } else {
      self.configuredRadius = Measurement(value: 25.0, unit: .meters)
    }
    
    syncState()
    startObservingService()
  }
  
  private func startObservingService() {
    stateUpdateTask.task?.cancel()
    stateUpdateTask.task = Task { [weak self] in
      guard let anchorService = self?.anchorService else { return }
      for await _ in anchorService.stateUpdates {
        guard !Task.isCancelled else { break }
        self?.syncState()
      }
    }
  }
  
  private func syncState() {
    self.currentDistance = anchorService.currentDistance
    self.sog = anchorService.latestFix?.speedOverGround
    self.gpsAccuracy = anchorService.gpsAccuracy
    self.status = anchorService.status
    
    self.isAlertSilenced = anchorService.isMuted
  }
  
  // MARK: - User Intents
  
  func dropAnchor() {
    guard let fix = anchorService.latestFix else {
      self.anchorDropError = String(localized: "No GPS fix available.")
      Logger.anchor.warning("Cannot drop anchor: No GPS fix available.")
      return
    }
    
    let accuracy = fix.horizontalAccuracy.converted(to: .meters).value
    if accuracy > 20.0 {
      self.anchorDropError = String(localized: "GPS signal too weak (Accuracy: \(Int(accuracy))m > 20m).")
      Logger.anchor.warning("Refused to drop anchor: poor accuracy (\(accuracy)m).")
      return
    }
    
    self.anchorDropError = nil
    self.anchorCoordinate = fix.coordinate
    Logger.anchor.info("Anchor dropped at current location. Ready to arm.")
  }
  
  func cancelDrop() {
    Logger.anchor.info("Canceling anchor drop before arming.")
    self.anchorCoordinate = nil
    self.anchorDropError = nil
  }
  
  func incrementRadius() {
    let currentVal = configuredRadius.converted(to: .meters).value
    let newVal = min(currentVal + 5.0, 200.0)
    updateRadius(to: newVal)
  }
  
  func decrementRadius() {
    let currentVal = configuredRadius.converted(to: .meters).value
    let newVal = max(currentVal - 5.0, 10.0)
    updateRadius(to: newVal)
  }
  
  private func updateRadius(to valueInMeters: Double) {
    let newRadius = Measurement(value: valueInMeters, unit: UnitLength.meters)
    self.configuredRadius = newRadius
    
    // If the alarm is already armed, apply the new radius to the active watch
    if anchorService.status != .inactive {
      if let coord = anchorService.activeWatch?.coordinate {
        anchorService.arm(coordinate: coord, radius: newRadius)
      }
    }
  }
  
  func armAlarm() {
    guard let coord = anchorCoordinate else {
      Logger.anchor.warning("Cannot arm alarm: Anchor has not been dropped yet.")
      return
    }
    Logger.anchor.info("Arming anchor alarm from ViewModel.")
    anchorService.arm(coordinate: coord, radius: configuredRadius)
  }
  
  func disarmAlarm() {
    Logger.anchor.info("Disarming anchor alarm from ViewModel.")
    anchorService.disarm()
    self.anchorCoordinate = nil
  }
  
  func silenceAlert() {
    Logger.anchor.info("Silencing anchor alert from ViewModel.")
    anchorService.silenceAlarm()
  }
}
