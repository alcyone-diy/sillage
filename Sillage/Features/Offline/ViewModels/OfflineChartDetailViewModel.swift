//
//  OfflineChartDetailViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-22.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import CoreLocation
import Foundation
import Observation
import OSLog
import SwiftUI

/// Observable ViewModel managing the presentation and lifecycle actions for an offline chart package.
///
/// **Technical Design Choices**:
/// - **Zero Dummy Values (Strict Optionals)**: If the physical `.mbtiles` file is missing or inaccessible on disk,
///   `fileSizeBytes` is set to `nil` (never a dummy `0 KB`), and `fileStatus` transitions to `.fileMissing`.
/// - **Off-MainActor Geometric Parsing & File Inspection**: WKT polygon parsing and file system checks are executed asynchronously via `Task.detached`
///   to ensure high UI responsiveness without blocking the main thread.
/// - **High-Precision Marine Coordinates**: Coordinates are formatted strictly in DDM (Degrees Decimal Minutes)
///   without truncation of `CLLocationDegrees` (`Double`).
@Observable
@MainActor
final class OfflineChartDetailViewModel {

  // MARK: - State Types

  enum FileStatus: Equatable, Sendable {
    case checking
    case ready
    case fileMissing
  }

  // MARK: - Injected Dependencies

  let chartID: UUID
  private let downloadRepository: GeoGarageDownloadRepositoryProtocol
  private let downloadService: GeoGarageDownloadServiceProtocol?

  // MARK: - Observable UI Properties

  private(set) var chartDownload: OfflineChartDownload?
  private(set) var fileStatus: FileStatus = .checking

  /// Indicates whether the chart detail view is currently in edit mode (renaming).
  var isEditing: Bool = false

  /// The working name being edited by the user in edit mode.
  var editableName: String = ""

  /// Indicates whether saving is currently disabled (e.g. while performing an async save or when the input is empty).
  var isSaveDisabled: Bool {
    isSaving || editableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Indicates whether a save operation is actively running.
  private(set) var isSaving: Bool = false

  /// The human-readable presentation name of the offline chart package.
  /// Pure presentation logic: falls back from user customName -> layerName -> localized "Unknown Chart".
  var chartName: String {
    if let custom = chartDownload?.customName, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return custom.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let layer = chartDownload?.layerName, !layer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return layer
    }
    return String(localized: "Unknown Chart")
  }

  /// The layer identifier (e.g. "shom", "ukho", "noaa").
  var layerID: String {
    chartDownload?.layerID ?? ""
  }

  /// Brand name or title for the cartographic provider.
  var layerBrand: String {
    chartDownload?.layerName ?? layerID.uppercased()
  }

  /// Physical file size on disk in bytes. Strict `nil` when file is missing from filesystem.
  private(set) var fileSizeBytes: Int64?

  /// Maximum zoom level packaged in this offline chart.
  var maxZoom: Int? {
    chartDownload?.zoomMax
  }

  /// The date when this chart was downloaded and persisted.
  var downloadDate: Date? {
    chartDownload?.downloadDate
  }

  /// Calculated surface area covered by this offline chart.
  private(set) var geographicArea: Measurement<UnitArea>?

  /// Parsed geographic bounding box for map framing.
  private(set) var geographicBounds: GeographicBoundingBox?

  /// Formatted center coordinates in DDM (Degrees Decimal Minutes).
  private(set) var formattedCenterCoordinate: String?

  /// Formatted South-West corner coordinate in DDM.
  private(set) var formattedSouthWestCoordinate: String?

  /// Formatted North-East corner coordinate in DDM.
  private(set) var formattedNorthEastCoordinate: String?

  /// Indicates whether an active deletion operation is underway.
  private(set) var isDeleting: Bool = false

  /// Current user-facing error message, if any operation failed.
  var errorMessage: String?

  // MARK: - Initialization

  init(
    chartID: UUID,
    downloadRepository: GeoGarageDownloadRepositoryProtocol,
    downloadService: GeoGarageDownloadServiceProtocol? = nil
  ) {
    self.chartID = chartID
    self.downloadRepository = downloadRepository
    self.downloadService = downloadService

    loadMetadata()
  }

  // MARK: - Metadata Loading & File Validation

