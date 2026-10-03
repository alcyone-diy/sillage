//
//  ActiveChecklistListView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Displays the list of ongoing checklist sessions with active progress.
@MainActor
public struct ActiveChecklistListView: View {
  @Environment(\.marineTheme) private var marineTheme

  let viewModel: ChecklistOverlayViewModel

  public init(viewModel: ChecklistOverlayViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    List {
      Section {
        ForEach(viewModel.activeSessions) { session in
          NavigationLink(value: session.id) {
            ActiveChecklistRowView(session: session)
          }
          .marineListCell()
        }
      } header: {
        Text("In Progress")
          .marineFont(.caption)
          .foregroundStyle(marineTheme.colors.textSecondary)
      }
    }
    .listStyle(.insetGrouped)
    .marineListBackground()
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .navigationTitle(String(localized: "Active Checklists"))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button {
          viewModel.dismiss()
        } label: {
          Image(marineIcon: .cancelAction)
            .foregroundStyle(.tertiary)
            .font(.title2)
        }
        .accessibilityLabel(String(localized: "Close"))
      }
    }
  }
}

/// Row representing a single active checklist session in the list.
@MainActor
private struct ActiveChecklistRowView: View {
  @Environment(\.marineTheme) private var marineTheme
  let session: ChecklistSession

  var body: some View {
    HStack(alignment: .center, spacing: MarineTheme.Spacing.medium) {
      VStack(alignment: .leading, spacing: 4) {
        Text(session.templateTitleSnapshot)
          .marineFont(.body)
          .fontWeight(.semibold)
          .foregroundStyle(marineTheme.colors.textPrimary)

        Text("Started \(session.startedAt.formatted(date: .abbreviated, time: .shortened))")
          .marineFont(.caption)
          .foregroundStyle(marineTheme.colors.textSecondary)
          .lineLimit(1)
      }

      Spacer()

      Text(verbatim: "\(session.completedCount)/\(session.totalCount)")
        .marineFont(.subheadline)
        .fontWeight(.bold)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(marineTheme.colors.accent.opacity(0.15))
        .foregroundStyle(marineTheme.colors.accent)
        .clipShape(Capsule())
    }
    .frame(minHeight: marineTheme.minTouchTarget)
    .contentShape(Rectangle())
  }
}
