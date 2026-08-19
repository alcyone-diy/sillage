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
  
  @State private var viewModel: GeoGarageLoginViewModel
  @Environment(\.dismiss) private var dismiss
  
  @Environment(GeoGarageAuthService.self) private var authService
  @Environment(MessageService.self) private var messageService
  
  @State private var showLogoutConfirmation = false
  
  init(offlineMapManager: OfflineMapManager) {
    self._viewModel = State(initialValue: GeoGarageLoginViewModel(offlineMapManager: offlineMapManager))
  }
  
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
    .background(marineTheme.colors.panelBackground)
    .navigationTitle(viewModel.isAuthenticated ? "GeoGarage Account" : "GeoGarage Login")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(viewModel.isLoading)
    .interactiveDismissDisabled(viewModel.isLoading)
    .overlay {
      if viewModel.isLoading {
        ZStack {
          marineTheme.colors.overlay.ignoresSafeArea()
          ProgressView()
            .controlSize(.large)
            .tint(marineTheme.colors.onPrimary)
        }
      }
    }
    .onChange(of: viewModel.isAuthorizationReady) { oldState, isReady in
      if isReady {
        chartViewModel.clearGeoGarageMessages()
        if let firstLayer = viewModel.availableLayers.first {
          chartViewModel.switchChartSource(to: .remoteGeoGarage(clientID: AppConfiguration.shared.geoGarageClientID, layerID: firstLayer.layer))
        }
        dismiss()
      }
    }
    .onDisappear {
      viewModel.cancelLogin()
    }
    .alert("Log Out", isPresented: $showLogoutConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Log Out", role: .destructive, action: performLogout)
    } message: {
      Text("Logging out will permanently delete all offline maps to comply with GeoGarage licensing. You will need an active internet connection to download them again. Proceed?")
    }
  }

  // MARK: - State Views
  
  private func authenticatedView(username: String?) -> some View {
    VStack(spacing: MarineTheme.Spacing.large) {
      accountInfoView(username: username)
        .padding(MarineTheme.Spacing.medium)
        .background(marineTheme.colors.surfaceBackground)
        .cornerRadius(12)
      
      Button(action: initiateLogout) {
        Text("Log Out")
      }
      .buttonStyle(MarinePrimaryButtonStyle(isDestructive: true, minHeight: marineTheme.minTouchTarget * scaleFactor))
      
      if let accountURL = viewModel.accountManagementURL(authService: authService) {
        Link("My Account", destination: accountURL)
          .buttonStyle(.borderless)
          .tint(marineTheme.colors.primary)
          .padding(.top, MarineTheme.Spacing.small)
      }
    }
  }

  private func authenticationErrorView(error: String, username: String?) -> some View {
    VStack(spacing: MarineTheme.Spacing.large) {
      accountInfoView(username: username)
      
      VStack(spacing: MarineTheme.Spacing.small) {
        Text("Authentication Error")
          .font(.headline)
          .foregroundColor(marineTheme.colors.error)
        Text(error)
          .font(.footnote)
          .foregroundColor(marineTheme.colors.error)
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

        Button(action: initiateLogout) {
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
          .foregroundColor(marineTheme.colors.error)
        Text(error)
          .font(.footnote)
          .foregroundColor(marineTheme.colors.error)
          .multilineTextAlignment(.center)
      }

      loginForm()

      VStack(spacing: MarineTheme.Spacing.medium) {
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

        Button("Cancel", role: .cancel) {
          viewModel.forceReauthentication = false
        }
        .foregroundColor(marineTheme.colors.primary)
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
            .foregroundColor(marineTheme.colors.destructive)
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
        
        if let discoverURL = viewModel.discoverURL(authService: authService) {
          Link("Discover GeoGarage", destination: discoverURL)
            .buttonStyle(.borderless)
            .tint(marineTheme.colors.primary)
            .padding(.top, MarineTheme.Spacing.large)
        }
      }
    }.padding(.top, MarineTheme.Spacing.small)
  }

  // MARK: - Actions

  private func initiateLogout() {
    if viewModel.requiresOfflineMapsWarning() {
      showLogoutConfirmation = true
    } else {
      performLogout()
    }
  }

  private func performLogout() {
    Task {
      await viewModel.performLogout(
        authService: authService,
        messageService: messageService,
        chartViewModel: chartViewModel
      )
    }
  }

  // MARK: - Components

  private func accountInfoView(username: String?) -> some View {
    HStack(spacing: MarineTheme.Spacing.medium) {
      Image(systemName: "person.crop.circle.fill")
        .font(.system(size: 40))
        .foregroundColor(marineTheme.colors.primary)
      
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
  @Environment(\.marineTheme) private var marineTheme

  let isDestructive: Bool
  let minHeight: CGFloat

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .fontWeight(.bold)
      .frame(maxWidth: .infinity, minHeight: minHeight)
      .background(isDestructive ? marineTheme.colors.destructiveBackground : marineTheme.colors.primary)
      .foregroundColor(isDestructive ? marineTheme.colors.error : marineTheme.colors.onPrimary)
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
