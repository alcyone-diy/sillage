//
//  MarinePinGraphicsFactory.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-14.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import UIKit
import SwiftUI

/// Unified high-performance graphics factory generating Retina-resolution nautical map pins for MapLibre GPU layers.
/// Encapsulates the entire CoreGraphics drawing pipeline (shadows, nautical pin shape, grip badge, and precision focal reticle)
/// for both distance measurement pins (Pins A and B) and contextual chart target pins.
@MainActor
final class MarinePinGraphicsFactory {
  private static let cache = NSCache<NSString, UIImage>()

  public static let canvasSize = CGSize(width: 52.0, height: 84.0)
  public static let focalPointY: CGFloat = 6.0
  public static let pinWidth: CGFloat = MarineMapPinShape.defaultWidth
  public static let pinHeight: CGFloat = MarineMapPinShape.defaultHeight

  /// Content rendered inside the circular grip badge at the bottom of the pin.
  public enum BadgeContent: Equatable, Sendable {
    case text(String)
    case icon(MarineIcon)
  }

  /// Visual styling parameters for pin rendering.
  public struct Style: Sendable {
    public var fillColor: UIColor
    public var strokeColor: UIColor
    public var badgeColor: UIColor
    public var reticleColor: UIColor
    public var centerDotColor: UIColor
    public var scale: CGFloat
    public var shadowBlur: CGFloat
    public var shadowAlpha: CGFloat

    public var colorSignature: String {
      "\(fillColor.description)_\(strokeColor.description)_\(badgeColor.description)_\(reticleColor.description)_\(centerDotColor.description)_\(scale)"
    }

    public init(
      fillColor: UIColor,
      strokeColor: UIColor,
      badgeColor: UIColor,
      reticleColor: UIColor,
      centerDotColor: UIColor,
      scale: CGFloat = 1.0,
      shadowBlur: CGFloat = 4.0,
      shadowAlpha: CGFloat = 0.45
    ) {
      self.fillColor = fillColor
      self.strokeColor = strokeColor
      self.badgeColor = badgeColor
      self.reticleColor = reticleColor
      self.centerDotColor = centerDotColor
      self.scale = scale
      self.shadowBlur = shadowBlur
      self.shadowAlpha = shadowAlpha
    }
  }

