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

/// A unified view for inspecting, executing, composing, and modifying a maritime checklist template.
@MainActor
public struct ChecklistTemplateDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.marineTheme) private var marineTheme
  @Environment(PanelManagerViewModel.self) private var panelManager: PanelManagerViewModel?

  let templateId: UUID?
  @State private var viewModel: ChecklistTemplateDetailViewModel
  @State private var editMode: EditMode = .inactive
  @State private var showDeleteConfirmation: Bool = false
  public var onTemplateSaved: (@MainActor (ChecklistTemplate) -> Void)?

  public init(
    templateId: UUID? = nil,
    template: ChecklistTemplate? = nil,
    checklistService: any ChecklistServiceProtocol,
    startEditable: Bool = false,
    initialCategory: ChecklistCategory = .routine,
    onTemplateSaved: (@MainActor (ChecklistTemplate) -> Void)? = nil
  ) {
    self.templateId = templateId ?? template?.id
    self.onTemplateSaved = onTemplateSaved
    _viewModel = State(initialValue: ChecklistTemplateDetailViewModel(
      templateId: templateId,
      template: template,
      checklistService: checklistService,
      startEditable: startEditable,
      initialCategory: initialCategory
    ))
  }

  public var body: some View {
    VStack(spacing: 0) {
      Form {
        if viewModel.isLoading && viewModel.template == nil {
          loadingSection
        } else if viewModel.isEditable {
          generalEditSection
          stepsEditSection
        } else {
          generalConsultationSection
          stepsConsultationSection
        }
      }
      .marineListBackground()
      .environment(\.editMode, $editMode)
      .onChange(of: viewModel.items.count) { _, newCount in
        if newCount <= 1 && editMode == .active {
          editMode = .inactive
        }
      }

      if !viewModel.isEditable && viewModel.template != nil {
        bottomActionBar
      }
    }
    .interactiveDismissDisabled(viewModel.isSaving)
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .navigationTitle(
      viewModel.isEditable
        ? (viewModel.isNew ? String(localized: "New Checklist") : String(localized: "Edit Checklist"))
        : (viewModel.title.isEmpty ? String(localized: "Checklist") : viewModel.title)
    )
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(viewModel.isEditable)
    .toolbar {
      if viewModel.isEditable {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            if viewModel.isNew {
              dismiss()
            } else {
              withAnimation {
                editMode = .inactive
                viewModel.revert()
              }
            }
          } label: {
            Image(marineIcon: .close)
              .foregroundStyle(marineTheme.colors.textSecondary)
              .padding(8)
              .contentShape(Rectangle())
          }
          .disabled(viewModel.isSaving)
          .accessibilityLabel(String(localized: "Cancel"))
        }

        ToolbarItem(placement: .confirmationAction) {
          Button {
            guard viewModel.isValid else {
              viewModel.alertTitle = String(localized: "Incomplete Checklist")
              viewModel.errorMessage = viewModel.validationErrorMessage
              return
            }

            Task {
              let wasNew = viewModel.isNew
              if let saved = await viewModel.save() {
                onTemplateSaved?(saved)
                editMode = .inactive
                if wasNew {
                  dismiss()
                }
              }
            }
          } label: {
            Image(marineIcon: .save)
              .padding(8)
              .contentShape(Rectangle())
          }
          .disabled(viewModel.isSaving)
          .accessibilityLabel(String(localized: "Save"))
        }
      } else {
        if viewModel.template != nil {
          ToolbarItem(placement: .primaryAction) {
            Button {
              withAnimation {
                viewModel.isEditable = true
              }
            } label: {
              Text("Edit")
                .marineFont(.body)
                .foregroundStyle(marineTheme.colors.accent)
            }
            .accessibilityLabel(String(localized: "Edit Checklist"))
          }
        }
      }
    }
    .task(id: templateId) {
      await viewModel.startObserving()
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
      viewModel.alertTitle,
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

  // MARK: - Sections (Consultation Mode)

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
  private var generalConsultationSection: some View {
    Section("Information") {
      HStack {
        Text("Category")
          .marineFont(.body)
          .foregroundStyle(marineTheme.colors.textSecondary)
        Spacer()
        HStack(spacing: MarineTheme.Spacing.small) {
          Image(systemName: viewModel.category.systemImage)
            .foregroundStyle(viewModel.category.color(for: marineTheme))
          Text(viewModel.category.title)
            .marineFont(.body)
            .foregroundStyle(marineTheme.colors.textPrimary)
        }
      }
      .marineListCell()

      HStack {
        Text("Status")
          .marineFont(.body)
          .foregroundStyle(marineTheme.colors.textSecondary)
        Spacer()
        switch viewModel.usageStatus {
        case .inProgress(let session):
          Text("Started \(session.startedAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened)) • \(session.completedCount)/\(session.totalCount) checked")
            .marineFont(.body)
            .foregroundStyle(marineTheme.colors.textPrimary)
            .multilineTextAlignment(.trailing)
        case .completed(let date):
          Text("Completed \(date, format: Date.FormatStyle(date: .abbreviated, time: .shortened))")
            .marineFont(.body)
            .foregroundStyle(marineTheme.colors.textPrimary)
            .multilineTextAlignment(.trailing)
        case .neverUsed:
          Text("Never used")
            .marineFont(.body)
            .foregroundStyle(marineTheme.colors.textPrimary)
            .multilineTextAlignment(.trailing)
        }
      }
      .marineListCell()

      if let description = viewModel.description {
        VStack(alignment: .leading, spacing: MarineTheme.Spacing.small) {
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
  private var stepsConsultationSection: some View {
    Section("Steps") {
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
            detail: item.detail.isEmpty ? nil : item.detail
          )
        }
      }
    }
  }

  @ViewBuilder
  private var bottomActionBar: some View {
    VStack(spacing: MarineTheme.Spacing.small) {
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
    }
    .padding(MarineTheme.Spacing.medium)
    .background(marineTheme.colors.surfaceBackground)
  }

  // MARK: - Sections (Edit Mode)

  @ViewBuilder
  private var generalEditSection: some View {
    Section("Information") {
      VStack(alignment: .leading, spacing: MarineTheme.Spacing.small) {
        Text("Title")
          .marineFont(.caption)
          .foregroundStyle(marineTheme.colors.textSecondary)
        TextField("Checklist Title", text: $viewModel.title)
          .marineFont(.body)
      }
      .marineListCell()

      Picker("Category", selection: $viewModel.category) {
        ForEach(ChecklistCategory.allCases, id: \.self) { category in
          Label(category.title, systemImage: category.systemImage).tag(category)
        }
      }
      .pickerStyle(.menu)
      .marineFont(.body)
      .marineListCell()

      VStack(alignment: .leading, spacing: MarineTheme.Spacing.small) {
        Text("Description")
          .marineFont(.caption)
          .foregroundStyle(marineTheme.colors.textSecondary)
        MarineExpandingTextEditor(
          placeholder: "Checklist Description (Optional)",
          text: $viewModel.descriptionText
        )
      }
      .marineListCell()
    }
  }

  @ViewBuilder
  private var stepsEditSection: some View {
    Section {
      if viewModel.items.isEmpty {
        Text("No steps added yet")
          .marineFont(.body)
          .foregroundStyle(marineTheme.colors.textSecondary)
          .marineListCell()
      } else {
        ForEach($viewModel.items) { $item in
          let item = $item.wrappedValue
          let isFirst = item.id == viewModel.items.first?.id
          let isLast = item.id == viewModel.items.last?.id
          let displayIndex = viewModel.items.firstIndex(where: { $0.id == item.id }) ?? 0

          VStack(alignment: .leading, spacing: MarineTheme.Spacing.small) {
            HStack(alignment: .center, spacing: MarineTheme.Spacing.small) {
              Text("\(displayIndex + 1).")
                .marineFont(.subheadline)
                .foregroundStyle(marineTheme.colors.textSecondary)
                .frame(minWidth: 22, alignment: .leading)

              TextField("Step title", text: $item.title)
                .marineFont(.body)

              if editMode == .active {
                HStack(spacing: MarineTheme.Spacing.tiny) {
                  Button {
                    withAnimation {
                      viewModel.moveItemUp(id: item.id)
                    }
                  } label: {
                    Image(systemName: "chevron.up")
                      .font(.body.weight(.semibold))
                      .foregroundStyle(isFirst ? marineTheme.colors.inactive.opacity(0.3) : marineTheme.colors.accent)
                      .frame(minWidth: 32, minHeight: 32)
                      .contentShape(Rectangle())
                  }
                  .buttonStyle(.plain)
                  .disabled(isFirst)
                  .accessibilityLabel(Text("Move up"))

                  Button {
                    withAnimation {
                      viewModel.moveItemDown(id: item.id)
                    }
                  } label: {
                    Image(systemName: "chevron.down")
                      .font(.body.weight(.semibold))
                      .foregroundStyle(isLast ? marineTheme.colors.inactive.opacity(0.3) : marineTheme.colors.accent)
                      .frame(minWidth: 32, minHeight: 32)
                      .contentShape(Rectangle())
                  }
                  .buttonStyle(.plain)
                  .disabled(isLast)
                  .accessibilityLabel(Text("Move down"))
                }
              }
            }

            TextField("Detail / instructions (Optional)", text: $item.detail)
              .marineFont(.subheadline)
              .foregroundStyle(marineTheme.colors.textSecondary)
              .padding(.leading, 30)
          }
          .padding(.vertical, 6)
          .marineListCell()
        }
        .onDelete(perform: viewModel.removeItems)
        .onMove(perform: viewModel.moveItems)
      }

      Button {
        viewModel.addItem()
      } label: {
        HStack(spacing: MarineTheme.Spacing.small) {
          Image(marineIcon: .add)
          Text("Add Step")
        }
        .foregroundStyle(marineTheme.colors.accent)
        .marineFont(.body)
      }
      .marineListCell()
    } header: {
      HStack {
        Text("Steps")
        Spacer()
        if viewModel.items.count > 1 {
          Button {
            withAnimation {
              editMode = editMode == .active ? .inactive : .active
            }
          } label: {
            HStack(spacing: 4) {
              Image(systemName: editMode == .active ? "checkmark" : "arrow.up.arrow.down")
              Text(editMode == .active ? "Done" : "Reorder")
                .textCase(nil)
            }
            .foregroundStyle(marineTheme.colors.accent)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
              Capsule()
                .fill(marineTheme.colors.secondaryActionBackground)
            )
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(editMode == .active ? "Done" : "Reorder"))
        }
      }
    } footer: {
      VStack(alignment: .leading, spacing: MarineTheme.Spacing.medium) {
        if editMode == .active {
          Text("Drag handles or tap arrows to change step order.")
            .marineFont(.caption)
            .foregroundStyle(marineTheme.colors.textSecondary)
        } else if viewModel.items.count > 1 {
          Text("Swipe to delete. Tap Reorder to change step order.")
            .marineFont(.caption)
            .foregroundStyle(marineTheme.colors.textSecondary)
        } else {
          Text("Swipe to delete.")
            .marineFont(.caption)
            .foregroundStyle(marineTheme.colors.textSecondary)
        }

        if !viewModel.isNew {
          Button(action: {
            showDeleteConfirmation = true
          }) {
            HStack {
              Image(marineIcon: .delete)
              Text("Delete")
            }
          }
          .buttonStyle(MarineButtonStyle(.destructive))
          .disabled(!viewModel.canDelete)
          .textCase(nil)
          .padding(.top, MarineTheme.Spacing.medium)
        }
      }
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
