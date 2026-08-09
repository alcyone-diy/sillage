//
//  AnchorAlarmView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-04.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import OSLog

public struct AnchorAlarmView: View {
  @Environment(AnchorViewModel.self) private var viewModel
  @Environment(ChartViewModel.self) private var chartViewModel: ChartViewModel?
  @Environment(PanelManagerViewModel.self) private var panelManagerViewModel: PanelManagerViewModel?
  @Environment(\.marineTheme) private var marineTheme
  @Environment(PermissionService.self) private var permissionService
  @Environment(\.locale) private var locale

  public init() {}
  
  private var isArmed: Bool {
    if case .armed = viewModel.state { return true }
    return false
  }
  
  private var isDragging: Bool {
    if case .armed(let dragging) = viewModel.state { return dragging }
    return false
  }
  
  private var navigationTitleText: LocalizedStringKey {
    switch viewModel.state {
    case .setup: return "Anchor Setup"
    case .droppedPendingPosition: return "Waiting for GPS..."
    case .dropped: return "Anchor Dropped"
    case .armed(let dragging): return dragging ? "DRAGGING ALERT" : "Alarm Armed"
    }
  }
  
  public var body: some View {
    @Bindable var viewModel = viewModel
    
    Form {
      Section {
        VStack(spacing: MarineTheme.Spacing.large) {
          if hasHeaderAlerts {
            headerSection
          }
          
          bodySection
          
          Divider()
            .background(marineTheme.colors.surfaceBackground)
          
          footerSection
        }
        .padding(.vertical, MarineTheme.Spacing.small)
      }
      .listRowBackground(marineTheme.colors.surfaceBackground)
    }
    .marineListBackground()
    .listSectionSpacing(.compact)
    .navigationTitle(navigationTitleText)
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      viewModel.isSetupModeActive = true
    }
    .onDisappear {
      viewModel.isSetupModeActive = false
    }
    .sheet(item: $viewModel.permissionGateType) { gateType in
      PermissionGateView(type: gateType)
        .presentationDetents([.medium, .large])
    }
    .onChange(of: permissionService.notificationStatus) { _, status in
      if status == .authorized {
        viewModel.finalizePendingAction()
        viewModel.permissionGateType = nil
      }
    }
  }
  
  // MARK: - 1. HEADER (Alerts)
  private var hasHeaderAlerts: Bool {
    if case .droppedPendingPosition = viewModel.state { return true }
    if isDragging && viewModel.triggerReasonDescription != nil { return true }
    if let initialAcc = viewModel.initialAccuracy?.converted(to: .meters).value, initialAcc > 15.0 { return true }
    if viewModel.isGPSAccuracyDegraded && viewModel.gpsAccuracy != nil { return true }
    if viewModel.anchorDropError != nil { return true }
    return false
  }

  @ViewBuilder
  private var headerSection: some View {
    if hasHeaderAlerts {
      VStack(spacing: MarineTheme.Spacing.small) {
        if case .droppedPendingPosition = viewModel.state {
          HStack(spacing: 6) {
            ProgressView()
              .tint(marineTheme.colors.warning)
            Text("Anchor dropped. Position will lock automatically on first GPS fix.")
              .font(.caption.bold())
              .multilineTextAlignment(.center)
          }
          .foregroundColor(marineTheme.colors.warning)
          .padding(MarineTheme.Spacing.small)
          .background(marineTheme.colors.warning.opacity(0.2))
          .cornerRadius(MarineTheme.Metrics.cornerRadius)
        } else if isDragging, let reasonDesc = viewModel.triggerReasonDescription {
          HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(reasonDesc)
              .font(.subheadline.bold())
              .multilineTextAlignment(.center)
          }
          .foregroundColor(marineTheme.colors.destructive)
          .padding(MarineTheme.Spacing.small)
          .background(marineTheme.colors.destructiveBackground)
          .cornerRadius(MarineTheme.Metrics.cornerRadius)
        } else if let initialAcc = viewModel.initialAccuracy, initialAcc.converted(to: .meters).value > 15.0 {
          HStack(spacing: 4) {
            Image(systemName: "info.circle.fill")
            Text("Anchor dropped with degraded accuracy (±\(initialAcc.marineAnchorDistanceFormatted(locale: locale)))")
          }
          .font(.caption.bold())
          .foregroundColor(marineTheme.colors.warning)
          .padding(MarineTheme.Spacing.small)
          .background(marineTheme.colors.warning.opacity(0.2))
          .cornerRadius(MarineTheme.Metrics.cornerRadius)
        } else if viewModel.isGPSAccuracyDegraded, let accuracy = viewModel.gpsAccuracy {
          HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("GPS: \(accuracy.marineAnchorDistanceFormatted(locale: locale))")
          }
          .font(.caption.bold())
          .foregroundColor(marineTheme.colors.warning)
          .padding(MarineTheme.Spacing.small)
          .background(marineTheme.colors.warning.opacity(0.2))
          .cornerRadius(MarineTheme.Metrics.cornerRadius)
        } else if let error = viewModel.anchorDropError {
          HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(error)
              .font(.subheadline.bold())
          }
          .foregroundColor(marineTheme.colors.destructive)
          .padding(MarineTheme.Spacing.small)
          .background(marineTheme.colors.destructiveBackground)
          .cornerRadius(MarineTheme.Metrics.cornerRadius)
        }
      }
    }
  }
  
  // MARK: - 2. BODY (Telemetry)
  @ViewBuilder
  private var bodySection: some View {
    VStack(spacing: MarineTheme.Spacing.large) {
      // Coordinates line
      HStack {
        Text("Anchor:")
          .font(.subheadline)
          .foregroundColor(marineTheme.colors.textSecondary)
        Spacer()
        if let coord = viewModel.anchorCoordinate {
          Text(coord.formatted(.marineCoordinate))
            .font(.system(.subheadline, design: .monospaced).bold())
            .foregroundColor(marineTheme.colors.textSecondary)
        } else {
          Text("--")
            .font(.system(.subheadline, design: .monospaced).bold())
            .foregroundColor(marineTheme.colors.textSecondary)
        }
      }
      
      // Distance vs Radius
      HStack(alignment: .top) {
        // Left: Distance
        VStack(alignment: .leading, spacing: MarineTheme.Spacing.small) {
          Text("Distance")
            .font(.subheadline)
            .foregroundColor(marineTheme.colors.textSecondary)
          
          if let dist = viewModel.currentDistance {
            Text(dist.marineAnchorDistanceFormatted(locale: locale))
              .font(.system(.title, design: .default).monospacedDigit().bold())
              .foregroundColor(isDragging ? marineTheme.colors.destructive : marineTheme.colors.primary)
              .frame(height: marineTheme.minTouchTarget)
          } else {
            Text("--")
              .font(.system(.title, design: .default).monospacedDigit().bold())
              .foregroundColor(marineTheme.colors.primary)
              .frame(height: marineTheme.minTouchTarget)
          }
        }
        
        Spacer()
        
        // Right: Radius (Stepper inline)
        VStack(alignment: .trailing, spacing: MarineTheme.Spacing.small) {
          Text("Radius")
            .font(.subheadline)
            .foregroundColor(marineTheme.colors.textSecondary)
          
          HStack(spacing: MarineTheme.Spacing.small) {
            Button(action: { viewModel.decrementRadius(locale: locale) }) {
              Image(systemName: "minus")
                .font(.title3.bold())
                .frame(width: marineTheme.minTouchTarget, height: marineTheme.minTouchTarget)
                .background(marineTheme.colors.disabledBackground)
                .foregroundColor(marineTheme.colors.textSecondary)
                .cornerRadius(MarineTheme.Metrics.cornerRadius)
            }
            .buttonStyle(MarineButtonStyle())
            .opacity(isArmed ? 0.3 : 1.0)
            .disabled(isArmed)
            
            Text(viewModel.configuredRadius.marineAnchorDistanceFormatted(locale: locale))
              .font(.system(.title, design: .default).monospacedDigit().bold())
              .foregroundColor(marineTheme.colors.textSecondary)
              .frame(width: 90, alignment: .center)
              
            Button(action: { viewModel.incrementRadius(locale: locale) }) {
              Image(systemName: "plus")
                .font(.title3.bold())
                .frame(width: marineTheme.minTouchTarget, height: marineTheme.minTouchTarget)
                .background(marineTheme.colors.disabledBackground)
                .foregroundColor(marineTheme.colors.textSecondary)
                .cornerRadius(MarineTheme.Metrics.cornerRadius)
            }
            .buttonStyle(MarineButtonStyle())
            .opacity(isArmed ? 0.3 : 1.0)
            .disabled(isArmed)
          }
        }
      }
    }
  }
  
  // MARK: - 3. FOOTER (Actions)
  @ViewBuilder
  private var footerSection: some View {
    VStack(spacing: MarineTheme.Spacing.large) {
      switch viewModel.state {
      case .setup:
        Button(action: {
          Logger.anchor.info("User requested to drop anchor")
          // Center the map camera on the vessel while preserving current zoom level
          chartViewModel?.centerOnUserLocation()
          viewModel.startPreparingDropAnchor()
          panelManagerViewModel?.closePanel()
        }) {
          Label("Select Drop Point", systemImage: "water.waves.and.arrow.down")
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: marineTheme.minTouchTarget)
            .background(marineTheme.colors.primary)
            .foregroundColor(marineTheme.colors.onPrimary)
            .clipShape(RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(MarineButtonStyle())
        
      case .droppedPendingPosition:
        Button(action: {
          Logger.anchor.info("User requested to arm alarm while position is pending")
          viewModel.requestArmAlarm(in: permissionService)
        }) {
          Label("Arm Alarm", systemImage: "bell.fill")
            .font(.title3.bold())
            .frame(maxWidth: .infinity, minHeight: marineTheme.minTouchTarget)
            .background(marineTheme.colors.vectorHDG)
            .foregroundColor(marineTheme.colors.onPrimary)
            .clipShape(RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(MarineButtonStyle())
        .disabled(viewModel.anchorCoordinate == nil)
        .opacity(viewModel.anchorCoordinate == nil ? 0.5 : 1.0)
        
        SlideActionButton(
          customTrackColor: marineTheme.colors.disabledBackground,
          customThumbColor: marineTheme.colors.textSecondary,
          customTextColor: marineTheme.colors.textSecondary,
          title: "SLIDE TO CANCEL",
          action: {
            Logger.anchor.info("User requested to cancel pending drop")
            viewModel.cancelDrop()
          }
        )

      case .dropped:
        Button(action: {
          Logger.anchor.info("User requested to arm alarm")
          viewModel.requestArmAlarm(in: permissionService)
        }) {
          Label("Arm Alarm", systemImage: "bell.fill")
            .font(.title3.bold())
            .frame(maxWidth: .infinity, minHeight: marineTheme.minTouchTarget)
            .background(marineTheme.colors.vectorHDG)
            .foregroundColor(marineTheme.colors.onPrimary)
            .clipShape(RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(MarineButtonStyle())
        
        adjustPositionButton
        
        SlideActionButton(
          customTrackColor: marineTheme.colors.disabledBackground,
          customThumbColor: marineTheme.colors.textSecondary,
          customTextColor: marineTheme.colors.textSecondary,
          title: "SLIDE TO CANCEL",
          action: {
            Logger.anchor.info("User requested to cancel drop")
            viewModel.cancelDrop()
          }
        )
        
      case .armed:
        adjustPositionButton
        
        SlideActionButton(isDragging: isDragging, title: "SLIDE TO DISARM", action: {
          Logger.anchor.info("User requested to disarm alarm")
          viewModel.disarmAlarm()
        })
      }
    }
  }
  
  @ViewBuilder
  private var adjustPositionButton: some View {
    Button(action: {
      Logger.anchor.info("User requested to adjust anchor position")
      chartViewModel?.trackingMode = .free
      if let coord = viewModel.anchorCoordinate {
        chartViewModel?.centerOnAnchor(coordinate: coord)
      } else if let vesselCoord = chartViewModel?.currentCoordinate {
        chartViewModel?.centerOnAnchor(coordinate: vesselCoord)
      }
      viewModel.startAdjustingAnchor()
      panelManagerViewModel?.closePanel()
    }) {
      Label("Adjust Position", systemImage: "scope")
        .font(.headline)
        .frame(maxWidth: .infinity, minHeight: marineTheme.minTouchTarget)
        .background(marineTheme.colors.surfaceBackground)
        .foregroundColor(marineTheme.colors.primary)
        .overlay(
          RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius)
            .stroke(marineTheme.colors.primary, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous))
    }
    .buttonStyle(MarineButtonStyle())
  }
}

// MARK: - Slide Action Component
fileprivate struct SlideActionButton: View {
  @Environment(\.marineTheme) private var marineTheme

  var isDragging: Bool = false
  var customTrackColor: Color?
  var customThumbColor: Color?
  var customTextColor: Color?
  let title: LocalizedStringKey
  let action: () -> Void
  
  @State private var offset: CGFloat = 0.0
  private var trackColor: Color { customTrackColor ?? marineTheme.colors.destructiveBackground }
  private var thumbColor: Color { customThumbColor ?? marineTheme.colors.destructive }
  private var textColor: Color { customTextColor ?? marineTheme.colors.destructive }
  
  var body: some View {
    GeometryReader { geo in
      let thumbSize: CGFloat = marineTheme.minTouchTarget
      let maxOffset = max(0, geo.size.width - thumbSize)
      
      ZStack(alignment: .leading) {
        // Track background
        Rectangle()
          .fill(trackColor)
          .cornerRadius(MarineTheme.Metrics.cornerRadius)
        
        // Instructional Text
        Text(title)
          .font(.title3.bold())
          .foregroundColor(textColor)
          .frame(maxWidth: .infinity)
          .opacity(maxOffset > 0 ? 1.0 - Double(offset / maxOffset) : 1.0)
        
        // Draggable Thumb
        ZStack {
          Rectangle()
            .fill(thumbColor)
            .cornerRadius(MarineTheme.Metrics.cornerRadius)
            .frame(width: thumbSize, height: thumbSize)
          
          Image(systemName: "chevron.right.2")
            .font(.title2.bold())
            .foregroundColor(marineTheme.colors.onPrimary)
        }
        .offset(x: offset)
        .gesture(
          DragGesture(minimumDistance: 30)
            .onChanged { value in
              let newOffset = value.translation.width
              offset = min(max(newOffset, 0), maxOffset)
            }
            .onEnded { value in
              if offset >= maxOffset * 0.9 {
                action()
                withAnimation(.spring()) { offset = 0 }
              } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                  offset = 0
                }
              }
            }
        )
      }
    }
    .frame(height: marineTheme.minTouchTarget)
    .phaseAnimator(isDragging ? [false, true] : [false]) { content, phase in
      content
        .scaleEffect(phase ? 1.02 : 1.0)
        .opacity(phase ? 0.8 : 1.0)
    } animation: { _ in
      .easeInOut(duration: 0.6)
    }
  }
}
