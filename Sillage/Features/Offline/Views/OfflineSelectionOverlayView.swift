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

/// An overlay view providing an interactive, resizable crop box for selecting an offline map region.
/// This view overlays the MapLibre view and captures drag gestures to compute geographic bounding boxes.
struct OfflineSelectionOverlayView: View {
  @Environment(OfflineSelectionViewModel.self) private var viewModel: OfflineSelectionViewModel?
  @Environment(ChartViewModel.self) private var chartViewModel: ChartViewModel?
  @Environment(\.marineTheme) private var marineTheme
  
  @State private var dragStartSize: CGSize?
  @State private var localCropSize: CGSize?
  @State private var bottomPanelHeight: CGFloat = 0
  
  var body: some View {
    if let viewModel = viewModel, viewModel.isSelectionModeActive {
      GeometryReader { geometry in
        let size = getCropSize(in: geometry, viewModel: viewModel)
        ZStack {
          MarineTheme.Colors.overlay
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .reverseMask {
              RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius)
                .frame(width: size.width, height: size.height)
            }
            
          Rectangle()
            .strokeBorder(MarineTheme.Colors.accent, lineWidth: MarineTheme.Metrics.borderWidth * 3.0)
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
            
          handles(size: size, in: geometry)
          
          VStack {
            Spacer()
            bottomPanel
              .onGeometryChange(for: CGFloat.self) { proxy in
                  proxy.size.height
              } action: { newValue in
                  self.bottomPanelHeight = newValue
              }
          }
          
          if !viewModel.offlineMapManager.isDownloading {
            VStack {
              HStack {
                Spacer()
                Button(action: {
                  viewModel.resetSelection()
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
      .ignoresSafeArea() // Critical for geometric alignment with full-screen MapLibreView
    }
  }
  
  /// Determines the active size of the crop box, falling back to initial ratios if no user resize has occurred.
  /// - Parameters:
  ///   - geometry: The screen bounds provided by the parent GeometryReader.
  ///   - viewModel: The offline selection state manager.
  /// - Returns: A constrained `CGSize` representing the current crop box dimensions.
  private func getCropSize(in geometry: GeometryProxy, viewModel: OfflineSelectionViewModel) -> CGSize {
    if let size = localCropSize {
      return size
    }
    if let size = viewModel.cropSize {
      return size
    }
    
    let ratio = viewModel.cropBoxWidthRatio
    let aspect = viewModel.cropBoxAspect
    let width = min(geometry.size.width, geometry.size.height) * ratio
    return CGSize(width: width, height: width * aspect)
  }
  
  /// Generates the four corner drag handles used to resize the crop box.
  /// - Parameters:
  ///   - size: The current size of the crop box.
  ///   - geometry: The screen bounds provided by the parent GeometryReader.
  /// - Returns: A view containing the four draggable corner handles.
  @ViewBuilder
  private func handles(size: CGSize, in geometry: GeometryProxy) -> some View {
      let halfW = size.width / 2
      let halfH = size.height / 2
      
      ZStack {
          handleCircle()
              .offset(x: -halfW, y: -halfH)
              .gesture(resizeGesture(xDir: -1, yDir: -1, currentSize: size, geometry: geometry))
              
          handleCircle()
              .offset(x: halfW, y: -halfH)
              .gesture(resizeGesture(xDir: 1, yDir: -1, currentSize: size, geometry: geometry))
              
          handleCircle()
              .offset(x: -halfW, y: halfH)
              .gesture(resizeGesture(xDir: -1, yDir: 1, currentSize: size, geometry: geometry))
              
          handleCircle()
              .offset(x: halfW, y: halfH)
              .gesture(resizeGesture(xDir: 1, yDir: 1, currentSize: size, geometry: geometry))
      }
  }
  
  /// Creates a single resize handle with a responsive hit target dynamically adjusting for Glove Mode.
  /// Note: `marineTheme.metrics.touchTarget` strictly satisfies Apple's minimum 44pt touch 
  /// guidelines, and scales up when Glove Mode is enabled for marine environments.
  /// - Returns: A standard SwiftUI View representing the interaction handle.
  private func handleCircle() -> some View {
      let touchTarget = marineTheme.metrics.touchTarget
      let handleVisualSize = marineTheme.metrics.handleSize
      return Circle()
          .fill(MarineTheme.Colors.accent)
          .frame(width: handleVisualSize, height: handleVisualSize)
          .overlay(Circle().stroke(MarineTheme.Colors.panelBackground, lineWidth: MarineTheme.Metrics.borderWidth * 2.0))
          .frame(width: touchTarget, height: touchTarget)
          .contentShape(Rectangle())
  }
  
  private func resizeGesture(xDir: CGFloat, yDir: CGFloat, currentSize: CGSize, geometry: GeometryProxy) -> some Gesture {
      DragGesture()
          .onChanged { value in
              let start = dragStartSize ?? currentSize
              if dragStartSize == nil {
                  dragStartSize = start
              }
              
              // Minimum constraint: The area cannot be smaller than 2x the touch target
              // (which scales automatically with Glove Mode). This ensures that opposing 
              // handles do not overlap and remain fully interactable even in rough seas.
              let minSize = marineTheme.metrics.touchTarget * 2.0
              
              localCropSize = calculateConstrainedSize(
                  translation: value.translation,
                  startSize: start,
                  xDir: xDir,
                  yDir: yDir,
                  geometry: geometry,
                  minSize: minSize,
                  bottomPanelHeight: bottomPanelHeight
              )
          }
          .onEnded { _ in
              if let size = localCropSize {
                  viewModel?.updateCropSize(size)
              }
              dragStartSize = nil
              localCropSize = nil
          }
  }
  
  /// Calculates the constrained dimensions of the offline selection area dynamically during a drag gesture.
  /// Enforces geometric boundaries including safe areas, the bottom panel, and touch targets to prevent layout overlapping.
  ///
  /// - Parameters:
  ///   - translation: The raw translation vector from the DragGesture.
  ///   - startSize: The initial size of the crop box at the start of the drag.
  ///   - xDir: X-axis direction multiplier (1 for right, -1 for left).
  ///   - yDir: Y-axis direction multiplier (1 for bottom, -1 for top).
  ///   - geometry: The screen bounds provided by the parent GeometryReader.
  ///   - minSize: The minimum allowed dimension (to prevent handles from merging).
  ///   - bottomPanelHeight: The dynamic height of the action panel to avoid overlap.
  /// - Returns: A CGSize structurally guaranteed to fit within the map viewport bounds.
  private func calculateConstrainedSize(
      translation: CGSize,
      startSize: CGSize,
      xDir: CGFloat,
      yDir: CGFloat,
      geometry: GeometryProxy,
      minSize: CGFloat,
      bottomPanelHeight: CGFloat
  ) -> CGSize {
      // Convert translation into growth dimensions based on gesture direction
      let dx = translation.width * xDir
      let dy = translation.height * yDir
      
      // Safety padding retrieved from the theme
      let horizontalPadding = MarineTheme.Spacing.medium + MarineTheme.Spacing.large
      let verticalPadding = MarineTheme.Spacing.medium
      
      // The symmetric expansion factor (2.0) ensures the box resizes equally from its center.
      // Because the crop box is always centered over the MapLibre viewport (driven by the ZStack layout),
      // a drag translation of `dy` at the bottom handle must be mirrored at the top handle to keep the box centered,
      // resulting in a total height growth of `dy * 2.0`.
      let symmetricExpansionFactor = 2.0
      
      // Y bounds calculations: the crop box is centered at (geometry.height / 2).
      // We must restrict the max height so the top edge doesn't cross the top safe area
      // and the bottom edge doesn't cross the bottom panel (which sits above the bottom safe area).
      let maxFromTop = geometry.size.height - symmetricExpansionFactor * (geometry.safeAreaInsets.top + verticalPadding)
      let maxFromBottom = geometry.size.height - symmetricExpansionFactor * (bottomPanelHeight + geometry.safeAreaInsets.bottom + verticalPadding)
      let maxAllowedHeight = min(maxFromTop, maxFromBottom)
      
      // X bounds calculations: restrict max width so it doesn't cross the screen edges
      let maxAllowedWidth = geometry.size.width - symmetricExpansionFactor * horizontalPadding
      
      let newWidth = max(minSize, min(maxAllowedWidth, startSize.width + dx * symmetricExpansionFactor))
      let newHeight = max(minSize, min(maxAllowedHeight, startSize.height + dy * symmetricExpansionFactor))
      
      return CGSize(width: newWidth, height: newHeight)
  }
  
  /// Displays contextual information and actions based on the current state of the offline selection (e.g., download progress or area estimation).
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
              viewModel.resetSelection()
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
              viewModel.resetSelection()
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

