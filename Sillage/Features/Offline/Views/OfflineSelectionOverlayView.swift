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
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.physicalSafeArea) private var physicalSafeArea
  
  private struct DragState {
    var translation: CGSize
    var edge: CropBoxCorner?
    
    static let inactive = DragState(translation: .zero, edge: nil)
  }
  
  @GestureState private var activeDrag: DragState = .inactive
  @State private var bottomPanelHeight: CGFloat = 0
  
  private enum CropBoxCorner {
    case topLeft, topRight, bottomLeft, bottomRight
  }
  
  var body: some View {
    if let viewModel = viewModel, viewModel.isSelectionModeActive {
      GeometryReader { geometry in
        let baseRect = getBaseRect(in: geometry, viewModel: viewModel)
        
        let rect: CGRect = {
          if let edge = activeDrag.edge {
            let minSize = marineTheme.metrics.touchTarget * 2.0
            return calculateConstrainedRect(
              translation: activeDrag.translation,
              startRect: baseRect,
              activeEdge: edge,
              geometry: geometry,
              safeArea: physicalSafeArea,
              minSize: minSize,
              bottomPanelHeight: bottomPanelHeight
            )
          } else {
            return baseRect
          }
        }()
        
        ZStack(alignment: .topLeading) {
          MarineTheme.Colors.overlay
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .reverseMask {
              RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            }
            
          Rectangle()
            .strokeBorder(MarineTheme.Colors.accent, lineWidth: MarineTheme.Metrics.borderWidth * 3.0)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
            
          handles(activeRect: rect, baseRect: baseRect, in: geometry)
          
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
        .onChange(of: geometry.size) { oldSize, newSize in
          if let current = viewModel.cropRect {
            // We use the physical safe area passed from the parent geometry reader.
            let constrained = constrainRect(current, size: newSize, safeArea: physicalSafeArea, bottomPanelHeight: bottomPanelHeight)
            if current != constrained {
              Task { @MainActor in
                viewModel.updateCropRect(constrained)
              }
            }
          }
        }
      }
      .ignoresSafeArea() // Critical for geometric alignment with full-screen MapLibreView
    }
  }
  
  /// Determines the fundamental, immutable rect of the crop box from the view model (or fallback default), completely ignoring any active drag states.
  /// This forms the immutable base reference upon which drag translations are natively applied.
  /// - Parameters:
  ///   - geometry: The screen bounds provided by the parent GeometryReader.
  ///   - viewModel: The offline selection state manager.
  /// - Returns: A constrained `CGRect` representing the persistent selection bounds.
  private func getBaseRect(in geometry: GeometryProxy, viewModel: OfflineSelectionViewModel) -> CGRect {
    if let rect = viewModel.cropRect {
      return rect
    }
    
    let ratio = viewModel.cropBoxWidthRatio
    let aspect = viewModel.cropBoxAspect
    let minSize = marineTheme.metrics.touchTarget * 2.0
    let baseSize = max(minSize, min(geometry.size.width, geometry.size.height) * ratio)
    let size = CGSize(width: baseSize, height: baseSize * aspect)
    let x = (geometry.size.width - size.width) / 2.0
    let y = (geometry.size.height - size.height) / 2.0
    
    let defaultRect = CGRect(x: x, y: y, width: size.width, height: size.height)
    return constrainRect(defaultRect, size: geometry.size, safeArea: physicalSafeArea, bottomPanelHeight: bottomPanelHeight)
  }
  
  /// Generates the four corner drag handles used to resize the crop box.
  /// - Parameters:
  ///   - activeRect: The actively rendering frame (including ongoing drag translations).
  ///   - geometry: The screen bounds provided by the parent GeometryReader.
  /// - Returns: A view containing the four draggable corner handles.
  @ViewBuilder
  private func handles(activeRect: CGRect, baseRect: CGRect, in geometry: GeometryProxy) -> some View {
    let touchTarget = max(44.0, marineTheme.metrics.touchTarget)
    let offset = touchTarget / 2.0

    Rectangle()
      .fill(Color.clear)
      .frame(width: activeRect.width, height: activeRect.height)
      .overlay(alignment: .topLeading) {
        handleCircle()
          .gesture(resizeGesture(activeEdge: .topLeft, baseRect: baseRect, geometry: geometry))
          .offset(x: -offset, y: -offset)
      }
      .overlay(alignment: .topTrailing) {
        handleCircle()
          .gesture(resizeGesture(activeEdge: .topRight, baseRect: baseRect, geometry: geometry))
          .offset(x: offset, y: -offset)
      }
      .overlay(alignment: .bottomLeading) {
        handleCircle()
          .gesture(resizeGesture(activeEdge: .bottomLeft, baseRect: baseRect, geometry: geometry))
          .offset(x: -offset, y: offset)
      }
        .overlay(alignment: .bottomTrailing) {
          handleCircle()
            .gesture(resizeGesture(activeEdge: .bottomRight, baseRect: baseRect, geometry: geometry))
            .offset(x: offset, y: offset)
      }
      .position(x: activeRect.midX, y: activeRect.midY)
  }
  
  /// Creates a single resize handle with a responsive hit target dynamically adjusting for Glove Mode.
  /// - Returns: A standard SwiftUI View representing the interaction handle.
  private func handleCircle() -> some View {
    let touchTarget = max(44.0, marineTheme.metrics.touchTarget)
    let handleVisualSize = marineTheme.metrics.handleSize

    return ZStack {
      // Invisible touch target strictly enforcing the Glove Mode constraints
      Rectangle()
        .fill(Color.clear)
        .frame(width: touchTarget, height: touchTarget)
        .contentShape(Rectangle())
        
      // Visual handle drawn over the touch target
      Circle()
        .fill(MarineTheme.Colors.accent)
        .frame(width: handleVisualSize, height: handleVisualSize)
        .overlay(Circle().stroke(MarineTheme.Colors.panelBackground, lineWidth: MarineTheme.Metrics.borderWidth * 2.0))
    }
  }
  
  /// Creates a unified DragGesture for a specific corner using GestureState for automatic lifecycle management.
  private func resizeGesture(activeEdge: CropBoxCorner, baseRect: CGRect, geometry: GeometryProxy) -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .global)
      .updating($activeDrag) { value, state, _ in
        state.translation = value.translation
        state.edge = activeEdge
      }
      .onEnded { value in
        let minSize = marineTheme.metrics.touchTarget * 2.0
        let finalRect = calculateConstrainedRect(
          translation: value.translation,
          startRect: baseRect,
          activeEdge: activeEdge,
          geometry: geometry,
          safeArea: physicalSafeArea,
          minSize: minSize,
          bottomPanelHeight: bottomPanelHeight
        )
        viewModel?.updateCropRect(finalRect)
      }
  }
  
  /// Calculates the constrained bounds of the offline selection area dynamically during a drag gesture.
  /// Enforces independent asymmetric resizing while respecting geometric boundaries including safe areas, the bottom panel, and touch targets.
  ///
  /// - Parameters:
  ///   - translation: The raw translation vector from the DragGesture.
  ///   - startRect: The initial rect of the crop box at the start of the drag.
  ///   - activeEdge: The corner currently being dragged.
  ///   - geometry: The screen bounds provided by the parent GeometryReader.
  ///   - minSize: The minimum allowed dimension (to prevent handles from merging).
  ///   - bottomPanelHeight: The dynamic height of the action panel to avoid overlap.
  /// - Returns: A CGRect structurally guaranteed to fit within the map viewport bounds.
  private func calculateConstrainedRect(
    translation: CGSize,
    startRect: CGRect,
    activeEdge: CropBoxCorner,
    geometry: GeometryProxy,
    safeArea: EdgeInsets,
    minSize: CGFloat,
    bottomPanelHeight: CGFloat
  ) -> CGRect {
    let anchorX: CGFloat
    let anchorY: CGFloat
    let activeX: CGFloat
    let activeY: CGFloat

    switch activeEdge {
    case .topLeft:
      anchorX = startRect.maxX
      anchorY = startRect.maxY
      activeX = startRect.minX
      activeY = startRect.minY
    case .topRight:
      anchorX = startRect.minX
      anchorY = startRect.maxY
      activeX = startRect.maxX
      activeY = startRect.minY
    case .bottomLeft:
      anchorX = startRect.maxX
      anchorY = startRect.minY
      activeX = startRect.minX
      activeY = startRect.maxY
    case .bottomRight:
      anchorX = startRect.minX
      anchorY = startRect.minY
      activeX = startRect.maxX
      activeY = startRect.maxY
    }

    var newActiveX = activeX + translation.width
    var newActiveY = activeY + translation.height
      
      // Safety padding retrieved from the theme
    let horizontalPadding: CGFloat = 0
    let verticalPadding: CGFloat = 0
    let touchRadius = marineTheme.metrics.touchTarget / 2.0

    // Strict constraint: Use mathematically provided physical insets

    // Bounds checks
    let minAllowedX = safeArea.leading + horizontalPadding + touchRadius
    let maxAllowedX = geometry.size.width - safeArea.trailing - horizontalPadding - touchRadius
    let minAllowedY = safeArea.top + verticalPadding + touchRadius
    let maxAllowedY = geometry.size.height - bottomPanelHeight - verticalPadding - touchRadius

    newActiveX = max(minAllowedX, min(maxAllowedX, newActiveX))
    newActiveY = max(minAllowedY, min(maxAllowedY, newActiveY))

    // Minimum size checks (prevent handle inversion and overlap)
    if anchorX > activeX {
      newActiveX = min(newActiveX, anchorX - minSize)
    } else {
      newActiveX = max(newActiveX, anchorX + minSize)
    }

    if anchorY > activeY {
      newActiveY = min(newActiveY, anchorY - minSize)
    } else {
      newActiveY = max(newActiveY, anchorY + minSize)
    }

    return CGRect(
      x: min(anchorX, newActiveX),
      y: min(anchorY, newActiveY),
      width: abs(anchorX - newActiveX),
      height: abs(anchorY - newActiveY)
    )
  }
  
  /// Clamps an existing rect into the current screen constraints (used for device rotation).
  private func constrainRect(_ rect: CGRect, size: CGSize, safeArea: EdgeInsets, bottomPanelHeight: CGFloat) -> CGRect {
    let horizontalPadding = MarineTheme.Spacing.medium
    let verticalPadding = MarineTheme.Spacing.small
    let minSize = marineTheme.metrics.touchTarget * 2.0
    let touchRadius = marineTheme.metrics.touchTarget / 2.0
    
    let minAllowedX = safeArea.leading + horizontalPadding + touchRadius
    let maxAllowedX = size.width - safeArea.trailing - horizontalPadding - touchRadius
    let minAllowedY = safeArea.top + verticalPadding + touchRadius
    let maxAllowedY = size.height - bottomPanelHeight - verticalPadding - touchRadius
    
    let newX = max(minAllowedX, min(maxAllowedX - minSize, rect.minX))
    let newY = max(minAllowedY, min(maxAllowedY - minSize, rect.minY))
    
    var newWidth = min(rect.width, maxAllowedX - newX)
    var newHeight = min(rect.height, maxAllowedY - newY)
    
    newWidth = max(minSize, newWidth)
    newHeight = max(minSize, newHeight)
    
    return CGRect(x: newX, y: newY, width: newWidth, height: newHeight)
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

