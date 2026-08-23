//
//  TrackDetailViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-20.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation
import OSLog
import UIKit
import GRDB

@MainActor
@Observable
final class TrackDetailViewModel {
  var session: TrackSession?
  var name: String = ""
  var description: String = ""

  var isEditing: Bool = false
  var isSaving: Bool = false

  // MARK: - Export State
  var isExporting: Bool = false
  var exportProgress: Double = 0.0
  var shareItem: TrackShareItem? = nil
  var exportError: String? = nil

  @ObservationIgnored
  private var exportTask: Task<Void, Error>? = nil

  let sessionID: String
  private let trackService: TrackService
  private let trackRecordingService: TrackRecordingService

  init(
    sessionID: String,
    trackService: TrackService,
    trackRecordingService: TrackRecordingService
  ) {
    self.sessionID = sessionID
    self.trackService = trackService
    self.trackRecordingService = trackRecordingService
  }

  deinit {
    exportTask?.cancel()
  }

  /// Indicates whether deletion is allowed (hides/disables the button in the UI)
  var canDelete: Bool {
    return !trackRecordingService.isSessionActive(sessionID)
  }

  // MARK: - Export Lifecycle

  /// Starts exporting the track session to a GPX file in background, streaming progress to UI.
  func startExport() {
    guard !isExporting else { return }

    exportTask?.cancel()
    isExporting = true
    exportProgress = 0.0
    exportError = nil

    let rawName = name.isEmpty ? "Track_\(sessionID)" : name
    let invalidCharacters = CharacterSet.alphanumerics.inverted
    var safeName = rawName.components(separatedBy: invalidCharacters)
                          .filter { !$0.isEmpty }
                          .joined(separator: "-")
    if safeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      safeName = "Track_\(sessionID)"
    }
    let fileName = "\(safeName).gpx"
    let tempDir = FileManager.default.temporaryDirectory
    let uniqueURL = tempDir.appendingPathComponent("\(UUID().uuidString)_\(fileName)")

    // Prevent device from sleeping during long track exports to avoid background task suspension
    UIApplication.shared.isIdleTimerDisabled = true

    exportTask = Task { [weak self] in
      defer {
        Task { @MainActor in
          UIApplication.shared.isIdleTimerDisabled = false
        }
      }

      guard let self else { return }

      do {
        for try await progress in self.trackService.exportSession(id: self.sessionID, to: uniqueURL) {
          try Task.checkCancellation()
          self.exportProgress = progress
        }

        self.isExporting = false
        self.shareItem = TrackShareItem(fileURL: uniqueURL)
      } catch is CancellationError {
        Logger.tracking.info("GPX export cancelled for session \(self.sessionID, privacy: .public)")
        self.isExporting = false
        self.exportProgress = 0.0
        try? FileManager.default.removeItem(at: uniqueURL)
      } catch {
        Logger.tracking.error("GPX export failed for session \(self.sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        self.isExporting = false
        self.exportProgress = 0.0
        self.exportError = String(localized: "Failed to export track: \(error.localizedDescription)")
        try? FileManager.default.removeItem(at: uniqueURL)
        throw error
      }
    }
  }

  /// Cancels any in-progress GPX export task and resets the export state.
  func cancelExport() {
    exportTask?.cancel()
    exportTask = nil
    isExporting = false
    exportProgress = 0.0
  }

  // MARK: - Live Metrics
  
  private var liveTelemetry: TrackSessionTelemetry? {
    guard trackRecordingService.isSessionActive(sessionID) else { return nil }
    return trackRecordingService.telemetry
  }
  
  var totalDuration: Duration? {
    if let liveTelemetry {
      return liveTelemetry.activeTotalDuration()
    }
    return session?.totalDuration
  }
  
  var totalDistanceOverGround: Measurement<UnitLength>? {
    if let liveTelemetry {
      return liveTelemetry.totalDistanceOverGround
    }
    return session?.totalDistanceOverGround
  }
  
  var totalPointCount: Int? {
    if let liveTelemetry {
      return liveTelemetry.totalPointCount
    }
    return session?.totalPointCount
  }
  
  var maxSpeedOverGround: Measurement<UnitSpeed>? {
    if let liveTelemetry {
      return liveTelemetry.maxSpeedOverGround
    }
    return session?.maxSpeedOverGround
  }
  
  var totalAverageSpeedOverGround: Measurement<UnitSpeed>? {
    if let liveTelemetry {
      return liveTelemetry.totalAverageSpeedOverGround()
    }
    return session?.totalAverageSpeedOverGround
  }
  
  var segmentCount: Int? {
    if let liveTelemetry {
      return liveTelemetry.segmentIndex.map { $0 + 1 }
    }
    return session?.segmentCount
  }

  func load() async {
    // Observe session updates reactively
    do {
      for try await updatedSession in trackService.observeTrackSession(id: sessionID) {
        self.session = updatedSession
        if let updatedSession, !isEditing {
          self.name = updatedSession.name ?? ""
          self.description = updatedSession.description ?? ""
        }
      }
    } catch is CancellationError {
      Logger.database.debug("Track session observation cancelled for \(self.sessionID, privacy: .public)")
    } catch {
      Logger.database.error("Failed to observe track session \(self.sessionID, privacy: .public): \(error, privacy: .public)")
    }
  }

  func saveChanges() async throws {
    guard let session else { return }
    isSaving = true
    defer { isSaving = false }

    do {
      let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
      let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)

      let finalName = trimmedName.isEmpty ? nil : trimmedName
      let finalDesc = trimmedDesc.isEmpty ? nil : trimmedDesc

      try await trackService.updateSession(
        id: session.id,
        name: finalName,
        description: finalDesc
      )
      isEditing = false
    } catch {
      Logger.database.error("Failed to update track session \(self.sessionID, privacy: .public): \(error, privacy: .public)")
      throw error
    }
  }

  func cancelEditing() {
    isEditing = false
    if let session {
      name = session.name ?? ""
      description = session.description ?? ""
    }
  }

  /// Deletes the track session from the database.
  /// - Throws: `TrackDeletionError` or other database errors.
  func deleteSession() async throws {
    guard canDelete else {
      let error = TrackDeletionError.activeSession
      Logger.database.warning("Attempted to delete active session: \(self.sessionID, privacy: .public)")
      throw error
    }

    do {
      try await trackService.deleteSession(id: sessionID)
    } catch {
      Logger.database.error("Failed to delete track session \(self.sessionID, privacy: .public): \(error, privacy: .public)")
      throw error
    }
  }
}

public enum TrackDeletionError: LocalizedError {
  case activeSession

  public var errorDescription: String? {
    switch self {
    case .activeSession:
      return String(localized: "Cannot delete a track while it is actively recording.")
    }
  }
}

public struct TrackShareItem: Identifiable, Sendable {
  public let id = UUID()
  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }
}
