//
//  PermissionGateView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-06.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

enum PermissionIcon {
    case system(String)
    case marine(MarineIcon)
}

enum LocationPermissionTrigger: Hashable {
    case mapTracking
    case trackRecording
    case anchorAlarm
}

enum NotificationPermissionTrigger: Hashable {
    case anchorAlarm
    case baroAlarm
}

enum PermissionGateType: Identifiable, Hashable {
    case location(trigger: LocationPermissionTrigger)
    case motion
    case notification(trigger: NotificationPermissionTrigger)
    
    var id: String {
        switch self {
        case .location(let trigger): return "location-\(trigger)"
        case .motion: return "motion"
        case .notification(let trigger): return "notification-\(trigger)"
        }
    }
    
    var icon: PermissionIcon {
        switch self {
        case .location(let trigger):
            switch trigger {
            case .mapTracking: return .system("location.fill")
            case .trackRecording: return .marine(.track)
            case .anchorAlarm: return .marine(.anchorAlarm)
            }
        case .motion:
            return .marine(.instruments)
        case .notification(.anchorAlarm), .notification(.baroAlarm):
            return .system("bell.fill")
        }
    }
    
    var title: LocalizedStringResource {
        switch self {
        case .location(let trigger):
            switch trigger {
            case .mapTracking: return "Show your Vessel"
            case .trackRecording: return "Record Track"
            case .anchorAlarm: return "Anchor Watch GPS"
            }
        case .motion:
            return "Barometer Access"
        case .notification(.anchorAlarm):
            return "Anchor Alerts"
        case .notification(.baroAlarm):
            return "Weather Alerts"
        }
    }
    
    var description: LocalizedStringResource {
        switch self {
        case .location(let trigger):
            switch trigger {
            case .mapTracking:
                return "\(AppConstants.appName) requires access to your GPS to display your vessel's position on the chart."
            case .trackRecording:
                return "\(AppConstants.appName) needs location access to accurately log your voyage and compute statistics."
            case .anchorAlarm:
                return "To alert you if your vessel drags anchor, \(AppConstants.appName) needs continuous background GPS access."
            }
        case .motion:
            return "\(AppConstants.appName) needs 'Motion & Fitness' access to read your device's internal altimeter, enabling the weather alarm feature."
        case .notification(.anchorAlarm):
            return "\(AppConstants.appName) requires permission to send notifications to alert you if your vessel drags its anchor."
        case .notification(.baroAlarm):
            return "\(AppConstants.appName) requires permission to send notifications to warn you of severe weather changes."
        }
    }
    
    var buttonTitle: LocalizedStringResource {
        switch self {
        case .location: return "Allow Location"
        case .motion: return "Allow Access"
        case .notification: return "Allow Notifications"
        }
    }
    
    var deniedMessage: LocalizedStringResource {
        switch self {
        case .location(let trigger):
            switch trigger {
            case .mapTracking: return "\(AppConstants.appName) requires location access to show you on the map."
            case .trackRecording: return "\(AppConstants.appName) requires location access to record your track."
            case .anchorAlarm: return "\(AppConstants.appName) requires location access to monitor your anchor."
            }
        case .motion: return "\(AppConstants.appName) requires motion and fitness access to read the barometer."
        case .notification(.anchorAlarm): return "\(AppConstants.appName) requires notification access to warn you of a dragging anchor."
        case .notification(.baroAlarm): return "\(AppConstants.appName) requires notification access to warn you of severe weather changes."
        }
    }
    
    func currentStatus(in service: PermissionService) -> PermissionStatus {
        switch self {
        case .location: return service.locationStatus
        case .motion: return service.motionStatus
        case .notification: return service.notificationStatus
        }
    }
    
    func requestAuthorization(in service: PermissionService) async {
        switch self {
        case .location: await service.requestLocationAuthorization()
        case .motion: await service.requestMotionAuthorization()
        case .notification: _ = await service.requestCriticalNotificationAuthorization()
        }
    }
}

struct PermissionGateView: View {
    @Environment(PermissionService.self) private var permissionService
    @Environment(\.dismiss) private var dismiss
    
    let type: PermissionGateType
    
    init(type: PermissionGateType) {
        self.type = type
    }
    
    var body: some View {
        let status = type.currentStatus(in: permissionService)
        
        Group {
            if status == .unknown {
                Color.clear
                    .ignoresSafeArea()
            } else if status == .notDetermined {
                PrePermissionView(type: type) {
                    Task {
                        await type.requestAuthorization(in: permissionService)
                    }
                }
            } else if status == .denied {
                VStack {
                    Spacer()
                    PermissionDeniedView(message: type.deniedMessage)
                    Spacer()
                }
                .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            } else {
                Color.clear
                    .onAppear {
                        dismiss()
                    }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: status)
    }
}

struct PrePermissionView: View {
    @Environment(\.marineTheme) private var marineTheme

    let type: PermissionGateType
    let onAllow: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Group {
                switch type.icon {
                case .system(let name):
                    Image(systemName: name)
                        .resizable()
                case .marine(let icon):
                    Image(marineIcon: icon)
                        .resizable()
                }
            }
            .scaledToFit()
            .frame(width: 80, height: 80)
            .foregroundColor(marineTheme.colors.primary)
            .padding(.bottom, 10)
            
            Text(type.title)
                .marineFont(.title)
                .multilineTextAlignment(.center)
            
            Text(type.description)
                .marineFont(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 30)
            
            Spacer()
            
            Button(action: onAllow) {
                Text(type.buttonTitle)
                    .marineFont(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(marineTheme.colors.primary)
                    .foregroundColor(marineTheme.colors.onPrimary)
                    .cornerRadius(MarineTheme.Metrics.cornerRadius)
            }
            .buttonStyle(MarineButtonStyle())
            .padding(.horizontal, 40)
            
            Text("You can change this at any time in the Settings app.")
                .marineFont(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }
}
