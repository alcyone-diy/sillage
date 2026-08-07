//
//  AnchorGraphicsFactory.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-07.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import UIKit
import SwiftUI

@MainActor
final class AnchorGraphicsFactory {
  private static let cache = NSCache<NSString, UIImage>()

  /// Creates or returns a cached high-contrast marine anchor badge image for MapLibre based on status.
  static func createAnchorImage(
    for status: AnchorVisualStatus,
    theme: MarineTheme,
    size: CGSize = CGSize(width: 44, height: 44)
  ) -> UIImage? {
    let key = "anchor-\(status.rawValue)-\(Int(size.width))x\(Int(size.height))" as NSString
    if let cachedImage = cache.object(forKey: key) {
      return cachedImage
    }

    let statusColor: UIColor
    switch status {
    case .setup:
      statusColor = UIColor(theme.colors.anchorDropped).withAlphaComponent(0.6)
    case .dropped:
      statusColor = UIColor(theme.colors.anchorDropped)
    case .armed:
      statusColor = UIColor(theme.colors.anchorArmed)
    case .dragging:
      statusColor = UIColor(theme.colors.anchorDragging)
    }

    return createAnchorImage(size: size, color: statusColor, cacheKey: key)
  }

  /// Creates or returns a cached AirTag-style high-contrast marine anchor badge image for MapLibre.
  static func createAnchorImage(size: CGSize = CGSize(width: 44, height: 44), color: UIColor, cacheKey: NSString? = nil) -> UIImage? {
    let key = cacheKey ?? "\(size.width)x\(size.height)-\(color.description)" as NSString
    if let cachedImage = cache.object(forKey: key) {
      return cachedImage
    }

    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { _ in
      let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)

      // 1. Outer Ring (Fond): Full circle filled with statusColor
      let outerRadius = min(size.width, size.height) / 2.0
      let outerPath = UIBezierPath(arcCenter: center, radius: outerRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
      color.setFill()
      outerPath.fill()

      // 2. Inner Disc (Centre): Superimposed smaller white circle (18% radius reduction)
      let innerRadius = outerRadius * 0.82
      let innerPath = UIBezierPath(arcCenter: center, radius: innerRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
      UIColor.white.setFill()
      innerPath.fill()

      // 3. Anchor Emoji (Icon): Centered ⚓️ (U+2693) text inside inner white disc
      let emojiString = NSString(string: "⚓️")
      let paragraphStyle = NSMutableParagraphStyle()
      paragraphStyle.alignment = .center

      let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: size.height * 0.48),
        .paragraphStyle: paragraphStyle
      ]

      let textSize = emojiString.size(withAttributes: attributes)
      let textRect = CGRect(
        x: center.x - (textSize.width / 2.0),
        y: center.y - (textSize.height / 2.0),
        width: textSize.width,
        height: textSize.height
      ).integral

      emojiString.draw(in: textRect, withAttributes: attributes)
    }

    cache.setObject(image, forKey: key)
    return image
  }
}
