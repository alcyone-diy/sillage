//
//  BarometerViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation

@Observable
@MainActor
public final class BarometerViewModel {
    
    // MARK: - Dependencies
    private let service: BarometricService
    
    // MARK: - Private Formatters
    
    private let pressureFormatter: MeasurementFormatter = {
        let fmt = MeasurementFormatter()
        fmt.unitOptions = .providedUnit 
        fmt.numberFormatter.minimumFractionDigits = 1
        fmt.numberFormatter.maximumFractionDigits = 1
        fmt.numberFormatter.usesGroupingSeparator = false 
        return fmt
    }()
    
    private let trendFormatter: MeasurementFormatter = {
        let fmt = MeasurementFormatter()
        fmt.unitOptions = .providedUnit 
        fmt.numberFormatter.minimumFractionDigits = 1
        fmt.numberFormatter.maximumFractionDigits = 1
        fmt.numberFormatter.usesGroupingSeparator = false 
        // Delegate sign rendering to Foundation to ensure proper localization support
        fmt.numberFormatter.positivePrefix = "+"
        return fmt
    }()
    
    // MARK: - Initialization
    public init(service: BarometricService) {
        self.service = service
    }
    
    // MARK: - Presentation State (Computed)
    
    /// Formatted current pressure, strictly nil if data is unavailable.
    public var formattedPressure: String? {
        guard let pressure = service.currentPressure else { return nil }
        return pressureFormatter.string(from: pressure)
    }
    
    /// Formatted trend over 3 hours, strictly nil if buffer is insufficient.
    public var formattedTrend: String? {
        guard let trend = service.trend3Hours else { return nil }
        let trendString = trendFormatter.string(from: trend)
        return String(localized: "\(trendString)/3h", comment: "Format for 3-hour barometric trend suffix")
    }
    
    public var sensorState: SensorHealth {
        return service.sensorState
    }
    
    /// Evaluates the 3-hour trend to return a mutually exclusive weather alarm level.
    /// Strictly returns nil if the trend buffer is insufficient to evaluate the weather state.
    public var alarmLevel: WeatherAlarmLevel? {
        guard let trend = service.trend3Hours else { return nil }
        
        // Evaluate in descending order of severity
        if trend <= .stormThreshold {
            return .storm
        } else if trend <= .galeThreshold {
            return .gale
        } else if trend <= .vigilanceThreshold {
            return .vigilance
        } else {
            return .none
        }
    }
}
