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
  @Environment(\.marineTheme) private var marineTheme
  @ScaledMetric(relativeTo: .body) private var scaleFactor: CGFloat = 1.0

  @State private var viewModel: TrackDetailViewModel
  @Environment(\.dismiss) private var dismiss
  @State private var showDeleteConfirmation = false

  init(
    sessionId: TrackSession.ID,
    trackService: TrackService,
    trackRecordingService: TrackRecordingService
  ) {
    _viewModel = State(wrappedValue: TrackDetailViewModel(
      sessionId: sessionId,
      trackService: trackService,
      trackRecordingService: trackRecordingService
    ))
  }

  var body: some View {
    VStack(spacing: 0) {
      List {
        // Identity Section (Editable)
        Section(header: Text("Identity")) {
          if viewModel.isEditing {
            VStack(alignment: .leading, spacing: MarineTheme.Spacing.small) {
              Text("Name")
                .foregroundStyle(.secondary)
                .marineFont(.caption)
              TextField("Track Name", text: $viewModel.name)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 44)
            }
            .marineListCell()

            VStack(alignment: .leading, spacing: MarineTheme.Spacing.small) {
              Text("Description")
                .foregroundStyle(.secondary)
                .marineFont(.caption)
              TextField("Track Description", text: $viewModel.description, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 44)
            }
            .marineListCell()
          } else {
            VStack(alignment: .leading, spacing: 4) {
              Text("Name")
                .foregroundStyle(.secondary)
                .marineFont(.caption)
              Text(viewModel.name.isEmpty ? (viewModel.session?.startTime.formatted(date: .complete, time: .shortened) ?? String(localized: "Unnamed Track")) : viewModel.name)
                .marineFont(.body)
            }
            .marineListCell()

            VStack(alignment: .leading, spacing: 4) {
              Text("Description")
                .foregroundStyle(.secondary)
                .marineFont(.caption)
              Text(viewModel.description.isEmpty ? "No description" : viewModel.description)
                .marineFont(.body)
                .foregroundStyle(viewModel.description.isEmpty ? .secondary : .primary)
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
            value: viewModel.session?.duration?.marineFormatted ?? "—"
          )
          .marineListCell()

          DetailRow(
            label: "Length",
            value: viewModel.session?.totalDistance.map {
              $0.converted(to: .nauticalMiles).formatted(
                .measurement(
                  width: .abbreviated,
                  usage: .asProvided,
                  numberFormatStyle: .number.precision(.fractionLength(2))
                )
              )
            } ?? "—"
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
            value: viewModel.session?.maxSpeed.map {
              $0.converted(to: .knots).formatted(
                .measurement(
                  width: .abbreviated,
                  usage: .asProvided,
                  numberFormatStyle: .number.precision(.fractionLength(1))
                )
              )
            } ?? "—"
          )
          .marineListCell()

          DetailRow(
            label: "Average Speed",
            value: viewModel.session?.averageSpeed.map {
              $0.converted(to: .knots).formatted(
                .measurement(
                  width: .abbreviated,
                  usage: .asProvided,
                  numberFormatStyle: .number.precision(.fractionLength(1))
                )
              )
            } ?? "—"
          )
          .marineListCell()
        }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .background(MarineTheme.Colors.panelBackground)
      .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)

      // Bottom Buttons Panel
      VStack(spacing: MarineTheme.Spacing.small) {
        Button(action: {
          // Action for View will be implemented later
        }) {
          Text("View")
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: marineTheme.minTouchTarget * scaleFactor)
            .background(MarineTheme.Colors.primary)
            .cornerRadius(MarineTheme.Metrics.cornerRadius)
        }
        .buttonStyle(MarineButtonStyle())

        Button(role: .destructive, action: {
          showDeleteConfirmation = true
        }) {
          Text("Delete")
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(viewModel.canDelete ? .red : .gray)
            .frame(maxWidth: .infinity, minHeight: marineTheme.minTouchTarget * scaleFactor)
            .background(viewModel.canDelete ? Color(uiColor: .systemRed).opacity(0.15) : Color.gray.opacity(0.15))
            .cornerRadius(MarineTheme.Metrics.cornerRadius)
        }
        .buttonStyle(MarineButtonStyle())
        .disabled(!viewModel.canDelete)
        .confirmationDialog(
          "Delete Track?",
          isPresented: $showDeleteConfirmation,
          titleVisibility: .visible
        ) {
          Button("Delete", role: .destructive) {
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
      .padding(MarineTheme.Spacing.medium)
      .background(MarineTheme.Colors.surfaceBackground)
      .border(Color.gray.opacity(0.2), width: 0.5)
    }
    .navigationTitle("Track Detail")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        if viewModel.isEditing {
          HStack {
            Button("Cancel") {
              viewModel.cancelEditing()
            }
            Button("Save") {
              Task {
                await viewModel.saveChanges()
              }
            }
            .fontWeight(.semibold)
            .disabled(viewModel.isSaving)
          }
        } else {
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
