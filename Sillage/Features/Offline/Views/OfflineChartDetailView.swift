//
//  OfflineChartDetailView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-22.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import OSLog

@MainActor
struct OfflineChartDetailView: View {
  @Bindable var viewModel: OfflineChartDetailViewModel
  @Environment(ChartViewModel.self) private var chartViewModel
  @Environment(PanelManagerViewModel.self) private var panelManagerViewModel
  @Environment(\.marineTheme) private var marineTheme
  @Environment(\.dismiss) private var dismiss

  @State private var showDeleteConfirmation = false
  @FocusState private var isNameFieldFocused: Bool

  var body: some View {
    List {
      // MARK: - Missing File Warning Banner
      if viewModel.fileStatus == .fileMissing {
        Section {
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.title2)
              .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
              Text("File Not Found on Disk")
                .marineFont(.headline)
                .foregroundStyle(.primary)

              Text("The underlying .mbtiles file is missing or unreachable in local storage. You can delete this orphaned record.")
                .marineFont(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .marineListCell()
        }
      }

      // MARK: - Identity Section
      Section {
        if viewModel.isEditing {
          VStack(alignment: .leading, spacing: MarineTheme.Spacing.small) {
            Text("Name")
              .marineFont(.caption)
              .foregroundStyle(.secondary)

            HStack(spacing: 8) {
              TextField("Chart Name", text: $viewModel.editableName)
                .marineFont(.body)
                .focused($isNameFieldFocused)
                .submitLabel(.done)
                .onSubmit {
                  performSave()
                }
                .frame(minHeight: max(44, marineTheme.minTouchTarget))

              if !viewModel.editableName.isEmpty {
                Button {
                  viewModel.editableName = ""
                } label: {
                  Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear text")
              }
            }
          }
          .marineListCell()
        } else {
          VStack(alignment: .leading, spacing: MarineTheme.Spacing.small) {
            Text("Name")
              .marineFont(.caption)
              .foregroundStyle(.secondary)

            Text(viewModel.chartName)
              .marineFont(.title3)
              .foregroundStyle(.primary)

            HStack(spacing: 6) {
              Text(viewModel.layerBrand)
                .marineFont(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(marineTheme.colors.accent.opacity(0.15))
                .foregroundStyle(marineTheme.colors.accent)
                .clipShape(Capsule())

              Text("MBTiles")
                .marineFont(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
            }
            .padding(.top, 2)
          }
          .marineListCell()
        }
      }

      // MARK: - Package Characteristics
      Section(header: Text("Characteristics")) {
        DetailRow(
          label: String(localized: "File Size"),
          value: {
            switch viewModel.fileStatus {
            case .checking:
              return String(localized: "Checking…")
            case .ready:
              if let bytes = viewModel.fileSizeBytes {
                return bytes.formatted(.byteCount(style: .file))
              }
              return String(localized: "Unavailable")
            case .fileMissing:
              return String(localized: "File Missing")
            }
          }()
        )
        .marineListCell()

        if let maxZoom = viewModel.maxZoom {
          DetailRow(
            label: String(localized: "Max Zoom Level"),
            value: "Zoom \(maxZoom)"
          )
          .marineListCell()
        }

        if let downloadDate = viewModel.downloadDate {
          DetailRow(
            label: String(localized: "Downloaded On"),
            value: downloadDate.formatted(date: .abbreviated, time: .shortened)
          )
          .marineListCell()
        }
      }

      // MARK: - Geographic Coverage
      Section(header: Text("Geographic Coverage")) {
        if let area = viewModel.geographicArea {
          let nm2 = area.converted(to: .squareNauticalMiles).value
          DetailRow(
            label: String(localized: "Surface Area"),
            value: String(format: "%.1f NM²", nm2)
          )
          .marineListCell()
        }

        if let center = viewModel.formattedCenterCoordinate {
          DetailRow(
            label: String(localized: "Center Coordinates"),
            value: center
          )
          .marineListCell()
        }

        if let sw = viewModel.formattedSouthWestCoordinate {
          DetailRow(
            label: String(localized: "South-West Bound"),
            value: sw
          )
          .marineListCell()
        }

        if let ne = viewModel.formattedNorthEastCoordinate {
          DetailRow(
            label: String(localized: "North-East Bound"),
            value: ne
          )
          .marineListCell()
        }
      }

      // MARK: - Actions Section
      Section {
        Button {
          viewModel.showOnChart(using: chartViewModel, panelManager: panelManagerViewModel)
        } label: {
          Label("Show on Chart", systemImage: "map")
            .marineFont(.body)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .disabled(viewModel.geographicBounds == nil)
        .marineListCell()

        Button(role: .destructive) {
          showDeleteConfirmation = true
        } label: {
          HStack {
            Spacer()
            if viewModel.isDeleting {
              ProgressView()
                .controlSize(.small)
            } else {
              Label("Delete Chart", systemImage: "trash")
                .marineFont(.body)
                .foregroundStyle(.red)
            }
            Spacer()
          }
        }
        .disabled(viewModel.isDeleting)
        .marineListCell()
      }
    }
    .navigationTitle("Chart Details")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if viewModel.isEditing {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            viewModel.cancelEditing()
          }
        }

        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            performSave()
          }
          .disabled(viewModel.isSaveDisabled)
        }
      } else {
        ToolbarItem(placement: .primaryAction) {
          Button("Edit") {
            viewModel.startEditing()
          }
        }
      }
    }
    .onChange(of: viewModel.isEditing) { _, isEditing in
      if isEditing {
        isNameFieldFocused = true
      }
    }
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .marineListBackground()
    .confirmationDialog(
      "Delete Offline Chart",
      isPresented: $showDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button("Delete \"\(viewModel.chartName)\"", role: .destructive) {
        performDelete()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Are you sure you want to delete this offline chart package? This will remove the map files from local storage.")
    }
    .alert("Error", isPresented: Binding(
      get: { viewModel.errorMessage != nil },
      set: { if !$0 { viewModel.errorMessage = nil } }
    )) {
      Button("OK", role: .cancel) {
        viewModel.errorMessage = nil
      }
    } message: {
      if let errorMessage = viewModel.errorMessage {
        Text(errorMessage)
      }
    }
  }

  // MARK: - Private Helpers

  private func performSave() {
    guard !viewModel.isSaveDisabled else { return }
    Task { @MainActor in
      do {
        try await viewModel.saveCustomName()
      } catch {
        viewModel.errorMessage = error.localizedDescription
      }
    }
  }

  private func performDelete() {
    Task { @MainActor in
      do {
        try await viewModel.deleteChart()
        dismiss()
      } catch {
        viewModel.errorMessage = error.localizedDescription
      }
    }
  }
}

// MARK: - Subcomponents

private struct DetailRow: View {
  let label: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .marineFont(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .marineFont(.body)
        .foregroundStyle(.primary)
        .textSelection(.enabled)
    }
  }
}
