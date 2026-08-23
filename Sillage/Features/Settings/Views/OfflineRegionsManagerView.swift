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
        ContentUnavailableView {
          Label("No Offline Charts", systemImage: "map.slash")
        } description: {
          if chartViewModel.showOfflineAreaWarning {
            Text("⚠️ Offline maps require GeoGarage. Switch to GeoGarage in Chart Preferences to download offline charts.")
          } else {
            Text("Tap '+' to select an area on the chart to download.")
          }
        } actions: {
          if chartViewModel.showOfflineAreaWarning {
            NavigationLink(value: PanelManagerViewModel.CommandDestination.chartPreferences) {
              Text("Chart Preferences")
            }
            .buttonStyle(.borderedProminent)
          }
        }
      } else {
        List {
          if chartViewModel.showOfflineAreaWarning {
            Section {
              NavigationLink(value: PanelManagerViewModel.CommandDestination.chartPreferences) {
                HStack(alignment: .top, spacing: 12) {
                  Text("⚠️")
                    .font(.title2)

                  VStack(alignment: .leading, spacing: 4) {
                    Text("GeoGarage Required")
                      .marineFont(.headline)
                      .foregroundStyle(.primary)

                    Text("Offline maps work only with GeoGarage charts. Switch to GeoGarage in Chart Preferences.")
                      .marineFont(.subheadline)
                      .foregroundStyle(.secondary)
                      .fixedSize(horizontal: false, vertical: true)
                  }
                }
              }
              .marineListCell()
            }
          }

          // Summary section
          Section {
            OfflineRegionsHeaderView()
          }

          // Charts sections grouped by GeoGarage chart type
          ForEach(groupedCharts) { group in
            Section(header: Text(group.title)) {
              ForEach(group.items) { item in
                let isEnabled = isMatchingChartSelected(for: item)
                OfflineChartItemRowView(item: item)
                  .swipeActions(edge: .leading, allowsFullSwipe: isEnabled) {
                    Button {
                      if isEnabled {
                        showOnChart(item)
                      }
                    } label: {
                      Label("Show on chart", systemImage: MarineIcon.offlineChart.rawValue)
                    }
                    .tint(isEnabled ? .blue : Color(uiColor: .systemGray3))
                    .disabled(!isEnabled)
                  }
                  .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button {
                      itemToDelete = item
                    } label: {
                      Label("Delete", systemImage: MarineIcon.delete.rawValue)
                    }
                    .tint(.red)
                  }
              }
            }
          }
        }
        .animation(.default, value: allChartItems)
        .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
        .marineListBackground()
      }
    }
    .navigationTitle("Offline Charts")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          offlineSelectionViewModel.isSelectionModeActive = true
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
      return
    }
    chartViewModel.fitBounds(bounds)
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
}

// MARK: - Subviews

private struct OfflineRegionsHeaderView: View {
  @Environment(OfflineSelectionViewModel.self) private var offlineSelectionViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      let downloadsCount = offlineSelectionViewModel.downloadedCharts.count
      let totalSize = offlineSelectionViewModel.totalDownloadedSize

      Text("\(downloadsCount) offline charts")
        .marineFont(.headline)

      Text("Total size: \(totalSize.formatted(.byteCount(style: .file)))")
        .marineFont(.subheadline)
        .foregroundStyle(.secondary)
    }
    .marineListCell()
  }
}

private struct OfflineChartItemRowView: View {
  let item: OfflineChartItem

  var body: some View {
    switch item {
    case .downloaded(let download):
      NavigationLink(value: PanelManagerViewModel.CommandDestination.offlineChartDetail(id: download.id)) {
        OfflineDownloadRowView(download: download)
      }
      .marineListCell()
    case .inProgress(let pending, let phase):
      OfflineInProgressRowView(pending: pending, phase: phase)
    }
  }
}

private struct OfflineDownloadRowView: View {
  let download: OfflineChartDownload

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

          if let size = download.fileSizeBytes {
            Text("•")
              .marineFont(.caption)
              .foregroundColor(.secondary)
            Text(size.formatted(.byteCount(style: .file)))
              .marineFont(.caption)
              .foregroundColor(.secondary)
          }
        }
      }

      Spacer()
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