  /// Generates or returns a cached high-resolution Retina image for a pin with specific badge content and styling.
  public static func createPinImage(
    badge: BadgeContent,
    style: Style,
    cacheKey: String
  ) -> UIImage? {
    let key = cacheKey as NSString
    if let cached = cache.object(forKey: key) {
      return cached
    }

    let format = UIGraphicsImageRendererFormat()
    // Technical Design Choice: Setting scale to 0.0 automatically selects native display scale without referencing deprecated UIScreen.main
    format.scale = 0.0
    format.opaque = false

    let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
    let image = renderer.image { context in
      let cgContext = context.cgContext

      let scaledWidth = pinWidth * style.scale
      let scaledHeight = pinHeight * style.scale

      let pinRect = CGRect(
        x: (canvasSize.width - scaledWidth) / 2.0,
        y: focalPointY,
        width: scaledWidth,
        height: scaledHeight
      )

      let focalCenter = CGPoint(x: canvasSize.width / 2.0, y: focalPointY)

      // 1. Draw Drop Shadow for the Pin Body
      cgContext.saveGState()
      cgContext.setShadow(
        offset: CGSize(width: 0, height: 3.0),
        blur: style.shadowBlur,
        color: UIColor.black.withAlphaComponent(style.shadowAlpha).cgColor
      )

      let pinShape = MarineMapPinShape(direction: .up)
      let pinPath = pinShape.path(in: pinRect).cgPath

      style.fillColor.setFill()
      cgContext.addPath(pinPath)
      cgContext.fillPath()
      cgContext.restoreGState()

      // 2. Stroke Pin Outline
      style.strokeColor.setStroke()
      cgContext.setLineWidth(2.0)
      cgContext.addPath(pinPath)
      cgContext.strokePath()

      // 3. Draw Badge Content in bottom circular grip head
      let headRadius = scaledWidth / 2.0
      let headCenterY = pinRect.maxY - headRadius

      switch badge {
      case .text(let text):
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
          .font: UIFont.systemFont(ofSize: 18.0 * style.scale, weight: .bold),
          .foregroundColor: style.badgeColor,
          .paragraphStyle: paragraphStyle
        ]

        let attrString = NSString(string: text)
        let textSize = attrString.size(withAttributes: attributes)
        let textRect = CGRect(
          x: (canvasSize.width - textSize.width) / 2.0,
          y: headCenterY - (textSize.height / 2.0),
          width: textSize.width,
          height: textSize.height
        )
        attrString.draw(in: textRect, withAttributes: attributes)

      case .icon(let marineIcon):
        let config = UIImage.SymbolConfiguration(pointSize: 16.0 * style.scale, weight: .semibold)
        if let symbolImage = UIImage(systemName: marineIcon.rawValue, withConfiguration: config)?
          .withTintColor(style.badgeColor, renderingMode: .alwaysOriginal) {
          let iconRect = CGRect(
            x: (canvasSize.width - symbolImage.size.width) / 2.0,
            y: headCenterY - (symbolImage.size.height / 2.0),
            width: symbolImage.size.width,
            height: symbolImage.size.height
          )
          symbolImage.draw(in: iconRect)
        } else {
          // Procedural fallback crosshair
          let crossRadius: CGFloat = 7.0 * style.scale
          cgContext.setLineWidth(1.5)
          style.badgeColor.setStroke()
          cgContext.addArc(center: CGPoint(x: canvasSize.width / 2.0, y: headCenterY), radius: crossRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
          cgContext.move(to: CGPoint(x: canvasSize.width / 2.0 - crossRadius - 2.0, y: headCenterY))
          cgContext.addLine(to: CGPoint(x: canvasSize.width / 2.0 + crossRadius + 2.0, y: headCenterY))
          cgContext.move(to: CGPoint(x: canvasSize.width / 2.0, y: headCenterY - crossRadius - 2.0))
          cgContext.addLine(to: CGPoint(x: canvasSize.width / 2.0, y: headCenterY + crossRadius + 2.0))
          cgContext.strokePath()
        }
      }

      // 4. Precision Focal Target Reticle at top focal center (22, 6)
      let reticleRadius: CGFloat = 4.0
      // White contrast ring for high legibility over both dark & light nautical charts
      cgContext.setLineWidth(2.5)
      UIColor.white.withAlphaComponent(0.85).setStroke()
      cgContext.addArc(center: focalCenter, radius: reticleRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
      cgContext.strokePath()

      // Inner colored ring
      cgContext.setLineWidth(1.5)
      style.reticleColor.setStroke()
      cgContext.addArc(center: focalCenter, radius: reticleRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
      cgContext.strokePath()

      // Center focal needle dot
      style.centerDotColor.setFill()
      cgContext.addArc(center: focalCenter, radius: 1.25, startAngle: 0, endAngle: .pi * 2, clockwise: true)
      cgContext.fillPath()
    }

    cache.setObject(image, forKey: key)
    return image
  }

  // MARK: - Domain Convenience Factories

  /// Creates or returns a cached high-resolution image for a distance measurement pin (Pin A or Pin B).
  public static func createMeasurePinImage(
    for pin: ActiveMeasurePin,
    isSelected: Bool,
    theme: MarineTheme
  ) -> UIImage? {
    let pinLetter = pin == .start ? "a" : "b"
    let stateKey = isSelected ? "selected" : "idle"

    let style = Style(
      fillColor: isSelected ? UIColor(theme.colors.accent) : UIColor(theme.colors.surfaceBackground),
      strokeColor: isSelected ? UIColor(theme.colors.textPrimary) : UIColor(theme.colors.accent),
      badgeColor: isSelected ? UIColor(theme.colors.panelBackground) : UIColor(theme.colors.textPrimary),
      reticleColor: isSelected ? UIColor(theme.colors.accent) : UIColor(theme.colors.primary),
      centerDotColor: isSelected ? UIColor(theme.colors.accent) : UIColor(theme.colors.textPrimary),
      scale: 1.0,
      shadowBlur: 4.0,
      shadowAlpha: 0.45
    )

    let cacheKey = "measure-pin-\(pinLetter)-\(stateKey)-\(style.colorSignature)"

    return createPinImage(
      badge: .text(pin == .start ? "A" : "B"),
      style: style,
      cacheKey: cacheKey
    )
  }
}
