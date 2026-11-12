//
//  ModelsInfoView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-12.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct ModelsInfoView: View {
  @Environment(\.marineTheme) private var marineTheme

  var body: some View {
    Form {
      // MARK: - Geomagnetism
      Section {
        infoRow(title: "Model", value: "NOAA / NCEI WMM-2025")
        infoRow(title: "Validity Period", value: "2025.0 – 2030.0")
        infoRow(title: "Harmonic Degree", value: "n = 12 (Spherical)")
        infoRow(title: "Reference Altitude", value: "Sea Level (0 m WGS-84)")
      } header: {
        Text("Geomagnetism").marineSectionHeader()
      } footer: {
        Text("Magnetic declination is computed offline at sea level without relying on the device's hardware magnetometer (avoiding onboard magnetic interference) and does not account for local crustal magnetic anomalies.")
          .marineFont(.footnote)
      }

      // MARK: - Solar Ephemeris
      Section {
        infoRow(title: "Algorithm", value: "USNO Almanac (Solar MIT)")
        infoRow(title: "Sunrise / Sunset", value: "Zenith 90.83° (90° 50')")
        infoRow(title: "Nautical Twilight", value: "Zenith 102° (-12°)")
        infoRow(title: "Display Time Zone", value: "Device System Time Zone")
      } header: {
        Text("Solar Ephemeris").marineSectionHeader()
      } footer: {
        Text("Computed from the U.S. Naval Observatory Almanac for Computers algorithm anchored to the UTC calendar day and formatted in the device's time zone. Assumes an unobstructed sea-level horizon with standard refraction, without observer elevation or terrain relief corrections.")
          .marineFont(.footnote)
      }

      // MARK: - Geodesy & Kinematics
      Section {
        infoRow(title: "Geodetic Datum", value: "WGS-84")
        infoRow(title: "Bearings & COG", value: "True North (°T)")
        infoRow(title: "Navigation & Anchor", value: "Haversine Sphere (R = 6,371 km)")
        infoRow(title: "Track Log Distance", value: "WGS-84 Ellipsoid")
        infoRow(title: "COG Predictor Vector", value: "Rhumb Line (Loxodromic)")
        infoRow(title: "COG Damping", value: "4 s Vector Avg. (Cut-off 0.5 kt)")
      } header: {
        Text("Geodesy & Calculations").marineSectionHeader()
      } footer: {
        Text("Waypoint bearings, cross-track error (XTE), ruler measurements, and anchor swing distances use spherical Great Circle trigonometry (R = 6,371 km). Recorded track distances use the WGS-84 ellipsoid, while the COG predictor vector projects along a Mercator rhumb line.")
          .marineFont(.footnote)
      }

      // MARK: - Barometry
      Section {
        infoRow(title: "Sensor Smoothing", value: "2-min Moving Avg. (800–1100 hPa)")
        infoRow(title: "Displayed Trend", value: "Linear Regression (≥ 80% Window)")
        infoRow(title: "Alarm Evaluation", value: "Peak-to-Current Max Drop")
        infoRow(title: "Squall Imminent (High)", value: "Drop ≥ 2.0 hPa / 1h")
        infoRow(title: "Vigilance (High)", value: "Drop ≥ 1.5 hPa / 3h")
        infoRow(title: "Gale Warning (Medium)", value: "Drop ≥ 3.0 hPa / 3h")
        infoRow(title: "Storm Warning (Low)", value: "Drop ≥ 5.0 hPa / 3h")
      } header: {
        Text("Barometry").marineSectionHeader()
      } footer: {
        Text("Hardware barometer readings are smoothed over a 2-minute window to filter wave motion. Displayed trends use least-squares linear regression, whereas safety alarms compare current pressure against the highest peak in the 1h or 3h window according to the selected sensitivity.")
          .marineFont(.footnote)
      }
    }
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .marineListBackground()
    .navigationTitle("Models & Data Sources")
    .navigationBarTitleDisplayMode(.inline)
  }

  @ViewBuilder
  private func infoRow(title: LocalizedStringKey, value: LocalizedStringKey) -> some View {
    HStack {
      Text(title)
        .marineFont(.body)
      Spacer(minLength: MarineTheme.Spacing.small)
      Text(value)
        .marineFont(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.trailing)
    }
    .marineListCell()
  }
}

#Preview {
  NavigationStack {
    ModelsInfoView()
      .environment(\.marineTheme, .standard)
  }
}
