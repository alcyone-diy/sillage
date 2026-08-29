//
//  MarineCrosshairView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Standardized high-contrast crosshair view used across marine map overlays
/// (e.g. anchor position adjustment, map callout waypoint targeting).
public struct MarineCrosshairView: View {
  @Environment(\.marineTheme) private var marineTheme

  public static let defaultSize: CGFloat = 44.0

  public var size: CGFloat
  public var color: Color?
  public var centerDotColor: Color?

  public init(
    size: CGFloat = MarineCrosshairView.defaultSize,
    color: Color? = nil,
    centerDotColor: Color? = nil
  ) {
    self.size = size
    self.color = color
    self.centerDotColor = centerDotColor
  }

  public var body: some View {
    let mainColor = color ?? marineTheme.colors.primary
    let dotColor = centerDotColor ?? mainColor
    let circleDiameter = size * 0.65

    ZStack {
      // 1. Outer crosshair ring with dual-layer white contrast stroke for high legibility over dark & light chart layers
      Circle()
        .stroke(Color.white, lineWidth: 3.5)
        .frame(width: circleDiameter, height: circleDiameter)

      Circle()
        .stroke(mainColor, lineWidth: 2.0)
        .frame(width: circleDiameter, height: circleDiameter)

      // 2. Crosshair tick lines (+)
      Rectangle()
        .fill(mainColor)
        .frame(width: size, height: 1.5)

      Rectangle()
        .fill(mainColor)
        .frame(width: 1.5, height: size)

      // 3. Center focal dot
      Circle()
        .fill(dotColor)
        .frame(width: 6, height: 6)
    }
    .shadow(color: Color.black.opacity(0.5), radius: 4, x: 0, y: 2)
    .allowsHitTesting(false)
  }
}
