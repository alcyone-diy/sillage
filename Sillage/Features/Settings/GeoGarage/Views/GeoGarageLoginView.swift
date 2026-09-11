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
import AuthenticationServices

struct GeoGarageLoginView: View {
  @Environment(\.marineTheme) private var marineTheme
  @Environment(ChartViewModel.self) private var chartViewModel
  @ScaledMetric(relativeTo: .body) private var scaleFactor: CGFloat = 1.0

  @State private var viewModel: GeoGarageLoginViewModel
  @Environment(\.dismiss) private var dismiss

  @Environment(GeoGarageAuthService.self) private var authService
  @Environment(MessageService.self) private var messageService
  @Environment(\.webAuthenticationSession) private var webAuthenticationSession

  @State private var showLogoutConfirmation = false

  init(offlineMapManager: OfflineMapManager) {
    self._viewModel = State(initialValue: GeoGarageLoginViewModel(offlineMapManager: offlineMapManager))
  }

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
        case .authenticated:
          authenticatedView()
        case .authenticationError(let error):
          authenticationErrorView(error: error)
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

  private func authenticatedView() -> some View {
    VStack(spacing: MarineTheme.Spacing.large) {
      accountInfoView()
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

  private func authenticationErrorView(error: String) -> some View {
    VStack(spacing: MarineTheme.Spacing.large) {
      accountInfoView()

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
        signInButton()

        Button(action: initiateLogout) {
          Text("Log Out")
        }
        .buttonStyle(MarinePrimaryButtonStyle(isDestructive: true, minHeight: marineTheme.minTouchTarget * scaleFactor))
      }
    }
  }

  private func unauthenticatedView(error: String?) -> some View {
    VStack(spacing: MarineTheme.Spacing.extraLarge) {
      VStack(spacing: MarineTheme.Spacing.medium) {
        Text("Sign in on accounts.geogarage.com to stream and download your GeoGarage charts. Sillage never sees your password.")
          .marineFont(.body)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)

        if let error {
          Text(error)
            .marineFont(.body)
            .foregroundColor(marineTheme.colors.destructive)
            .multilineTextAlignment(.center)
        }

        signInButton()

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

  private func startSignIn() {
    // La page de connexion s'ouvre dans le navigateur système (ASWebAuthenticationSession) :
    // Sillage ne voit jamais le mot de passe GeoGarage (RFC 8252, passage en PKCE du 11 sept. 2026).
    viewModel.login(
      authService: authService,
      messageService: messageService,
      presenter: WebAuthenticationSessionPresenter(session: webAuthenticationSession)
    )
  }

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

  private func signInButton() -> some View {
    Button(action: startSignIn) {
      if viewModel.isLoading {
        ProgressView()
          .progressViewStyle(CircularProgressViewStyle(tint: .white))
      } else {
        Text("Sign in with GeoGarage")
      }
    }
    .buttonStyle(MarinePrimaryButtonStyle(isDestructive: false, minHeight: marineTheme.minTouchTarget * scaleFactor))
    .disabled(viewModel.isLoading)
  }

  private func accountInfoView() -> some View {
    HStack(spacing: MarineTheme.Spacing.medium) {
      Image(systemName: "person.crop.circle.fill")
        .font(.system(size: 40))
        .foregroundColor(marineTheme.colors.primary)

      VStack(alignment: .leading, spacing: MarineTheme.Spacing.tiny) {
        Text("Account Connected")
          .marineFont(.headline)
          .foregroundColor(.primary)
        Text("Manage your subscriptions on accounts.geogarage.com.")
          .marineFont(.subheadline)
          .foregroundColor(.secondary)
      }

      Spacer()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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