  /// Loads the chart record from the repository and verifies physical file existence and geometric metadata off the main thread.
  func loadMetadata() {
    guard let download = downloadRepository.downloads.first(where: { $0.id == chartID }) else {
      Logger.offline.warning("OfflineChartDetailViewModel: Chart with ID \(self.chartID.uuidString, privacy: .public) not found in repository.")
      self.chartDownload = nil
      self.fileStatus = .fileMissing
      self.fileSizeBytes = nil
      return
    }

    self.chartDownload = download
    self.fileStatus = .checking

    let fileURL = download.resolvedFileURL()
    let wkt = download.boundsWKT
    let layerName = download.layerName

    Task { [weak self] in
      let inspectionResult = await Task.detached(priority: .userInitiated) { () -> (size: Int64?, isMissing: Bool, box: GeographicBoundingBox?) in
        var size: Int64? = nil
        var isMissing = true

        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
          isMissing = false
          if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
             let fileSize = attrs[.size] as? Int64 {
            size = fileSize
          }
        }

        let parsedBox: GeographicBoundingBox? = wkt.isEmpty ? nil : GeographicBoundingBox(wkt: wkt)
        return (size, isMissing, parsedBox)
      }.value

      guard let self else { return }

      if inspectionResult.isMissing {
        Logger.offline.warning("OfflineChartDetailViewModel: MBTiles file missing on disk for chart \(layerName, privacy: .public)")
        self.fileSizeBytes = nil
        self.fileStatus = .fileMissing
      } else {
        self.fileSizeBytes = inspectionResult.size
        self.fileStatus = .ready
      }

      if let box = inspectionResult.box {
        self.geographicBounds = box
        self.geographicArea = box.estimatedArea
        self.formattedCenterCoordinate = CoordinateFormatStyle().format(box.center)
        self.formattedSouthWestCoordinate = CoordinateFormatStyle().format(box.southWest)
        self.formattedNorthEastCoordinate = CoordinateFormatStyle().format(box.northEast)
      }
    }
  }

  // MARK: - Edit Mode Lifecycle

  /// Enters editing mode and pre-fills `editableName` with the current custom or default name.
  func startEditing() {
    isEditing = true
    editableName = chartDownload?.customName ?? chartDownload?.layerName ?? ""
  }

  /// Cancels editing mode and discards uncommitted changes to `editableName`.
  func cancelEditing() {
    isEditing = false
    editableName = ""
  }

  /// Commits the edited chart name to the repository and updates disk persistence atomically.
  /// If the trimmed string is empty or matches the original layerName, `customName` is set to `nil`
  /// to trigger the natural fallback.
  func saveCustomName() async throws {
    guard let currentDownload = chartDownload else { return }

    let trimmed = editableName.trimmingCharacters(in: .whitespacesAndNewlines)
    // If trimmed string is empty or equal to the default layerName, reset customName to nil
    let newCustomName: String? = (trimmed.isEmpty || trimmed == currentDownload.layerName) ? nil : trimmed
    let previousName = currentDownload.customName ?? currentDownload.layerName

    isSaving = true
    defer { isSaving = false }

    let updatedDownload = currentDownload.updatingCustomName(newCustomName)

    do {
      try await downloadRepository.save(updatedDownload)
      self.chartDownload = updatedDownload
      self.isEditing = false
      self.editableName = ""
      self.errorMessage = nil

      Logger.offline.info("Updated offline chart name for ID \(self.chartID.uuidString, privacy: .public): '\(previousName, privacy: .public)' -> '\(newCustomName ?? currentDownload.layerName, privacy: .public)'")
    } catch {
      Logger.offline.error("Failed to save custom chart name for ID \(self.chartID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
      self.errorMessage = error.localizedDescription
      throw error
    }
  }

  // MARK: - User Actions

  /// Centers the navigation chart camera on the bounding box of this offline package and closes the command panel.
  ///
  /// - Parameters:
  ///   - chartViewModel: The active chart state manager.
  ///   - panelManager: The panel manager controlling the command view stack.
  func showOnChart(
    using chartViewModel: ChartViewModel,
    panelManager: PanelManagerViewModel
  ) {
    guard let bounds = geographicBounds else {
      Logger.offline.warning("OfflineChartDetailViewModel: showOnChart called but geographicBounds is nil.")
      return
    }

    // Execute map camera movement on @MainActor and close the panel smoothly
    chartViewModel.fitBounds(bounds)
    panelManager.closePanel()
  }

  /// Deletes the offline chart record and its underlying physical `.mbtiles` file.
  func deleteChart() async throws {
    isDeleting = true
    defer { isDeleting = false }

    do {
      guard let download = chartDownload else {
        try await downloadRepository.delete(id: chartID)
        return
      }

      if let downloadService {
        try await downloadService.deleteDownload(download)
      } else {
        // Fallback direct cleanup
        if let fileURL = download.resolvedFileURL(), FileManager.default.fileExists(atPath: fileURL.path) {
          try? FileManager.default.removeItem(at: fileURL)
        }
        try await downloadRepository.delete(id: download.id)
      }
      Logger.offline.info("Successfully deleted offline chart \(download.layerName, privacy: .public)")
      self.errorMessage = nil
    } catch {
      Logger.offline.error("Failed to delete offline chart: \(error.localizedDescription, privacy: .public)")
      self.errorMessage = error.localizedDescription
      throw error
    }
  }
}
