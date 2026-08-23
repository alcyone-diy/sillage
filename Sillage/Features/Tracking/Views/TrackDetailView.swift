//
//  TrackDetailView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-20.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import OSLog
import SwiftUI

@MainActor
struct TrackDetailView: View {
  @Bindable var viewModel: TrackDetailViewModel
  @Environment(\.marineTheme) private var marineTheme
  @Environment(ChartViewModel.self) private var chartViewModel
  
  var onViewRequested: ((String) async throws -> Void)?
  
  @Environment(\.dismiss) private var dismiss
  @State private var showDeleteConfirmation = false
  @State private var errorMessage: String?
  
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
        Section(
          header: Text("Details"),
          footer: Group {
            if viewModel.isEditing {
              Button(action: {
                showDeleteConfirmation = true
              }) {
                HStack {
                  Image(marineIcon: .delete)
                  Text("Delete")
                }
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(viewModel.canDelete ? marineTheme.colors.onPrimary : marineTheme.colors.inactive)
                .frame(maxWidth: .infinity, minHeight: marineTheme.minTouchTarget)
                .background(viewModel.canDelete ? marineTheme.colors.destructive : marineTheme.colors.disabledBackground)
                .clipShape(RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous))
              }
              .buttonStyle(MarineButtonStyle())
              .disabled(!viewModel.canDelete)
              .textCase(nil)
              .padding(.top, MarineTheme.Spacing.medium)
            }
          }
        ) {
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
            value: viewModel.totalDuration?.marineFormatted ?? "—"
          )
          .marineListCell()
          
          DetailRow(
            label: "Length",
            value: viewModel.totalDistanceOverGround?.marineNauticalMilesFormatted ?? "—"
          )
          .marineListCell()
          
          DetailRow(
            label: "Segments",
            value: viewModel.segmentCount.map { String($0) } ?? "—"
          )
          .marineListCell()
          
          DetailRow(
            label: "Points",
            value: viewModel.totalPointCount.map { String($0) } ?? "—"
          )
          .marineListCell()
          
          DetailRow(
            label: "Max Speed",
            value: viewModel.maxSpeedOverGround?.marineFormatted ?? "—"
          )
          .marineListCell()
          
          DetailRow(
            label: "Average Speed",
            value: viewModel.totalAverageSpeedOverGround?.marineFormatted ?? "—"
          )
          .marineListCell()
        }
      }
      .listStyle(.insetGrouped)
      .marineListBackground()
      .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
      
      if !viewModel.isEditing {
        VStack(spacing: MarineTheme.Spacing.small) {
          ShareLink(
            item: viewModel.gpxExport,
            preview: SharePreview(
              viewModel.name.isEmpty ? "Track Export" : viewModel.name,
              image: Image(marineIcon: .track)
            )
          ) {
            exportButtonLabel
          }
          .buttonStyle(MarineButtonStyle())

          let isVisible = chartViewModel.displayedTrackSessionID == viewModel.sessionID
          Button(action: {
            Task {
              do {
                if isVisible {
                  chartViewModel.clearSavedTrack()
                } else {
                  if let onViewRequested = onViewRequested {
                    try await onViewRequested(viewModel.sessionID)
                  }
                }
              } catch {
                Logger.chart.error("Failed to load and display track \(viewModel.sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                errorMessage = String(localized: "Failed to load track points.")
              }
            }
          }) {
            HStack {
              Image(marineIcon: .track)
              Text(isVisible ? "Hide" : "Show")
            }
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(marineTheme.colors.onPrimary)
            .frame(maxWidth: .infinity, minHeight: marineTheme.minTouchTarget)
            .background(isVisible ? marineTheme.colors.cancelAction : marineTheme.colors.primary)
            .clipShape(RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous))
          }
          .buttonStyle(MarineButtonStyle())
        }
        .padding(MarineTheme.Spacing.medium)
        .background(marineTheme.colors.surfaceBackground)
      }
    }
    .alert(
      "Delete Track?",
      isPresented: $showDeleteConfirmation
    ) {
      Button("Delete", role: .destructive) {
        Task {
          do {
            try await viewModel.deleteSession()
            dismiss()
          } catch {
            errorMessage = String(localized: "Failed to delete track. Please try again.")
          }
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Are you sure you want to delete this track? This action cannot be undone.")
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
            Image(marineIcon: .close)
          }
          .accessibilityLabel(String(localized: "Cancel"))
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
          Button {
            Task {
              do {
                try await viewModel.saveChanges()
              } catch {
                errorMessage = String(localized: "Failed to save changes. Please try again.")
              }
            }
          } label: {
            Image(marineIcon: .save)
          }
          .fontWeight(.semibold)
          .disabled(viewModel.isSaving)
          .accessibilityLabel(String(localized: "Save"))
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
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      ),
      presenting: errorMessage
    ) { _ in
      Button("OK", role: .cancel) {}
    } message: { message in
      Text(verbatim: message)
    }
  }
  
  private var exportButtonLabel: some View {
    HStack {
      Image(marineIcon: .share)
      Text(String(localized: "Export GPX"))
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
