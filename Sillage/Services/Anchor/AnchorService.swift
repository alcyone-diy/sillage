//
//  AnchorService.swift
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
final class AnchorService {
  
  private let positioningService: PositioningService
  private var preferencesService: PreferencesServiceProtocol
  private let notificationService: NotificationService
  private let permissionService: PermissionServiceProtocol
  private let backgroundMonitoringService: BackgroundMonitoringService
  private let stateStore: AnchorStateStoreProtocol
  let alarmAudioService = AlarmAudioService()
  
  private(set) var activeWatch: AnchorWatch?
  private(set) var status: AnchorStatus = .inactive
  private(set) var triggerReason: AnchorTriggerReason?
  private(set) var isMuted: Bool = false
  private(set) var isSensorDegraded: Bool = false
  private var isDegradedAlertSent: Bool = false
  
  var defaultRadius: Measurement<UnitLength> {
    get { preferencesService.savedAnchorRadius }
    set { preferencesService.savedAnchorRadius = newValue }
  }
  
  private(set) var latestFix: NavigationFix?
  private(set) var currentDistance: Measurement<UnitLength>?
  private(set) var gpsAccuracy: Measurement<UnitLength>?
  
  /// Returns the best available navigation fix for anchor operations.
  /// Technical Design Choice: Enforces a strict 60-second Time-To-Live (TTL) freshness check on `lastKnownLocation`.
  /// If `latestFix` is missing and `lastKnownLocation` is older than 60 seconds, it is rejected (returns `nil`)
  /// to prevent anchoring at an obsolete location miles away.
  var bestAvailableFix: NavigationFix? {
    if let latest = latestFix {
      return latest
    }
    if let lastKnown = positioningService.lastKnownLocation {
      let ageInSeconds = Date().timeIntervalSince(lastKnown.timestamp)
      if ageInSeconds <= 60.0 {
        Logger.anchor.info("⚓️ Utilizing fresh lastKnownLocation (age: \(ageInSeconds, privacy: .public)s <= 60s)")
        return lastKnown
      } else {
        Logger.anchor.warning("⚓️ Rejecting lastKnownLocation due to TTL expiration: \(ageInSeconds, privacy: .public)s > 60s")
      }
    }
    return nil
  }
  
  private var monitoringToken: (any BackgroundMonitoringToken)?
  @ObservationIgnored private var setupLocationToken: (any LocationUpdateToken)?
  
  private final class TaskCancellable: @unchecked Sendable {
    var task: Task<Void, Never>?
    deinit { task?.cancel() }
  }
  
  private var locationUpdateTask = TaskCancellable()
  private var degradedAlertTask: Task<Void, Never>?
  
  // MARK: - State Stream
  
