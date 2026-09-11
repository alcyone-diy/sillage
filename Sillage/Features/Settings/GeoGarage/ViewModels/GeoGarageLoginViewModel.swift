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

/// État de l'écran GeoGarage. Plus de saisie d'identifiants depuis le passage en authorization code
/// (11 sept. 2026) : l'app ne connaît ni le mot de passe ni le nom d'utilisateur.
enum GeoGarageViewState: Equatable {
  case unauthenticated(error: String?)
  case authenticated
  case authenticationError(error: String)
}

@MainActor
@Observable
final class GeoGarageLoginViewModel {
  var isLoading = false
  var availableLayers: [GeoGarageLayer] = []
  var isAuthorizationReady: Bool = false
  var errorMessage: String?
  var loginTask: Task<Void, Never>?

  private let offlineMapManager: OfflineMapManagerProtocol

  init(offlineMapManager: OfflineMapManagerProtocol) {
    self.offlineMapManager = offlineMapManager
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

  /// Lance la connexion GeoGarage : page d'autorisation dans le navigateur système (PKCE), puis
  /// lecture des abonnements. Les tokens sont rangés dans le trousseau par le service.
  func login(
    authService: GeoGarageAuthServiceProtocol,
    messageService: MessageService?,
    presenter: any GeoGarageAuthorizationPresenting
  ) {
    loginTask?.cancel()
    loginTask = Task { [weak self] in
      self?.isLoading = true
      defer { self?.isLoading = false }

      do {
        let response = try await authService.authenticate(presenter: presenter)
        let settingsResponse = try await authService.fetchAccountSettings(accessToken: response.access_token)

        self?.availableLayers = settingsResponse.layers
        self?.isAuthorizationReady = true

        let layerNames = settingsResponse.layers.map { $0.brandName }.joined(separator: ", ")
        Logger.network.info("Successfully fetched layers: \(layerNames, privacy: .public)")

        self?.errorMessage = nil
        messageService?.clear(category: .geoGarage)
      } catch AuthError.cancelled {
        // L'utilisateur a fermé la page GeoGarage : rien à afficher.
        Logger.network.info("GeoGarage sign-in cancelled by the user.")
      } catch let error as AuthError {
        self?.errorMessage = error.localizedDescription
      } catch {
        self?.errorMessage = AuthError.unknown.localizedDescription
      }
    }
  }

  func cancelLogin() {
    loginTask?.cancel()
  }
}
