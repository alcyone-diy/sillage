//
//  AnchorCommandRowView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Atomic Command Panel row representing the Anchor Alarm.
/// Technical Design Choice (DDD & Framework Isolation):
/// Directly encapsulates domain observation of `AnchorViewModel` and its navigation action,
/// keeping `CommandPanelView` purely an opaque container without domain coupling.
@MainActor
struct AnchorCommandRowView: View {
  @Environment(AnchorViewModel.self) private var anchorViewModel
  @Environment(PanelManagerViewModel.self) private var panelViewModel
  @Environment(PermissionService.self) private var permissionService
  @Environment(\.marineTheme) private var marineTheme

  @Binding var permissionGateType: PermissionGateType?

  /// Evaluates the visual alarm state directly from the single source of truth (`AnchorViewModel.status`).
  /// Technical Design Choice (State Preservation & Crash Survival):
  /// Because `AnchorService` restores session state synchronously during bootstrap from `AnchorStateStore`,
  /// this computed property immediately returns `.armed` or `.triggered` upon cold boot without requiring a fresh GPS fix.
  var alarmState: CommandAlarmState? {
    switch anchorViewModel.status {
    case .dragging:
      return .triggered
    case .armed:
      return .armed
    case .inactive, .droppedPendingPosition, .dropped:
      return nil
    }
  }

  var body: some View {
    Button {
      if let gate = panelViewModel.executeOrRequestPermission(
        type: .location(trigger: .anchorAlarm),
        in: permissionService,
        action: { [weak panelViewModel] in
          panelViewModel?.commandPath.append(.anchorAlarm)
        }
      ) {
        permissionGateType = gate
      }
    } label: {
      HStack {
        Label {
          Text("Anchor Alarm").foregroundStyle(.primary)
        } icon: {
          Image(marineIcon: .anchorAlarm).foregroundStyle(.blue)
        }
        .marineFont(.body)

        Spacer()

        if let alarmState {
          AlarmStatusIndicatorView(state: alarmState)
        }

        Image(systemName: "chevron.right")
          .font(.footnote.weight(.semibold))
          .foregroundColor(Color(uiColor: .tertiaryLabel))
      }
    }
    .tint(.primary)
    .marineListCell()
  }
}
