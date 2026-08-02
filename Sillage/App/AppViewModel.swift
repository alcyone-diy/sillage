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
import CoreLocation

public struct CoordinateWrapper: Identifiable {
  public let id = UUID()
  public let coordinate: CLLocationCoordinate2D
  public let defaultName: String?
  
  public init(coordinate: CLLocationCoordinate2D, defaultName: String?) {
    self.coordinate = coordinate
    self.defaultName = defaultName
  }
}


@Observable
@MainActor
final class AppViewModel {
  private var preferencesService: PreferencesServiceProtocol
  private let chartImportService: ChartImportService
  private let authService: GeoGarageAuthService?
  private let panelManagerViewModel: PanelManagerViewModel

  var importError: ChartImportError?
  var showImportError: Bool = false
  
  var waypointDraft: CoordinateWrapper?

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
    preferencesService: PreferencesServiceProtocol,
    chartImportService: ChartImportService? = nil,
    authService: GeoGarageAuthService? = nil,
    panelManagerViewModel: PanelManagerViewModel
  ) {
    self.preferencesService = preferencesService
    self.chartImportService = chartImportService ?? ChartImportService()
    self.authService = authService
    self.panelManagerViewModel = panelManagerViewModel
    self.isGloveModeEnabled = preferencesService.gloveModeEnabled
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

  @MainActor
  func handleNotification(identifier: String) {
    if identifier.starts(with: "sillage.barometer") {
      if panelManagerViewModel.commandPath.last != .baroAlarm {
        panelManagerViewModel.commandPath.append(.baroAlarm)
      }
      panelManagerViewModel.openPanel(.command)
    }
  }
}
