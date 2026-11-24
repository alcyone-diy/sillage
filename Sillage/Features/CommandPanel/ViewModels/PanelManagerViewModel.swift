//
//  PanelManagerViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import SwiftUI
import Observation

/// A view model managing the state and UI flow for panels.
@MainActor
@Observable
public final class PanelManagerViewModel {

  public enum ActivePanel: Equatable {
    case none
    case command
  }

  /// Represents the UI destinations within the Command Panel.
  ///
  /// - Important: `CommandPanelView` uses a homogeneous `NavigationStack(path: $commandPath)`
  ///   typed to `[CommandDestination]`. Do NOT declare local navigation enums or nested
  ///   `.navigationDestination(for:)` in child views. All pushable destinations must be added
  ///   here and declared at the root level in `CommandPanelView.swift`.
  public enum CommandDestination: Hashable {
    case settings
    case tracks
    case waypoints
    case trackSessionDetail(sessionID: TrackSession.ID, session: TrackSession? = nil)
    case waypointDetail(String, waypoint: Waypoint? = nil)
    case waypointDraft(CoordinateWrapper)
    case baroAlarm
    case anchorAlarm
    case geoGarageLogin(context: GeoGarageLoginContext = .initialSetup)
    case offlineCharts
    case offlineChartDetail(id: UUID)
    case chartPreferences
    case cogPreferences
    case legalList
    case legalDetail(LegalDocumentID)
    case versionInfo
    case modelsInfo
#if DEBUG
    case debugMenu
#endif
    case checklists
    case checklistCategories
    case checklistCategoryDetail(ChecklistCategoryDetailPayload)
    case checklistTemplateDetail(ChecklistTemplateDetailPayload)
    /// Active checklist session execution view.
    case checklistSession(ChecklistSessionPayload)
  }

  /// The currently active panel visible to the user.
  public var activePanel: ActivePanel = .none

  /// The view stack path for the Command Panel.
  public var commandPath: [CommandDestination] = []

  /// Tracks whether the panel is temporarily suspended (preserving `commandPath` across dismiss).
  @ObservationIgnored private var isSuspended = false

  // MARK: - Action Confirmation Card Layout State
  public var actionConfirmationCardHeight: CGFloat = 0
  public var actionConfirmationCardBottomPadding: CGFloat = 0

  public init() {}

  /// Opens the specified panel.
  public func openPanel(_ panel: ActivePanel) {
    isSuspended = false
    withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
      activePanel = panel
    }
  }

  /// Opens the command panel specifically directed to the Anchor Alarm sub-view.
  public func openAnchorAlarmPanel() {
    if commandPath.last != .anchorAlarm {
      commandPath.append(.anchorAlarm)
    }
    openPanel(.command)
  }

  /// Opens the command panel specifically directed to the Offline Charts sub-view.
  public func openOfflineChartsPanel() {
    if commandPath.last != .offlineCharts {
      commandPath.append(.offlineCharts)
    }
    openPanel(.command)
  }

  /// Closes any active panel and resets the UI path state after the dismiss animation completes.
  public func closePanel() {
    isSuspended = false
    withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
      activePanel = .none
    } completion: { [weak self] in
      guard let self, self.activePanel == .none, !self.isSuspended else { return }
      self.resetCommandPath()
    }
  }

  /// Suspends the active panel by closing it without clearing the command path,
  /// allowing it to be resumed after an interactive chart action (e.g. waypoint position adjustment).
  public func suspendPanel() {
    isSuspended = true
    withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
      activePanel = .none
    }
  }

  /// Resumes a previously suspended panel.
  public func resumePanel() {
    isSuspended = false
    withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
      activePanel = .command
    }
  }

  /// Handles UIKit native sheet dismissal completion.
  /// Clears the command path only when the panel is genuinely closed (not suspended or rotating to a drawer).
  public func handleSheetDismissed() {
    guard activePanel == .none, !isSuspended else { return }
    resetCommandPath()
  }

  /// Toggles the visibility of the specified panel.
  /// If it is already active, it is closed. Otherwise, it is opened.
  public func togglePanel(_ panel: ActivePanel) {
    if activePanel == panel {
      closePanel()
    } else {
      openPanel(panel)
    }
  }

  /// Resets the UI path to the root menu.
  private func resetCommandPath() {
    guard !commandPath.isEmpty else { return }
    commandPath.removeAll()
  }

  // MARK: - Intent Dispatch
  
  public func handle(intent: AppMessageIntent) {
    switch intent {
    case .openSettings(let target):
      if target == .geoGarage {
        commandPath.append(.geoGarageLogin(context: .reauthentication))
      } else {
        commandPath.append(.settings)
      }
    case .none:
      break
    }
  }

  // MARK: - Permission & Action Handling

  /// The pending action waiting for a permission grant.
  private var pendingAction: (@MainActor () -> Void)? = nil
  private var pendingGateType: PermissionGateType? = nil

  /// Evaluates the permission and executes the action, or prepares the request if necessary.
  func executeOrRequestPermission(
      type: PermissionGateType,
      in service: PermissionService,
      action: @escaping @MainActor () -> Void
  ) -> PermissionGateType? {
      
      // 1. Source of truth is guaranteed by the enum
      let status = type.currentStatus(in: service)
      
      // 2. Evaluation
      if status == .authorized {
          action()
          return nil
      } else {
          self.pendingGateType = type
          self.pendingAction = action
          return type
      }
  }

  /// Called when a permission status changes to authorized.
  /// Executes any pending action for that permission.
  func finalizePendingLocationAction() {
      if case .location = pendingGateType {
          pendingAction?()
          pendingAction = nil
          pendingGateType = nil
      }
  }
  
  func finalizePendingMotionAction() {
      if case .motion = pendingGateType {
          pendingAction?()
          pendingAction = nil
          pendingGateType = nil
      }
  }
  
  func finalizePendingNotificationAction() {
      if case .notification = pendingGateType {
          pendingAction?()
          pendingAction = nil
          pendingGateType = nil
      }
  }
}
