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
enum SunEphemerisRowValue: Equatable {
  case time(Date, referenceDate: Date, timeZone: TimeZone)
  case unavailable
  case missing
}

/// Shared presentation model for solar ephemeris rows across `MapCalloutView` and `WaypointDetailView`.
struct SunEphemerisDisplayRow: Identifiable {
  let id: String
  let title: LocalizedStringKey
  let icon: String
  let value: SunEphemerisRowValue

  /// Builds the fixed 4-row solar ephemeris list, showing `.unavailable` when an event does not occur on that day.
  /// Always keep all 4 rows in chronological order for UX stability and predictable scannability.
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

    let dawnValue: SunEphemerisRowValue
    let duskValue: SunEphemerisRowValue
    switch ephemeris.nauticalTwilight {
    case let .cycle(dawn, dusk):
      dawnValue = .time(dawn, referenceDate: ref, timeZone: tz)
      duskValue = .time(dusk, referenceDate: ref, timeZone: tz)
    case .continuousTwilight, .continuousDark:
      dawnValue = .unavailable
      duskValue = .unavailable
    }

    let sunriseValue: SunEphemerisRowValue
    let sunsetValue: SunEphemerisRowValue
    switch ephemeris.daylight {
    case let .cycle(sunrise, sunset):
      sunriseValue = .time(sunrise, referenceDate: ref, timeZone: tz)
      sunsetValue = .time(sunset, referenceDate: ref, timeZone: tz)
    case .polarDay, .polarNight:
      sunriseValue = .unavailable
      sunsetValue = .unavailable
    }

    return [
      SunEphemerisDisplayRow(id: "dawn", title: "Nautical Dawn", icon: "sun.horizon", value: dawnValue),
      SunEphemerisDisplayRow(id: "sunrise", title: "Sunrise", icon: "sunrise", value: sunriseValue),
      SunEphemerisDisplayRow(id: "sunset", title: "Sunset", icon: "sunset", value: sunsetValue),
      SunEphemerisDisplayRow(id: "dusk", title: "Nautical Dusk", icon: "moon.stars", value: duskValue)
    ]
  }

  /// Returns an explanatory footer for polar daylight or continuous twilight conditions, or `nil` for a standard cycle.
  static func footerText(for ephemeris: SunEphemeris?) -> String? {
    guard let ephemeris else {
      return nil
    }

    switch (ephemeris.daylight, ephemeris.nauticalTwilight) {
    case (.cycle, .cycle):
      return nil
    case (.cycle, .continuousTwilight):
      return String(localized: "No Nautical Night")
    case (.cycle, .continuousDark):
      return String(localized: "Continuous Dark")
    case (.polarDay, .cycle), (.polarDay, .continuousTwilight):
      return String(localized: "Polar Day")
    case (.polarDay, .continuousDark):
      return "\(String(localized: "Polar Day")) • \(String(localized: "Continuous Dark"))"
    case (.polarNight, .cycle):
      return String(localized: "Polar Night")
    case (.polarNight, .continuousTwilight):
      return "\(String(localized: "Polar Night")) • \(String(localized: "No Nautical Night"))"
    case (.polarNight, .continuousDark):
      return "\(String(localized: "Polar Night")) • \(String(localized: "Continuous Dark"))"
    }
  }
}
