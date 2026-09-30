//
//  ChecklistListView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Displays the catalog of available maritime checklists.
@MainActor
struct ChecklistListView: View {
  @Environment(\.marineTheme) private var marineTheme
  @Environment(PanelManagerViewModel.self) private var panelManager: PanelManagerViewModel?
  private let checklistService: any ChecklistServiceProtocol
  @State private var viewModel: ChecklistListViewModel
  @State private var isShowingCreateSheet = false
  @State private var templateToDelete: ChecklistTemplate?
  @State private var templateToEdit: ChecklistTemplate?

  init(checklistService: any ChecklistServiceProtocol) {
    self.checklistService = checklistService
    _viewModel = State(initialValue: ChecklistListViewModel(checklistService: checklistService))
  }

  var body: some View {
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
              isShowingCreateSheet = true
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
              ChecklistTemplateRowView(
                template: template,
                activeSession: viewModel.activeSession(for: template.id)
              )
              .contentShape(Rectangle())
              .onTapGesture {
                // TODO: Ouvrir la checklist en mode readonly (sera fait dans un deuxième temps)
              }
              .swipeActions(edge: .leading, allowsFullSwipe: true) {
                let hasActive = viewModel.hasActiveSession(for: template.id)
                Button {
                  panelManager?.commandPath.append(.checklistDetail(templateId: template.id))
                } label: {
                  Label(
                    hasActive ? "Continue" : "Start",
                    systemImage: hasActive ? "play.circle.fill" : "play.fill"
                  )
                }
                .tint(marineTheme.colors.accent)
              }
              .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                  templateToDelete = template
                } label: {
                  Label("Delete", systemImage: MarineIcon.delete.rawValue)
                }
                .tint(.red)

                Button {
                  templateToEdit = template
                } label: {
                  Label("Edit", systemImage: MarineIcon.edit.rawValue)
                }
                .tint(marineTheme.colors.accent)
              }
              .marineListCell()
            }
          } header: {
            HStack(spacing: MarineTheme.Spacing.small) {
              Image(systemName: section.category.systemImage)
                .foregroundStyle(categoryColor(for: section.category))
              Text(section.category.title)
            }
            .marineFont(.caption)
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
          isShowingCreateSheet = true
        } label: {
          Image(marineIcon: .add)
            .foregroundStyle(marineTheme.colors.accent)
        }
        .accessibilityLabel(String(localized: "New Checklist"))
      }
    }
    .sheet(isPresented: $isShowingCreateSheet) {
      NavigationStack {
        ChecklistCreateView(
          checklistService: checklistService,
          onTemplateCreated: { _ in
            Task {
              await viewModel.loadTemplates()
            }
          }
        )
      }
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
    }
    .sheet(item: $templateToEdit) { template in
      NavigationStack {
        ChecklistEditView(
          template: template,
          checklistService: checklistService,
          onTemplateUpdated: { _ in
            Task {
              await viewModel.loadTemplates()
            }
          }
        )
      }
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
    }
    .task {
      await viewModel.loadTemplates()
    }
    .task {
      await viewModel.observeActiveSessions()
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
        Task {
          do {
            try await checklistService.deleteCustomTemplate(id: template.id)
            await viewModel.loadTemplates()
          } catch {
            viewModel.errorMessage = error.localizedDescription
          }
          templateToDelete = nil
        }
      }
      Button("Cancel", role: .cancel) {
        templateToDelete = nil
      }
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

  private func categoryColor(for category: ChecklistCategory) -> Color {
    switch category {
    case .safetyEmergency:
      return marineTheme.colors.warning
    case .navigationManeuver:
      return marineTheme.colors.accent
    case .routine:
      return marineTheme.colors.primary
    case .engineTechnical:
      return marineTheme.colors.textSecondary
    case .winteringMaintenance:
      return marineTheme.colors.inactive
    }
  }
}

/// Row representing a single checklist template in the catalog.
@MainActor
private struct ChecklistTemplateRowView: View {
  @Environment(\.marineTheme) private var marineTheme
  let template: ChecklistTemplate
  var activeSession: ChecklistSession? = nil

  var body: some View {
    HStack(alignment: .center, spacing: MarineTheme.Spacing.medium) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: MarineTheme.Spacing.small) {
          Text(template.title)
            .marineFont(.body)
            .foregroundStyle(marineTheme.colors.textPrimary)

          if let activeSession {
            Text("\(activeSession.completedCount)/\(activeSession.totalCount)")
              .marineFont(.caption)
              .foregroundStyle(marineTheme.colors.accent)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(
                Capsule()
                  .fill(marineTheme.colors.accent.opacity(0.15))
              )
          }
        }

        if let description = template.description, !description.isEmpty {
          Text(description)
            .marineFont(.caption)
            .foregroundStyle(marineTheme.colors.textSecondary)
            .lineLimit(1)
        }
      }

      Spacer()

      Text("\(template.items.count) items")
        .marineFont(.caption)
        .foregroundStyle(marineTheme.colors.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
          Capsule()
            .fill(marineTheme.colors.secondaryActionBackground)
        )
    }
  }
}
