//
//  CommandPanelView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import OSLog
import CoreLocation
@MainActor
struct CommandPanelView: View {
  @Environment(PanelManagerViewModel.self) private var viewModel
  @Environment(ChartViewModel.self) private var chartViewModel
  @Environment(AppViewModel.self) private var appViewModel
  @Environment(AppEnvironment.self) private var appEnvironment
  @Environment(\.marineTheme) private var marineTheme
  @Environment(WaypointService.self) private var waypointService
  @Environment(TrackRecordingService.self) private var trackRecordingService
  @Environment(BarometerViewModel.self) private var barometerViewModel
  @Environment(PermissionService.self) private var permissionService

  @Environment(ActiveTrackViewModel.self) private var activeTrackViewModel
  @Environment(OfflineSelectionViewModel.self) private var offlineSelectionViewModel

  @State private var permissionGateType: PermissionGateType? = nil

  var body: some View {
    @Bindable var bindableViewModel = viewModel

    NavigationStack(path: $bindableViewModel.commandPath) {
      VStack(spacing: 0) {
        MessageCarouselView()
          .background(marineTheme.colors.panelBackground)

        List {
          quickActionsSection
          navigationSection
          safetySection
          systemSection
        }
        .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
        .listStyle(.insetGrouped)
        .marineListBackground()
      }
      .navigationTitle("Command Panel")
      .navigationBarTitleDisplayMode(.inline)
      .navigationDestination(for: PanelManagerViewModel.CommandDestination.self) { destination in
        destinationView(for: destination)
      }
      .handleTrackRecordingErrors()
      .alert(
        "Track Recording",
        isPresented: Binding(
          get: { activeTrackViewModel.recordingError != nil },
          set: { if !$0 { activeTrackViewModel.recordingError = nil } }
        ),
        presenting: activeTrackViewModel.recordingError
      ) { _ in
        Button("OK", role: .cancel) { }
      } message: { error in
        Text(error.errorDescription ?? "")
      }
      .toolbar {
        if bindableViewModel.commandPath.isEmpty {
          ToolbarItem(placement: .navigationBarTrailing) {
            MarineCloseButton {
              bindableViewModel.closePanel()
            }
          }
        }
      }
      .sheet(item: $permissionGateType) { gateType in
        PermissionGateView(type: gateType)
          .presentationDetents([.medium, .large])
      }
      .onChange(of: permissionService.locationStatus) { _, status in
        if status == .authorized {
          viewModel.finalizePendingLocationAction()
          permissionGateType = nil
        }
      }
      .onChange(of: permissionService.motionStatus) { _, status in
        if status == .authorized {
          viewModel.finalizePendingMotionAction()
          permissionGateType = nil
        }
      }
      .onChange(of: permissionService.notificationStatus) { _, status in
        if status == .authorized {
          viewModel.finalizePendingNotificationAction()
          permissionGateType = nil
        }
      }
    }
  }

  // MARK: - Sections

