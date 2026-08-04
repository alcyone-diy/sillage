//
//  PermissionDeniedView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-06.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct PermissionDeniedView: View {
    @Environment(PermissionService.self) private var permissionService
    @Environment(\.marineTheme) private var marineTheme
    let message: LocalizedStringResource
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundColor(marineTheme.colors.destructive)
            
            Text("Permission Required")
                .marineFont(.title2)
                .multilineTextAlignment(.center)
            
            Text(message)
                .marineFont(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 30)
            
            Button(action: {
                permissionService.openSystemSettings()
            }) {
                Text("Open Settings")
                    .marineFont(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(marineTheme.colors.primary)
                    .foregroundColor(marineTheme.colors.onPrimary)
                    .cornerRadius(MarineTheme.Metrics.cornerRadius)
            }
            .buttonStyle(MarineButtonStyle())
            .padding(.horizontal, 40)
            .padding(.top, 10)
        }
        .padding()
        .background(Material.ultraThinMaterial)
        .cornerRadius(16)
        .padding()
    }
}
