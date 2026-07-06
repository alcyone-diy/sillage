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
    public let service: BarometricService
    private var preferencesService: PreferencesService
    
    // MARK: - Settings Bindings
    public var isAlarmEnabled: Bool {
        get { preferencesService.isBaroAlarmEnabled }
        set { preferencesService.isBaroAlarmEnabled = newValue }
    }
    
    public var sensitivity: BaroAlarmSensitivity {
        get { preferencesService.baroAlarmSensitivity }
        set { preferencesService.baroAlarmSensitivity = newValue }
    }
    
    public var offsetValueForStepper: Double {
        get { preferencesService.barometerOffset.converted(to: .hectopascals).value }
        set { preferencesService.barometerOffset = Measurement(value: newValue, unit: .hectopascals) }
    }
    
    /// Provides raw uncalibrated pressure for UI display
    public var rawPressureFormatted: String? {
        guard let current = service.currentPressure else { return nil }
        // Subtract current offset via Measurement API to preserve type safety and precision
        let offsetMeasurement = preferencesService.barometerOffset
        let rawMeasurement = current - offsetMeasurement
        return pressureFormatter.string(from: rawMeasurement)
    }
    
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
    init(service: BarometricService, preferencesService: PreferencesService) {
        self.service = service
        self.preferencesService = preferencesService
    }
    
    // MARK: - History State
    
    /// Holds the 24-hour barometric history for chart rendering.
    public var history24h: [BarometricReading] = []
    
    /// Wrapper for graph data to properly break the line across missing data gaps.
    public struct ChartDataPoint: Identifiable, Sendable {
        public let id = UUID()
        public let reading: BarometricReading
        public let segmentId: Int
    }
    
    public var chartData: [ChartDataPoint] = []
    
    /// Asynchronously refreshes the 24-hour history from the service.
    public func refreshHistory() async {
        let readings = await service.getHistoryReadings(lastHours: 24)
        
        var newChartData: [ChartDataPoint] = []
        var currentSegment = 0
        var lastTimestamp: Date?
        
        // Segregate data into disconnected lines if gaps > 5 minutes are found
        for reading in readings.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let last = lastTimestamp {
                if reading.timestamp.timeIntervalSince(last) > 300 {
                    currentSegment += 1
                }
            }
            newChartData.append(ChartDataPoint(reading: reading, segmentId: currentSegment))
            lastTimestamp = reading.timestamp
        }
        
        self.history24h = readings
        self.chartData = newChartData
    }
    
    // MARK: - Lifecycle Actions
    
    /// Starts barometric updates if not already running.
    public func startUpdates() {
        service.startUpdates()
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
        return service.activeAlarm
    }
}
