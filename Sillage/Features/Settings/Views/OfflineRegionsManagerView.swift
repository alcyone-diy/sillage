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
  @Environment(AppEnvironment.self) private var environment
  @Environment(OfflineSelectionViewModel.self) private var offlineSelectionViewModel
  @Environment(ChartViewModel.self) private var chartViewModel
  @Environment(PanelManagerViewModel.self) private var panelManagerViewModel
  @Environment(\.marineTheme) private var marineTheme

  @State private var downloadToDelete: OfflineChartDownload?
  @State private var errorMessage: String?

  private var downloadedCharts: [OfflineChartDownload] {
    environment.geoGarageDownloadRepository?.downloads ?? []
  }

  private var isOfflineAreaDisabled: Bool {
    offlineSelectionViewModel.isSelectionModeActive || !chartViewModel.isOfflineAreaEnabled
  }

  var body: some View {
    Group {
      if downloadedCharts.isEmpty && !offlineSelectionViewModel.isDownloading {
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

          Section {
            OfflineRegionsHeaderView()

            ForEach(downloadedCharts, id: \.id) { download in
              OfflineDownloadRowView(
                download: download,
                onActivate: { activateDownload(download) },
                onDelete: { downloadToDelete = download }
              )
              .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                  Task {
                    await deleteDownload(download)
                  }
                } label: {
                  Label("Delete", systemImage: "trash")
                }
              }
            }
          } header: {
            Text("Downloaded Charts")
          }
          .animation(.default, value: downloadedCharts)
        }
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
    .confirmationDialog(
      "Delete Offline Chart",
      isPresented: Binding(
        get: { downloadToDelete != nil },
        set: { if !$0 { downloadToDelete = nil } }
      ),
      presenting: downloadToDelete
    ) { download in
      Button("Delete \"\(download.layerName)\"", role: .destructive) {
        Task {
          await deleteDownload(download)
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text("Are you sure you want to delete this downloaded chart package?")
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

  private func activateDownload(_ download: OfflineChartDownload) {
    let sharedSecret = AppConfiguration.shared.geoGarageSharedSecret
    guard let customerID = environment.preferencesService?.geoGarageCustomerID, !customerID.isEmpty else {
      errorMessage = String(localized: "User is not authenticated with GeoGarage.")
      return
    }
    Task {
      do {
        try await offlineSelectionViewModel.activateDownload(download, sharedSecret: sharedSecret, customerID: customerID)
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  private func deleteDownload(_ download: OfflineChartDownload) async {
    do {
      if let downloader = environment.geoGarageChartDownloader {
        try await downloader.deleteLocalChart(id: download.id)
      } else {
        try await offlineSelectionViewModel.deleteDownload(download)
      }
    } catch {
      Logger.offline.error("Failed to delete offline chart \(download.layerName, privacy: .public): \(error.localizedDescription, privacy: .public)")
      errorMessage = error.localizedDescription
    }
  }
}

// MARK: - Subviews

private struct OfflineRegionsHeaderView: View {
  @Environment(AppEnvironment.self) private var environment
  @Environment(OfflineSelectionViewModel.self) private var offlineSelectionViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if offlineSelectionViewModel.isDownloading {
        switch offlineSelectionViewModel.downloadPhase {
        case .requesting:
          Text("Requesting chart package…")
            .marineFont(.headline)
          ProgressView()
            .controlSize(.small)

        case .generating(let progress, let message):
          Text(message)
            .marineFont(.headline)
          if let progress {
            ProgressView(value: progress)
              .progressViewStyle(.linear)
              .tint(.accentColor)
          } else {
            ProgressView()
              .controlSize(.small)
          }

        case .downloading(let received, let total):
          HStack {
            Text("Downloading chart…")
              .marineFont(.headline)
            Spacer()
            if total > 0 {
              Text("\(Int64(received).formatted(.byteCount(style: .file))) / \(Int64(total).formatted(.byteCount(style: .file)))")
                .marineFont(.subheadline)
                .foregroundStyle(.secondary)
            }
          }
          if total > 0 {
            ProgressView(value: Double(received), total: Double(total))
              .progressViewStyle(.linear)
              .tint(.accentColor)
          } else {
            ProgressView()
              .controlSize(.small)
          }

        default:
          EmptyView()
        }
      } else {
        let downloads = environment.geoGarageDownloadRepository?.downloads ?? []
        let totalSize = downloads.reduce(0) { $0 + $1.fileSizeBytes }

        Text("\(downloads.count) offline charts")
          .marineFont(.headline)

        Text("Total size: \(totalSize.formatted(.byteCount(style: .file)))")
          .marineFont(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .marineListCell()
  }
}

private struct OfflineDownloadRowView: View {
  let download: OfflineChartDownload
  let onActivate: () -> Void
  let onDelete: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(download.layerName)
          .marineFont(.body)
          .foregroundColor(.primary)
        HStack(spacing: 8) {
          Text(download.layerID.uppercased())
            .marineFont(.caption)
            .fontWeight(.bold)
            .foregroundColor(.blue)
          Text("•")
            .marineFont(.caption)
            .foregroundColor(.secondary)
          Text(download.fileSizeBytes.formatted(.byteCount(style: .file)))
            .marineFont(.caption)
            .foregroundColor(.secondary)
          Text("•")
            .marineFont(.caption)
            .foregroundColor(.secondary)
          Text(download.downloadDate.formatted(date: .abbreviated, time: .omitted))
            .marineFont(.caption)
            .foregroundColor(.secondary)
        }
      }

      Spacer()

      Button(action: onActivate) {
        Image(marineIcon: .trackingFree)
          .foregroundColor(.blue)
      }
      .buttonStyle(.plain)

      Button(action: onDelete) {
        Image(marineIcon: .delete)
          .foregroundColor(.red)
      }
      .buttonStyle(.plain)
    }
    .marineListCell()
  }
}
