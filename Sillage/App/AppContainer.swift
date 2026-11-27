//
//  AppContainer.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-25.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

extension AppEnvironment {
  @MainActor
  struct AppContainer {
    let userDefaults: UserDefaults
    let messageService: MessageService
    let preferencesService: PreferencesService
    let positioningService: any PositioningService
    let trackRecordingService: TrackRecordingService
    let trackService: TrackService
    let waypointService: WaypointService
    let activeNavigationService: ActiveNavigationService
    let instrumentDampingService: InstrumentDampingService<ContinuousClock>
    let geoGarageAuthService: GeoGarageAuthService
    let geoGarageLayerRepository: GeoGarageLayerRepository
    let geoGarageDownloadRepository: GeoGarageDownloadRepository
    let geoGaragePackageService: GeoGaragePackageService
    let geoGarageChartDownloader: GeoGarageChartDownloader
    let geoGarageDownloadService: GeoGarageDownloadService
    let geoGarageOfflineTileProvider: GeoGarageOfflineTileProvider
    let anchorService: AnchorService
    let kinematicsService: VesselKinematicsService

    let appViewModel: AppViewModel
    let chartViewModel: ChartViewModel
    let activeTrackViewModel: ActiveTrackViewModel
    let barometerViewModel: BarometerViewModel
    let anchorViewModel: AnchorViewModel
    let permissionService: PermissionService
    let offlineSelectionViewModel: OfflineSelectionViewModel
    let networkMonitorService: NetworkMonitorService
    let notificationService: NotificationService
    let secondaryTelemetryViewModel: SecondaryTelemetryViewModel
    let checklistCatalogService: ChecklistCatalogService
    let checklistSessionService: ChecklistSessionService

    #if DEBUG
    private(set) var developerSettingsService = DeveloperSettingsService()

    func withDeveloperSettings(_ service: DeveloperSettingsService) -> Self {
      var copy = self
      copy.developerSettingsService = service
      return copy
    }
    #endif
  }
}
