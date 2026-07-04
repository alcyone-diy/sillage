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
  
  private var backgroundToken: (any BackgroundLocationToken)?
  
  private final class TaskCancellable: @unchecked Sendable {
    var task: Task<Void, Never>?
    deinit { task?.cancel() }
  }
  private let locationUpdateTask = TaskCancellable()
  
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
  }
  
  func arm(coordinate: CLLocationCoordinate2D, radius: Measurement<UnitLength>) {
    Logger.anchor.info("⚓️ Arming anchor watch. Radius: \(radius.value) \(radius.unit.symbol)")
    
    let watch = AnchorWatch(coordinate: coordinate, radius: radius)
    self.activeWatch = watch
    self.status = .armed
    
    persistState()
    startObservingLocation()
  }
  
  func disarm() {
    Logger.anchor.info("⚓️ Disarming anchor watch.")
    
    self.activeWatch = nil
    self.status = .inactive
    
    persistState()
    stopObservingLocation()
  }
  
  private func resumeWatch() {
    Logger.anchor.info("⚓️ Resuming anchor watch from persisted state.")
    startObservingLocation()
  }
  
  private func persistState() {
    preferencesService.savedAnchorWatch = activeWatch
    preferencesService.savedAnchorStatus = status
  }
  
  private func startObservingLocation() {
    // Dynamically request background location token
    if backgroundToken == nil {
      backgroundToken = positioningService.requestBackgroundLocation()
    }
    
    locationUpdateTask.task?.cancel()
    locationUpdateTask.task = Task { [weak self] in
      guard let positioningService = self?.positioningService else { return }
      
      for await fix in positioningService.locationUpdates {
        guard !Task.isCancelled else { break }
        self?.processLocationFix(fix)
      }
    }
  }
  
  private func stopObservingLocation() {
    locationUpdateTask.task?.cancel()
    locationUpdateTask.task = nil
    
    backgroundToken?.invalidate()
    backgroundToken = nil
  }
  
  private func processLocationFix(_ fix: NavigationFix) {
    guard let watch = activeWatch, status != .inactive else { return }
    
    let anchorLocation = CLLocation(latitude: watch.coordinate.latitude, longitude: watch.coordinate.longitude)
    let fixLocation = CLLocation(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
    
    let distanceInMeters = fixLocation.distance(from: anchorLocation)
    let radiusInMeters = watch.radius.converted(to: .meters).value
    
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
        persistState()
      }
    }
  }
  
  private func triggerAlarm(distance: Double, radius: Double) {
    Logger.anchor.fault("🚨 ANCHOR DRAGGING! Distance: \(distance, privacy: .public)m, Radius: \(radius, privacy: .public)m")
    
    status = .dragging
    persistState()
    
    Task { [weak self] in
      guard let self = self else { return }
      await self.notificationService.sendNotification(
        title: String(localized: "⚓️ Anchor Dragging"),
        body: String(localized: "Vessel is out of the safe zone (\(Int(distance))m)."),
        identifier: "AnchorDraggingAlarm"
      )
    }
  }
  
}
