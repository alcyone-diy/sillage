//
//  ActiveTrackViewModelTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-29.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Testing
import CoreLocation
import Foundation
@testable import Sillage

@MainActor
@Suite("Active Track View Model Tests")
struct ActiveTrackViewModelTests {
  
  // MARK: - Mocks & Helpers
  
  class MockBackgroundLocationToken: BackgroundLocationToken {
    let onInvalidate: (() -> Void)?
    init(onInvalidate: (() -> Void)? = nil) {
      self.onInvalidate = onInvalidate
    }
    func invalidate() {
      onInvalidate?()
    }
  }

  @MainActor
  class MockPositioningService: PositioningService, Sendable {
    let (locationUpdates, locationContinuation) = AsyncStream.makeStream(of: PositioningState.self)
    var currentDistanceFilter: Measurement<UnitLength> = Measurement(value: 5, unit: .meters)
    let (authorizationStatusStream, authContinuation) = AsyncStream.makeStream(of: CLAuthorizationStatus.self)
    
    var currentAuthorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var lastKnownLocation: NavigationFix?

    private final class MockLocationUpdateToken: LocationUpdateToken {
      let onInvalidate: () -> Void
      init(onInvalidate: @escaping () -> Void) {
        self.onInvalidate = onInvalidate
      }
      func invalidate() {
        onInvalidate()
      }
    }
    
    func requestAuthorization() {}
    
    func requestLocationUpdates() -> any LocationUpdateToken {
      return MockLocationUpdateToken {}
    }
    
    func requestDistanceFilter(_ distance: Measurement<UnitLength>, for identifier: String) {}
    func removeDistanceFilter(for identifier: String) {}
    
    func requestBackgroundLocation() -> any BackgroundLocationToken {
      return MockBackgroundLocationToken {}
    }
    
    func emit(fix: NavigationFix) {
      locationContinuation.yield(.active(fix))
    }
  }

  @Observable
  class MockPreferencesService: PreferencesServiceProtocol {
    var savedChartSource: String?
    var savedGeoGarageLayerID: String?
    var geoGarageUsername: String?
    var geoGarageCustomerID: String?
    var savedLatitude: Double?
    var savedLongitude: Double?
    var savedZoom: Double?
    var savedDirection: Double?
    var savedTrackingMode: ChartTrackingMode = .northUp
    var gloveModeEnabled: Bool = false
    var hasAcceptedDisclaimer: Bool = false
    var isOpenSeaMapOverlayEnabled: Bool = false
    var isCOGVectorEnabled: Bool = false
    var cogVectorTimeHorizon: Measurement<UnitDuration> = Measurement(value: 3600, unit: .seconds)
    var isCOGVectorTicksEnabled: Bool = false
    
    func saveCameraState(coordinate: CLLocationCoordinate2D, zoom: Double, direction: Double) {}
    func loadCameraState() -> (coordinate: CLLocationCoordinate2D, zoom: Double, direction: Double)? { return nil }
    
    var activeTrackSessionID: String?
    func saveActiveTrackSessionID(_ id: String) {
      activeTrackSessionID = id
    }
    func clearActiveTrackSessionID() {
      activeTrackSessionID = nil
    }
    
    var goToWaypointID: String?
    var displayedTrackSessionID: String?
    
    var isBaroAlarmEnabled: Bool = false
    var baroAlarmSensitivity: BaroAlarmSensitivity = .medium
    var barometerOffset: Measurement<UnitPressure> = Measurement(value: 0, unit: .hectopascals)
    
    var savedAnchorRadius: Measurement<UnitLength> = Measurement(value: 25.0, unit: .meters)
    var hudEditOpenCount: Int = 0
    var gpsAccuracyMode: GPSAccuracyMode = .best
    var pendingCAASDownloads: [PendingCAASDownload] = []
  }

