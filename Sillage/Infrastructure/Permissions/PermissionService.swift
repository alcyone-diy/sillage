//
//  PermissionService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-06.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation
import UserNotifications
import CoreMotion
import Observation
import OSLog
import UIKit

public enum PermissionStatus: Sendable, Equatable {
    case unknown
    case notDetermined
    case authorized
    case denied
}

/// `PermissionService` acts as the single source of truth for all system permissions.
/// **IMPORTANT ARCHITECTURAL RULE:**
/// This service must NEVER be used to hide or block business logic that could otherwise function in a degraded mode.
/// For example, viewing offline charts does not strictly require GPS; the UI should adapt (e.g. hiding the user location puck)
/// rather than completely blocking access if location permissions are denied.
/// Use this service strictly to drive explicit permission workflows (like `PermissionGateView`) and informative UI components.
@Observable
@MainActor
final class PermissionService: PermissionServiceProtocol {
    
    public private(set) var locationStatus: PermissionStatus = .unknown
    public private(set) var notificationStatus: PermissionStatus = .unknown
    public private(set) var criticalAlertStatus: NotificationAlertCapabilityStatus = .unknown
    public private(set) var timeSensitiveStatus: NotificationAlertCapabilityStatus = .unknown
    public private(set) var motionStatus: PermissionStatus = .unknown
    
    private let positioningService: PositioningService
    private let notificationService: NotificationService
    private let authorizationProvider: any NotificationAuthorizationProviding
    
    private var isRequestingLocation = false
    private var isRequestingNotification = false
    private var hasAttemptedCriticalAlertRequest = false
    #if DEBUG
    private var isForcedAuthorizedForScreenshots = false
    #endif
    
    @ObservationIgnored
    nonisolated(unsafe) private var locationObservationTask: Task<Void, Never>?
    @ObservationIgnored
    nonisolated(unsafe) private var lifecycleObservationTask: Task<Void, Never>?
    
    init(
      positioningService: PositioningService,
      notificationService: NotificationService,
      authorizationProvider: any NotificationAuthorizationProviding = SystemNotificationAuthorizationProvider()
    ) {
        self.positioningService = positioningService
        self.notificationService = notificationService
        self.authorizationProvider = authorizationProvider
        
        // Sync initialization for statuses that don't require async
        refreshMotionStatus()
        
        let locAuth = positioningService.currentAuthorizationStatus
        switch locAuth {
        case .notDetermined: self.locationStatus = .notDetermined
        case .restricted, .denied: self.locationStatus = .denied
        case .authorizedAlways, .authorizedWhenInUse: self.locationStatus = .authorized
        @unknown default: self.locationStatus = .unknown
        }
        
        Task { [weak self] in
            await self?.checkInitialStatuses()
        }
        
        observeLocationStatus()
        observeAppLifecycle()
    }
    
    deinit {
        locationObservationTask?.cancel()
        lifecycleObservationTask?.cancel()
    }
    
