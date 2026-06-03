//
//  WaypointEditView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-06-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

@MainActor
struct WaypointEditView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.marineTheme) private var marineTheme
  
  @Bindable var viewModel: WaypointEditViewModel
  
  var body: some View {
    NavigationStack {
      Form {
        Section(header: Text("Details")) {
          TextField("Name", text: $viewModel.name)
            .marineFont(.body)
            .marineListCell()
          
          TextField("Description (Optional)", text: $viewModel.description)
            .marineFont(.body)
            .marineListCell()
        }
        
        Section(
          header: Text("Location"),
          footer: Text("Format: N 45° 12.345' or decimal degrees.")
        ) {
          VStack(alignment: .leading, spacing: 4) {
            TextField("Latitude (e.g. N 45° 12.345')", text: $viewModel.latitudeString)
              .marineFont(.body)
              .keyboardType(.numbersAndPunctuation)
            
            if !viewModel.latitudeString.isEmpty && viewModel.parsedLatitude == nil {
              Text("Invalid Latitude")
                .foregroundStyle(.red)
                .marineFont(.caption)
            }
          }
          .marineListCell()
          
          VStack(alignment: .leading, spacing: 4) {
            TextField("Longitude (e.g. W 02° 34.567')", text: $viewModel.longitudeString)
              .marineFont(.body)
              .keyboardType(.numbersAndPunctuation)
            
            if !viewModel.longitudeString.isEmpty && viewModel.parsedLongitude == nil {
              Text("Invalid Longitude")
                .foregroundStyle(.red)
                .marineFont(.caption)
            }
          }
          .marineListCell()
        }
      }
      .scrollContentBackground(.hidden)
      .background(MarineTheme.Colors.panelBackground)
      .navigationTitle(viewModel.editingWaypointId == nil ? "New Waypoint" : "Edit Waypoint")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            Task {
              if await viewModel.save() {
                dismiss()
              }
            }
          }
          .disabled(!viewModel.isValid || viewModel.isSaving)
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
}