  private var updateContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]
  
  var stateUpdates: AsyncStream<Void> {
    let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
    let id = UUID()
    updateContinuations[id] = continuation
    
    continuation.onTermination = { @Sendable [weak self] _ in
      Task { @MainActor [weak self] in
        self?.updateContinuations.removeValue(forKey: id)
      }
    }
    
    return stream
  }
  
  private func notifyStateChange() {
    for continuation in updateContinuations.values {
      continuation.yield(())
    }
  }
  
  @MainActor
  init(
    positioningService: PositioningService,
    preferencesService: PreferencesServiceProtocol,
    notificationService: NotificationService,
    permissionService: PermissionServiceProtocol,
    backgroundMonitoringService: BackgroundMonitoringService,
    stateStore: AnchorStateStoreProtocol? = nil
  ) {
    let resolvedStore = stateStore ?? AnchorStateStore()
    self.positioningService = positioningService
    self.preferencesService = preferencesService
    self.notificationService = notificationService
    self.permissionService = permissionService
    self.backgroundMonitoringService = backgroundMonitoringService
    self.stateStore = resolvedStore
    
    // Resume from persistent state
    let session = resolvedStore.loadSession()
    self.activeWatch = session.activeWatch
    self.status = session.status
    self.triggerReason = session.triggerReason
    
    if self.status != .inactive {
      resumeWatch()
    }
    
    startListeningToGPS()
  }
  
  /// Technical Design Choice: Resource & Lifecycle Management
  /// Requests a foreground `LocationUpdateToken` when setup UI is active, preventing continuous high-frequency GPS drain
  /// when the user is not actively viewing or setting up an anchor.
  func startSetupLocationUpdates() {
    guard setupLocationToken == nil else { return }
    Logger.anchor.info("⚓️ Starting setup location updates for Anchor UI")
    setupLocationToken = positioningService.requestLocationUpdates()
  }

  func stopSetupLocationUpdates() {
    guard setupLocationToken != nil else { return }
    Logger.anchor.info("⚓️ Stopping setup location updates for Anchor UI")
    setupLocationToken?.invalidate()
    setupLocationToken = nil
  }
  
  /// Drops anchor using the provided coordinate or best available fix.
  /// If no fix is available at drop time, enters `.droppedPendingPosition` state until the first GPS fix arrives.
  func drop(coordinate: CLLocationCoordinate2D? = nil, radius: Measurement<UnitLength>) {
    let fixToUse = (coordinate != nil) ? nil : bestAvailableFix
    let resolvedCoordinate = coordinate ?? fixToUse?.coordinate
    let resolvedAccuracy = fixToUse?.horizontalAccuracy
    
    if let coord = resolvedCoordinate {
      let accuracyValue = resolvedAccuracy?.converted(to: .meters).value ?? 0.0
      Logger.anchor.info("⚓️ Dropping anchor at (\(coord.latitude, privacy: .public), \(coord.longitude, privacy: .public)) with accuracy \(accuracyValue, privacy: .public)m")
      self.activeWatch = AnchorWatch(coordinate: coord, radius: radius, initialAccuracy: resolvedAccuracy)
      self.status = .dropped
    } else {
      Logger.anchor.warning("⚓️ No GPS fix available at drop time. Transitioning to pending position state (.droppedPendingPosition)")
      self.activeWatch = AnchorWatch(coordinate: nil, radius: radius, initialAccuracy: nil)
      self.status = .droppedPendingPosition
    }
    
    self.triggerReason = nil
    self.isMuted = false
    persistState()
    
    startMonitoringSession()
    notifyStateChange()
  }
  
  func update(radius: Measurement<UnitLength>) {
    guard let watch = activeWatch else { return }
    Logger.anchor.info("⚓️ Updating anchor radius to \(radius.value, privacy: .public) \(radius.unit.symbol, privacy: .public)")
    self.activeWatch = AnchorWatch(
      coordinate: watch.coordinate,
      radius: radius,
      initialAccuracy: watch.initialAccuracy,
      createdAt: watch.createdAt
    )
    persistState()
    notifyStateChange()
  }
  
  /// Technical Design Choice: Manual Anchor Position Adjustment
  /// Re-instantiates `activeWatch` with the new coordinate, recalculates distance immediately,
  /// and resets `initialAccuracy` to `nil` as manual human confirmation guarantees position accuracy.
  func adjustAnchorPosition(to newCoordinate: CLLocationCoordinate2D) {
    guard let watch = activeWatch else { return }
    Logger.anchor.info("⚓️ Manually adjusting anchor position to (\(newCoordinate.latitude, privacy: .public), \(newCoordinate.longitude, privacy: .public))")
    
    self.activeWatch = AnchorWatch(
      coordinate: newCoordinate,
      radius: watch.radius,
      initialAccuracy: nil,
      createdAt: watch.createdAt
    )
    
    if let fix = latestFix {
      let anchorLocation = CLLocation(latitude: newCoordinate.latitude, longitude: newCoordinate.longitude)
      let fixLocation = CLLocation(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
      self.currentDistance = Measurement(value: fixLocation.distance(from: anchorLocation), unit: UnitLength.meters)
    }
    
    persistState()
    notifyStateChange()
  }


  func arm(coordinate: CLLocationCoordinate2D, radius: Measurement<UnitLength>) {
    Logger.anchor.info("⚓️ Arming anchor watch at (\(coordinate.latitude, privacy: .public), \(coordinate.longitude, privacy: .public)). Radius: \(radius.value, privacy: .public) \(radius.unit.symbol, privacy: .public)")
    
    let initialAcc = activeWatch?.initialAccuracy ?? gpsAccuracy
    let watch = AnchorWatch(coordinate: coordinate, radius: radius, initialAccuracy: initialAcc)
    self.activeWatch = watch
    self.status = .armed
    self.triggerReason = nil
    self.isMuted = false
    persistState()
    
    Task {
      _ = await permissionService.requestCriticalNotificationAuthorization()
    }
    
    startMonitoringSession()
    notifyStateChange()
  }
  
  func disarm() {
    Logger.anchor.info("⚓️ Disarming anchor watch (reverting to dropped state).")
    
    self.status = .dropped
    self.triggerReason = nil
    self.isMuted = false
    self.isSensorDegraded = false
    persistState()
    
    degradedAlertTask?.cancel()
    degradedAlertTask = nil
    
    alarmAudioService.stopSiren()
    notificationService.clearAllNotifications()
    monitoringToken?.invalidate()
    monitoringToken = nil
    
    notifyStateChange()
  }
  
  func clear() {
    Logger.anchor.info("⚓️ Clearing anchor watch completely.")
    
    self.activeWatch = nil
    self.status = .inactive
    self.triggerReason = nil
    self.isMuted = false
    self.isSensorDegraded = false
    persistState()
    self.currentDistance = nil
    
    alarmAudioService.stopSiren()
    notificationService.clearAllNotifications()
    monitoringToken?.invalidate()
    monitoringToken = nil
    
    stopSetupLocationUpdates()
    isDegradedAlertSent = false
    
    notifyStateChange()
  }
  
  func silenceAlarm() {
    Logger.anchor.info("⚓️ Silencing anchor alarm notifications.")
    isMuted = true
    alarmAudioService.stopSiren()
    notificationService.clearAllNotifications()
    notifyStateChange()
  }

  func unSilenceAlarm() {
    Logger.anchor.info("⚓️ Unsilencing anchor alarm notifications.")
    isMuted = false
    notifyStateChange()
  }
  
  private func resumeWatch() {
    Logger.anchor.info("⚓️ Resuming anchor watch from persisted state.")
    startMonitoringSession()
  }
  
  private func startMonitoringSession() {
    if monitoringToken == nil {
      let watchdog = WatchdogConfiguration(
        identifier: NotificationIntent.anchorWatchdog.rawValue,
        title: String(localized: "⚠️ Sillage Inactive"),
        body: String(localized: "Anchor alarm is active but the app has stopped receiving GPS updates."),
        timeout: 300
      )
      monitoringToken = backgroundMonitoringService.startMonitoring(
        ownerIdentifier: "AnchorWatch",
        distanceFilter: Measurement(value: 1, unit: .meters),
        watchdog: watchdog
      )
    }
  }
  
  private func persistState() {
    let session = AnchorSessionData(
      activeWatch: activeWatch,
      status: status,
      triggerReason: triggerReason
    )
    stateStore.saveSession(session)
  }
  
  private func startListeningToGPS() {
    locationUpdateTask.task?.cancel()
    locationUpdateTask.task = Task { @MainActor [weak self] in
      guard let positioningService = self?.positioningService else { return }
      
      for await state in positioningService.locationUpdates {
        guard !Task.isCancelled else { break }
        switch state {
        case .active(let fix):
          self?.isDegradedAlertSent = false
          self?.isSensorDegraded = false
          self?.processLocationFix(fix)
        case .degraded(let fix):
          self?.handleDegradedGPS()
          self?.processLocationFix(fix)
        case .lost:
          if self?.status == .armed {
            self?.triggerAlarm(reason: .gpsSignalLost)
          }
        }
      }
    }
  }
  
  private func handleDegradedGPS() {
    guard status == .armed || status == .dragging else { return }
    guard !isDegradedAlertSent else { return }
    
    isDegradedAlertSent = true
    isSensorDegraded = true
    Logger.anchor.warning("⚓️ GPS accuracy lost at anchor. Verification temporarily suspended.")
    
    if !isMuted {
      // Unstructured task used as "fire-and-forget" to prevent blocking the GPS stream loop.
      degradedAlertTask?.cancel()
      degradedAlertTask = Task { [weak self] in
        guard let self = self else { return }
        await self.notificationService.sendCriticalNotification(
          title: String(localized: "⚠️ Monitoring Suspended"),
          body: String(localized: "Critical GPS accuracy. Anchor alarm is temporarily unreliable."),
          identifier: NotificationIntent.anchorGPSDegraded.rawValue
        )
      }
    }
  }
  
  private let evaluator = AnchorEvaluator()

  private func processLocationFix(_ fix: NavigationFix) {
    self.latestFix = fix
    self.gpsAccuracy = fix.horizontalAccuracy
    
    // Technical Design Choice: Auto-fulfill pending position drop on first incoming GPS fix
    if status == .droppedPendingPosition, let watch = activeWatch {
      let accuracyMeters = fix.horizontalAccuracy.converted(to: .meters).value
      Logger.anchor.info("⚓️ Acquired first GPS fix for pending anchor drop at (\(fix.coordinate.latitude, privacy: .public), \(fix.coordinate.longitude, privacy: .public)) with accuracy \(accuracyMeters, privacy: .public)m")
      
      self.activeWatch = AnchorWatch(
        coordinate: fix.coordinate,
        radius: watch.radius,
        initialAccuracy: fix.horizontalAccuracy,
        createdAt: watch.createdAt
      )
      self.status = .dropped
      persistState()
      notifyStateChange()
    }
    
    guard let watch = activeWatch, let anchorCoord = watch.coordinate, status != .inactive, status != .droppedPendingPosition else { return }
    
    let anchorLocation = CLLocation(latitude: anchorCoord.latitude, longitude: anchorCoord.longitude)
    let fixLocation = CLLocation(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
    self.currentDistance = Measurement(value: fixLocation.distance(from: anchorLocation), unit: UnitLength.meters)
    
    let evaluationResult = evaluator.evaluate(fix: fix, watch: watch, currentStatus: status)
    
    switch evaluationResult {
    case .maintainState:
      break
      
    case .triggerAlarm(let reason):
      triggerAlarm(reason: reason)
      
    case .autoResolveAlarm(let reason):
      switch reason {
      case .vesselReturnedInCircle(let distance):
        Logger.anchor.info("⚓️ Vessel returned within anchor radius (\(Int(distance.value), privacy: .public)m). Auto-resolving alarm.")
        status = .armed
        triggerReason = nil
        isMuted = false
        alarmAudioService.stopSiren()
        notificationService.clearAllNotifications()
        persistState()
      }
    }

    notifyStateChange()
  }

  private func triggerAlarm(reason: AnchorTriggerReason) {
    Logger.anchor.fault("🚨 ANCHOR ALARM TRIGGERED! Reason: \(String(describing: reason), privacy: .public)")
    
    self.triggerReason = reason
    self.status = .dragging
    persistState()
    
    if !isMuted {
      alarmAudioService.startSiren()
      Task { @MainActor [weak self] in
        guard let self = self else { return }
        await self.notificationService.sendCriticalNotification(
          title: String(localized: "⚓️ DRAGGING ANCHOR!"),
          body: String(localized: "Anchor alarm triggered."),
          identifier: NotificationIntent.anchorDragging.rawValue
        )
      }
    }
    
    notifyStateChange()
  }
  
  func simulateDebugDragging() {
    Logger.anchor.fault("🚨 Debug dragging simulation triggered!")
    self.isMuted = false
    
    // Offset simulated anchor coordinate from current GPS location so real GPS fixes compute distance > radius
    if let currentCoord = latestFix?.coordinate {
      let offsetLat = currentCoord.latitude + 0.0015 // ~165 meters north
      self.activeWatch = AnchorWatch(
        coordinate: CLLocationCoordinate2D(latitude: offsetLat, longitude: currentCoord.longitude),
        radius: Measurement(value: 30, unit: .meters),
        initialAccuracy: Measurement(value: 5, unit: .meters)
      )
    } else {
      self.activeWatch = AnchorWatch(
        coordinate: CLLocationCoordinate2D(latitude: 47.218371, longitude: -1.553621),
        radius: Measurement(value: 30, unit: .meters),
        initialAccuracy: Measurement(value: 5, unit: .meters)
      )
    }
    self.currentDistance = Measurement(value: 165, unit: .meters)
    triggerAlarm(reason: .debugSimulation)
  }
}
