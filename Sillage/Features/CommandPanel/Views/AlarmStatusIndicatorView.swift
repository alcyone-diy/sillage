//
//  AlarmStatusIndicatorView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Represents the visual alarm state for Command Panel rows.
enum CommandAlarmState: Sendable, Equatable {
  /// The alarm is actively armed and monitoring in the background.
  case armed
  /// The alarm condition has been met and the alarm has triggered.
  case triggered
}

/// A compact, high-contrast indicator for alarm states in command rows.
/// Conforms to MarineTheme guidelines with distinct colors for armed (cyan/activeToggle)
/// and triggered (destructive/alert red).
struct AlarmStatusIndicatorView: View {
  let state: CommandAlarmState
  @Environment(\.marineTheme) private var marineTheme

  var body: some View {
    switch state {
    case .armed:
      Image(marineIcon: .alarmArmed)
        .foregroundStyle(marineTheme.colors.activeToggle)
        .font(.subheadline)
    case .triggered:
      // Technical Design Choice:
      // In critical marine contexts, the combination of the perturbance icon (bell.and.waves)
      // and destructive alert color provides unmistakable alert awareness.
      // A discreet symbolEffect pulse provides visual urgency when active.
      Image(marineIcon: .alarmTriggered)
        .foregroundStyle(marineTheme.colors.destructive)
        .font(.subheadline)
        .symbolEffect(.pulse)
    }
  }
}
