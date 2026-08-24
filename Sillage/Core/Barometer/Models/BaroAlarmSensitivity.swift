//
//  BaroAlarmSensitivity.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

//
//  BaroAlarmSensitivity.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-03.
//  Copyright © 2026 Alcyone.
//

import Foundation

/// Defines the sensitivity level for weather alarms based on barometric pressure drops.
public enum BaroAlarmSensitivity: String, CaseIterable, Identifiable {
    /// Low sensitivity (Storms Only): Drop >= 5.0 hPa/3h.
    case low
    /// Medium sensitivity (Gales): Drop >= 3.0 hPa/3h.
    case medium
    /// High sensitivity (Fronts & Grains): Drop >= 1.5 hPa/3h OR >= 2.0 hPa/1h.
    case high
    
    public var id: String { rawValue }
    
    public var localizedName: String {
        switch self {
        case .low: return String(localized: "Low", comment: "Low sensitivity")
        case .medium: return String(localized: "Medium", comment: "Medium sensitivity")
        case .high: return String(localized: "High", comment: "High sensitivity")
        }
    }
    
    public var explanation: String {
        switch self {
        case .low: return String(localized: "Triggers on drops ≥ 5.0 hPa within 3h. Recommended offshore to avoid alarm fatigue.", comment: "Low sensitivity explanation")
        case .medium: return String(localized: "Triggers on drops ≥ 3.0 hPa within 3h. Standard setting for gale warnings.", comment: "Medium sensitivity explanation")
        case .high: return String(localized: "Triggers on drops ≥ 1.5 hPa within 3h or ≥ 2.0 hPa within 1h. Ideal for squall detection.", comment: "High sensitivity explanation")
        }
    }
}
