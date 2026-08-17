//
//  GeoGarageOfflineDownloadView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-17.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import CoreLocation

/// View for configuring and downloading GeoGarage offline chart packages (MBTiles)
/// based on the current camera viewport, and managing existing local offline charts.
struct GeoGarageOfflineDownloadView: View {

  @State var viewModel: GeoGarageOfflineViewModel
  @Environment(\.marineTheme) private var marineTheme
  @Environment(AppEnvironment.self) private var appEnvironment
  @Environment(ChartViewModel.self) private var chartViewModel
  @Environment(GeoGarageAuthService.self) private var authService

  @State private var downloadToDelete: OfflineChartDownload?
  @State private var showDeleteConfirmation = false
  @State private var errorMessage: String?

  private let areaFormatter: MeasurementFormatter = {
    let formatter = MeasurementFormatter()
    formatter.unitOptions = .naturalScale
    formatter.numberFormatter.maximumFractionDigits = 1
    return formatter
  }()

  private var isErrorPresented: Binding<Bool> {
    Binding(
      get: {
        if case .failed = viewModel.downloadPhase { return true }
        return errorMessage != nil
      },
      set: { isPresenting in
        if !isPresenting {
          errorMessage = nil
          if case .failed = viewModel.downloadPhase {
            viewModel.downloadPhase = .idle
          }
        }
      }
    )
  }

