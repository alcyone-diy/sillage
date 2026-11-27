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
import OSLog

@MainActor
final class AnchorService {
  
  private let positioningService: PositioningService
  private var preferencesService: PreferencesServiceProtocol
  private let notificationService: NotificationService
  private let permissionService: PermissionServiceProtocol
  private let backgroundMonitoringService: BackgroundMonitoringService
  private let stateStore: AnchorStateStoreProtocol
  public let alarmAudioService: any AlarmAudioServiceProtocol
  
  private enum DegradedPhase {
    case none
    case debouncing
    case elapsed
  }

  private(set) var activeWatch: AnchorWatch?
  private(set) var status: AnchorStatus = .inactive
  private(set) var triggerReason: AnchorTriggerReason?
  private(set) var isMuted: Bool = false
  private(set) var isSensorDegraded: Bool = false
  private var degradedPhase: DegradedPhase = .none
  
  var defaultRadius: Measurement<UnitLength> {
    get { preferencesService.savedAnchorRadius }
    set { preferencesService.savedAnchorRadius = newValue }
  }
  
  private(set) var latestFix: NavigationFix?
  private(set) var currentDistance: Measurement<UnitLength>?
  private(set) var gpsAccuracy: Measurement<UnitLength>?
  
  public var currentState: AnchorState {
    AnchorState(
      activeWatch: activeWatch,
      status: status,
      triggerReason: triggerReason,
      currentDistance: currentDistance,
      latestFix: latestFix,
      gpsAccuracy: gpsAccuracy,
      isMuted: isMuted,
      isSensorDegraded: isSensorDegraded
    )
  }
  
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
  private var setupLocationToken: (any LocationUpdateToken)?
  
  private final class TaskCancellable: @unchecked Sendable {
    var task: Task<Void, Never>?
    deinit { task?.cancel() }
  }
  
  private var locationUpdateTask = TaskCancellable()
  private var degradedAlertTask: Task<Void, Never>?
  private let degradedAlertDelay: Duration
  
  // MARK: - State Stream
  
  private var updateContinuations: [UUID: AsyncStream<AnchorState>.Continuation] = [:]
  
  public var stateUpdates: AsyncStream<AnchorState> {
    let (stream, continuation) = AsyncStream.makeStream(of: AnchorState.self)
    let id = UUID()
    updateContinuations[id] = continuation
    
    // Yield current state snapshot immediately upon subscription
    continuation.yield(currentState)
    
    continuation.onTermination = { @Sendable [weak self] _ in
      Task { @MainActor [weak self] in
        self?.updateContinuations.removeValue(forKey: id)
      }
    }
    
    return stream
  }
  
  private func notifyStateChange() {
    let snapshot = currentState
    for continuation in updateContinuations.values {
      continuation.yield(snapshot)
    }
  }
  
  @MainActor
  init(
    positioningService: PositioningService,
    preferencesService: PreferencesServiceProtocol,
    notificationService: NotificationService,
    permissionService: PermissionServiceProtocol,
    backgroundMonitoringService: BackgroundMonitoringService,
    alarmAudioService: (any AlarmAudioServiceProtocol)? = nil,
    stateStore: AnchorStateStoreProtocol,
    degradedAlertDelay: Duration = .seconds(2)
  ) {
    self.positioningService = positioningService
    self.preferencesService = preferencesService
    self.notificationService = notificationService
    self.permissionService = permissionService
    self.backgroundMonitoringService = backgroundMonitoringService
    self.alarmAudioService = alarmAudioService ?? AlarmAudioService()
    self.stateStore = stateStore
    self.degradedAlertDelay = degradedAlertDelay
    
    // Resume from persistent state
    let session = stateStore.loadSession()
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
    ensureListeningToGPS()
  }

