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
  @State private var viewModel: OfflineChartDetailViewModel
  @Environment(ChartViewModel.self) private var chartViewModel
  @Environment(OfflineSelectionViewModel.self) private var offlineSelectionViewModel: OfflineSelectionViewModel?
  @Environment(PanelManagerViewModel.self) private var panelManagerViewModel
  @Environment(\.marineTheme) private var marineTheme
  @Environment(\.dismiss) private var dismiss

  @State private var showDeleteConfirmation = false

  init(
    chartID: UUID,
    downloadRepository: GeoGarageDownloadRepositoryProtocol,
    downloadService: GeoGarageDownloadServiceProtocol? = nil
  ) {
    _viewModel = State(wrappedValue: OfflineChartDetailViewModel(
      chartID: chartID,
      downloadRepository: downloadRepository,
      downloadService: downloadService
    ))
  }

  init(viewModel: OfflineChartDetailViewModel) {
    _viewModel = State(wrappedValue: viewModel)
  }

  var body: some View {
    VStack(spacing: 0) {
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
                  .foregroundStyle(marineTheme.colors.textPrimary)

                Text("The underlying .mbtiles file is missing or unreachable in local storage. You can delete this orphaned record.")
                  .marineFont(.subheadline)
                  .foregroundStyle(marineTheme.colors.textSecondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
            .marineListCell()
          }
        }

        // MARK: - Identity Section (Editing)
        if viewModel.isEditing {
          Section {
            VStack(alignment: .leading, spacing: MarineTheme.Spacing.small) {
              Text("Name")
                .marineFont(.caption)
                .foregroundStyle(marineTheme.colors.textSecondary)

              HStack(spacing: 8) {
                TextField("Chart Name", text: $viewModel.editableName)
                  .marineFont(.body)
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
                      .foregroundStyle(marineTheme.colors.textSecondary)
                      .frame(minWidth: 44, minHeight: 44)
                  }
                  .buttonStyle(.plain)
                  .accessibilityLabel("Clear text")
                }
              }
            }
            .marineListCell()
          }
        }

        // MARK: - Package Characteristics
        Section {
          HStack {
            Text("Format")
              .marineFont(.body)
              .foregroundStyle(marineTheme.colors.textPrimary)

            Spacer()

            HStack(spacing: 6) {
              if !viewModel.layerBrand.isEmpty {
                Text(viewModel.layerBrand)
                  .marineFont(.caption)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 4)
                  .background(marineTheme.colors.accent.opacity(0.15))
                  .foregroundStyle(marineTheme.colors.accent)
                  .clipShape(Capsule())
              }

              Text("MBTiles")
                .marineFont(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(marineTheme.colors.textSecondary.opacity(0.15))
                .foregroundStyle(marineTheme.colors.textSecondary)
                .clipShape(Capsule())
            }
          }
          .marineListCell()

          DetailRow(
            label: "File Size",
            value: {
              switch viewModel.fileStatus {
              case .checking:
                return String(localized: "Checking…")
              case .ready:
                if let bytes = viewModel.fileSizeBytes {
                  return bytes.marineFormatted
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
              label: "Max Zoom Level",
              value: "Zoom \(maxZoom)"
            )
            .marineListCell()
          }

          if let downloadDate = viewModel.downloadDate {
            DetailRow(
              label: "Downloaded On",
              value: downloadDate.formatted(date: .abbreviated, time: .shortened)
            )
            .marineListCell()
          }
        } header: {
          Text("Characteristics").marineSectionHeader()
        }

        // MARK: - Geographic Coverage
        Section {
          if let area = viewModel.geographicArea {
            DetailRow(
              label: "Surface Area",
              value: area.marineFormatted
            )
            .marineListCell()
          }

          if let center = viewModel.formattedCenterCoordinate {
            DetailRow(
              label: "Center Coordinates",
              value: center
            )
            .marineListCell()
          }

          if let sw = viewModel.formattedSouthWestCoordinate {
            DetailRow(
              label: "South-West Bound",
              value: sw
            )
            .marineListCell()
          }

          if let ne = viewModel.formattedNorthEastCoordinate {
            DetailRow(
              label: "North-East Bound",
              value: ne
            )
            .marineListCell()
          }

          if viewModel.isEditing {
            Button(action: {
              startModifyingZone()
            }) {
              HStack {
                Image(marineIcon: .edit)
                Text("Change Zone")
              }
            }
            .buttonStyle(MarineButtonStyle(.secondary))
            .disabled(isChangeZoneDisabled)
            .marineListCell()
          }
        } header: {
          Text("Geographic Coverage").marineSectionHeader()
        } footer: {
          if viewModel.isEditing {
            Button(action: {
              showDeleteConfirmation = true
            }) {
              HStack {
                Image(marineIcon: .delete)
                Text("Delete Chart")
              }
            }
            .buttonStyle(MarineButtonStyle(.destructive))
            .disabled(viewModel.isDeleting)
            .textCase(nil)
            .padding(.top, MarineTheme.Spacing.medium)
          }
        }
      }
      .listStyle(.insetGrouped)
      .marineListBackground()
      .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)

      // MARK: - Footer (Normal Mode)
      if !viewModel.isEditing {
        let isEnabled = viewModel.geographicBounds != nil && chartViewModel.isGeoGarageLayerActive(viewModel.layerID)
        let isVisible = chartViewModel.highlightedOfflineRegion?.id == viewModel.chartID
        VStack(spacing: MarineTheme.Spacing.small) {
          if isVisible {
            Button(action: {
              withAnimation {
                chartViewModel.clearOfflineRegionHighlight()
              }
            }) {
              HStack {
                Image(marineIcon: .visibilityOff)
                Text("Hide from Chart")
              }
            }
            .buttonStyle(MarineButtonStyle(.secondary))
          } else {
            Button(action: {
              if isEnabled {
                viewModel.showOnChart(using: chartViewModel, panelManager: panelManagerViewModel)
              }
            }) {
              HStack {
                Image(marineIcon: .visibilityOn)
                Text("Show on Chart")
              }
            }
            .buttonStyle(MarineButtonStyle(.primary))
            .disabled(!isEnabled)
          }
        }
        .padding(MarineTheme.Spacing.medium)
        .background(marineTheme.colors.surfaceBackground)
      }
    }
    .alert(
      "Delete Offline Chart?",
      isPresented: $showDeleteConfirmation
    ) {
      Button("Delete", role: .destructive) {
        performDelete()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Are you sure you want to delete this offline chart package? This action cannot be undone.")
    }
    .navigationTitle(
      viewModel.isEditing
        ? String(localized: "Edit Chart")
        : (viewModel.chartName.isEmpty ? String(localized: "Unnamed Chart") : viewModel.chartName)
    )
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(viewModel.isEditing)
    .toolbar {
      if viewModel.isEditing {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            viewModel.cancelEditing()
          } label: {
            Image(marineIcon: .close)
              .padding(8)
              .contentShape(Rectangle())
          }
          .accessibilityLabel(String(localized: "Cancel"))
        }

        ToolbarItem(placement: .confirmationAction) {
          Button {
            performSave()
          } label: {
            Image(marineIcon: .save)
              .padding(8)
              .contentShape(Rectangle())
          }
          .disabled(viewModel.isSaveDisabled)
          .accessibilityLabel(String(localized: "Save"))
        }
      } else {
        ToolbarItem(placement: .primaryAction) {
          Button("Edit") {
            viewModel.startEditing()
          }
        }
      }
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
    .task {
      viewModel.loadMetadata()
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

  private var isChangeZoneDisabled: Bool {
    viewModel.isDeleting ||
    viewModel.isSaving ||
    (offlineSelectionViewModel?.isSelectionModeActive ?? false) ||
    !chartViewModel.isOfflineAreaEnabled
  }

  private func startModifyingZone() {
    guard let offlineSelectionViewModel, let download = viewModel.chartDownload else { return }
    let nameToPreserve = viewModel.editableName.trimmingCharacters(in: .whitespacesAndNewlines)
    offlineSelectionViewModel.startModifyingZone(
      for: download,
      customName: nameToPreserve.isEmpty ? nil : nameToPreserve,
      padding: marineTheme.offlineSelectionEdgeInsets
    )
    panelManagerViewModel.closePanel()
  }
}

// MARK: - Subcomponents

private typealias DetailRow = MarineDetailRow
