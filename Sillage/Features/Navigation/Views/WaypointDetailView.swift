//
//  WaypointDetailView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-06-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

@MainActor
struct WaypointDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.marineTheme) private var marineTheme
  
  @Bindable var viewModel: WaypointDetailViewModel
  var onGoToRequested: ((String) -> Void)?
  var onCancelNavigationRequested: (() -> Void)?
  
  @State private var showDeleteConfirmation = false
  
  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section(header: Text("Details")) {
          TextField("Name", text: $viewModel.name)
            .marineFont(.body)
            .marineListCell()
            .disabled(!viewModel.isEditable)
          
          TextField("Description (Optional)", text: $viewModel.description)
            .marineFont(.body)
            .marineListCell()
            .disabled(!viewModel.isEditable)
            
          ColorPicker("Color", selection: $viewModel.color, supportsOpacity: false)
            .marineFont(.body)
            .marineListCell()
            .disabled(!viewModel.isEditable)
            
          Toggle("Show", isOn: $viewModel.isVisible)
            .marineFont(.body)
            .marineListCell()
            .tint(marineTheme.colors.primary)
            .onChange(of: viewModel.isVisible) { _, _ in
              if !viewModel.isEditable {
                Task {
                  _ = await viewModel.save()
                }
              }
            }
        }
        
        Section(
          header: Text("Location"),
          footer: VStack(alignment: .leading, spacing: MarineTheme.Spacing.medium) {
            Text("Format: N/S Degrees Minutes.")
            
            if let _ = viewModel.editingWaypointID, viewModel.isEditable {
              Button(action: {
                showDeleteConfirmation = true
              }) {
                HStack {
                  Image(marineIcon: .delete)
                  Text("Delete Waypoint")
                }
              }
              .buttonStyle(MarineButtonStyle(.destructive))
              .textCase(nil)
            }
          }
        ) {
          VStack(alignment: .leading, spacing: 4) {
            CoordinateInputView(
              title: "Latitude",
              type: .latitude,
              hemisphere: $viewModel.latHemisphere,
              degrees: $viewModel.latDegrees,
              minutes: $viewModel.latMinutes
            )
            
            if viewModel.latDegrees != nil && viewModel.parsedLatitude == nil {
              Text("Invalid Latitude")
                .foregroundStyle(.red)
                .marineFont(.caption)
            }
          }
          .marineListCell()
          
          VStack(alignment: .leading, spacing: 4) {
            CoordinateInputView(
              title: "Longitude",
              type: .longitude,
              hemisphere: $viewModel.lonHemisphere,
              degrees: $viewModel.lonDegrees,
              minutes: $viewModel.lonMinutes
            )
            
            if viewModel.lonDegrees != nil && viewModel.parsedLongitude == nil {
              Text("Invalid Longitude")
                .foregroundStyle(.red)
                .marineFont(.caption)
            }
          }
          .marineListCell()
        }
        .disabled(!viewModel.isEditable)
      }
      .marineListBackground()
      
      if let waypointID = viewModel.editingWaypointID, !viewModel.isEditable {
        VStack(spacing: MarineTheme.Spacing.small) {
          if viewModel.isGoTo {
            Button(action: {
              onCancelNavigationRequested?()
            }) {
              HStack {
                Image(marineIcon: .cancelAction)
                Text("Cancel Navigation")
              }
            }
            .buttonStyle(MarineButtonStyle(.cancel))
          } else {
            Button(action: {
              onGoToRequested?(waypointID)
            }) {
              HStack {
                Image(marineIcon: .waypoint)
                Text("Go To")
              }
            }
            .buttonStyle(MarineButtonStyle(.primary))
          }
        }
        .padding(MarineTheme.Spacing.medium)
        .background(marineTheme.colors.surfaceBackground)
      }
    }
    .alert(
      "Delete Waypoint?",
      isPresented: $showDeleteConfirmation
    ) {
      Button("Delete", role: .destructive) {
        Task {
          if await viewModel.delete() {
            dismiss()
          }
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Are you sure you want to delete this waypoint? This action cannot be undone.")
    }
    .navigationTitle(viewModel.editingWaypointID == nil ? "New Waypoint" : (viewModel.isEditable ? "Edit Waypoint" : viewModel.name))
    .navigationBarTitleDisplayMode(.inline)
      .navigationBarBackButtonHidden(viewModel.isEditable && viewModel.editingWaypointID != nil)
      .toolbar {
        if viewModel.isEditable {
          ToolbarItem(placement: .cancellationAction) {
            Button {
              if viewModel.editingWaypointID == nil {
                dismiss()
              } else {
                viewModel.revert()
              }
            } label: {
              Image(marineIcon: .close)
                .padding(8)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "Cancel"))
          }
          ToolbarItem(placement: .confirmationAction) {
            Button {
              Task {
                if await viewModel.save() {
                  if viewModel.editingWaypointID == nil {
                    dismiss()
                  } else {
                    viewModel.isEditable = false
                  }
                }
              }
            } label: {
              Image(marineIcon: .save)
                .padding(8)
                .contentShape(Rectangle())
            }
            .disabled(!viewModel.isValid || viewModel.isSaving)
            .accessibilityLabel(String(localized: "Save"))
          }
        } else {
          ToolbarItem(placement: .primaryAction) {
            Button("Edit") {
              viewModel.isEditable = true
            }
          }
        }
      }
      .alert(
        "Error",
        isPresented: Binding(
          get: { viewModel.activeError != nil },
          set: { if !$0 { viewModel.activeError = nil } }
        ),
        presenting: viewModel.activeError
      ) { _ in
        Button("OK", role: .cancel) { }
      } message: { error in
        Text(error.localizedDescription)
    }
  }
}
