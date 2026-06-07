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
  
  @Bindable var viewModel: WaypointEditViewModel
  
  var body: some View {
    Form {
      Section(header: Text("Details")) {
          TextField("Name", text: $viewModel.name)
            .marineFont(.body)
            .marineListCell()
          
          TextField("Description (Optional)", text: $viewModel.description)
            .marineFont(.body)
            .marineListCell()
            
          ColorPicker("Color", selection: $viewModel.color, supportsOpacity: false)
            .marineFont(.body)
            .marineListCell()
            
          Toggle("Displayed on Map", isOn: $viewModel.isVisible)
            .marineFont(.body)
            .marineListCell()
            .tint(MarineTheme.Colors.primary)
        }
        .disabled(!viewModel.isEditable)
        
        Section(
          header: Text("Location"),
          footer: Text("Format: N/S Degrees Minutes.")
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
      .scrollContentBackground(.hidden)
      .background(MarineTheme.Colors.panelBackground)
      .navigationTitle(viewModel.editingWaypointId == nil ? "New Waypoint" : (viewModel.isEditable ? "Edit Waypoint" : viewModel.name))
      .navigationBarTitleDisplayMode(.inline)
      .navigationBarBackButtonHidden(viewModel.isEditable && viewModel.editingWaypointId != nil)
      .toolbar {
        if viewModel.isEditable {
          ToolbarItem(placement: .cancellationAction) {
            Button {
              if viewModel.editingWaypointId == nil {
                dismiss()
              } else {
                viewModel.revert()
              }
            } label: {
              Image(systemName: "xmark")
                .padding(8)
                .contentShape(Rectangle())
            }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button {
              Task {
                if await viewModel.save() {
                  if viewModel.editingWaypointId == nil {
                    dismiss()
                  } else {
                    viewModel.isEditable = false
                  }
                }
              }
            } label: {
              Image(systemName: "checkmark")
                .padding(8)
                .contentShape(Rectangle())
            }
            .disabled(!viewModel.isValid || viewModel.isSaving)
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
