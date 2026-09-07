//
//  MeasurePinGraphicsFactory.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-06.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import UIKit
import SwiftUI

@MainActor
final class MeasurePinGraphicsFactory {
  private static let cache = NSCache<NSString, UIImage>()

  public static let canvasSize = CGSize(width: 44.0, height: 74.0)
  public static let focalPointY: CGFloat = 6.0
  public static let pinWidth: CGFloat = MarineMapPinShape.defaultWidth
  public static let pinHeight: CGFloat = MarineMapPinShape.defaultHeight

  /// Generates or returns a cached high-resolution Retina image for a measure pin ("A" or "B", selected or idle).
  static func createPinImage(
    for pin: ActiveMeasurePin,
    isSelected: Bool,
    theme: MarineTheme
  ) -> UIImage? {
    let pinKey = pin == .start ? "a" : "b"
    let stateKey = isSelected ? "selected" : "idle"
    let key = "measure-pin-\(pinKey)-\(stateKey)-marine-theme" as NSString

    if let cached = cache.object(forKey: key) {
      return cached
    }

    let format = UIGraphicsImageRendererFormat()
    // Technical Design Choice: Setting scale to 0.0 automatically selects the native display scale without referencing deprecated UIScreen.main
    format.scale = 0.0
    format.opaque = false

    let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
    let image = renderer.image { context in
      let cgContext = context.cgContext
      let label = pin == .start ? "A" : "B"

      let pinRect = CGRect(
        x: (canvasSize.width - pinWidth) / 2.0,
        y: focalPointY,
        width: pinWidth,
        height: pinHeight
      )

      let focalCenter = CGPoint(x: canvasSize.width / 2.0, y: focalPointY)

      // 1. Draw Drop Shadow for the Pin Body
      cgContext.saveGState()
      cgContext.setShadow(
        offset: CGSize(width: 0, height: 3.0),
        blur: 4.0,
        color: UIColor.black.withAlphaComponent(0.45).cgColor
      )

      let pinShape = MarineMapPinShape(direction: .up)
      let pinPath = pinShape.path(in: pinRect).cgPath

      let fillColor = isSelected ? UIColor(theme.colors.accent) : UIColor(theme.colors.surfaceBackground)
      fillColor.setFill()
      cgContext.addPath(pinPath)
      cgContext.fillPath()
      cgContext.restoreGState()

      // 2. Stroke Pin Outline
      let strokeColor = isSelected ? UIColor(theme.colors.textPrimary) : UIColor(theme.colors.accent)
      strokeColor.setStroke()
      cgContext.setLineWidth(2.0)
      cgContext.addPath(pinPath)
      cgContext.strokePath()

      // 3. Draw Badge Letter ("A" or "B") in bottom circular head
      let headRadius = pinWidth / 2.0
      let headCenterY = pinRect.maxY - headRadius
      let paragraphStyle = NSMutableParagraphStyle()
      paragraphStyle.alignment = .center

      let textColor = isSelected ? UIColor(theme.colors.panelBackground) : UIColor(theme.colors.textPrimary)
      let textAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 18.0, weight: .bold),
        .foregroundColor: textColor,
        .paragraphStyle: paragraphStyle
      ]

      let letterString = NSString(string: label)
      let textSize = letterString.size(withAttributes: textAttributes)
      let textRect = CGRect(
        x: (canvasSize.width - textSize.width) / 2.0,
        y: headCenterY - (textSize.height / 2.0),
        width: textSize.width,
        height: textSize.height
      )
      letterString.draw(in: textRect, withAttributes: textAttributes)

      // 4. Precision Focal Target Reticle at top focal center (22, 6)
      let reticleRadius: CGFloat = 4.0
      // White contrast ring
      cgContext.setLineWidth(2.5)
      UIColor.white.withAlphaComponent(0.85).setStroke()
      cgContext.addArc(center: focalCenter, radius: reticleRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
      cgContext.strokePath()

      // Inner colored ring
      let reticleColor = isSelected ? UIColor(theme.colors.accent) : UIColor(theme.colors.primary)
      cgContext.setLineWidth(1.5)
      reticleColor.setStroke()
      cgContext.addArc(center: focalCenter, radius: reticleRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
      cgContext.strokePath()

      // Center focal needle dot
      let centerDotColor = isSelected ? UIColor(theme.colors.accent) : UIColor(theme.colors.textPrimary)
      centerDotColor.setFill()
      cgContext.addArc(center: focalCenter, radius: 1.25, startAngle: 0, endAngle: .pi * 2, clockwise: true)
      cgContext.fillPath()
    }

    cache.setObject(image, forKey: key)
    return image
  }
}
