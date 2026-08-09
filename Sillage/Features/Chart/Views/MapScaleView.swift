//
//  MapScaleView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct MapScaleView: View {
  let mapScale: Measurement<UnitLength>?
  let zoomLevel: Double?

  struct ScaleData: Equatable {
    let width: CGFloat
    let measurement: Measurement<UnitLength>
  }

  @State private var scaleData: ScaleData? = nil
  @State private var showOverlay: Bool = false
  @State private var hideTask: Task<Void, Never>? = nil
  @State private var anchorZoom: Double? = nil

  private let maxScaleWidth: CGFloat = 150.0

  var body: some View {
    Group {
      if let scaleData = scaleData, showOverlay {
        VStack(alignment: .leading, spacing: 6) {
          Text(scaleData.measurement.formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1)))
          ))
            .marineFont(.instrumentData)
            .foregroundColor(.white)
          
          // Scale Bar
          ZStack(alignment: .leading) {
            // Outline line
            ScaleBarShape()
              .stroke(Color.black, style: StrokeStyle(lineWidth: 5, lineCap: .square, lineJoin: .miter))
              .frame(width: scaleData.width, height: 8)
            
            // Main white line
            ScaleBarShape()
              .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .square, lineJoin: .miter))
              .frame(width: scaleData.width, height: 8)
          }
          .animation(.linear(duration: 0.05), value: scaleData.width)
        }
        .padding(10)
        .background(Material.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .transition(.opacity)
      }
    }
    .allowsHitTesting(false)
    .animation(.easeInOut(duration: 0.3), value: showOverlay)
    .onChange(of: mapScale) { _, newValue in
      guard let newMeasurement = newValue else { return }
      updateScale(mpp: newMeasurement.converted(to: .meters).value)
    }
    .onChange(of: zoomLevel) { _, newValue in
      guard let newZoom = newValue else { return }
      
      if anchorZoom == nil {
        anchorZoom = newZoom
      }
      
      let oldZoom = anchorZoom ?? newZoom
      let zoomDelta = abs(newZoom - oldZoom)
      
      if zoomDelta > 0.05 || showOverlay {
        showOverlay = true
        hideTask?.cancel()
        hideTask = Task { @MainActor in
          do {
            try await Task.sleep(for: .seconds(1.5))
            
            anchorZoom = nil
            
            withAnimation(.easeInOut(duration: 0.3)) {
              showOverlay = false
            }
          } catch is CancellationError {
            // Tâche annulée
          } catch {
            // Ignorer les autres erreurs
          }
        }
      }
    }
    .onAppear {
      if let mpp = mapScale?.converted(to: .meters).value {
        updateScale(mpp: mpp)
      }
      if let zl = zoomLevel {
        anchorZoom = zl
      }
    }
    .onDisappear {
      hideTask?.cancel()
    }
  }
  
  private func calculateNiceValue(for maxValue: Double) -> Double {
    let logVal = floor(log10(maxValue))
    let pow10 = pow(10, logVal)
    let fraction = maxValue / pow10
    
    if fraction >= 5 {
      return 5 * pow10
    } else if fraction >= 2 {
      return 2 * pow10
    } else {
      return 1 * pow10
    }
  }

  private func updateScale(mpp: Double) {
    guard mpp > 0 else { return }
    
    let maxDistanceMeters = Measurement(value: maxScaleWidth * mpp, unit: UnitLength.meters)
    guard maxDistanceMeters.value > 0 else { return }
    
    let niceMeasurement: Measurement<UnitLength>
    
    if maxDistanceMeters < MarineFormatters.shortDistanceThreshold {
      let isMetric = Locale.current.measurementSystem == .metric
      let targetUnit: UnitLength = isMetric ? .meters : .feet
      let maxDistInTargetUnit = maxDistanceMeters.converted(to: targetUnit).value
      let niceVal = calculateNiceValue(for: maxDistInTargetUnit)
      niceMeasurement = Measurement(value: niceVal, unit: targetUnit)
    } else {
      let maxNM = maxDistanceMeters.converted(to: .nauticalMiles).value
      let niceVal = calculateNiceValue(for: maxNM)
      niceMeasurement = Measurement(value: niceVal, unit: UnitLength.nauticalMiles)
    }
    
    let width = CGFloat(niceMeasurement.converted(to: .meters).value / mpp)
    
    self.scaleData = ScaleData(width: width, measurement: niceMeasurement)
  }
}

struct ScaleBarShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    // Left tick
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    // Bottom line
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    // Right tick
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    return path
  }
}
