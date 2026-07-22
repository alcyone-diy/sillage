//
//  GeoGarageLoginView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct GeoGarageLoginView: View {
  @Environment(\.marineTheme) private var marineTheme
  @Environment(ChartViewModel.self) private var chartViewModel
  @Environment(MessageService.self) private var messageService: MessageService?
  @ScaledMetric(relativeTo: .body) private var scaleFactor: CGFloat = 1.0
  @State private var viewModel = GeoGarageLoginViewModel()
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ZStack {
      ScrollView {
        VStack(spacing: MarineTheme.Spacing.large) {
          // Header
          Text("GeoGarage Login")
            .font(.title)
            .fontWeight(.semibold)
            .padding(.bottom, MarineTheme.Spacing.medium)

          // Form Fields
          VStack(spacing: MarineTheme.Spacing.medium) {
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

          if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
              .font(.footnote)
              .foregroundColor(MarineTheme.Colors.error)
              .padding(.horizontal)
              .multilineTextAlignment(.center)
          }

          // Login Button
              Button(action: {
                viewModel.login()
              }) {
                ZStack {
                  if viewModel.isLoading {
                    ProgressView()
                      .tint(MarineTheme.Colors.onPrimary)
                  } else {
                    Text("Log In")
                      .font(.headline)
                      .fontWeight(.bold)
                  }
                }
                .frame(maxWidth: .infinity, minHeight: marineTheme.minTouchTarget * scaleFactor)
                .background(viewModel.isLoading ? MarineTheme.Colors.primary.opacity(0.6) : MarineTheme.Colors.primary)
                .foregroundColor(MarineTheme.Colors.onPrimary)
                .cornerRadius(MarineTheme.Metrics.cornerRadius)
                .padding(.horizontal)
              }
              .disabled(viewModel.isLoading)
              .padding(.top, MarineTheme.Spacing.small)

              Spacer(minLength: MarineTheme.Spacing.extraLarge)
            }
            .padding(.vertical, MarineTheme.Spacing.extraLarge)
          }

      if viewModel.isLoading {
        MarineTheme.Colors.overlay
          .ignoresSafeArea()

        ProgressView()
          .controlSize(.large)
          .tint(MarineTheme.Colors.onPrimary)
      }
    }
    .navigationTitle("GeoGarage")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(viewModel.isLoading)
    .interactiveDismissDisabled(viewModel.isLoading)
    .onChange(of: viewModel.isAuthorizationReady) { oldState, isReady in
      if isReady {
        chartViewModel.updateGeoGarageLayers(viewModel.availableLayers)
        if let firstLayer = viewModel.availableLayers.first {
          chartViewModel.switchChartSource(to: .remoteGeoGarage(clientID: AppConfiguration.shared.geoGarageClientID, layerID: firstLayer.layer))
        }
        dismiss()
      }
    }
    .onAppear {
      viewModel.messageService = messageService
    }
    .onDisappear {
      viewModel.cancelLogin()
    }
  }
}

#Preview {
  NavigationStack {
    GeoGarageLoginView()
  }
}
