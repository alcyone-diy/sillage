//
//  OfflineRegionsManagerView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import OSLog
@MainActor
struct OfflineRegionsManagerView: View {
  @Environment(OfflineSelectionViewModel.self) private var offlineSelectionViewModel
  @Environment(ChartViewModel.self) private var chartViewModel
  @Environment(PanelManagerViewModel.self) private var panelManagerViewModel
  @Environment(\.marineTheme) private var marineTheme

  @State private var itemToDelete: OfflineChartItem?
  @State private var errorMessage: String?

  private var allChartItems: [OfflineChartItem] {
    offlineSelectionViewModel.allChartItems
  }

  /// Offline charts (downloaded and in-progress) grouped by GeoGarage layer type and sorted alphabetically by section title.
  private var groupedCharts: [OfflineChartTypeGroup] {
    offlineSelectionViewModel.groupedCharts
  }

  private var isOfflineAreaDisabled: Bool {
    offlineSelectionViewModel.isSelectionModeActive || !chartViewModel.isOfflineAreaEnabled
  }

  var body: some View {
    Group {
      if allChartItems.isEmpty {
        emptyStateView
      } else {
        List {
          if let warningReason = chartViewModel.offlineAreaWarningReason {
            Section {
              OfflineAreaWarningBannerView(reason: warningReason)
            }
          }

          // Summary section
          Section {
            OfflineRegionsHeaderView()
          }

          // Charts sections grouped by GeoGarage chart type
          ForEach(groupedCharts) { group in
            Section {
              ForEach(group.items) { item in
                let isEnabled = isMatchingChartSelected(for: item)
                let isVisible = chartViewModel.highlightedOfflineRegion?.id == item.id
                OfflineChartItemRowView(item: item, isVisible: isVisible)
                  .swipeActions(edge: .leading, allowsFullSwipe: isEnabled && !isVisible) {
                    if isVisible {
                      Button {
                        withAnimation {
                          chartViewModel.clearOfflineRegionHighlight()
                        }
                      } label: {
                        Label("Hide from Chart", systemImage: MarineIcon.visibilityOff.rawValue)
                      }
                      .tint(marineTheme.colors.cancelAction)
                    } else {
                      Button {
                        if isEnabled {
                          showOnChart(item)
                        }
                      } label: {
                        Label("Show on Chart", systemImage: MarineIcon.visibilityOn.rawValue)
                      }
                      .tint(isEnabled ? .blue : Color(uiColor: .systemGray3))
                      .disabled(!isEnabled)
                    }
                  }
                  .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                      itemToDelete = item
                    } label: {
                      Label("Delete", systemImage: MarineIcon.delete.rawValue)
                    }
                    .tint(.red)
                  }
              }
            } header: {
              Text(group.title).marineSectionHeader()
            }
          }
        }
        .animation(.default, value: allChartItems)
        .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
      }
    }
    .marineListBackground()
    .navigationTitle("Offline Charts")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          offlineSelectionViewModel.startNewSelection()
          panelManagerViewModel.closePanel()
        } label: {
          Image(systemName: "plus")
        }
        .disabled(isOfflineAreaDisabled)
      }
    }
    .alert(
      "Delete Offline Chart?",
      isPresented: Binding(
        get: { itemToDelete != nil },
        set: { if !$0 { itemToDelete = nil } }
      ),
      presenting: itemToDelete
    ) { item in
      Button("Delete", role: .destructive) {
        Task { @MainActor in
          await deleteItem(item)
        }
      }
      Button("Cancel", role: .cancel) {
        itemToDelete = nil
      }
    } message: { item in
      switch item {
      case .downloaded:
        Text("Are you sure you want to delete this downloaded chart package? This action cannot be undone.")
      case .inProgress:
        Text("Are you sure you want to cancel and delete this in-progress chart download?")
      }
    }
    .alert("Error", isPresented: Binding(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )) {
      Button("OK", role: .cancel) {
        errorMessage = nil
      }
    } message: {
      if let errorMessage {
        Text(errorMessage)
      }
    }
  }

  // MARK: - Actions

  private func isMatchingChartSelected(for item: OfflineChartItem) -> Bool {
    guard item.geographicBounds != nil else { return false }
    return chartViewModel.isGeoGarageLayerActive(item.layerID)
  }

  private func showOnChart(_ item: OfflineChartItem) {
    guard let bounds = item.geographicBounds else {
      Logger.offline.warning("Cannot show offline chart on map: bounds are missing.")
      errorMessage = String(localized: "Cannot show offline chart: boundary data is missing.")
      return
    }
    chartViewModel.highlightOfflineRegion(id: item.id, name: item.displayName, bounds: bounds)
    panelManagerViewModel.closePanel()
  }

  private func deleteItem(_ item: OfflineChartItem) async {
    do {
      try await offlineSelectionViewModel.deleteItem(item)
    } catch {
      Logger.offline.error("Failed to delete offline chart \(item.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
      errorMessage = error.localizedDescription
    }
  }

  // MARK: - Empty State

  @ViewBuilder
  private var emptyStateView: some View {
    switch chartViewModel.offlineAreaWarningReason {
    case .unauthenticated:
      ContentUnavailableView {
        Label {
          Text("GeoGarage Sign-In Required")
        } icon: {
          Image(systemName: "person.crop.circle.badge.plus")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(marineTheme.colors.primary)
        }
      } description: {
        Text("Sign in to your GeoGarage account to download and access certified marine charts offline.")
      } actions: {
        NavigationLink(value: PanelManagerViewModel.CommandDestination.geoGarageLogin(context: .initialSetup)) {
          Text("Sign in to GeoGarage")
        }
        .buttonStyle(MarineButtonStyle(.primary))
      }

    case .nonGeoGarageChartActive:
      ContentUnavailableView {
        Label {
          Text("GeoGarage Required")
        } icon: {
          Image(systemName: "map")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(marineTheme.colors.primary)
        }
      } description: {
        Text("Offline maps work only with GeoGarage charts. Switch to GeoGarage in Chart Preferences to download offline charts.")
      } actions: {
        NavigationLink(value: PanelManagerViewModel.CommandDestination.chartPreferences) {
          Text("Chart Preferences")
        }
        .buttonStyle(MarineButtonStyle(.primary))
      }

    case .none:
      ContentUnavailableView {
        Label {
          Text("No Offline Charts")
        } icon: {
          Image(systemName: "arrow.down.circle")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(marineTheme.colors.primary)
        }
      } description: {
        Text("Select an area on the chart to download marine charts for offline navigation.")
      } actions: {
        Button {
          offlineSelectionViewModel.startNewSelection()
          panelManagerViewModel.closePanel()
        } label: {
          Text("Download a Chart")
        }
        .buttonStyle(MarineButtonStyle(.primary))
      }
    }
  }
}