  func stopSetupLocationUpdates() {
    guard setupLocationToken != nil else { return }
    Logger.anchor.info("⚓️ Stopping setup location updates for Anchor UI")
    setupLocationToken?.invalidate()
    setupLocationToken = nil
    if status == .inactive {
      locationUpdateTask.task?.cancel()
      locationUpdateTask.task = nil
    }
  }
  
  /// Drops anchor using the provided coordinate or best available fix.
  /// If no fix is available at drop time, enters `.droppedPendingPosition` state until the first GPS fix arrives.
  func drop(
    coordinate: CLLocationCoordinate2D? = nil,
    radius: Measurement<UnitLength>,
    initialAccuracy: Measurement<UnitLength>? = nil
  ) {
    let fixToUse = (coordinate != nil) ? nil : bestAvailableFix
    let resolvedCoordinate = coordinate ?? fixToUse?.coordinate
    let resolvedAccuracy = initialAccuracy ?? fixToUse?.horizontalAccuracy
    
    if let coord = resolvedCoordinate {
      if let accuracy = resolvedAccuracy {
        let formattedAccuracy = accuracy.marineAnchorDistanceFormatted()
        Logger.anchor.info("⚓️ Dropping anchor at (\(coord.latitude, privacy: .public), \(coord.longitude, privacy: .public)) with accuracy \(formattedAccuracy, privacy: .public)")
      } else {
        Logger.anchor.info("⚓️ Dropping anchor at (\(coord.latitude, privacy: .public), \(coord.longitude, privacy: .public)) with unknown accuracy")
      }
      self.activeWatch = AnchorWatch(coordinate: coord, radius: radius, initialAccuracy: resolvedAccuracy)
      self.status = .dropped
    } else {
      Logger.anchor.warning("⚓️ No GPS fix available at drop time. Transitioning to pending position state (.droppedPendingPosition)")
      self.activeWatch = AnchorWatch(coordinate: nil, radius: radius, initialAccuracy: nil)
      self.status = .droppedPendingPosition
    }
    
    self.triggerReason = nil
    self.isMuted = false
    resetDegradedState()
    persistState()
    
    ensureListeningToGPS()
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
      createdAt: watch.createdAt,
      evitementHistory: watch.evitementHistory
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
      createdAt: watch.createdAt,
      evitementHistory: watch.evitementHistory
    )
    
    if let fix = latestFix {
      self.currentDistance = newCoordinate.geodesicDistance(to: fix.coordinate)
    }
    
