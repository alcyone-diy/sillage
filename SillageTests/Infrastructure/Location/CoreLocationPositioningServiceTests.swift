//
//  CoreLocationPositioningServiceTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-22.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Testing
import Foundation
import CoreLocation
@testable import Sillage

@MainActor
struct CoreLocationPositioningServiceTests {

  @Test("CoreLocationPositioningService initializes with default pausesLocationUpdatesAutomatically")
  func testDefaultPausesLocationUpdatesAutomatically() {
    let service = CoreLocationPositioningService(initialAccuracyMode: .best)
    #expect(service.pausesLocationUpdatesAutomatically == false)
  }

  @Test("CoreLocationPositioningService initializes and updates pausesLocationUpdatesAutomatically")
  func testCoreLocationPositioningServicePausesUpdates() {
    let service = CoreLocationPositioningService(
      initialAccuracyMode: .best,
      initialPausesLocationUpdatesAutomatically: true
    )
    #expect(service.pausesLocationUpdatesAutomatically == true)

    service.setPausesLocationUpdatesAutomatically(false)
    #expect(service.pausesLocationUpdatesAutomatically == false)

    service.setPausesLocationUpdatesAutomatically(true)
    #expect(service.pausesLocationUpdatesAutomatically == true)
  }
}
