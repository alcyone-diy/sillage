//
//  OfflineSelectionOverlayView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct OfflineSelectionOverlayView: View {
  @Environment(OfflineSelectionViewModel.self) private var viewModel: OfflineSelectionViewModel?
  @Environment(\.marineTheme) private var marineTheme
  
  var body: some View {
    if let viewModel = viewModel, viewModel.isSelectionModeActive {
      GeometryReader { geometry in
        ZStack {
          MarineTheme.Colors.overlay
            .ignoresSafeArea()
            .reverseMask {
              RoundedRectangle(cornerRadius: 12)
                .frame(width: cropWidth(in: geometry), height: cropHeight(in: geometry))
            }
          
          VStack {
            Spacer()
            bottomPanel
          }
        }
      }
    }
  }
  
  private func cropWidth(in geometry: GeometryProxy) -> CGFloat {
    let ratio = viewModel?.cropBoxWidthRatio ?? 0.7
    return min(geometry.size.width, geometry.size.height) * ratio
  }
  
  private func cropHeight(in geometry: GeometryProxy) -> CGFloat {
    let aspect = viewModel?.cropBoxAspect ?? 0.75
    return cropWidth(in: geometry) * aspect
  }
  
  @ViewBuilder
  private var bottomPanel: some View {
    if let viewModel = viewModel {
      VStack(spacing: 16) {
        if let area = viewModel.estimatedArea {
          Text(area.marineFormatted)
            .marineFont(.title2)
            .foregroundColor(viewModel.isValidSize ? .primary : MarineTheme.Colors.destructive)
        } else {
          Text("Calculating area...")
            .marineFont(.body)
            .foregroundColor(MarineTheme.Colors.textSecondary)
        }
        
        Button(action: {
          // Step 2: Trigger download
        }) {
          Text("Download")
            .marineFont(.headline)
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(viewModel.isValidSize ? MarineTheme.Colors.accent : MarineTheme.Colors.inactive)
            .cornerRadius(MarineTheme.Metrics.cornerRadius)
        }
        .buttonStyle(MarineButtonStyle())
        .disabled(!viewModel.isValidSize)
      }
      .padding()
      .background(MarineTheme.Colors.panelBackground)
      .cornerRadius(MarineTheme.Metrics.cornerRadius)
      .padding()
      .padding(.bottom, 20)
    }
  }
}

fileprivate extension View {
  func reverseMask<Mask: View>(
    alignment: Alignment = .center,
    @ViewBuilder _ mask: () -> Mask
  ) -> some View {
    self.mask(
      ZStack(alignment: alignment) {
        Color.black
        mask().blendMode(.destinationOut)
      }
      .compositingGroup()
    )
  }
}