  @ViewBuilder
  private var quickActionsSection: some View {
    @Bindable var bindableAppViewModel = appViewModel

    Section {
      HStack(spacing: MarineTheme.Spacing.medium) {
        Toggle("Glove Mode", isOn: $bindableAppViewModel.isGloveModeEnabled)
          .toggleStyle(.marine(icon: .gloveMode))

        Button {
          activeTrackViewModel.requestRecordingState(!activeTrackViewModel.isRecording)
        } label: {
          VStack(spacing: MarineTheme.Spacing.small) {
            Image(marineIcon: .record)
              .font(.title2)
            Text("Track")
              .marineFont(.caption)
          }
          .frame(maxWidth: .infinity, minHeight: marineTheme.metrics.touchTarget)
          .foregroundColor(activeTrackViewModel.isRecording ? marineTheme.colors.textOnActive : marineTheme.colors.textSecondary)
          .background {
            if activeTrackViewModel.isRecording {
              marineTheme.colors.activeToggle
            } else {
              MarineCellBackgroundView()
            }
          }
        }
        .buttonStyle(MarineButtonStyle(.custom))
        .clipShape(RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius))
        .disabled(activeTrackViewModel.isSaving)
      }
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())
    } header: {
      Text("Quick Actions").marineSectionHeader()
    }
  }

  @ViewBuilder
  private var navigationSection: some View {
    Section {
      NavigationLink(value: PanelManagerViewModel.CommandDestination.tracks) {
        Label {
          Text("Tracks").foregroundStyle(.primary)
        } icon: {
          Image(marineIcon: .track).foregroundStyle(.blue)
        }
        .marineFont(.body)
      }
      .marineListCell()

      NavigationLink(value: PanelManagerViewModel.CommandDestination.waypoints) {
        Label {
          Text("Waypoints").foregroundStyle(.primary)
        } icon: {
          Image(marineIcon: .waypoint).foregroundStyle(.blue)
        }
        .marineFont(.body)
      }
      .marineListCell()

      NavigationLink(value: PanelManagerViewModel.CommandDestination.offlineCharts) {
        HStack(spacing: MarineTheme.Spacing.medium) {
          Image(marineIcon: .offlineChart)
            .foregroundStyle(marineTheme.colors.accent)
            .marineFont(.body)

          VStack(alignment: .leading, spacing: 6) {
            Text("Offline Charts")
              .foregroundStyle(.primary)
              .marineFont(.body)

            if let progress = appEnvironment.offlineChartsDownloadProgress {
              ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(marineTheme.colors.accent)
            }
          }

          Spacer()
        }
      }
      .animation(.default, value: appEnvironment.offlineChartsDownloadProgress != nil)
      .marineListCell()
    } header: {
      Text("Navigation").marineSectionHeader()
    }
  }

  @ViewBuilder
  private var safetySection: some View {
    Section {
      AnchorCommandRowView(permissionGateType: $permissionGateType)
      BarometerCommandRowView(permissionGateType: $permissionGateType)
      NavigationLink(value: PanelManagerViewModel.CommandDestination.checklists) {
        Label {
          Text("Checklists").foregroundStyle(.primary)
        } icon: {
          Image(marineIcon: .checklist).foregroundStyle(marineTheme.colors.accent)
        }
        .marineFont(.body)
      }
      .marineListCell()
    } header: {
      Text("Safety").marineSectionHeader()
    }
  }

  @ViewBuilder
  private var systemSection: some View {
    Section {
      NavigationLink(value: PanelManagerViewModel.CommandDestination.settings) {
        Label("Settings", systemImage: MarineIcon.settings.rawValue)
          .marineFont(.body)
      }
      .marineListCell()
    } header: {
      Text("System").marineSectionHeader()
    }
  }

  // MARK: - Navigation Destination Router

  @ViewBuilder
  private func destinationView(for destination: PanelManagerViewModel.CommandDestination) -> some View {
    switch destination {
    case .settings:
      SettingsView()
    case .tracks:
      TracksManagerView()
    case .waypoints:
      WaypointListContainer(waypointService: waypointService)
    case .trackSessionDetail(let sessionID, let session):
      TrackDetailView(
        sessionID: sessionID,
        session: session,
        trackService: appEnvironment.trackService,
        trackRecordingService: trackRecordingService,
        onViewRequested: { id in
          try await chartViewModel.loadAndDisplaySavedTrack(sessionID: id)
          viewModel.closePanel()
        }
      )
    case .waypointDetail(let id, let waypoint):
      WaypointDetailContainer(
        waypointID: id,
        waypoint: waypoint
      )
    case .waypointDraft:
      if let draftViewModel = chartViewModel.activeWaypointDetailViewModel {
        WaypointDetailView(
          viewModel: draftViewModel,
          onModifyPositionRequested: {
            startDraftPositionAdjustment(for: draftViewModel)
          }
        )
      } else {
        Color.clear.onAppear {
          Logger.navigation.error("Waypoint draft destination appeared without an active draft ViewModel.")
        }
      }
    case .baroAlarm:
      BarometerAlarmView(viewModel: barometerViewModel)
    case .anchorAlarm:
      AnchorAlarmView()
    case .geoGarageLogin(let context):
      GeoGarageLoginView(
        offlineMapManager: appEnvironment.offlineMapManager,
        partnerSecretService: appEnvironment.geoGaragePartnerSecretService,
        downloadRepository: appEnvironment.geoGarageDownloadRepository,
        context: context
      )
    case .offlineCharts:
      OfflineRegionsManagerView()
    case .offlineChartDetail(let id):
      OfflineChartDetailView(
        chartID: id,
        downloadRepository: offlineSelectionViewModel.downloadRepository,
        downloadService: offlineSelectionViewModel.downloadService
      )
    case .chartPreferences:
      ChartPreferencesView()
    case .cogPreferences:
      COGPreferencesView()
    case .legalList:
      LegalListView()
    case .legalDetail(let documentID):
      LegalDetailView(documentID: documentID)
    case .versionInfo:
      VersionInfoView()
    case .modelsInfo:
      ModelsInfoView()
#if DEBUG
    case .debugMenu:
      DebugView()
#endif
    case .checklists:
      ChecklistTemplateListView(
        catalogService: appEnvironment.checklistCatalogService,
        sessionService: appEnvironment.checklistSessionService
      )
    case .checklistCategories:
      ChecklistCategoryListView(catalogService: appEnvironment.checklistCatalogService)
    case .checklistCategoryDetail(let payload):
      ChecklistCategoryDetailView(
        payload: payload,
        catalogService: appEnvironment.checklistCatalogService
      )
    case .checklistTemplateDetail(let payload):
      ChecklistTemplateDetailView(
        payload: payload,
        catalogService: appEnvironment.checklistCatalogService,
        sessionService: appEnvironment.checklistSessionService
      )
    case .checklistSession(let payload):
      let environment = appEnvironment
      ChecklistSessionView(
        payload: payload,
        catalogService: appEnvironment.checklistCatalogService,
        sessionService: appEnvironment.checklistSessionService,
        locationProvider: { [weak environment] in
          environment?.lastKnownLocation
        }
      )
    }
  }

  private func startDraftPositionAdjustment(for draftViewModel: WaypointDetailViewModel) {
    let panelViewModel = viewModel
    chartViewModel.startWaypointPositionAdjustment(
      viewModel: draftViewModel,
      onCancel: { [weak panelViewModel] in
        panelViewModel?.resumePanel()
      },
      onConfirm: { [weak draftViewModel, weak panelViewModel] newCoord in
        draftViewModel?.updateCoordinate(newCoord)
        panelViewModel?.updateActiveWaypointDraftCoordinate(newCoord)
        panelViewModel?.resumePanel()
      }
    )
    panelViewModel.suspendPanel()
  }
}

@MainActor
private struct WaypointListContainer: View {
  @State private var viewModel: WaypointListViewModel

  init(waypointService: WaypointService) {
    _viewModel = State(wrappedValue: WaypointListViewModel(waypointService: waypointService))
  }

  var body: some View {
    WaypointListView(viewModel: viewModel)
  }
}