// MARK: - Subviews

private struct OfflineAreaWarningBannerView: View {
  let reason: ChartViewModel.OfflineAreaWarningReason
  @Environment(\.marineTheme) private var marineTheme

  private var destination: PanelManagerViewModel.CommandDestination {
    switch reason {
    case .unauthenticated:
      return .geoGarageLogin(context: .reauthentication)
    case .nonGeoGarageChartActive:
      return .chartPreferences
    }
  }

  private var iconSystemName: String {
    switch reason {
    case .unauthenticated:
      return "person.crop.circle.badge.exclamationmark"
    case .nonGeoGarageChartActive:
      return "exclamationmark.triangle.fill"
    }
  }

  private var title: LocalizedStringKey {
    switch reason {
    case .unauthenticated:
      return "GeoGarage Sign-In Required"
    case .nonGeoGarageChartActive:
      return "GeoGarage Required"
    }
  }

  private var subtitle: LocalizedStringKey {
    switch reason {
    case .unauthenticated:
      return "Sign in to your GeoGarage account to download new offline charts."
    case .nonGeoGarageChartActive:
      return "Offline maps work only with GeoGarage charts. Switch to GeoGarage in Chart Preferences."
    }
  }

  var body: some View {
    NavigationLink(value: destination) {
      HStack(alignment: .center, spacing: MarineTheme.Spacing.actionRowHorizontal) {
        Image(systemName: iconSystemName)
          .marineFont(.title2)
          .foregroundStyle(marineTheme.colors.warning)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: MarineTheme.Spacing.tiny) {
          Text(title)
            .marineFont(.headline)
            .foregroundStyle(.primary)

          Text(subtitle)
            .marineFont(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .marineListCell()
  }
}

private struct OfflineRegionsHeaderView: View {
  @Environment(OfflineSelectionViewModel.self) private var offlineSelectionViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      let downloadsCount = offlineSelectionViewModel.downloadedCharts.count
      let totalSize = offlineSelectionViewModel.totalDownloadedSize

      Text("\(downloadsCount) offline charts")
        .marineFont(.headline)

      Text("Total size: \(totalSize.marineFormatted)")
        .marineFont(.subheadline)
        .foregroundStyle(.secondary)
    }
    .marineListCell()
  }
}

private struct OfflineChartItemRowView: View {
  let item: OfflineChartItem
  var isVisible: Bool = false

  var body: some View {
    switch item {
    case .downloaded(let download):
      NavigationLink(value: PanelManagerViewModel.CommandDestination.offlineChartDetail(id: download.id)) {
        OfflineDownloadRowView(download: download, isVisible: isVisible)
      }
      .marineListCell()
      .accessibilityLabel(accessibilityLabel(for: download))
    case .inProgress(let pending, let phase):
      OfflineInProgressRowView(pending: pending, phase: phase)
    }
  }

