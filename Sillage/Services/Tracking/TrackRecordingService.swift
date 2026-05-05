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

  init(locationService: LocationServiceProtocol? = nil) {
    self.locationService = locationService ?? LocationService.shared
  }

  private func startRecording() {
    let service = self.locationService
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
