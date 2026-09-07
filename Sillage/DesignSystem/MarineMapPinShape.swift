//
//  MarineMapPinShape.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-06.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// High-precision nautical map pin shape with a circular head and an elongated needle tip.
/// By default points upwards (`.up`), allowing the user's finger to rest on the circular badge
/// while keeping the needle tip and the underlying target map feature completely visible.
public struct MarineMapPinShape: Shape {
  public static let defaultWidth: CGFloat = 36.0
  public static let defaultHeight: CGFloat = 62.0

  /// The vertical distance from the needle tip to the center of the circular head (for direction .up).
  public static var needleToHeadCenterOffset: CGFloat {
    defaultHeight - (defaultWidth / 2.0)
  }

  public enum Direction: Sendable {
    case up
    case down
  }

  public var direction: Direction

  public init(direction: Direction = .up) {
    self.direction = direction
  }

  public func path(in rect: CGRect) -> Path {
    var path = Path()
    let width = rect.width
    let height = rect.height
    let radius = width / 2.0

    guard height > radius else {
      path.addEllipse(in: rect)
      return path
    }

    // Mathematical cubic Bezier circle constant: 4/3 * (sqrt(2) - 1)
    let kCircle: CGFloat = 0.55228475
    let circleControlOffset = radius * kCircle

    switch direction {
    case .up:
      let center = CGPoint(x: rect.midX, y: rect.maxY - radius)
      let tip = CGPoint(x: rect.midX, y: rect.minY)
      let needleControlDistance = max(8.0, (center.y - rect.minY) * 0.25)

      // 1. Move to needle tip at top center
      path.move(to: tip)

      // 2. Left needle taper curving down into the left vertical tangent of the circular head
      path.addCurve(
        to: CGPoint(x: rect.minX, y: center.y),
        control1: CGPoint(x: rect.midX - 2.0, y: rect.minY + needleControlDistance),
        control2: CGPoint(x: rect.minX, y: center.y - radius * 0.65)
      )

      // 3. Bottom-left quadrant of circular head
      path.addCurve(
        to: CGPoint(x: rect.midX, y: rect.maxY),
        control1: CGPoint(x: rect.minX, y: center.y + circleControlOffset),
        control2: CGPoint(x: rect.midX - circleControlOffset, y: rect.maxY)
      )

      // 4. Bottom-right quadrant of circular head
      path.addCurve(
        to: CGPoint(x: rect.maxX, y: center.y),
        control1: CGPoint(x: rect.midX + circleControlOffset, y: rect.maxY),
        control2: CGPoint(x: rect.maxX, y: center.y + circleControlOffset)
      )

      // 5. Right needle taper curving back up to the needle tip at top center
      path.addCurve(
        to: tip,
        control1: CGPoint(x: rect.maxX, y: center.y - radius * 0.65),
        control2: CGPoint(x: rect.midX + 2.0, y: rect.minY + needleControlDistance)
      )

      path.closeSubpath()

    case .down:
      let center = CGPoint(x: rect.midX, y: rect.minY + radius)
      let tip = CGPoint(x: rect.midX, y: rect.maxY)
      let needleControlDistance = max(8.0, (rect.maxY - center.y) * 0.25)

      // 1. Move to needle tip at bottom center
      path.move(to: tip)

      // 2. Left needle taper curving up into the left vertical tangent of the circular head
      path.addCurve(
        to: CGPoint(x: rect.minX, y: center.y),
        control1: CGPoint(x: rect.midX - 2.0, y: rect.maxY - needleControlDistance),
        control2: CGPoint(x: rect.minX, y: center.y + radius * 0.65)
      )

      // 3. Top-left quadrant of circular head
      path.addCurve(
        to: CGPoint(x: rect.midX, y: rect.minY),
        control1: CGPoint(x: rect.minX, y: center.y - circleControlOffset),
        control2: CGPoint(x: rect.midX - circleControlOffset, y: rect.minY)
      )

      // 4. Top-right quadrant of circular head
      path.addCurve(
        to: CGPoint(x: rect.maxX, y: center.y),
        control1: CGPoint(x: rect.midX + circleControlOffset, y: rect.minY),
        control2: CGPoint(x: rect.maxX, y: center.y - circleControlOffset)
      )

      // 5. Right needle taper curving symmetrically back down to the needle tip
      path.addCurve(
        to: tip,
        control1: CGPoint(x: rect.maxX, y: center.y + radius * 0.65),
        control2: CGPoint(x: rect.midX + 2.0, y: rect.maxY - needleControlDistance)
      )

      path.closeSubpath()
    }

    return path
  }
}
