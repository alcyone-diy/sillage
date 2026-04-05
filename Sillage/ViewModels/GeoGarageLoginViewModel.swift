//
//  GeoGarageLoginViewModel.swift
//  Alcyone Sillage
//
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

@MainActor
@Observable
final class GeoGarageLoginViewModel {
    var username = ""
    var password = ""
    var isLoading = false
    var errorMessage: LocalizedStringResource? = nil

    func login() {
        Task {
            isLoading = true
            errorMessage = nil

            // Simulate network delay
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            isLoading = false

            if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = "Please enter a valid username."
            } else {
                print("Mock login successful for user: \(username)")
            }
        }
    }
}
