//
//  ChecklistTemplateView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-01.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import OSLog

/// A presentation view for inspecting, starting, and editing a maritime checklist template.
@MainActor
struct ChecklistTemplateView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.marineTheme) private var marineTheme
  @Environment(\.checklistService) private var checklistService
  @Environment(PanelManagerViewModel.self) private var panelManager: PanelManagerViewModel?

  let templateId: UUID
  @State private var template: ChecklistTemplate?
  @State private var hasActiveSession: Bool = false
  @State private var isLoading: Bool = false
  @State private var errorMessage: String?
  @State private var showDeleteConfirmation: Bool = false
  @State private var isShowingEditSheet: Bool = false
  var onTemplateUpdated: (@MainActor (ChecklistTemplate) -> Void)?

  init(
    templateId: UUID,
    onTemplateUpdated: (@MainActor (ChecklistTemplate) -> Void)? = nil
  ) {
    self.templateId = templateId
    self.onTemplateUpdated = onTemplateUpdated
  }

  private var items: [ChecklistTemplateItem] {
    template?.items.sorted { $0.sortOrder < $1.sortOrder } ?? []
  }

  var body: some View {
    Form {
      if isLoading && template == nil {
        loadingSection
      } else {
        generalSection
        stepsSection
        actionsSection
      }
    }
    .marineListBackground()
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .navigationTitle(template?.title.isEmpty == false ? (template?.title ?? "") : String(localized: "Checklist"))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if template != nil && checklistService != nil {
        ToolbarItem(placement: .primaryAction) {
          Button {
            isShowingEditSheet = true
          } label: {
            Text("Edit")
              .marineFont(.body)
              .foregroundStyle(marineTheme.colors.accent)
          }
          .accessibilityLabel(String(localized: "Edit Checklist"))
        }
      }
    }
    .sheet(isPresented: $isShowingEditSheet) {
      if let template, let checklistService {
        NavigationStack {
          ChecklistEditView(
            template: template,
            checklistService: checklistService,
            onTemplateUpdated: { updatedTemplate in
              self.template = updatedTemplate
              onTemplateUpdated?(updatedTemplate)
            }
          )
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
      }
    }
    .task(id: templateId) {
      await load()
    }
    .alert(
      "Delete Template?",
      isPresented: $showDeleteConfirmation
    ) {
      Button("Delete", role: .destructive) {
        Task {
          await deleteTemplate()
        }
      }
      Button("Cancel", role: .cancel) { }
    } message: {
      Text("Are you sure you want to permanently delete this custom checklist?")
    }
    .alert(
      "Error",
      isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      ),
      presenting: errorMessage
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
      if let category = template?.category {
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

      if let description = template?.description, !description.isEmpty {
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
      if items.isEmpty {
        Text("No steps added yet")
          .marineFont(.body)
          .foregroundStyle(marineTheme.colors.textSecondary)
          .marineListCell()
      } else {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
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
        Text("\(items.count)")
          .foregroundStyle(marineTheme.colors.textSecondary)
      }
      .marineFont(.caption)
    }
  }

  @ViewBuilder
  private var actionsSection: some View {
    Section {
      Button {
        if let templateId = template?.id {
          panelManager?.commandPath.append(.checklistDetail(templateId: templateId))
        }
      } label: {
        HStack(spacing: MarineTheme.Spacing.small) {
          Image(systemName: hasActiveSession ? "play.circle.fill" : "play.fill")
          Text(hasActiveSession ? "Continue Checklist" : "Start Checklist")
        }
      }
      .buttonStyle(MarineButtonStyle(.primary))
      .marineListCell()

      if checklistService != nil {
        Button {
          isShowingEditSheet = true
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

  // MARK: - Actions

  private func load() async {
    guard let checklistService else { return }
    isLoading = true
    defer { isLoading = false }
    errorMessage = nil

    do {
      template = try await checklistService.fetchTemplate(id: templateId)
      let session = try await checklistService.fetchActiveSession(for: templateId)
      hasActiveSession = (session?.status == .inProgress && (session?.completedCount ?? 0) > 0)
    } catch {
      Logger.checklist.error("Failed to load checklist template \(self.templateId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
      errorMessage = error.localizedDescription
    }
  }

  private func deleteTemplate() async {
    guard let checklistService else { return }
    do {
      try await checklistService.deleteCustomTemplate(id: templateId)
      Logger.checklist.info("Successfully deleted custom template: \(self.templateId.uuidString, privacy: .public)")
      dismiss()
    } catch {
      Logger.checklist.error("Failed to delete template: \(error.localizedDescription, privacy: .public)")
      errorMessage = error.localizedDescription
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
