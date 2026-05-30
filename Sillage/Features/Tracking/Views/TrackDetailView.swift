//
//  TrackDetailView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-20.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

@MainActor
struct TrackDetailView: View {
  @Bindable var viewModel: TrackDetailViewModel
  @Environment(\.marineTheme) private var marineTheme
  
  @Environment(\.dismiss) private var dismiss
  @State private var showDeleteConfirmation = false
  
  var body: some View {
    VStack(spacing: 0) {
      List {
        // Identity Section (Editable)
        Section() {
          if viewModel.isEditing {
            VStack(alignment: .leading, spacing: MarineTheme.Spacing.small) {
              Text("Name")
                .foregroundStyle(.secondary)
                .marineFont(.caption)
              TextField("Track Name", text: $viewModel.name)
                .marineFont(.body)
            }
            .marineListCell()
            
            VStack(alignment: .leading, spacing: MarineTheme.Spacing.small) {
              Text("Description")
                .foregroundStyle(.secondary)
                .marineFont(.caption)
              MarineExpandingTextEditor(
                placeholder: "Track Description",
                text: $viewModel.description
              )
            }
            .marineListCell()
          } else {
            VStack(alignment: .leading, spacing: MarineTheme.Spacing.small) {
              Text("Name")
                .foregroundStyle(.secondary)
                .marineFont(.caption)
              Text(viewModel.name.isEmpty ? (viewModel.session?.startTime.formatted(date: .complete, time: .shortened) ?? String(localized: "Unnamed Track")) : viewModel.name)
                .marineFont(.body)
            }
            .marineListCell()
            
            VStack(alignment: .leading, spacing: MarineTheme.Spacing.small) {
              Text("Description")
                .foregroundStyle(.secondary)
                .marineFont(.caption)
              Text(viewModel.description.isEmpty ? "No description" : viewModel.description)
                .marineFont(.body)
                .foregroundStyle(viewModel.description.isEmpty ? .secondary : .primary)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            }
            .marineListCell()
          }
        }
        
        // Metrics Section (Static)
        Section(header: Text("Details")) {
          DetailRow(
            label: "Start Time",
            value: viewModel.session?.startTime.formatted(date: .abbreviated, time: .shortened) ?? "—"
          )
          .marineListCell()
          
          DetailRow(
            label: "End Time",
            value: viewModel.session?.endTime?.formatted(date: .abbreviated, time: .shortened) ?? "Active"
          )
          .marineListCell()
          
          DetailRow(
            label: "Duration",
            value: viewModel.session?.totalDuration?.marineFormatted ?? "—"
          )
          .marineListCell()
          
          DetailRow(
            label: "Length",
            value: viewModel.session?.totalDistance?.marineFormatted ?? "—"
          )
          .marineListCell()
          
          DetailRow(
            label: "Segments",
            value: viewModel.session?.segmentCount.map { String($0) } ?? "—"
          )
          .marineListCell()
          
          DetailRow(
            label: "Points",
            value: viewModel.session?.pointsCount.map { String($0) } ?? "—"
          )
          .marineListCell()
          
          DetailRow(
            label: "Max Speed",
            value: viewModel.session?.maxSpeed?.marineFormatted ?? "—"
          )
          .marineListCell()
          
          DetailRow(
            label: "Average Speed",
            value: viewModel.session?.averageSpeed?.marineFormatted ?? "—"
          )
          .marineListCell()
        }
        
        if viewModel.isEditing {
          Button(role: .destructive, action: {
            showDeleteConfirmation = true
          }) {
            HStack {
              Image(systemName: "trash")
              Text("Delete")
            }
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(viewModel.canDelete ? .red : .gray)
            .frame(maxWidth: .infinity, minHeight: marineTheme.minTouchTarget)
            .background(viewModel.canDelete ? MarineTheme.Colors.destructiveBackground : MarineTheme.Colors.disabledBackground)
            .cornerRadius(MarineTheme.Metrics.cornerRadius)
          }
          .buttonStyle(MarineButtonStyle())
          .disabled(!viewModel.canDelete)
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets())
          .confirmationDialog(
            "Delete Track?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
          ) {
            Button("Delete", systemImage: "trash", role: .destructive) {
              Task {
                let success = await viewModel.deleteSession()
                if success {
                  dismiss()
                }
              }
            }
            Button("Cancel", role: .cancel) {}
          } message: {
            Text("This action cannot be undone.")
          }
        }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .background(MarineTheme.Colors.panelBackground)
      .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
      
      if !viewModel.isEditing {
        VStack(spacing: MarineTheme.Spacing.small) {
          Button(action: {
            // Action for View will be implemented later
          }) {
            HStack {
              Image(systemName: "map")
              Text("View")
            }
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: marineTheme.minTouchTarget)
            .background(MarineTheme.Colors.primary)
            .cornerRadius(MarineTheme.Metrics.cornerRadius)
          }
          .buttonStyle(MarineButtonStyle())
        }
        .padding(MarineTheme.Spacing.medium)
        .background(MarineTheme.Colors.surfaceBackground)
      }
    }
    .navigationTitle("Track Detail")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(viewModel.isEditing)
    .toolbar {
      if viewModel.isEditing {
        ToolbarItem(placement: .navigationBarLeading) {
          Button {
            viewModel.cancelEditing()
          } label: {
            Image(systemName: "xmark")
          }
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
          Button {
            Task {
              await viewModel.saveChanges()
            }
          } label: {
            Image(systemName: "checkmark")
          }
          .fontWeight(.semibold)
          .disabled(viewModel.isSaving)
        }
      } else {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Edit") {
            viewModel.isEditing = true
          }
        }
      }
    }
    .task {
      await viewModel.load()
    }
    .alert(
      "Error",
      isPresented: Binding(
        get: { viewModel.errorMessage != nil },
        set: { if !$0 { viewModel.errorMessage = nil } }
      ),
      presenting: viewModel.errorMessage
    ) { _ in
      Button("OK", role: .cancel) {}
    } message: { message in
      Text(verbatim: message)
    }
  }
}

fileprivate struct DetailRow: View {
  let label: LocalizedStringKey
  let value: String
  
  var body: some View {
    HStack {
      Text(label)
        .foregroundStyle(.secondary)
        .marineFont(.body)
      Spacer()
      Text(verbatim: value)
        .marineFont(.body)
    }
  }
}
