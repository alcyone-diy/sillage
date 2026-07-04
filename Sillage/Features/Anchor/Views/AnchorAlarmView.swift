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

public struct AnchorAlarmView: View {
  @Environment(AnchorViewModel.self) private var viewModel
  
  @Environment(\.marineTheme) private var marineTheme
  
  private let distanceFormatter: MeasurementFormatter = {
    let formatter = MeasurementFormatter()
    formatter.unitOptions = .providedUnit
    formatter.numberFormatter.maximumFractionDigits = 0
    return formatter
  }()
  
  public init() {}
  
  public var body: some View {
    Form {
      Section {
        VStack(spacing: 24) {
          if viewModel.status == .inactive {
            setupStateView
          } else {
            armedStateView
          }
        }
        .padding(.vertical, 8)
      }
      .listRowBackground(MarineTheme.Colors.surfaceBackground)
    }
    .background(MarineTheme.Colors.panelBackground.opacity(0.95))
    .cornerRadius(MarineTheme.Metrics.cornerRadius)
    .navigationTitle("Anchor Alarm")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      viewModel.isSetupModeActive = true
    }
    .onDisappear {
      viewModel.isSetupModeActive = false
    }
  }
  
  // MARK: - Setup State
  @ViewBuilder
  private var setupStateView: some View {
    VStack(spacing: MarineTheme.Spacing.large) {
      if viewModel.isAnchorDropped {
        Text("Anchor Dropped")
          .font(.headline)
          .foregroundColor(MarineTheme.Colors.textSecondary)
      } else {
        Text("Setup Anchor")
          .font(.headline)
          .foregroundColor(MarineTheme.Colors.textSecondary)
      }
      
      HStack(spacing: MarineTheme.Spacing.large) {
        Button(action: { viewModel.decrementRadius() }) {
          Image(systemName: "minus")
            .font(.title)
            .frame(width: marineTheme.minTouchTarget, height: marineTheme.minTouchTarget)
            .background(MarineTheme.Colors.disabledBackground)
            .foregroundColor(MarineTheme.Colors.textSecondary)
            .cornerRadius(MarineTheme.Metrics.cornerRadius)
        }
        .buttonStyle(MarineButtonStyle())
        
        VStack {
          Text(distanceFormatter.string(from: viewModel.configuredRadius.converted(to: .meters)))
            .font(.system(size: 48, weight: .bold, design: .monospaced))
            .foregroundColor(MarineTheme.Colors.textSecondary)
        }
        .frame(minWidth: 100)
        
        Button(action: { viewModel.incrementRadius() }) {
          Image(systemName: "plus")
            .font(.title)
            .frame(width: marineTheme.minTouchTarget, height: marineTheme.minTouchTarget)
            .background(MarineTheme.Colors.disabledBackground)
            .foregroundColor(MarineTheme.Colors.textSecondary)
            .cornerRadius(MarineTheme.Metrics.cornerRadius)
        }
        .buttonStyle(MarineButtonStyle())
      }
      
      if !viewModel.isAnchorDropped {
        Button(action: {
          viewModel.dropAnchor()
        }) {
          Label("Drop Anchor", systemImage: "water.waves.and.arrow.down")
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: marineTheme.minTouchTarget)
            .background(MarineTheme.Colors.primary)
            .foregroundColor(MarineTheme.Colors.onPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(MarineButtonStyle())
        
        if let error = viewModel.anchorDropError {
          HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(error)
              .font(.subheadline.bold())
          }
          .foregroundColor(MarineTheme.Colors.destructive)
          .padding()
          .background(MarineTheme.Colors.destructiveBackground)
          .cornerRadius(MarineTheme.Metrics.cornerRadius)
        }
      } else {
        Button(action: {
          viewModel.armAlarm()
        }) {
          Label("Arm Alarm", systemImage: "bell.fill")
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: marineTheme.minTouchTarget)
            .background(MarineTheme.Colors.vectorHDG)
            .foregroundColor(MarineTheme.Colors.onPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(MarineButtonStyle())
        
        Button(action: {
          viewModel.cancelDrop()
        }) {
          Text("CANCEL")
            .font(.headline)
            .foregroundColor(MarineTheme.Colors.cancelAction)
        }
        .padding(.top, MarineTheme.Spacing.small)
      }
    }
  }
  
  // MARK: - Armed State
  @ViewBuilder
  private var armedStateView: some View {
    VStack(spacing: MarineTheme.Spacing.large) {
      HStack {
        Text(viewModel.status == .dragging ? "DRAGGING!" : "ARMED")
          .font(.headline)
          .foregroundColor(viewModel.status == .dragging ? MarineTheme.Colors.destructive : MarineTheme.Colors.vectorHDG)
        
        Spacer()
        
        if let accuracy = viewModel.gpsAccuracy?.converted(to: .meters).value {
          if accuracy > 15 {
            HStack(spacing: 4) {
              Image(systemName: "exclamationmark.triangle.fill")
              Text(String(format: "GPS: %.0fm", accuracy))
            }
            .font(.caption.bold())
            .foregroundColor(MarineTheme.Colors.warning)
            .padding(6)
            .background(MarineTheme.Colors.warning.opacity(0.2))
            .cornerRadius(6)
          }
        }
      }
      
      HStack {
        VStack(alignment: .leading) {
          Text("Distance")
            .font(.subheadline)
            .foregroundColor(MarineTheme.Colors.textSecondary)
          if let dist = viewModel.currentDistance {
            Text(distanceFormatter.string(from: dist.converted(to: .meters)))
              .font(.system(size: 32, weight: .bold, design: .monospaced))
              .foregroundColor(viewModel.status == .dragging ? MarineTheme.Colors.destructive : MarineTheme.Colors.primary)
          } else {
            Text("-- m")
              .font(.system(size: 32, weight: .bold, design: .monospaced))
              .foregroundColor(MarineTheme.Colors.primary)
          }
        }
        Spacer()
        VStack(alignment: .trailing) {
          Text("Radius")
            .font(.subheadline)
            .foregroundColor(MarineTheme.Colors.textSecondary)
          Text(distanceFormatter.string(from: viewModel.configuredRadius.converted(to: .meters)))
            .font(.system(size: 32, weight: .regular, design: .monospaced))
            .foregroundColor(MarineTheme.Colors.textSecondary)
        }
      }
      
      SlideToDisarmButton(action: {
        viewModel.disarmAlarm()
      })
    }
  }
}

