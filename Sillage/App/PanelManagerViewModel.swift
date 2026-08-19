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
    case sessionDetail(sessionID: TrackSession.ID)
    case waypointDetail(String)
    case baroAlarm
    case anchorAlarm
    case geoGarageLogin
    case offlineCharts
    case chartPreferences
    case geoGarageOfflineDownload
  }

  /// The currently active panel visible to the user.
  public var activePanel: ActivePanel = .none

  /// The view stack path for the Command Panel.
  public var commandPath: [CommandDestination] = []

  // MARK: - Action Confirmation Card Layout State
  public var actionConfirmationCardHeight: CGFloat = 0
  public var actionConfirmationCardBottomPadding: CGFloat = 0

  public init() {}

  /// Opens the specified panel.
  public func openPanel(_ panel: ActivePanel) {
    withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
      activePanel = panel
    }
  }

  /// Opens the command panel specifically routed to the Anchor Alarm sub-view.
  public func openAnchorAlarmPanel() {
    if commandPath.last != .anchorAlarm {
      commandPath.append(.anchorAlarm)
    }
    openPanel(.command)
  }

  /// Closes any active panel and resets the UI path state.
  public func closePanel() {
    resetCommandPath()
    withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
      activePanel = .none
    }
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
    commandPath.removeAll()
  }

  // MARK: - Intent Routing
  
  public func handle(intent: AppMessageIntent) {
    switch intent {
    case .openSettings(let target):
      if target == .geoGarage {
        commandPath.append(.geoGarageLogin)
      } else {
        commandPath.append(.settings)
      }
    case .none:
      break
    }
  }

  // MARK: - Permission & Action Routing

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
