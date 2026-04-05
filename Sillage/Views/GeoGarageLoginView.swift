//
//  GeoGarageLoginView.swift
//  Alcyone Sillage
//
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct GeoGarageLoginView: View {
  @Environment(\.marineUIStyle) private var marineUIStyle
  @State private var viewModel = GeoGarageLoginViewModel()

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        // Header
        Text("GeoGarage Login")
          .font(.title)
          .fontWeight(.semibold)
          .padding(.bottom, 16)

        // Form Fields
        VStack(spacing: 16) {
          TextField("Username", text: $viewModel.username)
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .disabled(viewModel.isLoading)
            .frame(minHeight: 44)
            .padding(.horizontal)

          SecureField("Password", text: $viewModel.password)
            .textFieldStyle(.roundedBorder)
            .disabled(viewModel.isLoading)
            .frame(minHeight: 44)
            .padding(.horizontal)
        }

        // Error Message
        if let errorMessage = viewModel.errorMessage {
          Text(errorMessage)
            .foregroundColor(.red)
            .font(.callout)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
        }

        // Login Button
        Button(action: {
          viewModel.login()
        }) {
          ZStack {
            if viewModel.isLoading {
              ProgressView()
                .tint(.white)
            } else {
              Text("Log In")
                .font(.headline)
                .fontWeight(.bold)
            }
          }
          .frame(maxWidth: .infinity, minHeight: marineUIStyle == .gloveMode ? 60 : 44)
          .background(viewModel.isLoading ? Color.blue.opacity(0.6) : Color.blue)
          .foregroundColor(.white)
          .cornerRadius(12)
          .padding(.horizontal)
        }
        .disabled(viewModel.isLoading)
        .padding(.top, 8)

        Spacer(minLength: 40)
      }
      .padding(.vertical, 32)
    }
    .navigationTitle("GeoGarage")
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  NavigationStack {
    GeoGarageLoginView()
  }
}
