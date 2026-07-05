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

struct PermissionGateView: View {
    @Environment(PermissionService.self) private var permissionService
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Group {
            if permissionService.locationStatus == .unknown {
                Color.clear
                    .ignoresSafeArea()
            } else if permissionService.locationStatus == .notDetermined {
                LocationPrePermissionView {
                    Task {
                        await permissionService.requestLocationAuthorization()
                    }
                }
            } else if permissionService.locationStatus == .denied {
                VStack {
                    Spacer()
                    PermissionDeniedView(message: "Alcyone Sillage requires location access to use this feature.")
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
        .animation(.easeInOut(duration: 0.3), value: permissionService.locationStatus)
    }
}
