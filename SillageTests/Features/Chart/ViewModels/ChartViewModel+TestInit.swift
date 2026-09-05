//
//  ChartViewModel+TestInit.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-29.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
@testable import Sillage

extension ChartViewModel {
  /// Test-only convenience initializer creating in-memory tracking dependencies.
  @MainActor
  convenience init(
    positioningService: PositioningService,
    instrumentDampingService: InstrumentDampingService<ContinuousClock>,
    preferencesService: PreferencesServiceProtocol,
    authService: GeoGarageAuthServiceProtocol,
    anchorService: AnchorService,
    anchorViewModel: AnchorViewModel,
    waypointService: WaypointService? = nil,
    messageService: MessageService? = nil
  ) {
    let db = (try? DatabaseManager.inMemory()) ?? {
      fatalError("Failed to initialize in-memory DatabaseManager for test")
    }()
    let trackService = TrackService(databaseManager: db)
    let trackRecordingService = TrackRecordingService(
      positioningService: positioningService,
      databaseManager: db,
      preferencesService: preferencesService,
      messageService: messageService ?? MessageService()
    )
    self.init(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: authService,
      anchorService: anchorService,
      anchorViewModel: anchorViewModel,
      trackService: trackService,
      trackRecordingService: trackRecordingService,
      waypointService: waypointService,
      messageService: messageService
    )
  }
}