// MARK: - Slide to Disarm Component
fileprivate struct SlideToDisarmButton: View {
  let action: () -> Void
  
  @State private var offset: CGFloat = 0.0
  @Environment(\.marineTheme) private var marineTheme
  
  var body: some View {
    GeometryReader { geo in
      let thumbSize: CGFloat = marineTheme.minTouchTarget
      let maxOffset = max(0, geo.size.width - thumbSize)
      
      ZStack(alignment: .leading) {
        // Track background
        Rectangle()
          .fill(MarineTheme.Colors.destructiveBackground)
          .cornerRadius(MarineTheme.Metrics.cornerRadius)
        
        // Instructional Text
        Text("SLIDE TO DISARM")
          .font(.title3.bold())
          .foregroundColor(MarineTheme.Colors.destructive)
          .frame(maxWidth: .infinity)
          .opacity(maxOffset > 0 ? 1.0 - Double(offset / maxOffset) : 1.0)
        
        // Draggable Thumb
        ZStack {
          Rectangle()
            .fill(MarineTheme.Colors.destructive)
            .cornerRadius(MarineTheme.Metrics.cornerRadius)
            .frame(width: thumbSize, height: thumbSize)
          
          Image(systemName: "chevron.right.2")
            .font(.title2.bold())
            .foregroundColor(MarineTheme.Colors.onPrimary)
        }
        .offset(x: offset)
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              let newOffset = value.translation.width
              offset = min(max(newOffset, 0), maxOffset)
            }
            .onEnded { value in
              if offset >= maxOffset - 15 {
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
  }
}
