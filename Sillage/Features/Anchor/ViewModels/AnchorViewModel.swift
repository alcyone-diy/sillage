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
  case droppedPendingPosition
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
  
  /// Indicates whether the UI is currently in manual anchor position adjustment mode.
  var isAdjustingAnchor: Bool = false

  /// Technical Design Choice: Ephemeral Preparation Mode
  /// Indicates whether the UI is in full-screen drop anchor confirmation mode.
  /// Strictly transient in-memory state that defaults to `false` and is never persisted across app launches.
  var isPreparingDropAnchor: Bool = false {
    didSet {
      updateLocationUpdatesState()
    }
  }

  /// Technical Design Choice: Lifecycle-bound location update token control
  /// When setup mode or drop anchor preparation is activated by the UI, `startSetupLocationUpdates()` requests location updates.
  /// When both are inactive, `stopSetupLocationUpdates()` releases the token, preventing high-frequency GPS battery drain.
  var isSetupModeActive: Bool = false {
    didSet {
      updateLocationUpdatesState()
    }
  }

  /// Technical Design Choice: Ephemeral Setup Visual State
  /// Indicates whether the UI is in any setup/preparation mode (manual position adjustment,
  /// setup panel active, or full-screen drop confirmation) where setup visuals (anchor point & alarm limit circle)
  /// should be rendered on the chart.
  public var isDisplayingSetupVisuals: Bool {
    isSetupModeActive || isPreparingDropAnchor || isAdjustingAnchor
  }

  private func updateLocationUpdatesState() {
    if isDisplayingSetupVisuals {
      anchorService.startSetupLocationUpdates()
    } else {
      anchorService.stopSetupLocationUpdates()
    }
  }
  
  var initialAccuracy: Measurement<UnitLength>? {
    anchorService.activeWatch?.initialAccuracy
  }
  
  var isGPSAccuracyDegraded: Bool {
    guard let accuracy = gpsAccuracy?.converted(to: .meters).value else { return false }
    return accuracy > 15.0
  }

  var triggerReasonDescription: String? {
    guard let reason = triggerReason else { return nil }
    switch reason {
    case .distanceExceeded(let distance, let radius):
      let distStr = distance.marineAnchorDistanceFormatted()
      let radStr = radius.marineAnchorDistanceFormatted()
      return String(localized: "Safety radius exceeded (\(distStr) / \(radStr))")
    case .poorAccuracy(let accuracy, let requiredAccuracy):
      let accStr = accuracy.marineAnchorDistanceFormatted()
      let reqStr = requiredAccuracy.marineAnchorDistanceFormatted()
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
    case .droppedPendingPosition:
      return .droppedPendingPosition
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
  
  /// Performs an anchor drop at any time using the best available fix (enforcing 60s TTL).
  /// If GPS fix is unavailable (nil), transitions to `.droppedPendingPosition` state until the first GPS fix arrives.
  func dropAnchor() {
    let fix = anchorService.bestAvailableFix
    self.anchorDropError = nil
    
    if let fix = fix {
      self.anchorCoordinate = fix.coordinate
      Logger.anchor.info("Anchor drop requested with available fix at (\(fix.coordinate.latitude, privacy: .public), \(fix.coordinate.longitude, privacy: .public)).")
      anchorService.drop(coordinate: fix.coordinate, radius: configuredRadius)
    } else {
      self.anchorCoordinate = nil
      Logger.anchor.warning("Anchor drop requested without immediate GPS fix. Pending position lock.")
      anchorService.drop(coordinate: nil, radius: configuredRadius)
    }
    syncState()
  }

  func cancelDrop() {
    Logger.anchor.info("Canceling anchor drop before arming.")
    self.anchorCoordinate = nil
    self.anchorDropError = nil
    anchorService.clear()
    syncState()
  }

  /// Technical Design Choice: Locale-Aware Round Stepping & Domain Bounds
  /// Enforces clean, natural steps (5m in metric, 10ft in US/UK imperial) with round min/max bounds
  /// (10m - 500m in metric, 30ft - 1600ft in feet) while maintaining single-source Measurement<UnitLength> domain state.
  private static let minRadiusMetric = Measurement<UnitLength>(value: 10.0, unit: .meters)
  private static let maxRadiusMetric = Measurement<UnitLength>(value: 500.0, unit: .meters)

  private static let minRadiusImperial = Measurement<UnitLength>(value: 30.0, unit: .feet)
  private static let maxRadiusImperial = Measurement<UnitLength>(value: 1600.0, unit: .feet)

  func incrementRadius(locale: Locale = .autoupdatingCurrent) {
    let isMetric = locale.measurementSystem == .metric
    let stepUnit: UnitLength = isMetric ? .meters : .feet
    let stepValue: Double = isMetric ? 5.0 : 10.0
    let minBound = isMetric ? Self.minRadiusMetric : Self.minRadiusImperial
    let maxBound = isMetric ? Self.maxRadiusMetric : Self.maxRadiusImperial

    let currentVal = configuredRadius.converted(to: stepUnit).value
    let roundedCurrent = (currentVal / stepValue).rounded() * stepValue
    let newVal = roundedCurrent + stepValue
    let candidateRadius = Measurement(value: newVal, unit: stepUnit)

    let clampedRadius = min(max(candidateRadius, minBound), maxBound)
    updateRadius(to: clampedRadius)
  }

  func decrementRadius(locale: Locale = .autoupdatingCurrent) {
    let isMetric = locale.measurementSystem == .metric
    let stepUnit: UnitLength = isMetric ? .meters : .feet
    let stepValue: Double = isMetric ? 5.0 : 10.0
    let minBound = isMetric ? Self.minRadiusMetric : Self.minRadiusImperial
    let maxBound = isMetric ? Self.maxRadiusMetric : Self.maxRadiusImperial

    let currentVal = configuredRadius.converted(to: stepUnit).value
    let roundedCurrent = (currentVal / stepValue).rounded() * stepValue
    let newVal = roundedCurrent - stepValue
    let candidateRadius = Measurement(value: newVal, unit: stepUnit)

    let clampedRadius = min(max(candidateRadius, minBound), maxBound)
    updateRadius(to: clampedRadius)
  }
  
  private func updateRadius(to newRadius: Measurement<UnitLength>) {
    self.configuredRadius = newRadius
    anchorService.defaultRadius = newRadius
    
    if anchorService.status != .inactive {
      anchorService.update(radius: newRadius)
    }
    syncState()
  }
  
  func armAlarm() {
    guard let coord = anchorCoordinate else {
      Logger.anchor.warning("Cannot arm alarm: Anchor position has not locked yet.")
      return
    }
    Logger.anchor.info("Arming anchor alarm from ViewModel.")
    anchorService.arm(coordinate: coord, radius: configuredRadius)
    syncState()
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
    syncState()
  }
  
  func silenceAlert() {
    Logger.anchor.info("Silencing anchor alert from ViewModel.")
    anchorService.silenceAlarm()
    syncState()
  }
  
  func unSilenceAlert() {
    Logger.anchor.info("Unsilencing anchor alert from ViewModel.")
    anchorService.unSilenceAlarm()
    syncState()
  }

  /// Technical Design Choice: Domain Isolation for Position Adjustment
  /// `AnchorViewModel` manages the UI mode flag and forwards confirmed coordinates to `AnchorService`.
  /// It does not perform map telemetry math (distance/bearing to map center), keeping it strictly decoupled from ChartViewModel.
  func startAdjustingAnchor() {
    Logger.anchor.info("Starting manual anchor position adjustment mode.")
    self.isAdjustingAnchor = true
  }

  func confirmAdjustAnchor(to newCoordinate: CLLocationCoordinate2D) {
    Logger.anchor.info("Confirming manual anchor position adjustment to (\(newCoordinate.latitude, privacy: .public), \(newCoordinate.longitude, privacy: .public)).")
    self.anchorCoordinate = newCoordinate
    anchorService.adjustAnchorPosition(to: newCoordinate)
    self.isAdjustingAnchor = false
    syncState()
  }

  func cancelAdjustAnchor() {
    Logger.anchor.info("Canceling manual anchor position adjustment.")
    self.isAdjustingAnchor = false
  }

  /// Technical Design Choice: Full-Screen Drop Anchor Preparation Flow
  /// Activates the full-screen preparation mode, displaying the anchor marker over the vessel
  /// and presenting MarineActionConfirmationCard while command panel is dismissed.
  func startPreparingDropAnchor() {
    Logger.anchor.info("Starting full-screen drop anchor preparation mode.")
    self.isPreparingDropAnchor = true
  }

  func confirmDropAnchor() {
    Logger.anchor.info("Confirming drop anchor from full-screen confirmation overlay.")
    dropAnchor()
    self.isPreparingDropAnchor = false
  }

  func cancelPreparingDropAnchor() {
    Logger.anchor.info("Canceling full-screen drop anchor preparation mode.")
    self.isPreparingDropAnchor = false
  }


  deinit {
    stateUpdateTask?.cancel()
  }
}
