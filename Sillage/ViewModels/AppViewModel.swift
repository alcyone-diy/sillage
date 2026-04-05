//
//  AppViewModel.swift
//  Alcyone Sillage
//

import Foundation
import Observation

@Observable
final class AppViewModel {
    private var preferencesService: PreferencesServiceProtocol

    var isGloveModeEnabled: Bool {
        didSet {
            preferencesService.gloveModeEnabled = isGloveModeEnabled
        }
    }

    var marineUIStyle: MarineUIStyle {
        return isGloveModeEnabled ? .gloveMode : .standard
    }

    init(preferencesService: PreferencesServiceProtocol = PreferencesService.shared) {
        self.preferencesService = preferencesService
        self.isGloveModeEnabled = preferencesService.gloveModeEnabled
    }
}
