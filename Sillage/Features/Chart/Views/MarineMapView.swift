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

  /// Computes the zoom anchor point locked onto an active crosshair for all zoom gestures
  /// (pinch, one-finger quick zoom, double-tap zoom-in, two-finger tap zoom-out).
  /// Returns `nil` when no crosshair is active or for non-zoom gestures so MapLibre preserves default behavior.
  static func zoomAnchorPoint(
    for gesture: UIGestureRecognizer,
    in bounds: CGRect,
    crosshairYFraction: CGFloat?
  ) -> CGPoint? {
    guard let crosshairYFraction, bounds.width > 0, bounds.height > 0 else {
      return nil
    }

    let anchor = CGPoint(x: bounds.midX, y: bounds.height * crosshairYFraction)

    if gesture is UIPinchGestureRecognizer || gesture is UILongPressGestureRecognizer {
      return anchor
    }

    if let tapGesture = gesture as? UITapGestureRecognizer {
      let isDoubleTapZoomIn = tapGesture.numberOfTapsRequired == 2 && tapGesture.numberOfTouchesRequired == 1
      let isTwoFingerTapZoomOut = tapGesture.numberOfTapsRequired == 1 && tapGesture.numberOfTouchesRequired == 2
      if isDoubleTapZoomIn || isTwoFingerTapZoomOut {
        return anchor
      }
    }

    return nil
  }
}
