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
  @Environment(ChartViewModel.self) private var chartViewModel: ChartViewModel?
  @Environment(\.marineTheme) private var marineTheme
  
  var body: some View {
    if let viewModel = viewModel, viewModel.isSelectionModeActive {
      GeometryReader { geometry in
        ZStack {
          MarineTheme.Colors.overlay
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .reverseMask {
              RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius)
                .frame(width: cropWidth(in: geometry), height: cropHeight(in: geometry))
            }
          
          VStack {
            Spacer()
            bottomPanel
          }
          
          if !viewModel.offlineMapManager.isDownloading {
            VStack {
              HStack {
                Spacer()
                Button(action: {
                  viewModel.close()
                }) {
                  Image(systemName: "xmark")
                    .font(.title3.weight(.bold))
                    .foregroundColor(MarineTheme.Colors.textPrimary)
                    .padding(MarineTheme.Spacing.small)
                    .background(Circle().fill(MarineTheme.Colors.overlay))
                }
                .padding()
                .padding(.top, MarineTheme.Spacing.large) // Safe area spacing if needed
              }
              Spacer()
            }
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
      VStack(spacing: MarineTheme.Spacing.medium) {
        if let error = viewModel.offlineMapManager.downloadError {
          Text(error)
            .marineFont(.footnote)
            .foregroundColor(MarineTheme.Colors.destructive)
            .lineLimit(nil)
            .multilineTextAlignment(.center)
        } else if let area = viewModel.estimatedArea {
          Text(area.marineFormatted)
            .marineFont(.title2)
            .foregroundColor(viewModel.isValidSize ? .primary : MarineTheme.Colors.destructive)
        } else {
          Text("Calculating area...")
            .marineFont(.body)
            .foregroundColor(MarineTheme.Colors.textSecondary)
        }
        
        if viewModel.offlineMapManager.isDownloadComplete {
          VStack(spacing: MarineTheme.Spacing.medium) {
            Text("Download complete")
              .marineFont(.headline)
              .foregroundColor(MarineTheme.Colors.accent)
            
            Button(action: {
              viewModel.close()
            }) {
              Text("Close")
                .marineFont(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(MarineTheme.Colors.accent)
                .cornerRadius(MarineTheme.Metrics.cornerRadius)
            }
            .buttonStyle(MarineButtonStyle())
          }
        } else if viewModel.offlineMapManager.isDownloading {
          let manager = viewModel.offlineMapManager
          HStack(spacing: MarineTheme.Spacing.medium) {
            ProgressView(value: manager.downloadProgress, total: 1.0)
              .progressViewStyle(LinearProgressViewStyle(tint: .white))
              .animation(.easeInOut, value: manager.downloadProgress)
            
            Button(action: {
              viewModel.cancelDownload()
              viewModel.close()
            }) {
              Image(systemName: "xmark.circle.fill")
                .foregroundColor(MarineTheme.Colors.destructive)
                .imageScale(.large)
            }
          }
          .padding()
          .frame(maxWidth: .infinity)
          .background(MarineTheme.Colors.accent)
          .cornerRadius(MarineTheme.Metrics.cornerRadius)
        } else {
          Button(action: {
            viewModel.startDownload(chartSource: chartViewModel?.currentChartSource)
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
      }
      .padding()
      .background(MarineTheme.Colors.panelBackground)
      .cornerRadius(MarineTheme.Metrics.cornerRadius)
      .padding()
      .padding(.bottom, MarineTheme.Spacing.medium)
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