    private func observeAppLifecycle() {
        lifecycleObservationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.willEnterForegroundNotification) {
                await self?.checkInitialStatuses()
            }
        }
    }
    
    private func checkInitialStatuses() async {
        refreshMotionStatus()
        await refreshNotificationStatuses()
    }

    private func refreshMotionStatus() {
        #if DEBUG
        if isForcedAuthorizedForScreenshots { return }
        #endif
        let motionAuth = CMMotionActivityManager.authorizationStatus()
        switch motionAuth {
        case .notDetermined: self.motionStatus = .notDetermined
        case .restricted, .denied: self.motionStatus = .denied
        case .authorized: self.motionStatus = .authorized
        @unknown default: self.motionStatus = .unknown
        }
    }

    private func refreshNotificationStatuses() async {
        #if DEBUG
        if isForcedAuthorizedForScreenshots { return }
        #endif
        let settings = await authorizationProvider.notificationSettings()
        #if DEBUG
        if isForcedAuthorizedForScreenshots { return }
        #endif
        applyNotificationSettings(settings)
    }

    private func applyNotificationSettings(_ settings: NotificationSettingsSnapshot) {
        self.notificationStatus = mapAuthorizationStatus(settings.authorizationStatus)
        self.criticalAlertStatus = mapNotificationSetting(settings.criticalAlertSetting)
        self.timeSensitiveStatus = mapNotificationSetting(settings.timeSensitiveSetting)
    }

    private func mapAuthorizationStatus(_ status: UNAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return .authorized
        @unknown default:
            return .unknown
        }
    }

    private func mapNotificationSetting(_ setting: UNNotificationSetting) -> NotificationAlertCapabilityStatus {
        switch setting {
        case .notSupported:
            return .notSupported
        case .disabled:
            return .disabled
        case .enabled:
            return .enabled
        @unknown default:
            return .unknown
        }
    }

    private func isNotificationAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }
    
    private func observeLocationStatus() {
        locationObservationTask = Task { [weak self] in
            guard let stream = self?.positioningService.authorizationStatusStream else { return }
            for await status in stream {
                guard !Task.isCancelled, let self = self else { break }
                self.updateLocationStatus(from: status)
            }
        }
    }
    
    private func updateLocationStatus(from status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self.locationStatus = .notDetermined
        case .restricted, .denied:
            self.locationStatus = .denied
        case .authorizedAlways, .authorizedWhenInUse:
            self.locationStatus = .authorized
        @unknown default:
            self.locationStatus = .unknown
        }
    }
    
    public func requestLocationAuthorization() async {
        guard !isRequestingLocation else { return }
        guard locationStatus == .notDetermined else {
            if locationStatus == .denied {
                openSystemSettings()
            }
            return
        }
        
        isRequestingLocation = true
        defer { isRequestingLocation = false }
        
        positioningService.requestAuthorization()
    }
    
    public func requestNotificationAuthorization() async -> Bool {
        guard !isRequestingNotification else { return false }

        if notificationStatus == .authorized {
            return true
        }

        if notificationStatus == .denied {
            openSystemSettings()
            return false
        }

        isRequestingNotification = true
        defer { isRequestingNotification = false }

        do {
            let granted = try await authorizationProvider.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                Logger.system.info("User granted local notification permissions.")
            } else {
                Logger.system.warning("User denied local notification permissions.")
            }
            await refreshNotificationStatuses()
            return granted
        } catch {
            Logger.system.error("Failed to request notification auth: \(error.localizedDescription, privacy: .public)")
            self.notificationStatus = .denied
            return false
        }
    }

    public func requestCriticalNotificationAuthorization() async -> Bool {
        guard !isRequestingNotification else { return false }

        let currentSettings = await authorizationProvider.notificationSettings()
        applyNotificationSettings(currentSettings)

        if currentSettings.authorizationStatus == .denied {
            openSystemSettings()
            return false
        }

        if isNotificationAuthorized(currentSettings.authorizationStatus) {
            if currentSettings.criticalAlertSetting == .enabled {
                return true
            }
            // Avoid repeating failing criticalAlert XPC requests on every arm when the entitlement is unsupported or already attempted this session.
            if currentSettings.criticalAlertSetting == .notSupported || hasAttemptedCriticalAlertRequest {
                return true
            }
        }
        // Note: When `.notDetermined`, iOS reports `criticalAlertSetting == .notSupported` even if the entitlement IS provisioned.
        // We therefore still attempt `.criticalAlert` once on first prompt (falling back cleanly if unentitled) so Critical Alerts work automatically once Apple grants the entitlement.

        isRequestingNotification = true
        defer { isRequestingNotification = false }
        hasAttemptedCriticalAlertRequest = true

        do {
            let granted = try await authorizationProvider.requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert])
            if granted {
                Logger.system.info("User granted critical notification permissions.")
            } else {
                Logger.system.warning("User denied critical notification permissions.")
            }
            await refreshNotificationStatuses()
            return granted
        } catch {
            Logger.system.warning("Failed critical notification auth request (likely missing entitlement): \(error.localizedDescription, privacy: .public). Falling back to standard notifications.")
            if isNotificationAuthorized(currentSettings.authorizationStatus) {
                await refreshNotificationStatuses()
                return true
            }
            do {
                let granted = try await authorizationProvider.requestAuthorization(options: [.alert, .sound, .badge])
                await refreshNotificationStatuses()
                return granted
            } catch {
                Logger.system.error("Failed standard notification auth fallback: \(error.localizedDescription, privacy: .public)")
                self.notificationStatus = .denied
                return false
            }
        }
    }
    
    @ObservationIgnored
    private var motionActivityManager: CMMotionActivityManager?
    
    public func requestMotionAuthorization() async {
        guard motionStatus == .notDetermined else {
            if motionStatus == .denied {
                openSystemSettings()
            }
            return
        }
        
        let manager = CMMotionActivityManager()
        self.motionActivityManager = manager
        
        let now = Date()
        manager.queryActivityStarting(from: now, to: now, to: .main) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let authStatus = CMMotionActivityManager.authorizationStatus()
                switch authStatus {
                case .notDetermined:
                    self.motionStatus = .notDetermined
                case .restricted, .denied:
                    self.motionStatus = .denied
                case .authorized:
                    self.motionStatus = .authorized
                @unknown default:
                    self.motionStatus = .unknown
                }
                self.motionActivityManager = nil
            }
        }
    }
    
    public func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    #if DEBUG
    func forceAuthorizedForSimulatedSensors(gps: Bool, baro: Bool) {
        guard gps || baro else { return }
        isForcedAuthorizedForScreenshots = true
        lifecycleObservationTask?.cancel()
        self.notificationStatus = .authorized
        self.criticalAlertStatus = .enabled
        self.timeSensitiveStatus = .enabled
        if gps {
            locationObservationTask?.cancel()
            self.locationStatus = .authorized
        }
        if baro {
            self.motionStatus = .authorized
        }
    }
    #endif
}
