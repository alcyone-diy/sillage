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
    let preferencesService = MockPreferencesService()
    preferencesService.clearAll()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService)
    let anchorService = AnchorService(
      positioningService: positioningService,
      preferencesService: preferencesService,
      notificationService: LocalNotificationService(),
      permissionService: permissionService,
      backgroundMonitoringService: backgroundMonitoringService,
      stateStore: MockAnchorStateStore()
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
    let preferencesService = MockPreferencesService()
    preferencesService.clearAll()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService)
    let anchorService = AnchorService(
      positioningService: positioningService,
      preferencesService: preferencesService,
      notificationService: LocalNotificationService(),
      permissionService: permissionService,
      backgroundMonitoringService: backgroundMonitoringService,
      stateStore: MockAnchorStateStore()
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
    let preferencesService = MockPreferencesService()
    preferencesService.clearAll()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService)
    let anchorService = AnchorService(
      positioningService: positioningService,
      preferencesService: preferencesService,
      notificationService: LocalNotificationService(),
      permissionService: permissionService,
      backgroundMonitoringService: backgroundMonitoringService,
      stateStore: MockAnchorStateStore()
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
    let preferencesService = MockPreferencesService()
    preferencesService.clearAll()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService)
    let anchorService = AnchorService(
      positioningService: positioningService,
      preferencesService: preferencesService,
      notificationService: LocalNotificationService(),
      permissionService: permissionService,
      backgroundMonitoringService: backgroundMonitoringService,
      stateStore: MockAnchorStateStore()
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
    let preferencesService = MockPreferencesService()
    preferencesService.clearAll()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService)
    let anchorService = AnchorService(
      positioningService: positioningService,
      preferencesService: preferencesService,
      notificationService: LocalNotificationService(),
      permissionService: permissionService,
      backgroundMonitoringService: backgroundMonitoringService,
      stateStore: MockAnchorStateStore()
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

  func testExistingWaypointPositionAdjustmentLivePreviewAndRevert() async throws {
    let dbManager = try DatabaseManager.inMemory()
    let service = WaypointService(databaseManager: dbManager)
    
    let positioningService = MockPositioningService()
    let preferencesService = MockPreferencesService()
    preferencesService.clearAll()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService)
    let anchorService = AnchorService(
      positioningService: positioningService,
      preferencesService: preferencesService,
      notificationService: LocalNotificationService(),
      permissionService: permissionService,
      backgroundMonitoringService: backgroundMonitoringService,
      stateStore: MockAnchorStateStore()
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
    
    // 1. Save an existing waypoint to database
    let originalCoord = CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15)
    let waypoint = Waypoint(
      id: UUID().uuidString,
      name: "Existing Waypoint",
      colorHex: "#FF0000",
      coordinate: originalCoord
    )
    try await service.saveWaypoint(waypoint)
    
    // Allow background ValueObservation to populate service.currentWaypoints and notify ChartViewModel
    for _ in 0..<50 {
      if !chartVM.visibleWaypointVisualStates.isEmpty { break }
      try await Task.sleep(for: .milliseconds(20))
    }
    
    XCTAssertEqual(chartVM.visibleWaypointVisualStates.count, 1)
    let initialVisualState = try XCTUnwrap(chartVM.visibleWaypointVisualStates.first)
    XCTAssertEqual(initialVisualState.coordinate.latitude, 46.16, accuracy: 0.0001)
    XCTAssertEqual(initialVisualState.coordinate.longitude, -1.15, accuracy: 0.0001)
    
    // 2. Open Waypoint in detail view and adjust position
    let vm = WaypointDetailViewModel(
      waypointService: service,
      editingWaypoint: waypoint,
      startEditable: true
    )
    
    chartVM.startWaypointPositionAdjustment(
      viewModel: vm,
      onCancel: {},
      onConfirm: { newCoord in
        vm.updateCoordinate(newCoord)
      }
    )
    
    let adjustedCoord = CLLocationCoordinate2D(latitude: 47.25, longitude: -2.35)
    chartVM.confirmWaypointPositionAdjustment(to: adjustedCoord)
    
    // 3. Verify that DB is unchanged, but chart visually previews the new position
    let dbWaypoint = try XCTUnwrap(service.currentWaypoints.first(where: { $0.id == waypoint.id }))
    XCTAssertEqual(dbWaypoint.coordinate.latitude, 46.16, accuracy: 0.0001)
    XCTAssertEqual(dbWaypoint.coordinate.longitude, -1.15, accuracy: 0.0001)
    
    let previewVisualState = try XCTUnwrap(chartVM.visibleWaypointVisualStates.first(where: { $0.id == waypoint.id }))
    XCTAssertEqual(previewVisualState.coordinate.latitude, 47.25, accuracy: 0.0001)
    XCTAssertEqual(previewVisualState.coordinate.longitude, -2.35, accuracy: 0.0001)
    XCTAssertTrue(previewVisualState.isSelected)
    
    // 4. User cancels / reverts edits without saving
    vm.revert()
    
    let revertedVisualState = try XCTUnwrap(chartVM.visibleWaypointVisualStates.first(where: { $0.id == waypoint.id }))
    XCTAssertEqual(revertedVisualState.coordinate.latitude, 46.16, accuracy: 0.0001)
    XCTAssertEqual(revertedVisualState.coordinate.longitude, -1.15, accuracy: 0.0001)
    // As long as the dialog is still open (even after revert / read-only), it stays selected
    XCTAssertTrue(revertedVisualState.isSelected)
    
    // 5. Test dismissing / cleaning up activeWaypointDetailViewModel restores original coordinates and unselects
    vm.updateCoordinate(CLLocationCoordinate2D(latitude: 48.0, longitude: -3.0))
    let modifiedVisualState = try XCTUnwrap(chartVM.visibleWaypointVisualStates.first(where: { $0.id == waypoint.id }))
    XCTAssertEqual(modifiedVisualState.coordinate.latitude, 48.0, accuracy: 0.0001)
    
    chartVM.activeWaypointDetailViewModel = nil
    let restoredVisualState = try XCTUnwrap(chartVM.visibleWaypointVisualStates.first(where: { $0.id == waypoint.id }))
    XCTAssertEqual(restoredVisualState.coordinate.latitude, 46.16, accuracy: 0.0001)
    XCTAssertEqual(restoredVisualState.coordinate.longitude, -1.15, accuracy: 0.0001)
    XCTAssertFalse(restoredVisualState.isSelected)
  }

  func testExistingGoToWaypointLivePreviewAndRevert() async throws {
    let dbManager = try DatabaseManager.inMemory()
    let service = WaypointService(databaseManager: dbManager)
    
    let positioningService = MockPositioningService()
    let preferencesService = MockPreferencesService()
    preferencesService.clearAll()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService)
    let anchorService = AnchorService(
      positioningService: positioningService,
      preferencesService: preferencesService,
      notificationService: LocalNotificationService(),
      permissionService: permissionService,
      backgroundMonitoringService: backgroundMonitoringService,
      stateStore: MockAnchorStateStore()
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
    
    let originalCoord = CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15)
    let waypoint = Waypoint(
      id: UUID().uuidString,
      name: "Nav Target",
      colorHex: "#0000FF",
      coordinate: originalCoord
    )
    try await service.saveWaypoint(waypoint)
    service.setDestination(waypointID: waypoint.id)
    
    // Allow background ValueObservation to populate service.currentWaypoints and ChartViewModel
    for _ in 0..<50 {
      if chartVM.goToWaypointVisualState != nil { break }
      try await Task.sleep(for: .milliseconds(20))
    }
    
    let initialGoTo = try XCTUnwrap(chartVM.goToWaypointVisualState)
    XCTAssertEqual(initialGoTo.coordinate.latitude, 46.16, accuracy: 0.0001)
    XCTAssertEqual(initialGoTo.coordinate.longitude, -1.15, accuracy: 0.0001)
    
    let vm = WaypointDetailViewModel(
      waypointService: service,
      editingWaypoint: waypoint,
      startEditable: true
    )
    
    chartVM.startWaypointPositionAdjustment(
      viewModel: vm,
      onCancel: {},
      onConfirm: { newCoord in
        vm.updateCoordinate(newCoord)
      }
    )
    
    let adjustedCoord = CLLocationCoordinate2D(latitude: 47.50, longitude: -2.80)
    chartVM.confirmWaypointPositionAdjustment(to: adjustedCoord)
    
    let previewGoTo = try XCTUnwrap(chartVM.goToWaypointVisualState)
    XCTAssertEqual(previewGoTo.coordinate.latitude, 47.50, accuracy: 0.0001)
    XCTAssertEqual(previewGoTo.coordinate.longitude, -2.80, accuracy: 0.0001)
    XCTAssertTrue(previewGoTo.isSelected)
    
    vm.revert()
    
    let revertedGoTo = try XCTUnwrap(chartVM.goToWaypointVisualState)
    XCTAssertEqual(revertedGoTo.coordinate.latitude, 46.16, accuracy: 0.0001)
    XCTAssertEqual(revertedGoTo.coordinate.longitude, -1.15, accuracy: 0.0001)
    XCTAssertTrue(revertedGoTo.isSelected)

    chartVM.activeWaypointDetailViewModel = nil
    let unselectedGoTo = try XCTUnwrap(chartVM.goToWaypointVisualState)
    XCTAssertFalse(unselectedGoTo.isSelected)
  }

  func testExistingWaypointReadOnlyDialogShowsSelectedOnMap() async throws {
    let dbManager = try DatabaseManager.inMemory()
    let service = WaypointService(databaseManager: dbManager)
    
    let positioningService = MockPositioningService()
    let preferencesService = MockPreferencesService()
    preferencesService.clearAll()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService)
    let anchorService = AnchorService(
      positioningService: positioningService,
      preferencesService: preferencesService,
      notificationService: LocalNotificationService(),
      permissionService: permissionService,
      backgroundMonitoringService: backgroundMonitoringService,
      stateStore: MockAnchorStateStore()
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
    
    let originalCoord = CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15)
    let waypoint = Waypoint(
      id: UUID().uuidString,
      name: "Read Only Point",
      colorHex: "#FF0000",
      coordinate: originalCoord
    )
    try await service.saveWaypoint(waypoint)
    
    for _ in 0..<50 {
      if !chartVM.visibleWaypointVisualStates.isEmpty { break }
      try await Task.sleep(for: .milliseconds(20))
    }
    
    let initialVisualState = try XCTUnwrap(chartVM.visibleWaypointVisualStates.first)
    XCTAssertFalse(initialVisualState.isSelected)
    
    // Open in read-only mode (startEditable: false)
    let vm = WaypointDetailViewModel(
      waypointService: service,
      editingWaypoint: waypoint,
      startEditable: false
    )
    chartVM.activeWaypointDetailViewModel = vm
    
    let openDialogVisualState = try XCTUnwrap(chartVM.visibleWaypointVisualStates.first)
    XCTAssertTrue(openDialogVisualState.isSelected)
    
    // Close dialog
    chartVM.activeWaypointDetailViewModel = nil
    let closedDialogVisualState = try XCTUnwrap(chartVM.visibleWaypointVisualStates.first)
    XCTAssertFalse(closedDialogVisualState.isSelected)
  }

  func testWaypointDetailViewModelFetchesPointInformation() async throws {
    let dbManager = try DatabaseManager.inMemory()
    let service = WaypointService(databaseManager: dbManager)

    let coord = CLLocationCoordinate2D(latitude: 47.218371, longitude: -1.553621)
    let waypoint = Waypoint(
      id: UUID().uuidString,
      name: "Nantes Point",
      colorHex: Waypoint.defaultColorHex,
      coordinate: coord
    )

    let vm = WaypointDetailViewModel(
      waypointService: service,
      editingWaypoint: waypoint,
      startEditable: false
    )

    XCTAssertNil(vm.sunEphemeris)
    XCTAssertNil(vm.magneticDeclination)
    XCTAssertNil(vm.pointInfoDate)
    XCTAssertFalse(vm.isPointInfoLoading)

    let calendar = Calendar(identifier: .gregorian)
    var components = DateComponents()
    components.year = 2026
    components.month = 1
    components.day = 1
    components.hour = 12
    components.minute = 0
    components.timeZone = TimeZone(identifier: "UTC")
    let fixedDate = try XCTUnwrap(calendar.date(from: components))

    await vm.loadPointInformation(for: fixedDate)

    XCTAssertFalse(vm.isPointInfoLoading)
    XCTAssertEqual(vm.pointInfoDate, fixedDate)
    XCTAssertNotNil(vm.sunEphemeris)
    XCTAssertNotNil(vm.sunEphemeris?.nauticalTwilightStart)
    XCTAssertNotNil(vm.sunEphemeris?.sunrise)
    XCTAssertNotNil(vm.sunEphemeris?.sunset)
    XCTAssertNotNil(vm.sunEphemeris?.nauticalTwilightEnd)
    XCTAssertNotNil(vm.magneticDeclination)
    if let decl = vm.magneticDeclination {
      XCTAssertEqual(decl.converted(to: .degrees).value, 0.91, accuracy: 0.05)
    }

    // Invalid coordinate resets pointInfoDate, sunEphemeris, and magneticDeclination
    vm.latDegrees = 95
    await vm.loadPointInformation(for: fixedDate)
    XCTAssertNil(vm.pointInfoDate)
    XCTAssertNil(vm.sunEphemeris)
    XCTAssertNil(vm.magneticDeclination)
    XCTAssertFalse(vm.isPointInfoLoading)

    // Restore valid coordinate and verify task cancellation resets isPointInfoLoading
    vm.updateCoordinate(coord)
    let cancelledTask = Task { @MainActor in
      await vm.loadPointInformation(for: fixedDate)
    }
    cancelledTask.cancel()
    await cancelledTask.value
    XCTAssertFalse(vm.isPointInfoLoading)
  }

  func testWaypointDetailViewModelMagneticDeclinationFooterText() throws {
    let dbManager = try DatabaseManager.inMemory()
    let service = WaypointService(databaseManager: dbManager)
    let vm = WaypointDetailViewModel(waypointService: service)

    XCTAssertNil(vm.magneticDeclinationFooterText)

    vm.magneticDeclination = Measurement<UnitAngle>(value: 1.2, unit: .degrees)
    let angle1_2 = "1.2°"
    XCTAssertEqual(
      vm.magneticDeclinationFooterText,
      String(localized: "True to Magnetic: subtract \(angle1_2) • Magnetic to True: add \(angle1_2)")
    )

    vm.magneticDeclination = Measurement<UnitAngle>(value: -2.5, unit: .degrees)
    let angle2_5 = "2.5°"
    XCTAssertEqual(
      vm.magneticDeclinationFooterText,
      String(localized: "True to Magnetic: add \(angle2_5) • Magnetic to True: subtract \(angle2_5)")
    )

    vm.magneticDeclination = Measurement<UnitAngle>(value: 0.0, unit: .degrees)
    XCTAssertEqual(
      vm.magneticDeclinationFooterText,
      String(localized: "No significant variation between True and Magnetic bearings.")
    )

    vm.magneticDeclination = Measurement<UnitAngle>(value: -0.04, unit: .degrees)
    XCTAssertEqual(
      vm.magneticDeclinationFooterText,
      String(localized: "No significant variation between True and Magnetic bearings.")
    )

    vm.magneticDeclination = nil
    XCTAssertNil(vm.magneticDeclinationFooterText)
  }

  func testWaypointDetailViewModelParseCoordinateBoundsAndValidation() throws {
    let dbManager = try DatabaseManager.inMemory()
    let service = WaypointService(databaseManager: dbManager)
    let vm = WaypointDetailViewModel(
      waypointService: service,
      defaultName: "Bounds Test",
      initialCoordinate: CLLocationCoordinate2D(latitude: 46.0, longitude: -1.0)
    )

    // Valid latitude bounds: 90° 00' N and S
    vm.latHemisphere = .north
    vm.latDegrees = 90
    vm.latMinutes = 0
    XCTAssertEqual(vm.parsedLatitude, 90.0)
    XCTAssertNotNil(vm.currentCoordinate)
    XCTAssertNotNil(service.draftWaypoint)

    vm.latHemisphere = .south
    XCTAssertEqual(vm.parsedLatitude, -90.0)

    // Out-of-bounds latitude: 90° 0.1' and 95° 00'
    vm.latHemisphere = .north
    vm.latDegrees = 90
    vm.latMinutes = 0.1
    XCTAssertNil(vm.parsedLatitude)
    XCTAssertNil(vm.currentCoordinate)
    XCTAssertNil(service.draftWaypoint)
    XCTAssertFalse(vm.isValid)

    vm.latDegrees = 95
    vm.latMinutes = 0
    XCTAssertNil(vm.parsedLatitude)
    XCTAssertNil(vm.currentCoordinate)
    XCTAssertFalse(vm.isValid)

    // Restore valid latitude
    vm.latDegrees = 46
    vm.latMinutes = 0

    // Valid longitude bounds: 180° 00' E and W
    vm.lonHemisphere = .east
    vm.lonDegrees = 180
    vm.lonMinutes = 0
    XCTAssertEqual(vm.parsedLongitude, 180.0)
    XCTAssertNotNil(vm.currentCoordinate)

    vm.lonHemisphere = .west
    XCTAssertEqual(vm.parsedLongitude, -180.0)

    // Out-of-bounds longitude: 180° 0.1' and 185° 00'
    vm.lonHemisphere = .east
    vm.lonDegrees = 180
    vm.lonMinutes = 0.1
    XCTAssertNil(vm.parsedLongitude)
    XCTAssertNil(vm.currentCoordinate)
    XCTAssertNil(service.draftWaypoint)
    XCTAssertFalse(vm.isValid)

    vm.lonDegrees = 185
    vm.lonMinutes = 0
    XCTAssertNil(vm.parsedLongitude)
    XCTAssertFalse(vm.isValid)

    // Invalid minutes & negative values & non-finite values
    vm.lonDegrees = 10
    vm.lonMinutes = 60
    XCTAssertNil(vm.parsedLongitude)

    vm.lonMinutes = -1
    XCTAssertNil(vm.parsedLongitude)

    vm.lonMinutes = .nan
    XCTAssertNil(vm.parsedLongitude)

    vm.lonMinutes = .infinity
    XCTAssertNil(vm.parsedLongitude)

    vm.lonDegrees = -10
    vm.lonMinutes = 0
    XCTAssertNil(vm.parsedLongitude)

    // Defense in depth: invalid exact coordinate via updateCoordinate
    vm.updateCoordinate(CLLocationCoordinate2D(latitude: 95.0, longitude: 0.0))
    XCTAssertNil(vm.currentCoordinate)
    XCTAssertNil(service.draftWaypoint)
    XCTAssertFalse(vm.isValid)
  }

  func testSetVisibleInEditModeDoesNotPersistAndRevertRestoresWithoutSaving() async throws {
    let dbManager = try DatabaseManager.inMemory()
    let service = WaypointService(databaseManager: dbManager)
    let waypoint = Waypoint(
      id: UUID().uuidString,
      name: "Edit Toggle Test",
      isVisible: true,
      coordinate: CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15)
    )
    try await service.saveWaypoint(waypoint)

    let vm = WaypointDetailViewModel(
      waypointService: service,
      editingWaypoint: waypoint,
      startEditable: true
    )

    var persistCallCount = 0
    vm.persistWaypointHandler = { _ in
      persistCallCount += 1
    }

    vm.setVisible(false)
    await vm.waitForPendingVisibilitySave()

    XCTAssertFalse(vm.isVisible)
    XCTAssertEqual(persistCallCount, 0)

    vm.revert()
    await vm.waitForPendingVisibilitySave()

    XCTAssertTrue(vm.isVisible)
    XCTAssertFalse(vm.isEditable)
    XCTAssertEqual(persistCallCount, 0)

    let persisted = try await service.fetchWaypoint(id: waypoint.id)
    XCTAssertEqual(persisted?.isVisible, true)
  }

  func testSetVisibleInReadOnlyModePersistsAndUpdatesOriginalWaypoint() async throws {
    let dbManager = try DatabaseManager.inMemory()
    let service = WaypointService(databaseManager: dbManager)
    let waypoint = Waypoint(
      id: UUID().uuidString,
      name: "Read-Only Toggle Test",
      isVisible: true,
      coordinate: CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15)
    )
    try await service.saveWaypoint(waypoint)

    let vm = WaypointDetailViewModel(
      waypointService: service,
      editingWaypoint: waypoint,
      startEditable: false
    )

    vm.setVisible(false)
    await vm.waitForPendingVisibilitySave()

    XCTAssertFalse(vm.isVisible)
    XCTAssertNil(vm.activeError)

    let persisted = try await service.fetchWaypoint(id: waypoint.id)
    XCTAssertEqual(persisted?.isVisible, false)

    // Verify originalWaypoint was updated: edit -> toggle -> revert must restore `false`
    vm.isEditable = true
    vm.setVisible(true)
    XCTAssertTrue(vm.isVisible)
    vm.revert()
    XCTAssertFalse(vm.isVisible)
    XCTAssertFalse(vm.isEditable)
  }

  func testSetVisibleInReadOnlyModeRollsBackOnPersistenceFailure() async throws {
    enum StubPersistenceError: Error {
      case writeFailed
    }

    let dbManager = try DatabaseManager.inMemory()
    let service = WaypointService(databaseManager: dbManager)
    let waypoint = Waypoint(
      id: UUID().uuidString,
      name: "Rollback Test",
      isVisible: true,
      coordinate: CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15)
    )

    let vm = WaypointDetailViewModel(
      waypointService: service,
      editingWaypoint: waypoint,
      startEditable: false
    )
    vm.persistWaypointHandler = { _ in
      throw StubPersistenceError.writeFailed
    }

    vm.setVisible(false)
    await vm.waitForPendingVisibilitySave()

    XCTAssertTrue(vm.isVisible)
    XCTAssertNotNil(vm.activeError)
  }

  func testSetVisibleRapidDoubleTapCancelsStaleWriteAndConverges() async throws {
    enum StubPersistenceError: Error {
      case staleFailure
    }

    let dbManager = try DatabaseManager.inMemory()
    let service = WaypointService(databaseManager: dbManager)
    let waypoint = Waypoint(
      id: UUID().uuidString,
      name: "Double Tap Test",
      isVisible: true,
      coordinate: CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15)
    )

    let vm = WaypointDetailViewModel(
      waypointService: service,
      editingWaypoint: waypoint,
      startEditable: false
    )

    var firstCallContinuation: CheckedContinuation<Void, Never>?
    var firstCallFinished = false
    var secondCallStartedAfterFirstFinished = false
    var recordedVisibilities: [Bool] = []
    var callIndex = 0

    vm.persistWaypointHandler = { updated in
      callIndex += 1
      let currentCall = callIndex
      recordedVisibilities.append(updated.isVisible)
      if currentCall == 1 {
        await withCheckedContinuation { continuation in
          firstCallContinuation = continuation
        }
        firstCallFinished = true
        // Even if the superseded first write fails after resuming, it must not roll back or set activeError
        throw StubPersistenceError.staleFailure
      } else if currentCall == 2 {
        secondCallStartedAfterFirstFinished = firstCallFinished
      }
    }

    // Rapid double-tap: true -> false -> true -> false
    vm.setVisible(false)
    await Task.yield()
    vm.setVisible(true)
    vm.setVisible(false)

    // While the first write is still suspended, no subsequent write should have started
    await Task.yield()
    XCTAssertEqual(recordedVisibilities, [false])

    // Resume the stale first call
    firstCallContinuation?.resume()
    await vm.waitForPendingVisibilitySave()

    XCTAssertFalse(vm.isVisible)
    XCTAssertNil(vm.activeError)
    // Intermediate cancelled `true` write must be skipped, and final `false` write must run strictly after the first finishes
    XCTAssertEqual(recordedVisibilities, [false, false])
    XCTAssertTrue(secondCallStartedAfterFirstFinished)

    // Confirm originalWaypoint converged to false
    vm.isEditable = true
    vm.setVisible(true)
    vm.revert()
    XCTAssertFalse(vm.isVisible)
  }
}

