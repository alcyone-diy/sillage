//
//  BarometerCommandRowView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Atomic Command Panel row representing the Barometer Weather Alarm.
/// Technical Design Choice (DDD & Framework Isolation):
/// Directly encapsulates domain observation of `BarometerViewModel` and its navigation action,
/// keeping `CommandPanelView` purely an opaque container without domain coupling.
@MainActor
struct BarometerCommandRowView: View {
  @Environment(BarometerViewModel.self) private var barometerViewModel
  @Environment(PanelManagerViewModel.self) private var panelViewModel
  @Environment(PermissionService.self) private var permissionService
  @Environment(\.marineTheme) private var marineTheme

  @Binding var permissionGateType: PermissionGateType?

  /// Evaluates the visual alarm state directly from `BarometerViewModel`.
  /// Technical Design Choice (Zero Dummy Values):
  /// `alarmLevel` is modeled as a strict Optional `WeatherAlarmLevel?`.
  /// `nil` denotes absence of alert condition, while non-nil indicates an active weather drop trigger.
  var alarmState: CommandAlarmState? {
    guard barometerViewModel.isAlarmEnabled else { return nil }
    if barometerViewModel.alarmLevel != nil {
      return .triggered
    } else {
      return .armed
    }
  }

  var body: some View {
    Button {
      if let gate = panelViewModel.executeOrRequestPermission(
        type: .motion,
        in: permissionService,
        action: { [weak panelViewModel] in
          panelViewModel?.commandPath.append(.baroAlarm)
        }
      ) {
        permissionGateType = gate
      }
    } label: {
      HStack {
        Label {
          Text("Baro Alarm").foregroundStyle(.primary)
        } icon: {
          Image(marineIcon: .instruments).foregroundStyle(.blue)
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
