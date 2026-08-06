//
//  SavedTrackVisualState.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-06.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

/// Represents the visual segment coordinates for a displayed saved track.
public struct SavedTrackVisualState: Equatable, Sendable {
  public let segments: [[CLLocationCoordinate2D]]
  
  public init(segments: [[CLLocationCoordinate2D]]) {
    self.segments = segments
  }
}
