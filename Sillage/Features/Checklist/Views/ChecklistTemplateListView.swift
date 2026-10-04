//
//  ChecklistTemplateListView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Displays the catalog of available maritime checklist templates.
@MainActor
public struct ChecklistTemplateListView: View {
  @Environment(\.marineTheme) private var marineTheme
  @Environment(PanelManagerViewModel.self) private var panelManager: PanelManagerViewModel?
  private let checklistService: any ChecklistServiceProtocol
  @State private var viewModel: ChecklistTemplateListViewModel
  @State private var templateToDelete: ChecklistTemplate?

  public init(checklistService: any ChecklistServiceProtocol) {
    self.checklistService = checklistService
    _viewModel = State(initialValue: ChecklistTemplateListViewModel(checklistService: checklistService))
  }

  public var body: some View {
    List {
      if viewModel.isLoading && viewModel.templates.isEmpty {
        Section {
          HStack {
            Spacer()
            ProgressView()
              .tint(marineTheme.colors.accent)
            Spacer()
          }
          .marineListCell()
        }
      } else if viewModel.templates.isEmpty {
        Section {
          VStack(spacing: MarineTheme.Spacing.medium) {
            Text("No checklists available")
              .foregroundStyle(marineTheme.colors.textSecondary)
              .marineFont(.body)

            Button {
              panelManager?.commandPath.append(.checklistTemplateDetail(templateId: nil, startEditable: true))
            } label: {
              HStack(spacing: MarineTheme.Spacing.small) {
                Image(marineIcon: .add)
                Text("Create Checklist")
              }
            }
            .buttonStyle(MarineButtonStyle())
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, MarineTheme.Spacing.medium)
          .marineListCell()
        }
      } else {
        ForEach(viewModel.groupedTemplates, id: \.category) { section in
          Section {
            ForEach(section.templates) { template in
              NavigationLink(value: PanelManagerViewModel.CommandDestination.checklistTemplateDetail(templateId: template.id, template: template)) {
                ChecklistTemplateRowView(
                  template: template,
                  activeSession: viewModel.activeSession(for: template.id),
                  latestCompletionDate: viewModel.latestCompletionDate(for: template.id)
                )
              }
              .swipeActions(edge: .leading, allowsFullSwipe: true) {
                let hasActive = viewModel.hasActiveSession(for: template.id)
                Button {
                  Task {
                    if let session = await viewModel.startOrResumeSession(for: template.id) {
                      panelManager?.commandPath.append(.activeSession(ChecklistSessionPayload(id: session.id, snapshot: session)))
                    }
                  }
                } label: {
                  Label(
                    hasActive ? "Continue" : "Start",
                    systemImage: hasActive ? "play.circle.fill" : "play.fill"
                  )
                }
                .tint(marineTheme.colors.accent)
              }
              .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                  templateToDelete = template
                } label: {
                  Label("Delete", systemImage: MarineIcon.delete.rawValue)
                }
                .tint(.red)
              }
              .marineListCell()
            }
          } header: {
            HStack(spacing: MarineTheme.Spacing.small) {
              Image(systemName: section.category.systemImage)
                .foregroundStyle(section.category.color(for: marineTheme))
              Text(section.category.title)
                .marineSectionHeader()
            }
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .marineListBackground()
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .navigationTitle("Checklists")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          panelManager?.commandPath.append(.checklistTemplateDetail(templateId: nil, startEditable: true))
        } label: {
          Image(marineIcon: .add)
            .foregroundStyle(marineTheme.colors.accent)
        }
        .accessibilityLabel(String(localized: "New Checklist"))
      }
    }
    .task {
      await viewModel.loadTemplates()
    }
    .task {
      await viewModel.observeActiveSessions()
    }
    .task {
      await viewModel.observeCompletedSessions()
    }
    .alert(
      "Delete Checklist?",
      isPresented: Binding(
        get: { templateToDelete != nil },
        set: { if !$0 { templateToDelete = nil } }
      ),
      presenting: templateToDelete
    ) { template in
      Button("Delete", role: .destructive) {
        let templateId = template.id
        Task {
          _ = await viewModel.deleteTemplate(id: templateId)
        }
      }
      Button("Cancel", role: .cancel) { }
    } message: { template in
      Text("Are you sure you want to delete \"\(template.title)\"? This action cannot be undone.")
    }
    .alert(
      "Error",
      isPresented: Binding(
        get: { viewModel.errorMessage != nil },
        set: { if !$0 { viewModel.errorMessage = nil } }
      ),
      presenting: viewModel.errorMessage
    ) { _ in
      Button("OK", role: .cancel) { }
    } message: { message in
      Text(message)
    }
  }
}

/// Row representing a single checklist template in the catalog.
@MainActor
private struct ChecklistTemplateRowView: View {
  @Environment(\.marineTheme) private var marineTheme
  let template: ChecklistTemplate
  var activeSession: ChecklistSession? = nil
  var latestCompletionDate: Date? = nil

  var body: some View {
    HStack(alignment: .center, spacing: MarineTheme.Spacing.medium) {
      VStack(alignment: .leading, spacing: 4) {
        Text(template.title)
          .marineFont(.body)
          .foregroundStyle(marineTheme.colors.textPrimary)

        if let activeSession {
          Text("Started \(activeSession.startedAt.formatted(date: .abbreviated, time: .shortened))")
            .marineFont(.caption)
            .foregroundStyle(marineTheme.colors.textSecondary)
            .lineLimit(1)
        } else if let latestCompletionDate {
          Text("Completed \(latestCompletionDate.formatted(date: .abbreviated, time: .shortened))")
            .marineFont(.caption)
            .foregroundStyle(marineTheme.colors.textSecondary)
            .lineLimit(1)
        } else {
          Text("Never used")
            .marineFont(.caption)
            .foregroundStyle(marineTheme.colors.textSecondary)
            .lineLimit(1)
        }
      }

      Spacer()

      if let activeSession {
        Text(verbatim: "\(activeSession.completedCount)/\(activeSession.totalCount)")
          .marineFont(.subheadline)
          .fontWeight(.bold)
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(marineTheme.colors.accent.opacity(0.15))
          .foregroundStyle(marineTheme.colors.accent)
          .clipShape(Capsule())
      } else {
        Text(verbatim: "\(template.items.count)")
          .marineFont(.subheadline)
          .fontWeight(.medium)
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(marineTheme.colors.secondaryActionBackground)
          .foregroundStyle(marineTheme.colors.textSecondary)
          .clipShape(Capsule())
      }
    }
    .frame(minHeight: marineTheme.minTouchTarget)
    .contentShape(Rectangle())
  }
}
