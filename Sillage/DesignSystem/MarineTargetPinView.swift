//
//  MarineTargetPinView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-14.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Standardized high-precision nautical inverted map pin view used for interactive map target selection.
/// Points upwards (`direction: .up`), positioning the precision focal reticle and needle tip directly
/// on the geographic coordinate while resting the circular grip badge below under the user's finger.
public struct MarineTargetPinView: View {
  @Environment(\.marineTheme) private var marineTheme

  public static let pinWidth: CGFloat = MarineMapPinShape.defaultWidth
  public static let pinHeight: CGFloat = MarineMapPinShape.defaultHeight
  public static let headCenterOffset: CGFloat = MarineMapPinShape.needleToHeadCenterOffset

  private static let dragScale: CGFloat = 1.08
  private static let strokeLineWidth: CGFloat = 2.0
  private static let shadowRadius: CGFloat = 4.0
  private static let shadowY: CGFloat = 3.0
  private static let gripIconSize: CGFloat = 16.0
  private static let reticleRingSize: CGFloat = 8.0
  private static let reticleContrastStrokeWidth: CGFloat = 2.5
  private static let reticleStrokeWidth: CGFloat = 1.5
  private static let reticleCenterDotSize: CGFloat = 2.5

  public var isDragging: Bool

  public init(isDragging: Bool = false) {
    self.isDragging = isDragging
  }

  public var body: some View {
    let pinShape = MarineMapPinShape(direction: .up)
    let mainColor = isDragging ? marineTheme.colors.textPrimary : marineTheme.colors.primary
    let fillColor = isDragging ? marineTheme.colors.primary : marineTheme.colors.surfaceBackground
    let headCenterY = Self.headCenterOffset

    ZStack {
      // 1. Pin body with shadow, fill, and crisp nautical stroke
      pinShape
        .fill(fillColor)
        .overlay(
          pinShape
            .stroke(mainColor, lineWidth: Self.strokeLineWidth)
        )
        .shadow(color: Color.black.opacity(0.45), radius: Self.shadowRadius, x: 0, y: Self.shadowY)
        .frame(width: Self.pinWidth, height: Self.pinHeight)

      // 2. Center badge in circular grip head (centered at (pinWidth/2, headCenterY))
      Image(marineIcon: .crosshair)
        .font(.system(size: Self.gripIconSize, weight: .semibold))
        .foregroundStyle(isDragging ? marineTheme.colors.panelBackground : marineTheme.colors.primary)
        .position(x: Self.pinWidth / 2.0, y: headCenterY)

      // 3. Precision focal target reticle at needle tip (centered at (pinWidth/2, 0))
      focalReticle(mainColor: mainColor)
        .position(x: Self.pinWidth / 2.0, y: 0)
    }
    .frame(width: Self.pinWidth, height: Self.pinHeight)
    .scaleEffect(isDragging ? Self.dragScale : 1.0, anchor: .top)
    .animation(.easeInOut(duration: 0.15), value: isDragging)
    .allowsHitTesting(false)
  }

  @ViewBuilder
  private func focalReticle(mainColor: Color) -> some View {
    ZStack {
      // White contrast ring for high legibility over both dark & light nautical charts
      Circle()
        .stroke(Color.white.opacity(0.85), lineWidth: Self.reticleContrastStrokeWidth)
        .frame(width: Self.reticleRingSize, height: Self.reticleRingSize)

      // Colored reticle ring
      Circle()
        .stroke(mainColor, lineWidth: Self.reticleStrokeWidth)
        .frame(width: Self.reticleRingSize, height: Self.reticleRingSize)

      // Center focal needle dot
      Circle()
        .fill(mainColor)
        .frame(width: Self.reticleCenterDotSize, height: Self.reticleCenterDotSize)
    }
  }
}
