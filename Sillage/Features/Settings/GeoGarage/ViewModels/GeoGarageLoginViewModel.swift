//
//  GeoGarageLoginViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import OSLog

/// State of the GeoGarage screen. No credential entry: with the authorization code flow the app
/// never knows the user name nor the password.
enum GeoGarageViewState: Equatable {
  case unauthenticated(error: String?)
  case authenticated
  case authenticationError(error: String)
}

@MainActor
@Observable
final class GeoGarageLoginViewModel {
  let context: GeoGarageLoginContext
  var isLoading = false
  var availableLayers: [GeoGarageLayer] = []
  var isAuthorizationReady: Bool = false
  var errorMessage: String?
  var loginTask: Task<Bool, Never>?

  private let offlineMapManager: OfflineMapManagerProtocol
  private let partnerSecretService: GeoGaragePartnerSecretServiceProtocol

  init(
    offlineMapManager: OfflineMapManagerProtocol,
    partnerSecretService: GeoGaragePartnerSecretServiceProtocol,
    context: GeoGarageLoginContext = .initialSetup
  ) {
    self.offlineMapManager = offlineMapManager
    self.partnerSecretService = partnerSecretService
    self.context = context
  }

  func currentError(authService: GeoGarageAuthServiceProtocol) -> String? {
    if let errorMessage {
      return errorMessage
    }
    if let authError = authService.authError {
      return authError.localizedDescription
    }
    return nil
  }

  func discoverURL(authService: GeoGarageAuthServiceProtocol) -> URL? {
    authService.discoverURL
  }

  func accountManagementURL(authService: GeoGarageAuthServiceProtocol) -> URL? {
    authService.accountManagementURL
  }

  func createAccountURL(authService: GeoGarageAuthServiceProtocol) -> URL? {
    authService.createAccountURL
  }

  var isAuthenticated: Bool {
    KeychainManager.shared.retrieveTokenSync(for: "geogarage_access_token") != nil
  }

  func viewState(authService: GeoGarageAuthServiceProtocol) -> GeoGarageViewState {
    let currentErrorMsg = currentError(authService: authService)
    if isAuthenticated {
      if let error = currentErrorMsg {
        return .authenticationError(error: error)
      }
      return .authenticated
    }
    return .unauthenticated(error: currentErrorMsg)
  }

  func requiresOfflineMapsWarning() -> Bool {
    return !offlineMapManager.downloadedRegions.isEmpty
  }

  func performLogout(
    authService: GeoGarageAuthServiceProtocol,
    messageService: MessageService?,
    chartViewModel: ChartViewModel
  ) async {
    loginTask?.cancel()
    availableLayers = []
    isAuthorizationReady = false
    errorMessage = nil
    await authService.logout()
    messageService?.clear(category: .geoGarage)
    // Signed out, the "offline charts unavailable" warning no longer makes sense.
    messageService?.clear(category: .offlineCharts)
    chartViewModel.logoutGeoGarage()

    do {
      try await offlineMapManager.deleteAllPacks()
    } catch {
      Logger.offline.error("Failed to delete offline packs during logout: \(error.localizedDescription, privacy: .public)")
      let appMessage = AppMessage(
        title: LocalizedStringResource("Offline Maps Error"),
        detail: LocalizedStringResource("Failed to delete some offline maps. Please check your storage."),
        severity: .error,
        category: .geoGarage
      )
      messageService?.post(appMessage)
    }

    try? await offlineMapManager.clearAmbientCache()

    if case .remoteGeoGarage = chartViewModel.currentChartSource {
      chartViewModel.switchChartSource(to: .openSeaMap)
    }
  }

  /// Starts the GeoGarage sign-in: authorization page in the system browser (PKCE), then fetches
  /// the subscriptions. The service stores the tokens in the Keychain. Returns `true` on success;
  /// a cancelled sign-in returns `false` without an error message.
  @discardableResult
  func login(
    authService: GeoGarageAuthServiceProtocol,
    messageService: MessageService?,
    presenter: any GeoGarageAuthorizationPresenting
  ) async -> Bool {
    // Set `isLoading` before the first suspension point: a quick double tap would otherwise open
    // two authorization pages.
    guard !isLoading else { return false }
    loginTask?.cancel()
    isLoading = true
    let task = Task { [weak self] () -> Bool in
      guard let self else { return false }
      // Otherwise the error of the previous attempt stays displayed after the sheet is dismissed.
      self.errorMessage = nil
      defer { self.isLoading = false }

      do {
        let response = try await authService.authenticate(presenter: presenter)

        // Fetch the decryption secret before `fetchAccountSettings`: the latter rewrites
        // `geoGarageCustomerID`, which triggers `reloadDownloads` in `AppEnvironment`, and the
        // secret must already be in the Keychain by then.
        var secretWarning: AppMessage?
        do {
          _ = try await self.partnerSecretService.refresh(accessToken: response.access_token)
          // Secret obtained: a warning left by a previous session (startup or failed sign-in) is
          // now stale.
          messageService?.clear(category: .offlineCharts)
        } catch PartnerSecretError.cancelled {
          // Sheet dismissed (or `loginTask` cancelled) during /partners/me/: not an unavailable
          // secret, exit silently.
          throw AuthError.cancelled
        } catch {
          // Signed in but no secret: online charts work, offline does not. Warn without blocking
          // the sign-in.
          Logger.network.error("Partner secret unavailable after sign-in: \(String(describing: error), privacy: .public)")
          secretWarning = AppMessage(
            title: LocalizedStringResource("Offline charts unavailable"),
            detail: LocalizedStringResource("GeoGarage did not provide the decryption secret. Online charts work; offline downloads are disabled until the next sign-in."),
            severity: .warning,
            // Dedicated category: clearing `.geoGarage` below (and in
            // `ChartViewModel.handleGeoGarageLoginSuccess`) would erase the warning as soon as it
            // is posted.
            category: .offlineCharts
          )
        }

        let settingsResponse = try await authService.fetchAccountSettings(accessToken: response.access_token)

        self.availableLayers = settingsResponse.layers
        self.isAuthorizationReady = true

        let layerNames = settingsResponse.layers.map { $0.brandName }.joined(separator: ", ")
        Logger.network.info("Successfully fetched layers: \(layerNames, privacy: .public)")

        self.errorMessage = nil
        messageService?.clear(category: .geoGarage)
        if let secretWarning {
          messageService?.post(secretWarning)
        }
        return true
      } catch AuthError.cancelled {
        // The user closed the GeoGarage page: nothing to display.
        Logger.network.info("GeoGarage sign-in cancelled by the user.")
        return false
      } catch let error as AuthError {
        self.errorMessage = error.localizedDescription
        return false
      } catch {
        self.errorMessage = AuthError.unknown.localizedDescription
        return false
      }
    }

    loginTask = task
    return await task.value
  }

  func cancelLogin() {
    loginTask?.cancel()
  }
}
