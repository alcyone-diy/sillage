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
  let checklistService: (any ChecklistServiceProtocol)?

  public init(viewModel: ChecklistOverlayViewModel, checklistService: (any ChecklistServiceProtocol)? = nil) {
    self.viewModel = viewModel
    self.checklistService = checklistService
  }

  public var body: some View {
    List {
      if !viewModel.inProgressSessions.isEmpty {
        Section {
          ForEach(viewModel.inProgressSessions) { session in
            NavigationLink(value: ChecklistOverlayDestination.session(sessionId: session.id)) {
              ActiveChecklistRowView(session: session)
            }
            .marineListCell()
          }
        } header: {
          Text("In Progress")
            .marineSectionHeader()
        }
      }

      // Completed checklists are intentionally retained in the list so that the mariner can review,
      // consult, or restart them from scratch at any moment without unexpected disappearance.
      if !viewModel.completedSessions.isEmpty {
        Section {
          ForEach(viewModel.completedSessions) { session in
            NavigationLink(value: ChecklistOverlayDestination.session(sessionId: session.id)) {
              ActiveChecklistRowView(session: session)
            }
            .marineListCell()
          }
        } header: {
          Text("COMPLETED IN LAST \(ChecklistService.completedSessionRetentionHours)h")
            .marineSectionHeader()
        }
      }

      if viewModel.activeSessions.isEmpty {
        Section {
          Text("No active or completed checklists")
            .marineFont(.body)
            .foregroundStyle(marineTheme.colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, MarineTheme.Spacing.medium)
            .marineListCell()
        }
      }
    }
    .listStyle(.insetGrouped)
    .marineListBackground()
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .navigationTitle(String(localized: "Checklists"))
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

/// Row representing a single active or completed checklist session in the list.
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

        if session.status == .completed, let completedAt = session.completedAt {
          Text("Completed \(completedAt.formatted(date: .abbreviated, time: .shortened))")
            .marineFont(.caption)
            .foregroundStyle(marineTheme.colors.textSecondary)
            .lineLimit(1)
        } else {
          Text("Started \(session.startedAt.formatted(date: .abbreviated, time: .shortened))")
            .marineFont(.caption)
            .foregroundStyle(marineTheme.colors.textSecondary)
            .lineLimit(1)
        }
      }

      Spacer()

      if session.status == .completed {
        HStack(spacing: 4) {
          Image(systemName: "checkmark.circle.fill")
          Text("Done")
        }
        .marineFont(.subheadline)
        .fontWeight(.bold)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.15))
        .foregroundStyle(Color.green)
        .clipShape(Capsule())
      } else {
        Text(verbatim: "\(session.completedCount)/\(session.totalCount)")
          .marineFont(.subheadline)
          .fontWeight(.bold)
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(marineTheme.colors.accent.opacity(0.15))
          .foregroundStyle(marineTheme.colors.accent)
          .clipShape(Capsule())
      }
    }
    .frame(minHeight: marineTheme.minTouchTarget)
    .contentShape(Rectangle())
  }
}
