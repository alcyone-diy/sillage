//
//  MarineMapView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-17.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import UIKit
import MapLibre

/// A subclass of `MLNMapView` enabling specialized gesture anchor point customization.
/// Allows nautical tools (such as crosshair targeting) to anchor camera transformations
/// (e.g. one-finger zoom) on custom focal points rather than the raw touch location.
final class MarineMapView: MLNMapView {

  /// Optional provider for intercepting user gesture anchor points.
  /// Return `nil` to fallback to MapLibre's default gesture anchoring behavior.
  var customGestureAnchorProvider: (@MainActor (UIGestureRecognizer) -> CGPoint?)?

  override func anchorPoint(forGesture gesture: UIGestureRecognizer) -> CGPoint {
    if let customPoint = customGestureAnchorProvider?(gesture) {
      return customPoint
    }
    return super.anchorPoint(forGesture: gesture)
  }
}
