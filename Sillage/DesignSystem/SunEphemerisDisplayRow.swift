//
//  SunEphemerisDisplayRow.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-22.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Presentation value for a single solar ephemeris row.
enum SunEphemerisRowValue {
  case time(Date, referenceDate: Date, timeZone: TimeZone)
  case status(LocalizedStringKey)
  case missing
}

/// Shared presentation model for solar ephemeris rows across `MapCalloutView` and `WaypointDetailView`.
struct SunEphemerisDisplayRow: Identifiable {
  let id: String
  let title: LocalizedStringKey
  let icon: String
  let value: SunEphemerisRowValue

  /// Builds the ordered list of display rows for `ephemeris`, fusing continuous polar/twilight bands into single status rows.
  static func rows(for ephemeris: SunEphemeris?) -> [SunEphemerisDisplayRow] {
    guard let ephemeris else {
      return [
        SunEphemerisDisplayRow(id: "dawn", title: "Nautical Dawn", icon: "sun.horizon", value: .missing),
        SunEphemerisDisplayRow(id: "sunrise", title: "Sunrise", icon: "sunrise", value: .missing),
        SunEphemerisDisplayRow(id: "sunset", title: "Sunset", icon: "sunset", value: .missing),
        SunEphemerisDisplayRow(id: "dusk", title: "Nautical Dusk", icon: "moon.stars", value: .missing)
      ]
    }

    let ref = ephemeris.referenceDate
    let tz = ephemeris.timeZone

    switch (ephemeris.daylight, ephemeris.nauticalTwilight) {
    case let (.cycle(sunrise, sunset), .cycle(dawn, dusk)):
      return [
        SunEphemerisDisplayRow(id: "dawn", title: "Nautical Dawn", icon: "sun.horizon", value: .time(dawn, referenceDate: ref, timeZone: tz)),
        SunEphemerisDisplayRow(id: "sunrise", title: "Sunrise", icon: "sunrise", value: .time(sunrise, referenceDate: ref, timeZone: tz)),
        SunEphemerisDisplayRow(id: "sunset", title: "Sunset", icon: "sunset", value: .time(sunset, referenceDate: ref, timeZone: tz)),
        SunEphemerisDisplayRow(id: "dusk", title: "Nautical Dusk", icon: "moon.stars", value: .time(dusk, referenceDate: ref, timeZone: tz))
      ]
    case let (.cycle(sunrise, sunset), .continuousTwilight):
      return [
        SunEphemerisDisplayRow(id: "sunrise", title: "Sunrise", icon: "sunrise", value: .time(sunrise, referenceDate: ref, timeZone: tz)),
        SunEphemerisDisplayRow(id: "sunset", title: "Sunset", icon: "sunset", value: .time(sunset, referenceDate: ref, timeZone: tz)),
        SunEphemerisDisplayRow(id: "twilight", title: "Nautical Twilight", icon: "sun.horizon", value: .status("No Nautical Night"))
      ]
    case let (.cycle(sunrise, sunset), .continuousDark):
      return [
        SunEphemerisDisplayRow(id: "sunrise", title: "Sunrise", icon: "sunrise", value: .time(sunrise, referenceDate: ref, timeZone: tz)),
        SunEphemerisDisplayRow(id: "sunset", title: "Sunset", icon: "sunset", value: .time(sunset, referenceDate: ref, timeZone: tz)),
        SunEphemerisDisplayRow(id: "twilight", title: "Nautical Twilight", icon: "moon.stars", value: .status("Continuous Dark"))
      ]
    case let (.polarDay, .cycle(dawn, dusk)):
      return [
        SunEphemerisDisplayRow(id: "dawn", title: "Nautical Dawn", icon: "sun.horizon", value: .time(dawn, referenceDate: ref, timeZone: tz)),
        SunEphemerisDisplayRow(id: "dusk", title: "Nautical Dusk", icon: "moon.stars", value: .time(dusk, referenceDate: ref, timeZone: tz)),
        SunEphemerisDisplayRow(id: "daylight", title: "Daylight", icon: "sun.max", value: .status("Polar Day"))
      ]
    case let (.polarNight, .cycle(dawn, dusk)):
      return [
        SunEphemerisDisplayRow(id: "dawn", title: "Nautical Dawn", icon: "sun.horizon", value: .time(dawn, referenceDate: ref, timeZone: tz)),
        SunEphemerisDisplayRow(id: "dusk", title: "Nautical Dusk", icon: "moon.stars", value: .time(dusk, referenceDate: ref, timeZone: tz)),
        SunEphemerisDisplayRow(id: "daylight", title: "Daylight", icon: "moon", value: .status("Polar Night"))
      ]
    case (.polarDay, .continuousTwilight):
      return [
        SunEphemerisDisplayRow(id: "daylight", title: "Daylight", icon: "sun.max", value: .status("Polar Day")),
        SunEphemerisDisplayRow(id: "twilight", title: "Nautical Twilight", icon: "sun.horizon", value: .status("No Nautical Night"))
      ]
    case (.polarDay, .continuousDark):
      return [
        SunEphemerisDisplayRow(id: "daylight", title: "Daylight", icon: "sun.max", value: .status("Polar Day")),
        SunEphemerisDisplayRow(id: "twilight", title: "Nautical Twilight", icon: "moon.stars", value: .status("Continuous Dark"))
      ]
    case (.polarNight, .continuousTwilight):
      return [
        SunEphemerisDisplayRow(id: "daylight", title: "Daylight", icon: "moon", value: .status("Polar Night")),
        SunEphemerisDisplayRow(id: "twilight", title: "Nautical Twilight", icon: "sun.horizon", value: .status("No Nautical Night"))
      ]
    case (.polarNight, .continuousDark):
      return [
        SunEphemerisDisplayRow(id: "daylight", title: "Daylight", icon: "moon", value: .status("Polar Night")),
        SunEphemerisDisplayRow(id: "twilight", title: "Nautical Twilight", icon: "moon.stars", value: .status("Continuous Dark"))
      ]
    }
  }
}
