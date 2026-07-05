//
//  RequiresLocationPermissionModifier.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-06.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct RequiresLocationPermissionModifier: ViewModifier {
    @Environment(PermissionService.self) private var permissionService
    @State private var showPrompt = false
    var action: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(permissionService.locationStatus == .authorized)
            .overlay {
                if permissionService.locationStatus != .authorized {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showPrompt = true
                        }
                }
            }
            .sheet(isPresented: $showPrompt) {
                PermissionGateView()
                    .presentationDetents([.medium, .large])
                    .onChange(of: permissionService.locationStatus) { _, status in
                        if status == .authorized {
                            showPrompt = false
                            action?()
                        }
                    }
            }
    }
}

public extension View {
    /// Protects an action behind a location permission check.
    /// If location is not authorized, it presents a permission workflow instead of executing the action.
    /// Once authorized, it automatically executes the action.
    func requiresLocationPermission(action: (() -> Void)? = nil) -> some View {
        self.modifier(RequiresLocationPermissionModifier(action: action))
    }
}
