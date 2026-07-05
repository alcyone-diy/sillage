//
//  LocationPrePermissionView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-06.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct LocationPrePermissionView: View {
    let onAllow: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "location.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundColor(MarineTheme.Colors.primary)
                .padding(.bottom, 10)
            
            Text("Location Access")
                .marineFont(.title)
                .multilineTextAlignment(.center)
            
            Text("Alcyone Sillage needs your location to display your vessel on the marine chart, record your track, and enable the anchor alarm.")
                .marineFont(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 30)
            
            Spacer()
            
            Button(action: onAllow) {
                Text("Allow Location")
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
