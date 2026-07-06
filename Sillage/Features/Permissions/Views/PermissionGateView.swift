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

enum PermissionGateType: Identifiable {
    case location
    case motion
    
    var id: Self { self }
    
    var icon: PermissionIcon {
        switch self {
        case .location: return .system("location.circle.fill")
        case .motion: return .marine(.instruments)
        }
    }
    
    var title: LocalizedStringKey {
        switch self {
        case .location: return "Location Access"
        case .motion: return "Barometer Access"
        }
    }
    
    var description: LocalizedStringKey {
        switch self {
        case .location: return "Alcyone Sillage needs your location to display your vessel on the marine chart, record your track, and enable the anchor alarm."
        case .motion: return "Alcyone Sillage needs 'Motion & Fitness' access to read your device's internal altimeter, enabling the weather alarm feature."
        }
    }
    
    var buttonTitle: LocalizedStringKey {
        switch self {
        case .location: return "Allow Location"
        case .motion: return "Allow Access"
        }
    }
    
    var deniedMessage: LocalizedStringKey {
        switch self {
        case .location: return "Alcyone Sillage requires location access to use this feature."
        case .motion: return "Alcyone Sillage requires motion and fitness access to read the barometer."
        }
    }
    
    func currentStatus(in service: PermissionService) -> PermissionStatus {
        switch self {
        case .location: return service.locationStatus
        case .motion: return service.motionStatus
        }
    }
    
    func requestAuthorization(in service: PermissionService) async {
        switch self {
        case .location: await service.requestLocationAuthorization()
        case .motion: await service.requestMotionAuthorization()
        }
    }
}

struct PermissionGateView: View {
    @Environment(PermissionService.self) private var permissionService
    @Environment(\.dismiss) private var dismiss
    
    let type: PermissionGateType
    
    init(type: PermissionGateType = .location) {
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
            .foregroundColor(MarineTheme.Colors.primary)
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
                    .background(MarineTheme.Colors.primary)
                    .foregroundColor(MarineTheme.Colors.onPrimary)
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