  var body: some View {
    Form {
      if viewModel.isDownloading {
        activeDownloadSection
      } else {
        newDownloadSection
      }

      downloadedChartsSection
    }
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .marineListBackground()
    .navigationTitle("GeoGarage Offline")
    .navigationBarTitleDisplayMode(.inline)
    .confirmationDialog(
      "Delete Offline Chart",
      isPresented: $showDeleteConfirmation,
      presenting: downloadToDelete
    ) { download in
      Button("Delete \"\(download.layerName)\"", role: .destructive) {
        Task {
          await viewModel.deleteDownload(download)
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: { download in
      Text("Are you sure you want to delete this downloaded chart package?")
    }
    .alert("Error", isPresented: isErrorPresented) {
      Button("OK", role: .cancel) {
        errorMessage = nil
        viewModel.downloadPhase = .idle
      }
    } message: {
      if case .failed(let msg) = viewModel.downloadPhase {
        Text(msg)
      } else if let errorMessage {
        Text(errorMessage)
      }
    }
  }

  // MARK: - Sections

  @ViewBuilder
  private var activeDownloadSection: some View {
    Section(header: Text("Current Download").marineFont(.headline)) {
      VStack(alignment: .leading, spacing: 12) {
        switch viewModel.downloadPhase {
        case .requesting:
          HStack(spacing: 12) {
            ProgressView()
              .controlSize(.regular)
            Text("Requesting chart package from server…")
              .marineFont(.body)
          }

        case .generating(let progress, let message):
          VStack(alignment: .leading, spacing: 8) {
            Text(message)
              .marineFont(.body)
            if let progress {
              ProgressView(value: progress, total: 1.0)
                .tint(.blue)
              Text("\(Int(progress * 100))%")
                .marineFont(.caption)
                .foregroundColor(.secondary)
            } else {
              ProgressView()
                .controlSize(.regular)
            }
          }

        case .downloading(let received, let total):
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("Downloading archive…")
                .marineFont(.body)
              Spacer()
              Text("\(received / (1024 * 1024)) MB / \(total / (1024 * 1024)) MB")
                .marineFont(.caption)
                .foregroundColor(.secondary)
            }
            if total > 0 {
              ProgressView(value: Double(received), total: Double(total))
                .tint(.blue)
            } else {
              ProgressView()
            }
          }

        default:
          EmptyView()
        }

        Button(role: .destructive, action: {
          viewModel.cancelDownload()
        }) {
          HStack {
            Spacer()
            Text("Cancel Download")
              .marineFont(.body)
              .fontWeight(.semibold)
              .foregroundColor(.red)
            Spacer()
          }
        }
        .buttonStyle(MarineButtonStyle())
      }
      .padding(.vertical, 8)
      .marineListCell()
    }
  }

  @ViewBuilder
  private var newDownloadSection: some View {
    @Bindable var vm = viewModel

    Section(header: Text("New Offline Area").marineFont(.headline)) {
      if !vm.availableLayers.isEmpty {
        Picker("Hydrographic Layer", selection: $vm.selectedLayerID) {
          ForEach(vm.availableLayers) { layer in
            Text(layer.brandName).tag(layer.layer)
          }
        }
        .marineFont(.body)
        .marineListCell()
      }

      HStack {
        Text("Area Name")
          .marineFont(.body)
        TextField("e.g. South Brittany", text: $vm.customName)
          .marineFont(.body)
          .multilineTextAlignment(.trailing)
      }
      .marineListCell()

      if let bounds = vm.currentViewportBounds {
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text("Selected Viewport Area")
              .marineFont(.body)
            Spacer()
            Text(areaFormatter.string(from: bounds.estimatedArea))
              .marineFont(.subheadline)
              .foregroundColor(.secondary)
          }
          Text("Bounds: \(String(format: "%.2f°N, %.2f°E", bounds.northEast.latitude, bounds.northEast.longitude)) to \(String(format: "%.2f°N, %.2f°E", bounds.southWest.latitude, bounds.southWest.longitude))")
            .marineFont(.caption)
            .foregroundColor(.secondary)
        }
        .marineListCell()
      } else {
        Text("No active map viewport detected. Pan or zoom the chart first.")
          .marineFont(.caption)
          .foregroundColor(.red)
          .marineListCell()
      }

      Button(action: {
        startDownload()
      }) {
        HStack {
          Spacer()
          Image(marineIcon: .save)
          Text("Download Current Viewport")
            .marineFont(.headline)
            .foregroundColor(.blue)
          Spacer()
        }
      }
      .disabled(vm.currentViewportBounds == nil)
      .buttonStyle(MarineButtonStyle())
      .marineListCell()
    }
  }

  @ViewBuilder
  private var downloadedChartsSection: some View {
    Section(header: Text("Downloaded Charts").marineFont(.headline)) {
      if viewModel.downloadedCharts.isEmpty {
        Text("No GeoGarage offline charts downloaded yet.")
          .marineFont(.body)
          .foregroundColor(.secondary)
          .marineListCell()
      } else {
        ForEach(viewModel.downloadedCharts, id: \.id) { download in
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
                Text(download.downloadDate.formatted(date: .abbreviated, time: .omitted))
                  .marineFont(.caption)
                  .foregroundColor(.secondary)
              }
            }

            Spacer()

            Button(action: {
              activateDownload(download)
            }) {
              Image(marineIcon: .trackingFree)
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)

            Button(action: {
              downloadToDelete = download
              showDeleteConfirmation = true
            }) {
              Image(marineIcon: .delete)
                .foregroundColor(.red)
            }
            .buttonStyle(.plain)
          }
          .marineListCell()
        }
      }
    }
  }

  // MARK: - Helpers

  private func startDownload() {
    guard let customerID = appEnvironment.preferencesService?.geoGarageCustomerID, !customerID.isEmpty else {
      errorMessage = String(localized: "User is not authenticated with GeoGarage. Please login first.")
      return
    }
    let caasKey = AppConfiguration.shared.geoGarageCaasApiKey
    Task {
      let token = await KeychainManager.shared.retrieveToken(for: "geogarage_access_token") ?? ""
      let apiKey = (!caasKey.isEmpty && caasKey != "test_caas_api_key") ? caasKey : token
      viewModel.startDownload(apiKey: apiKey, customerID: customerID)
    }
  }

  private func activateDownload(_ download: OfflineChartDownload) {
    let sharedSecret = AppConfiguration.shared.geoGarageSharedSecret
    guard let customerID = appEnvironment.preferencesService?.geoGarageCustomerID, !customerID.isEmpty else {
      errorMessage = String(localized: "User is not authenticated with GeoGarage.")
      return
    }
    Task {
      do {
        try await viewModel.activateDownload(download, sharedSecret: sharedSecret, customerID: customerID)
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }
}
