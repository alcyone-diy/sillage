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
  private let checklistService: any ChecklistServiceProtocol
  @State private var viewModel: ChecklistListViewModel
  @State private var isShowingCreateSheet = false

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
              ChecklistTemplateRowView(template: template)
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
    .task {
      await viewModel.loadTemplates()
    }
    .refreshable {
      await viewModel.loadTemplates()
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

  var body: some View {
    HStack(alignment: .center, spacing: MarineTheme.Spacing.medium) {
      VStack(alignment: .leading, spacing: 4) {
        Text(template.title)
          .marineFont(.body)
          .foregroundStyle(marineTheme.colors.textPrimary)

        if let description = template.description, !description.isEmpty {
          Text(description)
            .marineFont(.caption)
            .foregroundStyle(marineTheme.colors.textSecondary)
            .lineLimit(2)
        }
      }

      Spacer()

      Text("\(template.items.count) items")
        .marineFont(.caption)
        .foregroundStyle(marineTheme.colors.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
          Capsule()
            .fill(marineTheme.colors.secondaryActionBackground)
        )
    }
    .padding(.vertical, 4)
  }
}