    persistState()
    notifyStateChange()
  }


  func arm(coordinate: CLLocationCoordinate2D, radius: Measurement<UnitLength>) {
    Logger.anchor.info("⚓️ Arming anchor watch at (\(coordinate.latitude, privacy: .public), \(coordinate.longitude, privacy: .public)). Radius: \(radius.value, privacy: .public) \(radius.unit.symbol, privacy: .public)")
    
    let initialAcc = activeWatch?.initialAccuracy ?? gpsAccuracy
    let currentHistory = activeWatch?.evitementHistory ?? []
    let watch = AnchorWatch(
      coordinate: coordinate,
      radius: radius,
      initialAccuracy: initialAcc,
      evitementHistory: currentHistory
    )
    self.activeWatch = watch
    self.status = .armed
    self.triggerReason = nil
    self.isMuted = false
    resetDegradedState()
    persistState()
    
    Task {
      _ = await permissionService.requestCriticalNotificationAuthorization()
    }
    
    ensureListeningToGPS()
    startMonitoringSession()
    alarmAudioService.prepareAudioSession()
    notifyStateChange()
  }
  
  func disarm() {
    Logger.anchor.info("⚓️ Disarming anchor watch (reverting to dropped state).")
    
    self.status = .dropped
    self.triggerReason = nil
    self.isMuted = false
    resetDegradedState()
    persistState()
    
    alarmAudioService.stopSiren()
    notificationService.clearAllNotifications()
    monitoringToken?.invalidate()
    monitoringToken = nil
    
    notifyStateChange()
  }
  
  /// Clears the active anchor session and returns the service to `.inactive`.
  /// Preserves an active `setupLocationToken` so foreground setup UI continues receiving GPS updates cleanly.
  func clear() {
    Logger.anchor.info("⚓️ Clearing anchor watch completely.")
    
    self.activeWatch = nil
    self.status = .inactive
    self.triggerReason = nil
    self.isMuted = false
    resetDegradedState()
    persistState()
    self.currentDistance = nil
    
    alarmAudioService.stopSiren()
    notificationService.clearAllNotifications()
    monitoringToken?.invalidate()
    monitoringToken = nil
    
    if setupLocationToken != nil {
      ensureListeningToGPS()
    } else {
      locationUpdateTask.task?.cancel()
      locationUpdateTask.task = nil
    }
    
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
    switch status {
    case .armed:
      alarmAudioService.prepareAudioSession()
    case .dragging:
      // `AnchorEvaluator` only emits `.triggerAlarm` on transitions out of `.armed`;
      // relaunching directly into persisted `.dragging` must explicitly restart the siren.
      if !isMuted {
        alarmAudioService.startSiren()
      }
    case .inactive, .droppedPendingPosition, .dropped:
      break
    }
  }
  
  private func startMonitoringSession() {
    if monitoringToken == nil {
      monitoringToken = backgroundMonitoringService.startMonitoring(
        ownerIdentifier: "AnchorWatch",
        // A 1-meter filter guarantees high-precision telemetry and immediate wakeup if the anchor drags.
        distanceFilter: Measurement(value: 1.0, unit: .meters)
      )
    }
  }
  
  private func persistState() {
    debouncePersistTask?.cancel()
    debouncePersistTask = nil
    
    let session = AnchorSessionData(
      activeWatch: activeWatch,
      status: status,
      triggerReason: triggerReason
    )
    stateStore.saveSession(session)
  }

  
  private func ensureListeningToGPS() {
    if locationUpdateTask.task == nil {
      startListeningToGPS()
    }
  }

  private func cancelDegradedAlertTask() {
    degradedAlertTask?.cancel()
    degradedAlertTask = nil
  }

  private func resetDegradedState() {
    cancelDegradedAlertTask()
    isSensorDegraded = false
    degradedPhase = .none
  }

  private func startListeningToGPS() {
    locationUpdateTask.task?.cancel()
    locationUpdateTask.task = Task { @MainActor [weak self] in
      guard let positioningService = self?.positioningService else { return }
      
      for await state in positioningService.locationUpdates {
        guard !Task.isCancelled else { break }
        switch state {
        case .active(let fix):
          self?.resetDegradedState()
          self?.processLocationFix(fix, evaluateAlarm: true)
        case .degraded(let fix):
          self?.handleDegradedLocationFix(fix)
        case .lost:
          if self?.status == .armed {
            self?.triggerAlarm(reason: .gpsSignalLost)
          }
        }
      }
    }
  }
  
  /// Handles temporary GPS accuracy degradation during anchor watch.
  /// Technical Design Choice: Suspends alarm evaluation and debounces via `degradedAlertDelay` (2s default)
  /// to prevent false alarms and notification flapping on transient GPS accuracy fluctuations.
  /// If `.active`, `disarm()`, or `clear()` occurs within the window, `degradedAlertTask` is cancelled silently.
  /// Once the debounce window elapses, subsequent `.degraded` fixes immediately evaluate accuracy thresholds
  /// (`.poorAccuracy` / `.gpsSignalLost`) while never auto-resolving an active `.dragging` alarm on degraded data.
  private func handleDegradedLocationFix(_ fix: NavigationFix) {
    processLocationFix(fix, evaluateAlarm: false, notify: false)

    guard status == .armed || status == .dragging else {
      notifyStateChange()
      return
    }
    isSensorDegraded = true

    switch degradedPhase {
    case .none:
      degradedPhase = .debouncing
      Logger.anchor.warning("⚓️ GPS accuracy lost at anchor. Verification temporarily suspended.")
      scheduleDegradedAlertTask()
      notifyStateChange()
    case .debouncing:
      notifyStateChange()
    case .elapsed:
      if !triggerDegradedAccuracyAlarmIfNeeded() {
        notifyStateChange()
      }
    }
  }

  private func scheduleDegradedAlertTask() {
    let delay = degradedAlertDelay
    cancelDegradedAlertTask()
    degradedAlertTask = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard let self = self,
            !Task.isCancelled,
            self.isSensorDegraded,
            self.status == .armed || self.status == .dragging else { return }

      self.degradedPhase = .elapsed

      if self.triggerDegradedAccuracyAlarmIfNeeded() {
        return
      }

      guard !self.isMuted else { return }

      let bodyText: String
      if let accuracy = self.gpsAccuracy {
        let formattedAccuracy = accuracy.marineAnchorDistanceFormatted()
        bodyText = String(localized: "Critical GPS accuracy (\(formattedAccuracy)). Anchor alarm is temporarily unreliable.")
      } else {
        bodyText = String(localized: "Critical GPS accuracy. Anchor alarm is temporarily unreliable.")
      }

      do {
        try await self.notificationService.sendCriticalNotification(
          title: String(localized: "⚠️ Monitoring Suspended"),
          body: bodyText,
          identifier: NotificationIntent.anchorGPSDegraded.rawValue
        )
      } catch {
        Logger.anchor.error("Failed to schedule GPS degraded critical notification: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  /// Evaluates whether the latest degraded fix breaches accuracy thresholds while armed.
  /// Never evaluates `.distanceExceeded` or `.autoResolveAlarm` on degraded GPS data.
  @discardableResult
  private func triggerDegradedAccuracyAlarmIfNeeded() -> Bool {
    guard status == .armed, let watch = activeWatch, let fix = latestFix else {
      return false
    }
    let evaluationResult = evaluator.evaluate(fix: fix, watch: watch, currentStatus: .armed)
    guard case .triggerAlarm(let reason) = evaluationResult else {
      return false
    }
    switch reason {
    case .gpsSignalLost, .poorAccuracy:
      triggerAlarm(reason: reason)
      return true
    case .distanceExceeded, .debugSimulation:
      return false
    }
  }
  
  private let evaluator = AnchorEvaluator()

  private func processLocationFix(_ fix: NavigationFix, evaluateAlarm: Bool = true, notify: Bool = true) {
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
    }
    
    guard let watch = activeWatch, let anchorCoord = watch.coordinate, status != .inactive, status != .droppedPendingPosition else {
      // Publish live `latestFix` / `gpsAccuracy` updates even while in `.setup` (`.inactive`).
      if notify {
        notifyStateChange()
      }
      return
    }
    
    self.currentDistance = anchorCoord.geodesicDistance(to: fix.coordinate)
    
    if evaluateAlarm {
      let evaluationResult = evaluator.evaluate(fix: fix, watch: watch, currentStatus: status)
      
      // Record evitement swing point if vessel moved spatially >= 2m in dropped, armed, or dragging status
      if status == .dropped || status == .armed || status == .dragging {
        recordEvitementPointIfNeeded(fix: fix)
      }

      switch evaluationResult {
      case .maintainState:
        break
        
      case .triggerAlarm(let reason):
        triggerAlarm(reason: reason)
        return
        
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
    }

    if notify {
      notifyStateChange()
    }
  }

  // MARK: - Evitement History & Debounced Persistence

  private static let minEvitementDistanceThreshold = Measurement(value: 2.0, unit: UnitLength.meters)
  private var debouncePersistTask: Task<Void, Never>?

  /// Records a vessel location fix into activeWatch.evitementHistory if purely spatial filtering conditions are met.
  /// Technical Design Choice: Purely spatial sampling (>= 2m movement) ensures stationary vessels do not exhaust
  /// the circular buffer over long anchorage periods. Updates in-memory state immediately for live map rendering,
  /// while disk persistence is debounced asynchronously to ensure eventual consistency even if movement stops.
  private func recordEvitementPointIfNeeded(fix: NavigationFix) {
    guard var watch = activeWatch, (status == .dropped || status == .armed || status == .dragging) else { return }

    
    let newCoord = fix.coordinate
    if let lastPoint = watch.evitementHistory.last {
      // Purely spatial filter: strictly require moving >= 2 meters with valid geodesic coordinates
      guard let deltaDistance = lastPoint.coordinate.geodesicDistance(to: newCoord),
            deltaDistance >= Self.minEvitementDistanceThreshold else {
        return
      }
    }

    let sample = AnchorEvitementPoint(coordinate: newCoord, timestamp: fix.timestamp)
    watch.appendEvitementPoint(sample)
    self.activeWatch = watch
    
    schedulePersistState()
  }

  /// Schedules a debounced disk save task (5 minutes) if a persistence task is not already pending.
  /// Technical Design Choice: Ensures that state is deterministically flushed to disk after movement stops,
  /// without swamping disk I/O on every 2-meter position update.
  private func schedulePersistState() {
    guard debouncePersistTask == nil else { return }
    
    debouncePersistTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(300))
      guard !Task.isCancelled else { return }
      self?.persistState()
      self?.debouncePersistTask = nil
    }
  }



  /// Constructs localized notification titles and descriptive bodies for anchor alarm triggers.
  /// Technical Design Choice: Uses `marineAnchorDistanceFormatted()` on `Measurement<UnitLength>`
  /// to ensure dynamic unit representation (meters for metric, feet for US/UK) based on user phone settings.
  private func notificationContent(for reason: AnchorTriggerReason) -> (title: String, body: String) {
    switch reason {
    case .distanceExceeded(let distance, let radius):
      let distStr = distance.marineAnchorDistanceFormatted()
      let radStr = radius.marineAnchorDistanceFormatted()
      return (
        title: String(localized: "⚓️ DRAGGING ANCHOR!"),
        body: String(localized: "Vessel position is \(distStr) from anchor point (radius limit: \(radStr)).")
      )
    case .poorAccuracy(let accuracy, let requiredAccuracy):
      let accStr = accuracy.marineAnchorDistanceFormatted()
      let reqStr = requiredAccuracy.marineAnchorDistanceFormatted()
      return (
        title: String(localized: "⚠️ Anchor Alarm: GPS Degraded"),
        body: String(localized: "GPS accuracy degraded to \(accStr) (required: \(reqStr)).")
      )
    case .gpsSignalLost:
      return (
        title: String(localized: "⚠️ Anchor Alarm: GPS Lost"),
        body: String(localized: "GPS position signal lost during active anchor watch.")
      )
    case .debugSimulation:
      return (
        title: String(localized: "⚓️ DRAGGING ANCHOR! (Debug)"),
        body: String(localized: "Debug simulation anchor alarm triggered.")
      )
    }
  }

  private func triggerAlarm(reason: AnchorTriggerReason) {
    Logger.anchor.fault("🚨 ANCHOR ALARM TRIGGERED! Reason: \(String(describing: reason), privacy: .public)")
    
    cancelDegradedAlertTask()
    if isSensorDegraded {
      degradedPhase = .elapsed
    }
    self.triggerReason = reason
    self.status = .dragging
    persistState()
    
    if !isMuted {
      alarmAudioService.startSiren()
      let content = notificationContent(for: reason)
      Task { @MainActor [weak self] in
        guard let self = self else { return }
        do {
          try await self.notificationService.sendCriticalNotification(
            title: content.title,
            body: content.body,
            identifier: NotificationIntent.anchorDragging.rawValue
          )
        } catch {
          Logger.anchor.error("Failed to schedule anchor dragging critical notification: \(error.localizedDescription, privacy: .public)")
        }
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