  private func accessibilityLabel(for download: OfflineChartDownload) -> Text {
    let title: String
    if let custom = download.customName, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      title = custom.trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
      title = download.layerName.isEmpty ? download.downloadDate.formatted(date: .abbreviated, time: .shortened) : download.layerName
    }
    let date = download.downloadDate.formatted(date: .abbreviated, time: .shortened)
    let size = download.fileSize?.marineFormatted

    let components: [String?] = [
      title,
      date,
      size,
      isVisible ? String(localized: "Visible on chart") : nil
    ]
    let labelString = components.compactMap { $0 }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: ", ")
    return Text(labelString)
  }
}

private struct OfflineDownloadRowView: View {
  let download: OfflineChartDownload
  var isVisible: Bool = false
  @Environment(\.marineTheme) private var marineTheme

  private var title: String {
    if let custom = download.customName, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return custom.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return download.layerName.isEmpty ? download.downloadDate.formatted(date: .abbreviated, time: .shortened) : download.layerName
  }

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .marineFont(.body)
          .foregroundColor(.primary)

        HStack(spacing: 6) {
          Text(download.downloadDate.formatted(date: .abbreviated, time: .shortened))
            .marineFont(.caption)
            .foregroundColor(.secondary)

          if let size = download.fileSize {
            Text("•")
              .marineFont(.caption)
              .foregroundColor(.secondary)
            Text(size.marineFormatted)
              .marineFont(.caption)
              .foregroundColor(.secondary)
          }
        }
      }

      Spacer()

      if isVisible {
        Image(marineIcon: .visibilityOn)
          .marineFont(.body)
          .foregroundStyle(marineTheme.colors.primary)
          .accessibilityHidden(true)
      }
    }
  }
}

private struct OfflineInProgressRowView: View {
  let pending: PendingCAASDownload
  let phase: GeoGarageDownloadPhaseState

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(pending.createdAt.formatted(date: .abbreviated, time: .shortened))
          .marineFont(.body)
          .foregroundColor(.primary)

        Spacer()

        statusBadge
      }

      progressBar

      statusDetailText
        .marineFont(.caption)
        .foregroundColor(.secondary)
    }
    .marineListCell()
  }

  @ViewBuilder
  private var statusBadge: some View {
    switch phase {
    case .queued:
      Label("Queued", systemImage: "clock")
        .marineFont(.caption)
        .foregroundColor(.secondary)
    case .waitingForNetwork:
      Label("Waiting for connection", systemImage: "wifi.slash")
        .marineFont(.caption)
        .foregroundColor(.orange)
    case .requesting:
      HStack(spacing: 4) {
        ProgressView()
          .controlSize(.mini)
        Text("Requesting")
          .marineFont(.caption)
          .foregroundColor(.secondary)
      }
    case .generating:
      HStack(spacing: 4) {
        ProgressView()
          .controlSize(.mini)
        Text("Generating")
          .marineFont(.caption)
          .foregroundColor(.accentColor)
      }
    case .downloading:
      HStack(spacing: 4) {
        ProgressView()
          .controlSize(.mini)
        Text("Downloading")
          .marineFont(.caption)
          .foregroundColor(.accentColor)
      }
    case .failed:
      Label("Failed", systemImage: "exclamationmark.triangle")
        .marineFont(.caption)
        .foregroundColor(.red)
    case .idle, .completed, .cancelled:
      EmptyView()
    }
  }

  @ViewBuilder
  private var progressBar: some View {
    switch phase {
    case .generating(let progress, _):
      if let progress {
        ProgressView(value: progress)
          .progressViewStyle(.linear)
          .tint(.accentColor)
      }
    case .downloading(let received, let total):
      if total > 0 {
        ProgressView(value: Double(received), total: Double(total))
          .progressViewStyle(.linear)
          .tint(.accentColor)
      }
    default:
      EmptyView()
    }
  }

  @ViewBuilder
  private var statusDetailText: some View {
    switch phase {
    case .queued:
      Text("Waiting in download queue…")
    case .waitingForNetwork(let message):
      Text(message)
    case .requesting:
      Text("Requesting package…")
    case .generating(_, let message):
      Text(message)
    case .downloading(let received, let total):
      if total > 0 {
        Text("\(Int64(received).formatted(.byteCount(style: .file))) / \(Int64(total).formatted(.byteCount(style: .file)))")
      } else {
        Text("Downloading…")
      }
    case .failed(let errorMessage):
      Text(errorMessage)
    case .idle, .completed, .cancelled:
      Text("In progress")
    }
  }
}

