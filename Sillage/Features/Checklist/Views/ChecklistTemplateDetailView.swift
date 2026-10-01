//
//  ChecklistTemplateDetailView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-01.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import OSLog

/// A read-only presentation view for inspecting, starting, and editing a maritime checklist template.
@MainActor
public struct ChecklistTemplateDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.marineTheme) private var marineTheme
  @Environment(PanelManagerViewModel.self) private var panelManager: PanelManagerViewModel?

  let templateId: UUID
  @State private var viewModel: ChecklistTemplateDetailViewModel
  @State private var showDeleteConfirmation: Bool = false

  public init(
    templateId: UUID,
    checklistService: any ChecklistServiceProtocol
  ) {
    self.templateId = templateId
    _viewModel = State(initialValue: ChecklistTemplateDetailViewModel(
      templateId: templateId,
      checklistService: checklistService
    ))
  }

  public var body: some View {
    Form {
      if viewModel.isLoading && viewModel.template == nil {
        loadingSection
      } else {
        generalSection
        stepsSection
        actionsSection
      }
    }
    .marineListBackground()
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .navigationTitle(viewModel.title.isEmpty ? String(localized: "Checklist") : viewModel.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if viewModel.template != nil {
        ToolbarItem(placement: .primaryAction) {
          Button {
            panelManager?.commandPath.append(.checklistTemplateEditor(templateId: templateId))
          } label: {
            Text("Edit")
              .marineFont(.body)
              .foregroundStyle(marineTheme.colors.accent)
          }
          .accessibilityLabel(String(localized: "Edit Checklist"))
        }
      }
    }
    .task(id: templateId) {
      await viewModel.load()
    }
    .alert(
      "Delete Template?",
      isPresented: $showDeleteConfirmation
    ) {
      Button("Delete", role: .destructive) {
        Task {
          if await viewModel.deleteTemplate() {
            dismiss()
          }
        }
      }
      Button("Cancel", role: .cancel) { }
    } message: {
      Text("Are you sure you want to permanently delete this custom checklist?")
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

  // MARK: - Sections

  @ViewBuilder
  private var loadingSection: some View {
    Section {
      HStack {
        Spacer()
        ProgressView()
          .tint(marineTheme.colors.accent)
        Spacer()
      }
      .marineListCell()
    }
  }

  @ViewBuilder
  private var generalSection: some View {
    Section("Information") {
      if let category = viewModel.category {
        HStack {
          Text("Category")
            .marineFont(.body)
            .foregroundStyle(marineTheme.colors.textSecondary)
          Spacer()
          HStack(spacing: MarineTheme.Spacing.small) {
            Image(systemName: category.systemImage)
              .foregroundStyle(category.color(for: marineTheme))
            Text(category.title)
              .marineFont(.body)
              .foregroundStyle(marineTheme.colors.textPrimary)
          }
        }
        .marineListCell()
      }

      if let description = viewModel.description, !description.isEmpty {
        VStack(alignment: .leading, spacing: MarineTheme.Spacing.tiny) {
          Text("Description")
            .marineFont(.caption)
            .foregroundStyle(marineTheme.colors.textSecondary)
          Text(description)
            .marineFont(.body)
            .foregroundStyle(marineTheme.colors.textPrimary)
        }
        .marineListCell()
      }
    }
  }

  @ViewBuilder
  private var stepsSection: some View {
    Section {
      if viewModel.items.isEmpty {
        Text("No steps added yet")
          .marineFont(.body)
          .foregroundStyle(marineTheme.colors.textSecondary)
          .marineListCell()
      } else {
        ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
          ChecklistTemplateStepRow(
            index: index,
            title: item.title,
            detail: item.detail
          )
        }
      }
    } header: {
      HStack {
        Text("Steps")
        Spacer()
        Text("\(viewModel.items.count)")
          .foregroundStyle(marineTheme.colors.textSecondary)
      }
      .marineFont(.caption)
    }
  }

  @ViewBuilder
  private var actionsSection: some View {
    Section {
      Button {
        Task {
          if let sessionId = await viewModel.startOrResumeSession() {
            panelManager?.commandPath.append(.activeSession(sessionId: sessionId))
          }
        }
      } label: {
        HStack(spacing: MarineTheme.Spacing.small) {
          Image(systemName: viewModel.hasActiveSession ? "play.circle.fill" : "play.fill")
          Text(viewModel.hasActiveSession ? "Continue Checklist" : "Start Checklist")
        }
      }
      .buttonStyle(MarineButtonStyle(.primary))
      .marineListCell()

      Button {
        panelManager?.commandPath.append(.checklistTemplateEditor(templateId: templateId))
      } label: {
        HStack(spacing: MarineTheme.Spacing.small) {
          Image(systemName: "pencil")
          Text("Edit Template")
        }
      }
      .buttonStyle(MarineButtonStyle(.secondary))
      .marineListCell()

      Button(role: .destructive) {
        showDeleteConfirmation = true
      } label: {
        HStack(spacing: MarineTheme.Spacing.small) {
          Image(marineIcon: .delete)
          Text("Delete Template")
        }
      }
      .buttonStyle(MarineButtonStyle(.destructive))
      .marineListCell()
    }
  }
}

/// A step row in a checklist template.
@MainActor
struct ChecklistTemplateStepRow: View {
  @Environment(\.marineTheme) private var marineTheme

  let index: Int
  let title: String
  let detail: String?

  var body: some View {
    VStack(alignment: .leading, spacing: MarineTheme.Spacing.small) {
      HStack(alignment: .center, spacing: MarineTheme.Spacing.small) {
        Text("\(index + 1).")
          .marineFont(.subheadline)
          .foregroundStyle(marineTheme.colors.textSecondary)
          .frame(minWidth: 22, alignment: .leading)

        Text(title)
          .marineFont(.body)
          .foregroundStyle(marineTheme.colors.textPrimary)

        Spacer()
      }

      if let detail, !detail.isEmpty {
        Text(detail)
          .marineFont(.subheadline)
          .foregroundStyle(marineTheme.colors.textSecondary)
          .padding(.leading, 30)
      }
    }
    .padding(.vertical, 6)
    .marineListCell()
  }
}
