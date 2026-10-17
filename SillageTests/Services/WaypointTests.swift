//
//  WaypointTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-06-07.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
@testable import Sillage

@MainActor
final class WaypointTests: XCTestCase {
  
  func testWaypointInitialization() {
    let coordinate = CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15)
    let waypoint = Waypoint(name: "La Rochelle", coordinate: coordinate)
    
    // Check required fields
    XCTAssertEqual(waypoint.name, "La Rochelle")
    XCTAssertEqual(waypoint.coordinate.latitude, 46.16)
    XCTAssertEqual(waypoint.coordinate.longitude, -1.15)
    
    // Check defaults
    XCTAssertFalse(waypoint.id.isEmpty)
    XCTAssertTrue(waypoint.isVisible)
    XCTAssertNil(waypoint.description)
    XCTAssertNil(waypoint.symbol)
    XCTAssertNil(waypoint.colorHex)
    XCTAssertNotNil(waypoint.timestamp)
  }
  
  func testWaypointFullInitialization() {
    let coordinate = CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15)
    let timestamp = Date(timeIntervalSince1970: 1000)
    let waypoint = Waypoint(
      id: "test-id",
      name: "La Rochelle",
      description: "Port des Minimes",
      symbol: "anchor",
      colorHex: "#FF0000",
      isVisible: false,
      coordinate: coordinate,
      timestamp: timestamp
    )
    
    XCTAssertEqual(waypoint.id, "test-id")
    XCTAssertEqual(waypoint.name, "La Rochelle")
    XCTAssertEqual(waypoint.description, "Port des Minimes")
    XCTAssertEqual(waypoint.symbol, "anchor")
    XCTAssertEqual(waypoint.colorHex, "#FF0000")
    XCTAssertFalse(waypoint.isVisible)
    XCTAssertEqual(waypoint.coordinate.latitude, 46.16)
    XCTAssertEqual(waypoint.coordinate.longitude, -1.15)
    XCTAssertEqual(waypoint.timestamp, timestamp)
  }
  
  func testWaypointEquality() {
    let coordinate = CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15)
    let timestamp = Date(timeIntervalSince1970: 1000)
    
    let waypoint1 = Waypoint(
      id: "id-1",
      name: "Point A",
      coordinate: coordinate,
      timestamp: timestamp
    )
    
    let waypoint2 = Waypoint(
      id: "id-1",
      name: "Point A",
      coordinate: coordinate,
      timestamp: timestamp
    )
    
    let waypoint3 = Waypoint(
      id: "id-2", // Different ID
      name: "Point A",
      coordinate: coordinate,
      timestamp: timestamp
    )
    
    XCTAssertEqual(waypoint1, waypoint2)
    XCTAssertNotEqual(waypoint1, waypoint3)
  }

  func testDraftWaypointOnWaypointService() throws {
    let dbManager = try DatabaseManager.inMemory()
    let service = WaypointService(databaseManager: dbManager)
    
    XCTAssertNil(service.draftWaypoint)
    
    let draft = Waypoint(
      name: "Draft Point",
      coordinate: CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15)
    )
    service.setDraftWaypoint(draft)
    XCTAssertEqual(service.draftWaypoint?.name, "Draft Point")
    XCTAssertEqual(service.draftWaypoint?.coordinate.latitude, 46.16)
    
    service.setDraftWaypoint(nil)
    XCTAssertNil(service.draftWaypoint)
  }

  func testWaypointDetailViewModelDraftLifecycle() throws {
    let dbManager = try DatabaseManager.inMemory()
    let service = WaypointService(databaseManager: dbManager)
    
    let initialCoord = CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15)
    let vm = WaypointDetailViewModel(
      waypointService: service,
      defaultName: "New Draft Waypoint",
      initialCoordinate: initialCoord
    )
    
    // Draft waypoint should be published to service immediately upon initialization
    XCTAssertNotNil(service.draftWaypoint)
    XCTAssertEqual(service.draftWaypoint?.name, "New Draft Waypoint")
    XCTAssertEqual(service.draftWaypoint?.coordinate.latitude, 46.16)
    XCTAssertEqual(service.draftWaypoint?.coordinate.longitude, -1.15)
    
    // Updating name should update draft
    vm.name = "Renamed Draft"
    XCTAssertEqual(service.draftWaypoint?.name, "Renamed Draft")
    
    // Updating coordinates should update draft
    vm.latDegrees = 47
    vm.latMinutes = 0
    XCTAssertEqual(service.draftWaypoint?.coordinate.latitude, 47.0)
    
    // Canceling draft should clear it from service
    vm.cancelDraft()
    XCTAssertNil(service.draftWaypoint)
  }

  func testWaypointDetailViewModelSaveClearsDraftAndPersists() async throws {
    let dbManager = try DatabaseManager.inMemory()
    let service = WaypointService(databaseManager: dbManager)
    
    let initialCoord = CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15)
    let vm = WaypointDetailViewModel(
      waypointService: service,
      defaultName: "Point to Save",
      initialCoordinate: initialCoord
    )
    
    XCTAssertNotNil(service.draftWaypoint)
    let draftID = service.draftWaypoint?.id
    
    let success = await vm.save()
    XCTAssertTrue(success)
    
    // Draft waypoint must be cleared after save
    XCTAssertNil(service.draftWaypoint)
    
    // Saved waypoint must exist in persistence with the same ID
    if let id = draftID {
      let saved = try await service.fetchWaypoint(id: id)
      XCTAssertNotNil(saved)
      XCTAssertEqual(saved?.name, "Point to Save")
    }
  }

  func testChartViewModelIncludesDraftWaypoint() async throws {
    let dbManager = try DatabaseManager.inMemory()
    let service = WaypointService(databaseManager: dbManager)
    
    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService)
    let anchorService = AnchorService(
      positioningService: positioningService,
      preferencesService: preferencesService,
      notificationService: LocalNotificationService(),
      permissionService: permissionService,
      backgroundMonitoringService: backgroundMonitoringService
    )
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)
    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)
    let mockAuthService = MockGeoGarageAuthService()
    let messageService = MessageService()
    
    let chartVM = ChartViewModel(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: mockAuthService,
      anchorService: anchorService,
      anchorViewModel: anchorViewModel,
      waypointService: service,
      messageService: messageService
    )
    
    XCTAssertTrue(chartVM.visibleWaypointVisualStates.isEmpty)
    XCTAssertNil(chartVM.draftWaypointID)
    
    let initialCoord = CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15)
    let vm = WaypointDetailViewModel(
      waypointService: service,
      defaultName: "Live Draft",
      initialCoordinate: initialCoord
    )
    
    // Allow the MainActor task scheduled by withObservationTracking to execute
    await Task.yield()
    
    // Verify draft is registered on service
    XCTAssertNotNil(service.draftWaypoint)
    XCTAssertEqual(chartVM.draftWaypointID, service.draftWaypoint?.id)
    
    // Observation updates chart visual states
    XCTAssertEqual(chartVM.visibleWaypointVisualStates.count, 1)
    let visualState = chartVM.visibleWaypointVisualStates.first
    XCTAssertEqual(visualState?.name, "Live Draft")
    XCTAssertTrue(visualState?.isDraft == true)
    
    // Cancel clears draft from visible states
    vm.cancelDraft()
    await Task.yield()
    
    XCTAssertEqual(chartVM.visibleWaypointVisualStates.count, 0)
    XCTAssertNil(chartVM.draftWaypointID)
  }

  func testChartViewModelPositionsDraftWaypointAtQuarterScreenFraction() async throws {
    let dbManager = try DatabaseManager.inMemory()
    let service = WaypointService(databaseManager: dbManager)
    
    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService)
    let anchorService = AnchorService(
      positioningService: positioningService,
      preferencesService: preferencesService,
      notificationService: LocalNotificationService(),
      permissionService: permissionService,
      backgroundMonitoringService: backgroundMonitoringService
    )
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)
    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)
    let mockAuthService = MockGeoGarageAuthService()
    let messageService = MessageService()
    
    let chartVM = ChartViewModel(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: mockAuthService,
      anchorService: anchorService,
      anchorViewModel: anchorViewModel,
      waypointService: service,
      messageService: messageService
    )
    
    let stream = chartVM.cameraMoveStream
    let task = Task<CameraMoveEvent?, Never> {
      var iterator = stream.makeAsyncIterator()
      return await iterator.next()
    }
    
    let initialCoord = CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15)
    _ = WaypointDetailViewModel(
      waypointService: service,
      defaultName: "Live Draft",
      initialCoordinate: initialCoord
    )
    
    await Task.yield()
    
    let receivedEvent = await task.value
    if case .positionAtScreenFraction(let coordinate, let yFraction, let xFraction) = receivedEvent {
      XCTAssertEqual(coordinate.latitude, initialCoord.latitude, accuracy: 0.0001)
      XCTAssertEqual(coordinate.longitude, initialCoord.longitude, accuracy: 0.0001)
      XCTAssertEqual(yFraction, AppConstants.Map.aimingCrosshairYFraction, accuracy: 0.001)
      XCTAssertEqual(xFraction, 0.5, accuracy: 0.001)
    } else {
      XCTFail("Expected CameraMoveEvent.positionAtScreenFraction but got \(String(describing: receivedEvent))")
    }
  }

  func testDraftWaypointPreservesExactInitialCoordinatePrecision() async throws {
    let dbManager = try DatabaseManager.inMemory()
    let service = WaypointService(databaseManager: dbManager)
    
    // Choose coordinate with high precision where minutes would otherwise be rounded by roundMinutes
    let rawCoordinate = CLLocationCoordinate2D(latitude: 46.12345678, longitude: -1.87654321)
    let vm = WaypointDetailViewModel(
      waypointService: service,
      defaultName: "Precision Test",
      initialCoordinate: rawCoordinate
    )
    
    // Draft coordinate must strictly equal rawCoordinate without losing precision
    XCTAssertNotNil(service.draftWaypoint)
    XCTAssertEqual(service.draftWaypoint?.coordinate.latitude, rawCoordinate.latitude)
    XCTAssertEqual(service.draftWaypoint?.coordinate.longitude, rawCoordinate.longitude)
    
    // Modifying only latitude degrees should invalidate exact latitude (using parsed latitude),
    // but strictly preserve exact longitude without rounding
    vm.latDegrees = 47
    XCTAssertNotEqual(service.draftWaypoint?.coordinate.latitude, rawCoordinate.latitude)
    XCTAssertEqual(service.draftWaypoint?.coordinate.longitude, rawCoordinate.longitude)
    
    // Saving with partial axis edit must also preserve exact longitude
    let saved = await vm.save()
    XCTAssertTrue(saved)
    let waypoints = try await service.fetchWaypoints()
    let savedWaypoint = try XCTUnwrap(waypoints.first)
    let expectedLat = 47.0 + (vm.latMinutes ?? 0.0) / 60.0
    XCTAssertEqual(savedWaypoint.coordinate.latitude, expectedLat, accuracy: 0.0001)
    XCTAssertEqual(savedWaypoint.coordinate.longitude, rawCoordinate.longitude)
  }

  func testChartViewModelFollowsDraftCoordinateChanges() async throws {
    let dbManager = try DatabaseManager.inMemory()
    let service = WaypointService(databaseManager: dbManager)
    
    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService)
    let anchorService = AnchorService(
      positioningService: positioningService,
      preferencesService: preferencesService,
      notificationService: LocalNotificationService(),
      permissionService: permissionService,
      backgroundMonitoringService: backgroundMonitoringService
    )
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)
    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)
    let mockAuthService = MockGeoGarageAuthService()
    let messageService = MessageService()
    
    let chartVM = ChartViewModel(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: mockAuthService,
      anchorService: anchorService,
      anchorViewModel: anchorViewModel,
      waypointService: service,
      messageService: messageService
    )
    
    let initialCoord = CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15)
    let vm = WaypointDetailViewModel(
      waypointService: service,
      defaultName: "Live Draft",
      initialCoordinate: initialCoord
    )
    
    // Wait for initial position event to be emitted
    await Task.yield()
    
    // Setup listener for the updated coordinate event
    let stream = chartVM.cameraMoveStream
    let task = Task<CameraMoveEvent?, Never> {
      var iterator = stream.makeAsyncIterator()
      return await iterator.next()
    }
    
    // Modify latDegrees on ViewModel
    vm.latDegrees = 47
    await Task.yield()
    
    let receivedEvent = await task.value
    if case .positionAtScreenFraction(let coordinate, let yFraction, let xFraction) = receivedEvent {
      let expectedLat = 47.0 + (vm.latMinutes ?? 0.0) / 60.0
      XCTAssertEqual(coordinate.latitude, expectedLat, accuracy: 0.0001)
      XCTAssertEqual(yFraction, AppConstants.Map.aimingCrosshairYFraction, accuracy: 0.001)
      XCTAssertEqual(xFraction, 0.5, accuracy: 0.001)
    } else {
      XCTFail("Expected CameraMoveEvent.positionAtScreenFraction after coordinate edit but got \(String(describing: receivedEvent))")
    }
  }

  func testWaypointDetailViewModelUpdateCoordinate() async throws {
    let dbManager = try DatabaseManager.inMemory()
    let service = WaypointService(databaseManager: dbManager)
    
    let initialCoord = CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15)
    let vm = WaypointDetailViewModel(
      waypointService: service,
      defaultName: "Test Point",
      initialCoordinate: initialCoord
    )
    
    let initialCurrentCoord = try XCTUnwrap(vm.currentCoordinate)
    let initialDraftCoord = try XCTUnwrap(service.draftWaypoint?.coordinate)
    XCTAssertEqual(initialCurrentCoord.latitude, 46.16, accuracy: 0.0001)
    XCTAssertEqual(initialCurrentCoord.longitude, -1.15, accuracy: 0.0001)
    XCTAssertEqual(initialDraftCoord.latitude, 46.16, accuracy: 0.0001)
    
    let newCoord = CLLocationCoordinate2D(latitude: 47.25, longitude: -2.30)
    vm.updateCoordinate(newCoord)
    
    let updatedCurrentCoord = try XCTUnwrap(vm.currentCoordinate)
    let updatedDraftCoord = try XCTUnwrap(service.draftWaypoint?.coordinate)
    XCTAssertEqual(updatedCurrentCoord.latitude, 47.25, accuracy: 0.0001)
    XCTAssertEqual(updatedCurrentCoord.longitude, -2.30, accuracy: 0.0001)
    XCTAssertEqual(vm.latHemisphere, .north)
    XCTAssertEqual(vm.latDegrees, 47)
    XCTAssertEqual(vm.lonHemisphere, .west)
    XCTAssertEqual(vm.lonDegrees, 2)
    XCTAssertEqual(updatedDraftCoord.latitude, 47.25, accuracy: 0.0001)
    XCTAssertEqual(updatedDraftCoord.longitude, -2.30, accuracy: 0.0001)
  }

  func testChartViewModelWaypointPositionAdjustmentLifecycle() async throws {
    let dbManager = try DatabaseManager.inMemory()
    let service = WaypointService(databaseManager: dbManager)
    
    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService)
    let anchorService = AnchorService(
      positioningService: positioningService,
      preferencesService: preferencesService,
      notificationService: LocalNotificationService(),
      permissionService: permissionService,
      backgroundMonitoringService: backgroundMonitoringService
    )
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)
    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)
    let mockAuthService = MockGeoGarageAuthService()
    let messageService = MessageService()
    
    let chartVM = ChartViewModel(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: mockAuthService,
      anchorService: anchorService,
      anchorViewModel: anchorViewModel,
      waypointService: service,
      messageService: messageService
    )
    
    let initialCoord = CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15)
    let vm = WaypointDetailViewModel(
      waypointService: service,
      defaultName: "Test Waypoint",
      initialCoordinate: initialCoord
    )
    
    var didCancel = false
    var confirmedCoordinate: CLLocationCoordinate2D?
    
    // 1. Start adjustment
    chartVM.startWaypointPositionAdjustment(
      viewModel: vm,
      onCancel: { didCancel = true },
      onConfirm: { confirmedCoordinate = $0 }
    )
    
    XCTAssertNotNil(chartVM.waypointAdjustmentSession)
    XCTAssertTrue(chartVM.isActionConfirmationCardActive)
    XCTAssertTrue(chartVM.activeWaypointDetailViewModel === vm)
    XCTAssertEqual(chartVM.trackingMode, .free)
    
    // 2. Confirm adjustment
    let pickedCoordinate = CLLocationCoordinate2D(latitude: 47.50, longitude: -2.75)
    chartVM.confirmWaypointPositionAdjustment(to: pickedCoordinate)
    
    XCTAssertEqual(confirmedCoordinate?.latitude, 47.50)
    XCTAssertEqual(confirmedCoordinate?.longitude, -2.75)
    XCTAssertNil(chartVM.waypointAdjustmentSession)
    XCTAssertFalse(chartVM.isActionConfirmationCardActive)
    XCTAssertFalse(didCancel)
    // activeWaypointDetailViewModel is retained for the returning presentation
    XCTAssertTrue(chartVM.activeWaypointDetailViewModel === vm)
    
    // 3. Completing the edit session clears activeWaypointDetailViewModel
    chartVM.activeWaypointDetailViewModel = nil
    XCTAssertNil(chartVM.activeWaypointDetailViewModel)
    
    // 4. Test Cancel flow
    didCancel = false
    confirmedCoordinate = nil
    chartVM.startWaypointPositionAdjustment(
      viewModel: vm,
      onCancel: { didCancel = true },
      onConfirm: { confirmedCoordinate = $0 }
    )
    XCTAssertNotNil(chartVM.waypointAdjustmentSession)
    XCTAssertTrue(chartVM.isActionConfirmationCardActive)
    
    chartVM.cancelWaypointPositionAdjustment()
    XCTAssertTrue(didCancel)
    XCTAssertNil(confirmedCoordinate)
    XCTAssertNil(chartVM.waypointAdjustmentSession)
    XCTAssertFalse(chartVM.isActionConfirmationCardActive)
    XCTAssertTrue(chartVM.activeWaypointDetailViewModel === vm)
  }

  func testCancelPositionAdjustmentPreservesManualEditsAndActiveViewModel() async throws {
    let dbManager = try DatabaseManager.inMemory()
    let service = WaypointService(databaseManager: dbManager)
    
    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService)
    let anchorService = AnchorService(
      positioningService: positioningService,
      preferencesService: preferencesService,
      notificationService: LocalNotificationService(),
      permissionService: permissionService,
      backgroundMonitoringService: backgroundMonitoringService
    )
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)
    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)
    let mockAuthService = MockGeoGarageAuthService()
    let messageService = MessageService()
    
    let chartVM = ChartViewModel(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: mockAuthService,
      anchorService: anchorService,
      anchorViewModel: anchorViewModel,
      waypointService: service,
      messageService: messageService
    )
    
    let initialCoord = CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15)
    let vm = WaypointDetailViewModel(
      waypointService: service,
      defaultName: "Initial Draft",
      initialCoordinate: initialCoord
    )
    
    // 1. User performs manual edits in the detail view prior to tapping "Modify Position"
    vm.name = "Custom Edited Name"
    let manuallyEditedCoord = CLLocationCoordinate2D(latitude: 47.10, longitude: -2.20)
    vm.updateCoordinate(manuallyEditedCoord)
    
    // 2. User taps "Modify Position"
    var didCancel = false
    var restoredWrapper: CoordinateWrapper?
    
    chartVM.startWaypointPositionAdjustment(
      viewModel: vm,
      onCancel: {
        didCancel = true
        let restoreCoord = vm.currentCoordinate ?? initialCoord
        restoredWrapper = CoordinateWrapper(coordinate: restoreCoord, defaultName: vm.name)
      },
      onConfirm: { _ in }
    )
    
    XCTAssertTrue(chartVM.activeWaypointDetailViewModel === vm)
    
    // 3. User cancels adjustment
    chartVM.cancelWaypointPositionAdjustment()
    
    XCTAssertTrue(didCancel)
    let restored = try XCTUnwrap(restoredWrapper)
    XCTAssertEqual(restored.coordinate.latitude, 47.10, accuracy: 0.0001)
    XCTAssertEqual(restored.coordinate.longitude, -2.20, accuracy: 0.0001)
    XCTAssertEqual(restored.defaultName, "Custom Edited Name")
    
    // 4. Verify that the ViewModel itself retained the manual edits
    XCTAssertEqual(vm.name, "Custom Edited Name")
    let currentCoord = try XCTUnwrap(vm.currentCoordinate)
    XCTAssertEqual(currentCoord.latitude, 47.10, accuracy: 0.0001)
    XCTAssertEqual(currentCoord.longitude, -2.20, accuracy: 0.0001)
    
    // 5. Verify activeWaypointDetailViewModel remains preserved for presentation
    XCTAssertTrue(chartVM.activeWaypointDetailViewModel === vm)
  }
}
