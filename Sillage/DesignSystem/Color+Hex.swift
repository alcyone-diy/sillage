//
//  Color+Hex.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-06-04.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

//
//  Color+Hex.swift
//  Alcyone Sillage
//

import SwiftUI

extension Color {
  /// Initializes a Color from a hex string (e.g., "#FF0000" or "FF0000").
  public init?(hex: String) {
    var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

    var rgb: UInt64 = 0

    guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
      return nil
    }

    let length = hexSanitized.count
    let r, g, b, a: Double
    if length == 6 {
      r = Double((rgb & 0xFF0000) >> 16) / 255.0
      g = Double((rgb & 0x00FF00) >> 8) / 255.0
      b = Double(rgb & 0x0000FF) / 255.0
      a = 1.0
    } else if length == 8 {
      r = Double((rgb & 0xFF000000) >> 24) / 255.0
      g = Double((rgb & 0x00FF0000) >> 16) / 255.0
      b = Double((rgb & 0x0000FF00) >> 8) / 255.0
      a = Double(rgb & 0x000000FF) / 255.0
    } else {
      return nil
    }

    self.init(red: r, green: g, blue: b, opacity: a)
  }

  public var hexString: String? {
    #if canImport(UIKit)
    let uiColor = UIColor(self).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    
    let success = uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    
    if !success {
      guard let cgColor = uiColor.cgColor.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
            let components = cgColor.components, components.count >= 3 else {
        return nil
      }
      red = components[0]
      green = components[1]
      blue = components[2]
      alpha = components.count >= 4 ? components[3] : 1.0
    }
    
    if alpha == 1.0 {
      return String(
        format: "#%02lX%02lX%02lX",
        lroundf(Float(red * 255)),
        lroundf(Float(green * 255)),
        lroundf(Float(blue * 255))
      )
    } else {
      return String(
        format: "#%02lX%02lX%02lX%02lX",
        lroundf(Float(red * 255)),
        lroundf(Float(green * 255)),
        lroundf(Float(blue * 255)),
        lroundf(Float(alpha * 255))
      )
    }
    #else
    return nil
    #endif
  }
}
