//
//  WaypointAdjustHUD.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-17.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import CoreLocation
import OSLog

/// Overlay view providing real-time crosshair aiming and sightline telemetry for manual waypoint position adjustment.
public struct WaypointAdjustHUD: View {
  @Environment(ChartViewModel.self) private var chartViewModel

  public init() {}

  public var body: some View {
    MarinePositionPickerHUD(
      title: "Drag map to adjust waypoint position",
      onCancel: {
        Logger.navigation.info("User canceled waypoint position adjustment")
        chartViewModel.cancelWaypointPositionAdjustment()
      },
      onConfirm: { newCoordinate in
        Logger.navigation.info("User confirmed waypoint position adjustment to (\(newCoordinate.latitude, privacy: .public), \(newCoordinate.longitude, privacy: .public))")
        chartViewModel.confirmWaypointPositionAdjustment(to: newCoordinate)
      }
    )
  }
}
