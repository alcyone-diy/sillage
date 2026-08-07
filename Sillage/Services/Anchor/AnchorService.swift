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
  
  private var monitoringToken: (any BackgroundMonitoringToken)?
  
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
  
  func drop(coordinate: CLLocationCoordinate2D, radius: Measurement<UnitLength>) {
    Logger.anchor.info("⚓️ Dropping anchor at \(coordinate.latitude), \(coordinate.longitude)")
    self.activeWatch = AnchorWatch(coordinate: coordinate, radius: radius)
    self.status = .dropped
    self.triggerReason = nil
    self.isMuted = false
    persistState()
    
    startMonitoringSession()
    
    notifyStateChange()
  }
  
  func update(radius: Measurement<UnitLength>) {
    guard let watch = activeWatch else { return }
    Logger.anchor.info("⚓️ Updating anchor radius to \(radius.value) \(radius.unit.symbol)")
    self.activeWatch = AnchorWatch(coordinate: watch.coordinate, radius: radius)
    persistState()
    notifyStateChange()
  }

  func arm(coordinate: CLLocationCoordinate2D, radius: Measurement<UnitLength>) {
    Logger.anchor.info("⚓️ Arming anchor watch. Radius: \(radius.value) \(radius.unit.symbol)")
    
    let watch = AnchorWatch(coordinate: coordinate, radius: radius)
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
    
    guard let watch = activeWatch, status != .inactive else { return }
    
    let anchorLocation = CLLocation(latitude: watch.coordinate.latitude, longitude: watch.coordinate.longitude)
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
        Logger.anchor.info("⚓️ Vessel returned within anchor radius (\(Int(distance.value))m). Auto-resolving alarm.")
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
        radius: Measurement(value: 30, unit: .meters)
      )
    } else {
      self.activeWatch = AnchorWatch(
        coordinate: CLLocationCoordinate2D(latitude: 47.218371, longitude: -1.553621),
        radius: Measurement(value: 30, unit: .meters)
      )
    }
    self.currentDistance = Measurement(value: 165, unit: .meters)
    triggerAlarm(reason: .debugSimulation)
  }
}
