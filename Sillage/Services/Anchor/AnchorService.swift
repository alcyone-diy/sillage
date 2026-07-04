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
  
  private(set) var activeWatch: AnchorWatch?
  private(set) var status: AnchorStatus = .inactive
  private(set) var isMuted: Bool = false
  
  private(set) var latestFix: NavigationFix?
  private(set) var currentDistance: Measurement<UnitLength>?
  private(set) var gpsAccuracy: Measurement<UnitLength>?
  
  private var backgroundToken: (any BackgroundLocationToken)?
  
  private final class TaskCancellable: @unchecked Sendable {
    var task: Task<Void, Never>?
    deinit { task?.cancel() }
  }
  private let locationUpdateTask = TaskCancellable()
  
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
  
  init(
    positioningService: PositioningService,
    preferencesService: PreferencesServiceProtocol,
    notificationService: NotificationService
  ) {
    self.positioningService = positioningService
    self.preferencesService = preferencesService
    self.notificationService = notificationService
    
    // Resume from persistent state
    self.activeWatch = preferencesService.savedAnchorWatch
    self.status = preferencesService.savedAnchorStatus
    
    if self.status != .inactive {
      resumeWatch()
    }
    
    startListeningToGPS()
  }
  
  func arm(coordinate: CLLocationCoordinate2D, radius: Measurement<UnitLength>) {
    Logger.anchor.info("⚓️ Arming anchor watch. Radius: \(radius.value) \(radius.unit.symbol)")
    
    let watch = AnchorWatch(coordinate: coordinate, radius: radius)
    self.activeWatch = watch
    self.status = .armed
    self.isMuted = false
    persistState()
    
    Task {
      do {
        try await notificationService.requestCriticalAuthorization()
      } catch {
        Logger.anchor.error("Failed to request critical notification authorization: \(error)")
      }
    }
    
    if backgroundToken == nil {
      backgroundToken = positioningService.requestBackgroundLocation()
    }
    
    notifyStateChange()
  }
  
  func disarm() {
    Logger.anchor.info("⚓️ Disarming anchor watch.")
    
    self.activeWatch = nil
    self.status = .inactive
    self.isMuted = false
    persistState()
    self.currentDistance = nil
    
    notificationService.clearDeliveredNotifications()
    
    backgroundToken?.invalidate()
    backgroundToken = nil
    
    notifyStateChange()
  }
  
  func silenceAlarm() {
    Logger.anchor.info("⚓️ Silencing anchor alarm notifications.")
    isMuted = true
    notificationService.clearDeliveredNotifications()
    notifyStateChange()
  }
  
  private func resumeWatch() {
    Logger.anchor.info("⚓️ Resuming anchor watch from persisted state.")
    if backgroundToken == nil {
      backgroundToken = positioningService.requestBackgroundLocation()
    }
  }
  
  private func persistState() {
    preferencesService.savedAnchorWatch = activeWatch
    preferencesService.savedAnchorStatus = status
  }
  
  private func startListeningToGPS() {
    locationUpdateTask.task?.cancel()
    locationUpdateTask.task = Task { [weak self] in
      guard let positioningService = self?.positioningService else { return }
      
      for await fix in positioningService.locationUpdates {
        guard !Task.isCancelled else { break }
        self?.processLocationFix(fix)
      }
    }
  }
  
  private func processLocationFix(_ fix: NavigationFix) {
    self.latestFix = fix
    self.gpsAccuracy = fix.horizontalAccuracy
    
    guard let watch = activeWatch, status != .inactive else { return }
    
    let anchorLocation = CLLocation(latitude: watch.coordinate.latitude, longitude: watch.coordinate.longitude)
    let fixLocation = CLLocation(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
    
    let distanceInMeters = fixLocation.distance(from: anchorLocation)
    let radiusInMeters = watch.radius.converted(to: .meters).value
    
    self.currentDistance = Measurement(value: distanceInMeters, unit: .meters)
    
    // Strict Anti-False-Positive Filter:
    // Only trust the GPS if its horizontal accuracy is strictly positive and less than or equal to half the configured radius.
    let accuracyInMeters = fix.horizontalAccuracy.converted(to: .meters).value
    let requiredAccuracy = radiusInMeters / 2.0
    
    if accuracyInMeters <= 0 || accuracyInMeters > requiredAccuracy {
      Logger.anchor.warning("⚓️ Poor GPS accuracy (\(accuracyInMeters, privacy: .public)m). Required: > 0 and <= \(requiredAccuracy, privacy: .public)m. Skipping anchor watch evaluation to prevent false positive.")
      return
    }
    
    if distanceInMeters > radiusInMeters {
      if status != .dragging {
        triggerAlarm(distance: distanceInMeters, radius: radiusInMeters)
      }
    } else {
      if status == .dragging {
        Logger.anchor.info("⚓️ Vessel returned within anchor radius.")
        status = .armed
        isMuted = false
        persistState()
      }
    }
    
    notifyStateChange()
  }
  
  private func triggerAlarm(distance: Double, radius: Double) {
    Logger.anchor.fault("🚨 ANCHOR DRAGGING! Distance: \(distance, privacy: .public)m, Radius: \(radius, privacy: .public)m")
    
    status = .dragging
    persistState()
    
    if !isMuted {
      Task { [weak self] in
        guard let self = self else { return }
        await self.notificationService.sendCriticalNotification(
          title: String(localized: "⚓️ DRAGGING ANCHOR!"),
          body: String(localized: "Vessel is out of the safe zone (\(Int(distance))m)."),
          identifier: "AnchorDraggingAlarm"
        )
      }
    }
    
    notifyStateChange()
  }
  
}
