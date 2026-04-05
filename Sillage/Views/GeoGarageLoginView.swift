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
  @Environment(\.marineTheme) private var marineTheme
  @ScaledMetric(relativeTo: .body) private var scaleFactor: CGFloat = 1.0
  @State private var viewModel = GeoGarageLoginViewModel()

  var body: some View {
    ZStack {
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
              .textContentType(.username)
              .disabled(viewModel.isLoading)
              .frame(minHeight: 44)
              .padding(.horizontal)

            SecureField("Password", text: $viewModel.password)
              .textFieldStyle(.roundedBorder)
              .textContentType(.password)
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
            .frame(maxWidth: .infinity, minHeight: marineTheme.minTouchTarget * scaleFactor)
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

      if viewModel.isLoading {
        Color.black.opacity(0.3)
          .ignoresSafeArea()

        ProgressView()
          .controlSize(.large)
          .tint(.white)
      }
    }
    .navigationTitle("GeoGarage")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(viewModel.isLoading)
    .interactiveDismissDisabled(viewModel.isLoading)
  }
}

#Preview {
  NavigationStack {
    GeoGarageLoginView()
  }
}
