//
//  ChecklistCategoryListView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Displays the catalog of available maritime checklist categories.
@MainActor
public struct ChecklistCategoryListView: View {
  @Environment(\.marineTheme) private var marineTheme
  @Environment(PanelManagerViewModel.self) private var panelManager: PanelManagerViewModel?
  private let checklistService: any ChecklistServiceProtocol
  @State private var viewModel: ChecklistCategoryListViewModel
  @State private var editMode: EditMode = .inactive

  public init(checklistService: any ChecklistServiceProtocol) {
    self.checklistService = checklistService
    _viewModel = State(wrappedValue: ChecklistCategoryListViewModel(checklistService: checklistService))
  }

  public var body: some View {
    Group {
      if viewModel.isLoading && viewModel.categories.isEmpty {
        ProgressView()
          .tint(marineTheme.colors.accent)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let errorMessage = viewModel.errorMessage, viewModel.categories.isEmpty {
        ContentUnavailableView {
          Label("Error Loading Categories", systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(marineTheme.colors.warning)
        } description: {
          Text(errorMessage)
            .marineFont(.body)
        }
      } else if viewModel.categories.isEmpty {
        ContentUnavailableView {
          Label("No Categories", systemImage: "tag.slash")
        } description: {
          Text("No categories available")
            .marineFont(.body)
        }
      } else {
        List {
          Section {
            ForEach(viewModel.categories) { category in
              ZStack {
                ChecklistCategoryRowView(
                  category: category,
                  checklistCount: viewModel.checklistCount(for: category.id),
                  showsDisclosureIndicator: editMode != .active
                )

                if editMode != .active {
                  NavigationLink(
                    value: PanelManagerViewModel.CommandDestination.checklistCategoryDetail(
                      ChecklistCategoryDetailPayload(
                        categoryId: category.id,
                        category: category
                      )
                    )
                  ) {
                    EmptyView()
                  }
                  .opacity(0)
                }
              }
              .marineListCell()
            }
            .onMove(perform: viewModel.moveCategories)
          } header: {
            HStack {
              Text("Categories")
                .marineSectionHeader()
              Spacer()
              if viewModel.categories.count > 1 {
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
            if editMode == .active {
              Text("Drag handles to change category order.")
                .marineFont(.caption)
                .foregroundStyle(marineTheme.colors.textSecondary)
            } else if viewModel.categories.count > 1 {
              Text("Tap Reorder to change category order.")
                .marineFont(.caption)
                .foregroundStyle(marineTheme.colors.textSecondary)
            }
          }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, $editMode)
        .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
        .onChange(of: viewModel.categories.count) { _, newCount in
          if newCount <= 1 && editMode == .active {
            editMode = .inactive
          }
        }
      }
    }
    .marineListBackground()
    .navigationTitle("Checklist Categories")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          panelManager?.commandPath.append(
            .checklistCategoryDetail(
              ChecklistCategoryDetailPayload(categoryId: nil, startEditable: true)
            )
          )
        } label: {
          Image(marineIcon: .add)
            .foregroundStyle(marineTheme.colors.accent)
        }
        .accessibilityLabel(String(localized: "New Category"))
      }
    }
    .task {
      await viewModel.loadCategories()
    }
    .alert(
      "Error",
      isPresented: Binding(
        get: { viewModel.errorMessage != nil && !viewModel.categories.isEmpty },
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

private struct ChecklistCategoryRowView: View {
  @Environment(\.marineTheme) private var marineTheme
  let category: ChecklistCategoryItem
  let checklistCount: Int
  var showsDisclosureIndicator: Bool = true

  var body: some View {
    HStack(spacing: MarineTheme.Spacing.medium) {
      Image(systemName: category.displaySystemImage)
        .font(.title3)
        .foregroundStyle(marineTheme.colors.accent)
        .frame(width: 32, alignment: .center)

      VStack(alignment: .leading, spacing: 2) {
        Text(category.name)
          .marineFont(.body)
          .foregroundStyle(marineTheme.colors.textPrimary)

        Text("^[\(checklistCount) checklist](inflect: true)")
          .marineFont(.caption)
          .foregroundStyle(marineTheme.colors.textSecondary)
      }

      Spacer()

      if showsDisclosureIndicator {
        Image(systemName: "chevron.right")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(marineTheme.colors.textSecondary.opacity(0.5))
      }
    }
    .accessibilityElement(children: .combine)
  }
}
