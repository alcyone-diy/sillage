//
//  COGPreferencesView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import Foundation

struct COGPreferencesView: View {
  @Environment(\.marineTheme) private var marineTheme
  @Bindable private var preferences = PreferencesService.shared

  var body: some View {
    Form {
      Section {
        Toggle(isOn: $preferences.isCOGVectorEnabled) {
          Label("Enable COG Vector", systemImage: "location.north.line.fill")
            .marineFont(.body)
        }
        .marineListCell()

        if preferences.isCOGVectorEnabled {
          Picker("Time Horizon", selection: $preferences.cogVectorTimeHorizon) {
            Text("10 min").tag(Measurement(value: 600, unit: UnitDuration.seconds))
            Text("30 min").tag(Measurement(value: 1800, unit: UnitDuration.seconds))
            Text("1 hr").tag(Measurement(value: 3600, unit: UnitDuration.seconds))
            Text("3 hr").tag(Measurement(value: 10800, unit: UnitDuration.seconds))
            Text("6 hr").tag(Measurement(value: 21600, unit: UnitDuration.seconds))
          }
          .pickerStyle(.segmented)
          .marineListCell()

          Toggle(isOn: $preferences.isCOGVectorTicksEnabled) {
            Label("Show Time Ticks", systemImage: "ruler.fill")
              .marineFont(.body)
          }
          .marineListCell()
        }
      }
    }
    .navigationTitle("Predictor Vector")
    .navigationBarTitleDisplayMode(.inline)
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
  }
}

#Preview {
  COGPreferencesView()
    .environment(\.marineTheme, .standard)
}
