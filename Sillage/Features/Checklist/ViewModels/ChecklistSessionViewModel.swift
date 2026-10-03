//
//  ChecklistSessionViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation
import Observation
import OSLog

/// A view model managing the live, interactive execution of a maritime checklist session.
@MainActor
@Observable
public final class ChecklistSessionViewModel {
  public let sessionId: UUID
  private let checklistService: any ChecklistServiceProtocol
  private let locationProvider: (@MainActor () -> NavigationFix?)?

  public private(set) var session: ChecklistSession?
  public private(set) var template: ChecklistTemplate?
  public private(set) var isLoading: Bool = false
  public private(set) var isPerformingAction: Bool = false
  public private(set) var isSessionDeleted: Bool = false
  public var errorMessage: String?
  public var showResetConfirmation: Bool = false

  /// Initializes the session view model.
  /// - Parameters:
  ///   - sessionId: Persistent identifier for database lookup, persistence, and fallback.
  ///   - session: Optional in-memory session snapshot used to render the title and steps immediately,
  ///              preventing UI latency while the asynchronous database load completes.
  ///   - checklistService: The service handling checklist execution and persistence.
  ///   - locationProvider: Optional closure returning the latest GPS fix for geotagged checks.
  public init(
    sessionId: UUID,
    session: ChecklistSession? = nil,
    checklistService: any ChecklistServiceProtocol,
    locationProvider: (@MainActor () -> NavigationFix?)? = nil
  ) {
    self.sessionId = sessionId
    self.session = session
    self.checklistService = checklistService
    self.locationProvider = locationProvider
  }

  public var title: String {
    session?.templateTitleSnapshot ?? template?.title ?? ""
  }

  public var description: String? {
    guard let desc = template?.description else { return nil }
    let trimmed = desc.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  public var category: ChecklistCategory? {
    template?.category
  }

  public var items: [ChecklistSessionItem] {
    session?.items ?? []
  }

  /// Identifies the first unchecked item in the list for progressive disclosure styling.
  public var currentItemId: UUID? {
    items.first(where: { !$0.isChecked })?.stableId
  }

  public var totalCount: Int {
    session?.totalCount ?? 0
  }

  public var completedCount: Int {
    session?.completedCount ?? 0
  }

  public var progressRatio: Double {
    session?.progressRatio ?? 0.0
  }

  public var isCompleted: Bool {
    session?.status == .completed
  }

  public var canComplete: Bool {
    guard let session else { return false }
    return session.status == .inProgress && session.isFullyCompleted
  }

  public var canReset: Bool {
    guard let session else { return false }
    return session.completedCount > 0 || session.status == .completed
  }

  /// Loads the session and its parent template metadata.
  public func load() async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      if let fetchedSession = try await checklistService.fetchSession(id: sessionId) {
        self.session = fetchedSession
        self.template = try await checklistService.fetchTemplate(id: fetchedSession.templateId)
      } else {
        self.session = nil
        self.isSessionDeleted = true
        errorMessage = String(localized: "Checklist session not found.")
      }
    } catch {
      Logger.checklist.error("Failed to load checklist session '\(self.sessionId.uuidString, privacy: .public)': \(error.localizedDescription, privacy: .public)")
      errorMessage = error.localizedDescription
    }
  }

  /// Subscribes asynchronously to sessions stream to drive UI reactively from the database.
  public func observe() async {
    do {
      for try await sessions in checklistService.observeSessions() {
        if Task.isCancelled { break }
        if let matching = sessions.first(where: { $0.id == sessionId }) {
          self.session = matching
        } else if session != nil {
          // The session previously existed but was deleted (e.g. template deleted)
          self.session = nil
          self.isSessionDeleted = true
        }
      }
    } catch {
      if !Task.isCancelled {
        Logger.checklist.error("Error observing checklist sessions: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  /// Toggles the checked status of a checklist item with GPS audit coordinate.
  public func toggleItem(_ item: ChecklistSessionItem) async {
    // UI-level guard: strictly drop simultaneous parasitic touches (rebound, double-tap, sea spray)
    guard !isPerformingAction, let currentSession = session else { return }
    isPerformingAction = true
    defer { isPerformingAction = false }

    do {
      let coordinate = resolveAuditableCoordinate()
      let updated = try await checklistService.setItemChecked(
        sessionId: currentSession.id,
        itemId: item.id,
        isChecked: !item.isChecked,
        coordinate: coordinate
      )
      self.session = updated
    } catch {
      Logger.checklist.error("Failed to toggle checklist item '\(item.id.uuidString, privacy: .public)': \(error.localizedDescription, privacy: .public)")
      errorMessage = error.localizedDescription
    }
  }

  /// Marks the active session as fully completed.
  ///
  /// Note: This method deliberately does NOT trigger screen dismissal.
  /// Keeping the session open gives the skipper immediate confirmation and allows
  /// reviewing, unchecking, or restarting without disorienting navigation glitches.
  public func complete() async {
    guard let currentSession = session, canComplete, !isPerformingAction else { return }
    isPerformingAction = true
    defer { isPerformingAction = false }

    do {
      let completedSession = try await checklistService.completeSession(
        sessionId: currentSession.id,
        notes: nil
      )
      self.session = completedSession
    } catch {
      Logger.checklist.error("Failed to complete checklist session '\(currentSession.id.uuidString, privacy: .public)': \(error.localizedDescription, privacy: .public)")
      errorMessage = error.localizedDescription
    }
  }

  /// Resets all items in the active session.
  public func reset() async {
    guard let currentSession = session, !isPerformingAction else { return }
    isPerformingAction = true
    defer { isPerformingAction = false }

    do {
      let updated = try await checklistService.resetSession(sessionId: currentSession.id)
      self.session = updated
    } catch {
      Logger.checklist.error("Failed to reset checklist session '\(currentSession.id.uuidString, privacy: .public)': \(error.localizedDescription, privacy: .public)")
      errorMessage = error.localizedDescription
    }
  }


  // MARK: - Defensive GPS Accuracy Resolution

  private static let maximumAuditableAccuracy = Measurement<UnitLength>(value: 50.0, unit: .meters)

  private func resolveAuditableCoordinate() -> CLLocationCoordinate2D? {
    guard let fix = locationProvider?() else { return nil }
    guard fix.horizontalAccuracy.value >= 0,
          fix.horizontalAccuracy <= Self.maximumAuditableAccuracy else {
      return nil
    }
    return fix.coordinate
  }
}
