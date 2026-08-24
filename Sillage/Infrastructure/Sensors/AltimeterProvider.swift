//
//  AltimeterProvider.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreMotion

/// Protocol defining the interface for an altimeter to allow dependency injection and unit testing.
public protocol AltimeterProvider {
  /// Indicates whether the device supports relative altitude updates.
  var isAvailable: Bool { get }
  
  /// Starts the delivery of relative altitude updates to the specified queue.
  func startRelativeAltitudeUpdates(to queue: OperationQueue, withHandler handler: @escaping CMAltitudeHandler)
  
  /// Stops the delivery of relative altitude updates.
  func stopRelativeAltitudeUpdates()
}

/// Conformance of Apple's CoreMotion altimeter to our provider protocol.
extension CMAltimeter: AltimeterProvider {
  public var isAvailable: Bool {
    return CMAltimeter.isRelativeAltitudeAvailable()
  }
}
