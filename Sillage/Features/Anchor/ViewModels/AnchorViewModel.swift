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

public enum AnchorPresentationState: Sendable, Equatable {
  case setup
  case droppedPendingPosition
  case dropped
  case armed(isDragging: Bool)
}

@Observable
@MainActor
final class AnchorViewModel {
  
  private let anchorService: AnchorService
  
  // MARK: - UI Configuration & Transient State
  
  var configuredRadius: Measurement<UnitLength>
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
  
  // MARK: - Reactive UI State Properties
  
  private(set) var status: AnchorStatus = .inactive
  private(set) var triggerReason: AnchorTriggerReason?
  private(set) var currentDistance: Measurement<UnitLength>?
  private(set) var sog: Measurement<UnitSpeed>?
  private(set) var gpsAccuracy: Measurement<UnitLength>?
  private(set) var initialAccuracy: Measurement<UnitLength>?
  private(set) var anchorCoordinate: CLLocationCoordinate2D?
  private(set) var isAlertSilenced: Bool = false
  
  var isGPSAccuracyDegraded: Bool {
    guard let accuracy = gpsAccuracy else { return false }
    return accuracy > Measurement(value: 15.0, unit: .meters)
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
  
  var state: AnchorPresentationState {
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
  
  // MARK: - Internal UI Permission State
  
  var permissionGateType: PermissionGateType? = nil
  private var pendingGateType: PermissionGateType? = nil
  private var pendingAction: (@MainActor () -> Void)? = nil
  
  @ObservationIgnored
  private var stateObservationTask: Task<Void, Never>?
  
  // MARK: - Initialization
  
  init(anchorService: AnchorService) {
    self.anchorService = anchorService
    let initial = anchorService.currentState
    self.configuredRadius = initial.activeWatch?.radius ?? anchorService.defaultRadius
    applyState(initial)
    
    startObservingService()
  }
  
  private func startObservingService() {
    stateObservationTask?.cancel()
    stateObservationTask = Task { @MainActor [weak self] in
      guard let anchorService = self?.anchorService else { return }
      for await state in anchorService.stateUpdates {
        guard !Task.isCancelled else { break }
        self?.applyState(state)
      }
    }
  }
  
  private func applyState(_ state: Sillage.AnchorState) {
    let incomingCoordinate = state.activeWatch?.coordinate
    let coordinateChanged =
      self.anchorCoordinate?.latitude != incomingCoordinate?.latitude ||
      self.anchorCoordinate?.longitude != incomingCoordinate?.longitude

    // Discard any queued arm action if the watch leaves `.dropped` or its coordinate changes.
    if state.status != .dropped || coordinateChanged {
      cancelPendingAction()
    }

    self.status = state.status
    self.triggerReason = state.triggerReason
    self.currentDistance = state.currentDistance
    self.sog = state.latestFix?.speedOverGround
    self.gpsAccuracy = state.gpsAccuracy
    self.initialAccuracy = state.activeWatch?.initialAccuracy
    self.anchorCoordinate = incomingCoordinate
    self.isAlertSilenced = state.isMuted

    let resolvedRadius = state.activeWatch?.radius ?? anchorService.defaultRadius
    if self.configuredRadius != resolvedRadius {
      self.configuredRadius = resolvedRadius
    }
  }
  
  deinit {
    stateObservationTask?.cancel()
  }
  
  // MARK: - User Intents
  
  /// Performs an anchor drop at any time using the best available fix (enforcing 60s TTL).
  /// If GPS fix is unavailable (nil), transitions to `.droppedPendingPosition` state until the first GPS fix arrives.
  func dropAnchor() {
    let fix = anchorService.bestAvailableFix
    self.anchorDropError = nil
    cancelPendingAction()
    
    if let fix = fix {
      Logger.anchor.info("Anchor drop requested with available fix at (\(fix.coordinate.latitude, privacy: .public), \(fix.coordinate.longitude, privacy: .public)).")
      anchorService.drop(
        coordinate: fix.coordinate,
        radius: configuredRadius,
        initialAccuracy: fix.horizontalAccuracy
      )
    } else {
      Logger.anchor.warning("Anchor drop requested without immediate GPS fix. Pending position lock.")
      anchorService.drop(coordinate: nil, radius: configuredRadius)
    }
  }

  func cancelDrop() {
    Logger.anchor.info("Canceling anchor drop before arming.")
    self.anchorDropError = nil
    cancelPendingAction()
    anchorService.clear()
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
  }
  
  func armAlarm() {
    guard let coord = anchorCoordinate ?? anchorService.activeWatch?.coordinate else {
      Logger.anchor.warning("Cannot arm alarm: Anchor position has not locked yet.")
      return
    }
    Logger.anchor.info("Arming anchor alarm from ViewModel.")
    anchorService.arm(coordinate: coord, radius: configuredRadius)
  }
  
  func requestArmAlarm(in service: PermissionService) {
    guard anchorCoordinate != nil || anchorService.activeWatch?.coordinate != nil else {
      Logger.anchor.warning("Cannot request arm alarm: Anchor position has not locked yet.")
      return
    }

    let status = service.notificationStatus
    if status == .authorized {
      self.armAlarm()
    } else {
      let gateType: PermissionGateType = .notification(trigger: .anchorAlarm)
      self.pendingAction = { [weak self] in self?.armAlarm() }
      self.pendingGateType = gateType
      self.permissionGateType = gateType
    }
  }
  
  func finalizePendingAction() {
    let action = pendingAction
    cancelPendingAction()

    guard let action,
          anchorService.status == .dropped,
          anchorService.activeWatch?.coordinate != nil else {
      return
    }
    action()
  }

  /// Executes or discards the deferred arm action when the permission sheet closes, depending on authorization status.
  func handlePermissionSheetDismissed(in service: PermissionService) {
    guard let gate = pendingGateType else {
      cancelPendingAction()
      return
    }
    if gate.currentStatus(in: service) == .authorized {
      finalizePendingAction()
    } else {
      cancelPendingAction()
    }
  }

  /// Clears any deferred permission-gated arm action and closes the permission gate sheet.
  func cancelPendingAction() {
    pendingAction = nil
    pendingGateType = nil
    permissionGateType = nil
  }
  
  func disarmAlarm() {
    Logger.anchor.info("Disarming anchor alarm from ViewModel.")
    cancelPendingAction()
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

  /// Technical Design Choice: Domain Isolation for Position Adjustment
  /// `AnchorViewModel` manages the UI mode flag and forwards confirmed coordinates to `AnchorService`.
  /// It does not perform map telemetry math (distance/bearing to map center), keeping it strictly decoupled from ChartViewModel.
  func startAdjustingAnchor() {
    Logger.anchor.info("Starting manual anchor position adjustment mode.")
    self.isAdjustingAnchor = true
  }

  func confirmAdjustAnchor(to newCoordinate: CLLocationCoordinate2D) {
    Logger.anchor.info("Confirming manual anchor position adjustment to (\(newCoordinate.latitude, privacy: .public), \(newCoordinate.longitude, privacy: .public)).")
    cancelPendingAction()
    anchorService.adjustAnchorPosition(to: newCoordinate)
    self.isAdjustingAnchor = false
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
}
