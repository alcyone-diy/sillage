//
//  AppViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation
import OSLog


@Observable
@MainActor
final class AppViewModel {
  private var preferencesService: PreferencesServiceProtocol
  private let chartImportService: ChartImportService

  var importError: ChartImportError?
  var showImportError: Bool = false


  var isGloveModeEnabled: Bool {
    didSet {
      preferencesService.gloveModeEnabled = isGloveModeEnabled
    }
  }

  var marineUIStyle: MarineUIStyle {
    return isGloveModeEnabled ? .gloveMode : .standard
  }

  var marineTheme: MarineTheme {
    return isGloveModeEnabled ? .gloveMode : .standard
  }

  init(
    preferencesService: PreferencesServiceProtocol? = nil,
    chartImportService: ChartImportService? = nil
  ) {
    let resolvedPreferences = preferencesService ?? PreferencesService.shared
    self.preferencesService = resolvedPreferences
    self.chartImportService = chartImportService ?? ChartImportService()
    self.isGloveModeEnabled = resolvedPreferences.gloveModeEnabled
  }

  func handleIncomingURL(_ url: URL) {
    do {
      try chartImportService.handleIncomingURL(url)
    } catch let error as ChartImportError {
      self.importError = error
      self.showImportError = true
    } catch {
      self.importError = .moveFailed(error)
      self.showImportError = true
    }
  }
}
