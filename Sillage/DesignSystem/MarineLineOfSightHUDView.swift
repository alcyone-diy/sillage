//
//  MarineLineOfSightHUDView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-17.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import CoreLocation

/// Sightline telemetry HUD providing real-time OFFSET (distance) and DIR (bearing)
/// from a reference coordinate (typically the vessel) to a target coordinate.
public struct MarineLineOfSightHUDView: View {
  let vesselCoordinate: CLLocationCoordinate2D?
  let targetCoordinate: CLLocationCoordinate2D
  @Environment(\.locale) private var locale

  public init(vesselCoordinate: CLLocationCoordinate2D?, targetCoordinate: CLLocationCoordinate2D) {
    self.vesselCoordinate = vesselCoordinate
    self.targetCoordinate = targetCoordinate
  }

  public var body: some View {
    let distance = vesselCoordinate?.distance(to: targetCoordinate)
    let bearing = vesselCoordinate?.greatCircleBearing(to: targetCoordinate)

    let distanceString = distance?.marineContextualDistanceFormatted(locale: locale) ?? "---"
    let bearingString = bearing?.marineBearingFormatted ?? "---"

    let items = [
      MarineTelemetryItem(label: "OFFSET", value: distanceString, isPlaceholder: distance == nil),
      MarineTelemetryItem(label: "DIR", value: bearingString, isPlaceholder: bearing == nil)
    ]

    MarineTelemetryHUDCard(items: items)
  }
}
