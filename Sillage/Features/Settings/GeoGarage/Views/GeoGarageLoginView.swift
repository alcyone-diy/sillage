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
  @ScaledMetric(relativeTo: .body) private var scaleFactor: CGFloat = 1.0
  @State private var viewModel = GeoGarageLoginViewModel()
  @Environment(\.dismiss) private var dismiss
  @Environment(GeoGarageAuthService.self) private var authService
  @Environment(MessageService.self) private var messageService
  
  private enum Field {
    case username
    case password
  }
  @FocusState private var focusedField: Field?

  var body: some View {
    ScrollView {
      VStack(spacing: MarineTheme.Spacing.extraLarge) {
        
        // Header
        VStack(spacing: MarineTheme.Spacing.small) {
          Image("GeoGarageLogo")
            .resizable()
            .scaledToFit()
            .frame(height: 44)
        }
        .padding(.top, MarineTheme.Spacing.extraLarge)

        switch viewModel.viewState(authService: authService) {
        case .authenticated(let username):
          authenticatedView(username: username)
        case .authenticationError(let error, let username):
          authenticationErrorView(error: error, username: username)
        case .reauthenticating(let error, _):
          reauthenticatingView(error: error)
        case .unauthenticated(let error):
          unauthenticatedView(error: error)
        }
        
        Spacer(minLength: MarineTheme.Spacing.extraLarge)
      }
      .padding(.horizontal)
    }
    .background(MarineTheme.Colors.panelBackground)
    .navigationTitle(viewModel.isAuthenticated ? "GeoGarage Account" : "GeoGarage Login")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(viewModel.isLoading)
    .interactiveDismissDisabled(viewModel.isLoading)
    .overlay {
      if viewModel.isLoading {
        ZStack {
          MarineTheme.Colors.overlay.ignoresSafeArea()
          ProgressView()
            .controlSize(.large)
            .tint(MarineTheme.Colors.onPrimary)
        }
      }
    }
    .onChange(of: viewModel.isAuthorizationReady) { oldState, isReady in
      if isReady {
        chartViewModel.updateGeoGarageLayers(viewModel.availableLayers)
        if let firstLayer = viewModel.availableLayers.first {
          chartViewModel.switchChartSource(to: .remoteGeoGarage(clientID: AppConfiguration.shared.geoGarageClientID, layerID: firstLayer.layer))
        }
        dismiss()
      }
    }
    .onDisappear {
      viewModel.cancelLogin()
    }
  }

  // MARK: - State Views
  
  private func authenticatedView(username: String?) -> some View {
    VStack(spacing: MarineTheme.Spacing.large) {
      accountInfoView(username: username)
        .padding(MarineTheme.Spacing.medium)
        .background(MarineTheme.Colors.surfaceBackground)
        .cornerRadius(12)
      
      Button(action: performLogout) {
        Text("Log Out")
      }
      .buttonStyle(MarinePrimaryButtonStyle(isDestructive: true, minHeight: marineTheme.minTouchTarget * scaleFactor))
      
      Link("My Account", destination: viewModel.accountManagementURL(authService: authService))
        .buttonStyle(.borderless)
        .tint(MarineTheme.Colors.primary)
        .padding(.top, MarineTheme.Spacing.small)
    }
  }

  private func authenticationErrorView(error: String, username: String?) -> some View {
    VStack(spacing: MarineTheme.Spacing.large) {
      accountInfoView(username: username)
      
      VStack(spacing: MarineTheme.Spacing.small) {
        Text("Authentication Error")
          .font(.headline)
          .foregroundColor(MarineTheme.Colors.error)
        Text(error)
          .font(.footnote)
          .foregroundColor(MarineTheme.Colors.error)
          .multilineTextAlignment(.center)
      }

      VStack(spacing: MarineTheme.Spacing.medium) {
        Button(action: {
          if let username = username {
            viewModel.username = username
          }
          viewModel.forceReauthentication = true
        }) {
          Text("Re-authenticate")
        }
        .buttonStyle(MarinePrimaryButtonStyle(isDestructive: false, minHeight: marineTheme.minTouchTarget * scaleFactor))

        Button(action: performLogout) {
          Text("Log Out")
        }
        .buttonStyle(MarinePrimaryButtonStyle(isDestructive: true, minHeight: marineTheme.minTouchTarget * scaleFactor))
      }
    }
  }

  private func reauthenticatingView(error: String) -> some View {
    VStack(spacing: MarineTheme.Spacing.large) {
      VStack(spacing: MarineTheme.Spacing.small) {
        Text("Re-authenticate")
          .font(.headline)
          .foregroundColor(MarineTheme.Colors.error)
        Text(error)
          .font(.footnote)
          .foregroundColor(MarineTheme.Colors.error)
          .multilineTextAlignment(.center)
      }

      loginForm()

      VStack(spacing: MarineTheme.Spacing.medium) {
        Button(action: {
          viewModel.login(authService: authService, messageService: messageService)
        }) {
          Text("Log In")
        }
        .buttonStyle(MarinePrimaryButtonStyle(isDestructive: false, minHeight: marineTheme.minTouchTarget * scaleFactor))
        .disabled(viewModel.isLoading)

        Button("Cancel", role: .cancel) {
          viewModel.forceReauthentication = false
        }
        .foregroundColor(MarineTheme.Colors.primary)
        .padding(.vertical, MarineTheme.Spacing.small)
      }
    }
  }

  private func unauthenticatedView(error: String?) -> some View {
    VStack(spacing: MarineTheme.Spacing.extraLarge) {
      VStack(spacing: MarineTheme.Spacing.medium) {
        loginForm()
        
        if let error = error {
          Text(error)
            .marineFont(.body)
            .foregroundColor(MarineTheme.Colors.destructive)
            .multilineTextAlignment(.center)
        }
        
        Button(action: {
          focusedField = nil
          viewModel.login(authService: authService, messageService: messageService)
        }) {
          if viewModel.isLoading {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .white))
          } else {
            Text("Log In")
          }
        }
        .buttonStyle(MarinePrimaryButtonStyle(isDestructive: false, minHeight: marineTheme.minTouchTarget * scaleFactor))
        .disabled(viewModel.isLoading)
        
        Link("Discover GeoGarage", destination: viewModel.discoverURL(authService: authService))
          .buttonStyle(.borderless)
          .tint(MarineTheme.Colors.primary)
          .padding(.top, MarineTheme.Spacing.large)
      }
    }.padding(.top, MarineTheme.Spacing.small)
  }

  // MARK: - Actions

  private func performLogout() {
    viewModel.logout(authService: authService, messageService: messageService)
    chartViewModel.logoutGeoGarage()
    
    // Si la carte actuelle était une carte GeoGarage, on force le retour sur OpenSeaMap (gratuite et globale)
    // pour ne pas rester bloqué sur une source devenue invalide.
    if case .remoteGeoGarage = chartViewModel.currentChartSource {
      chartViewModel.switchChartSource(to: .openSeaMap)
    }
  }

  // MARK: - Components

  private func accountInfoView(username: String?) -> some View {
    HStack(spacing: MarineTheme.Spacing.medium) {
      Image(systemName: "person.crop.circle.fill")
        .font(.system(size: 40))
        .foregroundColor(MarineTheme.Colors.primary)
      
      VStack(alignment: .leading, spacing: MarineTheme.Spacing.tiny) {
        Text("Account Connected")
          .marineFont(.subheadline)
          .foregroundColor(.secondary)
        
        if let username = username, !username.isEmpty {
          Text(username)
            .marineFont(.headline)
            .foregroundColor(.primary)
        }
      }
      
      Spacer()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func loginForm() -> some View {
    VStack(spacing: MarineTheme.Spacing.medium) {
      TextField("Username", text: $viewModel.username)
        .textFieldStyle(.roundedBorder)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled(true)
        .textContentType(.username)
        .disabled(viewModel.isLoading)
        .focused($focusedField, equals: .username)
        .submitLabel(.next)
        .onSubmit {
          focusedField = .password
        }
        .frame(minHeight: 44)

      SecureField("Password", text: $viewModel.password)
        .textFieldStyle(.roundedBorder)
        .textContentType(.password)
        .disabled(viewModel.isLoading)
        .focused($focusedField, equals: .password)
        .submitLabel(.go)
        .onSubmit {
          focusedField = nil
          viewModel.login(authService: authService, messageService: messageService)
        }
        .frame(minHeight: 44)
    }
  }
}

// MARK: - Standard Button Style

private struct MarinePrimaryButtonStyle: ButtonStyle {
  let isDestructive: Bool
  let minHeight: CGFloat

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .fontWeight(.bold)
      .frame(maxWidth: .infinity, minHeight: minHeight)
      .background(isDestructive ? MarineTheme.Colors.destructiveBackground : MarineTheme.Colors.primary)
      .foregroundColor(isDestructive ? MarineTheme.Colors.error : MarineTheme.Colors.onPrimary)
      .cornerRadius(MarineTheme.Metrics.cornerRadius)
      .opacity(configuration.isPressed ? 0.7 : 1.0)
  }
}

#Preview {
  // NavigationStack {
  //   GeoGarageLoginView(...)
  // }
  EmptyView() // Preview disabled due to missing DI in preview context
}
