//
//  AnchorAdjustHUD.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import CoreLocation
import OSLog

/// Overlay view providing real-time crosshair aiming and sightline telemetry for manual anchor position adjustment.
public struct AnchorAdjustHUD: View {
  @Environment(AnchorViewModel.self) private var anchorViewModel
  @Environment(PanelManagerViewModel.self) private var panelManagerViewModel: PanelManagerViewModel?

  public init() {}

  public var body: some View {
    MarinePositionPickerHUD(
      title: "Drag map to adjust anchor position",
      onCancel: {
        Logger.anchor.info("User canceled anchor position adjustment")
        anchorViewModel.cancelAdjustAnchor()
        panelManagerViewModel?.openAnchorAlarmPanel()
      },
      onConfirm: { newCoordinate in
        Logger.anchor.info("User confirmed new anchor coordinate at (\(newCoordinate.latitude, privacy: .public), \(newCoordinate.longitude, privacy: .public))")
        anchorViewModel.confirmAdjustAnchor(to: newCoordinate)
        panelManagerViewModel?.openAnchorAlarmPanel()
      }
    )
  }
}
