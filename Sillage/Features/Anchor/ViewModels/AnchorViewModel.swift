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

public enum AnchorState: Equatable {
  case setup
  case dropped
  case armed(isDragging: Bool)
}

@Observable
@MainActor
final class AnchorViewModel {
  
  private let anchorService: AnchorService
  
  // MARK: - UI Properties
  
  private(set) var currentDistance: Measurement<UnitLength>?
  private(set) var sog: Measurement<UnitSpeed>?
  private(set) var gpsAccuracy: Measurement<UnitLength>?
  private(set) var status: AnchorStatus = .inactive
  private(set) var triggerReason: AnchorTriggerReason?
  private(set) var isAlertSilenced: Bool = false
  
  private(set) var configuredRadius: Measurement<UnitLength>
  private(set) var anchorDropError: String?
  
  var isSetupModeActive: Bool = false
  
  var isGPSAccuracyDegraded: Bool {
    guard let accuracy = gpsAccuracy?.converted(to: .meters).value else { return false }
    return accuracy > 15.0
  }

  var triggerReasonDescription: String? {
    guard let reason = triggerReason else { return nil }
    let formatStyle = Measurement<UnitLength>.FormatStyle.measurement(
      width: .abbreviated,
      usage: .asProvided,
      numberFormatStyle: .number.precision(.fractionLength(0))
    )
    switch reason {
    case .distanceExceeded(let distance, let radius):
      let distStr = distance.formatted(formatStyle)
      let radStr = radius.formatted(formatStyle)
      return String(localized: "Safety radius exceeded (\(distStr) / \(radStr))")
    case .poorAccuracy(let accuracy, let requiredAccuracy):
      let accStr = accuracy.formatted(formatStyle)
      let reqStr = requiredAccuracy.formatted(formatStyle)
      return String(localized: "Insufficient GPS accuracy (\(accStr), required <= \(reqStr))")
    case .gpsSignalLost:
      return String(localized: "GPS signal lost")
    case .debugSimulation:
      return String(localized: "Manual debug simulation")
    }
  }
  
  var state: AnchorState {
    switch status {
    case .armed:
      return .armed(isDragging: false)
    case .dragging:
      return .armed(isDragging: true)
    case .dropped:
      return .dropped
    case .inactive:
      return .setup
    }
  }
  
  // MARK: - Internal State
  
  var permissionGateType: PermissionGateType? = nil
  private var pendingAction: (@MainActor () -> Void)? = nil
  
  private(set) var anchorCoordinate: CLLocationCoordinate2D?
  @ObservationIgnored
  nonisolated(unsafe) private var stateUpdateTask: Task<Void, Never>?
  // MARK: - Initialization
  
  init(anchorService: AnchorService) {
    self.anchorService = anchorService
    
    if let watch = anchorService.activeWatch {
      self.configuredRadius = watch.radius
      self.anchorCoordinate = watch.coordinate
    } else {
      self.configuredRadius = anchorService.defaultRadius
    }
    
    syncState()
    startObservingService()
  }
  
  private func startObservingService() {
    stateUpdateTask?.cancel()
    stateUpdateTask = Task { [weak self] in
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
    self.triggerReason = anchorService.triggerReason
    
    if let watch = anchorService.activeWatch {
      self.anchorCoordinate = watch.coordinate
    } else {
      self.anchorCoordinate = nil
    }
    
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
      self.anchorDropError = String(localized: "Poor GPS accuracy: \(Int(accuracy))m")
      Logger.anchor.warning("Poor GPS accuracy (\(accuracy)m) when dropping anchor.")
    } else {
      self.anchorDropError = nil
    }
    
    self.anchorCoordinate = fix.coordinate
    anchorService.drop(coordinate: fix.coordinate, radius: configuredRadius)
    Logger.anchor.info("Anchor dropped at current location. Ready to arm.")
  }
  
  func cancelDrop() {
    Logger.anchor.info("Canceling anchor drop before arming.")
    self.anchorCoordinate = nil
    self.anchorDropError = nil
    anchorService.clear()
  }
  
  func incrementRadius() {
    let currentVal = configuredRadius.converted(to: .meters).value
    let newVal = min(currentVal + 5.0, 500.0)
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
    anchorService.defaultRadius = newRadius
    
    if anchorService.status != .inactive {
      anchorService.update(radius: newRadius)
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
  
  func requestArmAlarm(in service: PermissionService) {
    let status = service.notificationStatus
    if status == .authorized {
      self.armAlarm()
    } else {
      self.pendingAction = { [weak self] in self?.armAlarm() }
      self.permissionGateType = .notification(trigger: .anchorAlarm)
    }
  }
  
  func finalizePendingAction() {
    pendingAction?()
    pendingAction = nil
  }
  
  func disarmAlarm() {
    Logger.anchor.info("Disarming anchor alarm from ViewModel.")
    anchorService.disarm()
  }
  
  func silenceAlert() {
    Logger.anchor.info("Silencing anchor alert from ViewModel.")
    anchorService.silenceAlarm()
  }
  
  func unSilenceAlert() {
    Logger.anchor.info("Unsilencing anchor alert from ViewModel.")
    anchorService.unSilenceAlarm()
  }

  
  deinit {
    stateUpdateTask?.cancel()
  }
}