  func createNavigationFix(
    latitude: CLLocationDegrees,
    longitude: CLLocationDegrees,
    speed: Double = 5,
    accuracy: Double = 5,
    timestamp: Date = Date()
  ) -> NavigationFix {
    return NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
      horizontalAccuracy: Measurement(value: accuracy, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: speed, unit: .metersPerSecond),
      speedOverGroundAccuracy: nil,
      timestamp: timestamp
    )
  }

  func waitUntil(
    _ condition: @escaping @MainActor () -> Bool,
    timeout: Duration = .seconds(3)
  ) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await Task.sleep(for: timeout)
        throw CancellationError()
      }
      group.addTask { @MainActor in
        while !condition() {
          await withCheckedContinuation { continuation in
            withObservationTracking {
              _ = condition()
            } onChange: {
              Task { @MainActor in
                continuation.resume()
              }
            }
          }
        }
      }
      try await group.next()
      group.cancelAll()
    }
  }

  @Test("Stopping recording automatically displays saved track on chart")
  func testAutoDisplaySavedTrackOnStop() async throws {
    let databaseManager = try DatabaseManager.inMemory()
    let trackService = TrackService(databaseManager: databaseManager)
    let positioningService = MockPositioningService()
    let preferencesService = MockPreferencesService()
    let messageService = MessageService()
    let notificationService = LocalNotificationService()
    let permissionService = PermissionService(
      positioningService: positioningService,
      notificationService: notificationService
    )

    let trackRecordingService = TrackRecordingService(
      positioningService: positioningService,
      databaseManager: databaseManager,
      preferencesService: preferencesService,
      messageService: messageService
    )

    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService)
    let anchorService = AnchorService(
      positioningService: positioningService,
      preferencesService: preferencesService,
      notificationService: notificationService,
      permissionService: permissionService,
      backgroundMonitoringService: backgroundMonitoringService
    )
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)
    let mockAuthService = MockGeoGarageAuthService()

    let chartViewModel = ChartViewModel(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: mockAuthService,
      anchorService: anchorService,
      anchorViewModel: anchorViewModel,
      trackService: trackService,
      trackRecordingService: trackRecordingService,
      waypointService: nil,
      messageService: messageService
    )

    let activeTrackViewModel = ActiveTrackViewModel(
      trackRecordingService: trackRecordingService,
      permissionService: permissionService
    )

    #expect(chartViewModel.displayedTrackSessionID == nil)
    #expect(chartViewModel.savedTrackVisualState == nil)

    // 1. Start recording
    activeTrackViewModel.toggleRecording()

    try await waitUntil {
      trackRecordingService.state == .waitingForFix
    }

    // 2. Feed GPS fixes
    let baseTime = Date()
    let fix1 = createNavigationFix(latitude: 48.8566, longitude: 2.3522, timestamp: baseTime)
    let fix2 = createNavigationFix(latitude: 48.8576, longitude: 2.3532, timestamp: baseTime.addingTimeInterval(5))
    let fix3 = createNavigationFix(latitude: 48.8586, longitude: 2.3542, timestamp: baseTime.addingTimeInterval(10))

    positioningService.emit(fix: fix1)
    positioningService.emit(fix: fix2)
    positioningService.emit(fix: fix3)

    try await waitUntil {
      trackRecordingService.trackPoints.count >= 3
    }

    #expect(activeTrackViewModel.isRecording == true)

    // 3. Stop recording
    activeTrackViewModel.toggleRecording()

    try await waitUntil {
      trackRecordingService.state == .idle && chartViewModel.displayedTrackSessionID != nil
    }

    // 4. Assert that track is saved and automatically displayed on the chart
    let savedID = activeTrackViewModel.recentlySavedSessionID
    #expect(savedID != nil)
    #expect(chartViewModel.displayedTrackSessionID == savedID)
    #expect(chartViewModel.savedTrackVisualState != nil)
    #expect(chartViewModel.savedTrackVisualState?.segments.isEmpty == false)
  }
}
