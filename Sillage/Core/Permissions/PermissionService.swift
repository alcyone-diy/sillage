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
public final class PermissionService: PermissionServiceProtocol {
    
    public private(set) var locationStatus: PermissionStatus = .unknown
    public private(set) var notificationStatus: PermissionStatus = .unknown
    public private(set) var motionStatus: PermissionStatus = .unknown
    
    private let positioningService: PositioningService
    private let notificationService: NotificationService
    
    private let locationManager = CLLocationManager()
    
    private var isRequestingLocation = false
    private var isRequestingNotification = false
    
    @ObservationIgnored
    nonisolated(unsafe) private var locationObservationTask: Task<Void, Never>?
    @ObservationIgnored
    nonisolated(unsafe) private var lifecycleObservationTask: Task<Void, Never>?
    
    init(positioningService: PositioningService, notificationService: NotificationService) {
        self.positioningService = positioningService
        self.notificationService = notificationService
        
        checkInitialStatuses()
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
                self?.checkInitialStatuses()
            }
        }
    }
    
    private func checkInitialStatuses() {
        // Location
        let status = locationManager.authorizationStatus
        self.updateLocationStatus(from: status)
        
        // Notifications
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            
            switch settings.authorizationStatus {
            case .notDetermined:
                self.notificationStatus = .notDetermined
            case .denied:
                self.notificationStatus = .denied
            case .authorized, .provisional, .ephemeral:
                self.notificationStatus = .authorized
            @unknown default:
                self.notificationStatus = .unknown
            }
        }
        
        // Motion
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
    }
    
    private func observeLocationStatus() {
        locationObservationTask = Task { [weak self] in
            guard let self = self else { return }
            for await status in self.positioningService.authorizationStatusStream {
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
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                Logger.system.info("User granted local notification permissions.")
            } else {
                Logger.system.warning("User denied local notification permissions.")
            }
            self.notificationStatus = granted ? .authorized : .denied
            return granted
        } catch {
            Logger.system.error("Failed to request notification auth: \(error.localizedDescription, privacy: .public)")
            self.notificationStatus = .denied
            return false
        }
    }
    
    public func requestCriticalNotificationAuthorization() async -> Bool {
        guard !isRequestingNotification else { return false }
        
        if notificationStatus == .authorized {
            // Even if authorized for standard, we might need to request critical.
            // But we'll just attempt it.
        }
        
        if notificationStatus == .denied {
            openSystemSettings()
            return false
        }
        
        isRequestingNotification = true
        defer { isRequestingNotification = false }
        
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert])
            if granted {
                Logger.system.info("User granted critical notification permissions.")
            } else {
                Logger.system.warning("User denied critical notification permissions.")
            }
            self.notificationStatus = granted ? .authorized : .denied
            return granted
        } catch {
            Logger.system.error("Failed to request critical notification auth: \(error.localizedDescription, privacy: .public)")
            self.notificationStatus = .denied
            return false
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
}
