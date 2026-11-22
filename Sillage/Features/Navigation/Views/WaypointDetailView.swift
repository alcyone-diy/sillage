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
  @Environment(ChartViewModel.self) private var chartViewModel: ChartViewModel?
  
  @Bindable var viewModel: WaypointDetailViewModel
  var onGoToRequested: ((String) -> Void)?
  var onCancelNavigationRequested: (() -> Void)?
  var onModifyPositionRequested: (() -> Void)?
  
  @State private var showDeleteConfirmation = false
  
  var body: some View {
    VStack(spacing: 0) {
      Form {
        if viewModel.isEditable {
          Section {
            VStack(alignment: .leading, spacing: MarineTheme.Spacing.small) {
              Text("Name")
                .marineFont(.caption)
                .foregroundStyle(marineTheme.colors.textSecondary)
              TextField("Waypoint Name", text: $viewModel.name)
                .marineFont(.body)
            }
            .marineListCell()
            
            VStack(alignment: .leading, spacing: MarineTheme.Spacing.small) {
              Text("Description")
                .marineFont(.caption)
                .foregroundStyle(marineTheme.colors.textSecondary)
              MarineExpandingTextEditor(
                placeholder: "Waypoint Description (Optional)",
                text: $viewModel.description
              )
            }
            .marineListCell()
          }
        } else if let description = viewModel.trimmedDescription {
          Section {
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
        
        Section {
          ColorPicker("Color", selection: $viewModel.color, supportsOpacity: false)
            .marineFont(.body)
            .marineListCell()
            .disabled(!viewModel.isEditable)
            
          Toggle(
            "Show",
            isOn: Binding(
              get: { viewModel.isVisible },
              set: { viewModel.setVisible($0) }
            )
          )
            .marineFont(.body)
            .marineListCell()
            .tint(marineTheme.colors.primary)
        } header: {
          Text("Display").marineSectionHeader()
        }
        
        Section {
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
          
          if viewModel.isEditable {
            Button(action: {
              onModifyPositionRequested?()
            }) {
              HStack {
                Image(marineIcon: .crosshair)
                Text("Modify Position")
              }
            }
            .buttonStyle(MarineButtonStyle(.secondary))
            .marineListCell()
          }
        } header: {
          Text("Location").marineSectionHeader()
        } footer: {
          VStack(alignment: .leading, spacing: MarineTheme.Spacing.medium) {
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
        }
        .disabled(!viewModel.isEditable)

        if !viewModel.isEditable {
          Section {
            HStack(alignment: .center, spacing: MarineTheme.Spacing.small) {
              Text("Variation")
                .marineFont(.body)
                .foregroundColor(marineTheme.colors.textSecondary)

              Spacer(minLength: MarineTheme.Spacing.small)

              if let declination = viewModel.magneticDeclination {
                Text(verbatim: declination.marineDeclinationFormatted)
                  .monospacedDigit()
                  .marineFont(.body)
                  .foregroundColor(marineTheme.colors.textPrimary)
                  .lineLimit(1)
                  .minimumScaleFactor(MarineTheme.Metrics.compactTextScaleFactor)
                  .transaction { $0.animation = nil }
              } else if viewModel.isPointInfoLoading {
                Text(verbatim: "1.5° W")
                  .monospacedDigit()
                  .marineFont(.body)
                  .redacted(reason: .placeholder)
              } else {
                Text(verbatim: "---")
                  .monospacedDigit()
                  .marineFont(.body)
                  .foregroundColor(marineTheme.colors.textSecondary)
              }
            }
            .marineListCell()
          } header: {
            Text("MAGNETIC DECLINATION").marineSectionHeader()
          } footer: {
            if let footerText = viewModel.magneticDeclinationFooterText {
              Text(verbatim: footerText)
                .marineFont(.footnote)
                .foregroundStyle(.secondary)
            }
          }

          // Always render all 4 ephemeris rows (using "---" when unavailable) to keep layout and scanning predictable.
          Section {
            ForEach(SunEphemerisDisplayRow.rows(for: viewModel.sunEphemeris)) { row in
              ephemerisRow(row)
            }
          } header: {
            let referenceDate = viewModel.sunEphemeris?.referenceDate ?? viewModel.pointInfoDate ?? Date()
            let displayTimeZone = viewModel.sunEphemeris?.timeZone ?? .current
            let headerFormat = Date.FormatStyle(timeZone: displayTimeZone).weekday(.abbreviated).day().month(.abbreviated)
            let dateString = referenceDate.formatted(headerFormat).uppercased()
            Text("SOLAR EPHEMERIS - \(dateString)")
              .marineSectionHeader()
          } footer: {
            if let footerText = SunEphemerisDisplayRow.footerText(for: viewModel.sunEphemeris) {
              Text(verbatim: footerText)
                .marineFont(.footnote)
                .foregroundStyle(marineTheme.colors.textSecondary)
            }
          }
        }
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
    .navigationTitle(
      viewModel.editingWaypointID == nil
        ? String(localized: "New Waypoint")
        : (viewModel.isEditable
            ? String(localized: "Edit Waypoint")
            : (viewModel.name.isEmpty ? String(localized: "Unnamed Waypoint") : viewModel.name))
    )
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(viewModel.isEditable)
      .toolbar {
        if viewModel.isEditable {
          ToolbarItem(placement: .cancellationAction) {
            Button {
              if viewModel.editingWaypointID == nil {
                viewModel.cancelDraft()
                dismiss()
              } else {
                withAnimation {
                  viewModel.revert()
                }
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
                    withAnimation {
                      viewModel.isEditable = false
                    }
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
              withAnimation {
                viewModel.isEditable = true
              }
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
      .task(id: pointInfoTaskTrigger) {
        if !viewModel.isEditable {
          await viewModel.loadPointInformation()
        }
      }
      .onDisappear {
        guard chartViewModel?.waypointAdjustmentSession == nil else { return }
        viewModel.cancelDraft()
        if chartViewModel?.activeWaypointDetailViewModel === viewModel {
          chartViewModel?.activeWaypointDetailViewModel = nil
        }
      }
  }

  private struct PointInfoTaskTrigger: Equatable {
    let isEditable: Bool
    let latitude: Double?
    let longitude: Double?
  }

  private var pointInfoTaskTrigger: PointInfoTaskTrigger {
    let coordinate = viewModel.isEditable ? nil : viewModel.currentCoordinate
    return PointInfoTaskTrigger(
      isEditable: viewModel.isEditable,
      latitude: coordinate?.latitude,
      longitude: coordinate?.longitude
    )
  }

  @ViewBuilder
  private func ephemerisRow(_ row: SunEphemerisDisplayRow) -> some View {
    HStack(alignment: .center, spacing: MarineTheme.Spacing.small) {
      Image(systemName: row.icon)
        .marineFont(.body)
        .foregroundColor(marineTheme.colors.textSecondary)
        .frame(width: MarineTheme.Spacing.large)

      Text(row.title)
        .marineFont(.body)
        .foregroundColor(marineTheme.colors.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(MarineTheme.Metrics.compactTextScaleFactor)

      Spacer(minLength: MarineTheme.Spacing.small)

      ephemerisValueView(row.value)
    }
    .marineListCell()
  }

  @ViewBuilder
  private func ephemerisValueView(_ value: SunEphemerisRowValue) -> some View {
    switch value {
    case let .time(date, referenceDate, timeZone):
      Text(verbatim: date.marineEphemerisTimeFormatted(relativeTo: referenceDate, timeZone: timeZone))
        .monospacedDigit()
        .marineFont(.body)
        .foregroundColor(marineTheme.colors.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(MarineTheme.Metrics.compactTextScaleFactor)
        .transaction { $0.animation = nil }
    case .unavailable:
      Text(verbatim: "---")
        .marineFont(.body)
        .foregroundStyle(marineTheme.colors.textSecondary)
        .transaction { $0.animation = nil }
    case .missing:
      if viewModel.isPointInfoLoading {
        let tzAbbr = TimeZone.current.abbreviation() ?? "UTC"
        Text(verbatim: "06:00 \(tzAbbr)")
          .monospacedDigit()
          .marineFont(.body)
          .redacted(reason: .placeholder)
      } else {
        Text(verbatim: "---")
          .monospacedDigit()
          .marineFont(.body)
          .foregroundColor(marineTheme.colors.textSecondary)
      }
    }
  }
}
