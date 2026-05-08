//
//  TrackRecordingService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-03.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation
import Observation

@MainActor
@Observable
public final class TrackRecordingService {
  public private(set) var trackPoints: [TrackPoint] = []

  public var isRecording: Bool = false {
    didSet {
      if isRecording {
        startRecording()
      } else {
        stopRecording()
      }
    }
  }

  private let locationService: LocationServiceProtocol
  private var locationUpdatesTask: TaskCancellable?
  private var backgroundLocationToken: (any BackgroundLocationToken)?

  init(locationService: LocationServiceProtocol? = nil) {
    self.locationService = locationService ?? LocationService.shared
  }

  private func startRecording() {
    let service = self.locationService
    self.backgroundLocationToken = service.requestBackgroundLocation()
    
    locationUpdatesTask = TaskCancellable(Task { [weak self] in
      for await location in service.locationUpdates {
        guard !Task.isCancelled else { break }
        await MainActor.run {
          self?.append(location: location)
        }
      }
    })
  }

  private func stopRecording() {
    locationUpdatesTask?.cancel()
    locationUpdatesTask = nil
    self.backgroundLocationToken = nil

    let pointsToSave = trackPoints
    if !pointsToSave.isEmpty {
      Task.detached {
        await self.saveTrack(points: pointsToSave)
      }
    }
    
    trackPoints.removeAll()
  }

  private func saveTrack(points: [TrackPoint]) async {
    let exporter = GPXExportService()
    do {
      let gpxString = try await exporter.export(track: points)
      guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
      
      let tracksDirectory = documentsDirectory.appendingPathComponent("Tracks", isDirectory: true)
      if !FileManager.default.fileExists(atPath: tracksDirectory.path) {
        try FileManager.default.createDirectory(at: tracksDirectory, withIntermediateDirectories: true, attributes: nil)
      }
      
      var fileURL = tracksDirectory.appendingPathComponent("Track.gpx")
      var counter = 1
      while FileManager.default.fileExists(atPath: fileURL.path) {
        fileURL = tracksDirectory.appendingPathComponent("Track_\(counter).gpx")
        counter += 1
      }
      
      try gpxString.write(to: fileURL, atomically: true, encoding: .utf8)
      print("Successfully saved track to \(fileURL.path)")
    } catch {
      print("Failed to save track: \(error)")
    }
  }

  public func append(location: CLLocation) {
    let accuracy = Measurement(value: location.horizontalAccuracy, unit: UnitLength.meters)
    guard accuracy.value >= 0, accuracy.value <= 50 else { return }

    if let lastPoint = trackPoints.last {
      let lastLocation = CLLocation(latitude: lastPoint.latitude, longitude: lastPoint.longitude)
      let distance = Measurement(value: location.distance(from: lastLocation), unit: UnitLength.meters)
      guard distance.value >= 15 else { return }
    }

    var sog: Measurement<UnitSpeed>? = nil
    if location.speed >= 0 {
      sog = Measurement(value: location.speed, unit: UnitSpeed.metersPerSecond)
    }

    var cog: Measurement<UnitAngle>? = nil
    if location.course >= 0 {
      cog = Measurement(value: location.course, unit: UnitAngle.degrees)
    }

    let trackPoint = TrackPoint(
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude,
      timestamp: location.timestamp,
      sog: sog,
      cog: cog
    )

    trackPoints.append(trackPoint)
  }
}
