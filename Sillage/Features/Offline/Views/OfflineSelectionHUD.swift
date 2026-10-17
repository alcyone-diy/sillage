//
//  OfflineSelectionHUD.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// A HUD overlay presented during offline chart region selection.
/// The geographic selection zone and resize handles are rendered directly on the MapLibre canvas,
/// enabling free map panning and zooming without altering selection limits.
struct OfflineSelectionHUD: View {
  @Environment(OfflineSelectionViewModel.self) private var viewModel: OfflineSelectionViewModel?
  @Environment(ChartViewModel.self) private var chartViewModel: ChartViewModel?
  @Environment(PanelManagerViewModel.self) private var panelManagerViewModel: PanelManagerViewModel?
  @Environment(\.marineTheme) private var marineTheme

  var body: some View {
    if let viewModel = viewModel, viewModel.isSelectionModeActive {
      ZStack(alignment: .topLeading) {
        // Saved Offline Region Labels (Centered inside each offline package area)
        if let chartVM = chartViewModel, !chartVM.offlineRegionScreenLabels.isEmpty {
          ForEach(chartVM.offlineRegionScreenLabels) { label in
            if label.isVisible {
              OfflineRegionBadgeView(name: label.name)
                .position(x: label.screenPoint.x, y: label.screenPoint.y)
                .transition(.opacity)
            }
          }
          .allowsHitTesting(false)
        }

        VStack {
          Spacer()
          bottomPanel
        }
      }
      .ignoresSafeArea()
    }
  }

  /// Technical Design Choice: Modular Marine Action Card for Region Download
  ///
  /// Uses `MarineActionConfirmationCard` to standardize confirmation and cancellation across marine overlays:
  /// 1. **Glove Mode & Fitts's Law:** Enforces minimum touch targets (66pt+ in Glove Mode) on both Cancel and Download buttons for operation under rough sea conditions.
  /// 2. **High Glare Backdrop:** Employs `Material.ultraThinMaterial` backdrop to preserve chart context while ensuring high contrast readability under direct sunlight.
  /// 3. **Dynamic Feedback:** Real-time surface area calculation is rendered dynamically in the card's header content, visually alerting the user via `marineTheme.colors.destructive` when size limits are exceeded.
  @ViewBuilder
  private var bottomPanel: some View {
    if let viewModel = viewModel {
      MarineActionConfirmationCard(
        cancelTitle: "Cancel",
        cancelIcon: "xmark",
        onCancel: {
          viewModel.resetSelection()
          panelManagerViewModel?.openOfflineChartsPanel()
        },
        confirmTitle: "Download",
        confirmIcon: "arrow.down.circle",
        isConfirmDisabled: !viewModel.isValidSize,
        onConfirm: {
          viewModel.startDownload()
          viewModel.isSelectionModeActive = false
        },
        onHeightChange: { height in
          panelManagerViewModel?.actionConfirmationCardHeight = height
          panelManagerViewModel?.actionConfirmationCardBottomPadding = MarineTheme.Spacing.overlayCardBottom
        }
      ) {
        VStack(spacing: MarineTheme.Spacing.small) {
          if let area = viewModel.estimatedArea {
            Text(area.marineFormatted)
              .marineFont(.title2)
              .foregroundColor(viewModel.isValidSize ? marineTheme.colors.textPrimary : marineTheme.colors.destructive)
          } else {
            Text("Calculating area...")
              .marineFont(.body)
              .foregroundColor(marineTheme.colors.textSecondary)
          }
        }
      }
      .padding(.horizontal, MarineTheme.Spacing.medium)
      .padding(.bottom, MarineTheme.Spacing.overlayCardBottom)
      .onAppear {
        chartViewModel?.isActionConfirmationCardActive = true
      }
      .onDisappear {
        chartViewModel?.isActionConfirmationCardActive = false
      }
    }
  }
}
