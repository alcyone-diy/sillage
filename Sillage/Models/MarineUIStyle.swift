//
//  MarineUIStyle.swift
//  Alcyone Sillage
//

import SwiftUI

enum MarineUIStyle {
    case standard
    case gloveMode
}

private struct MarineUIStyleKey: EnvironmentKey {
    static let defaultValue: MarineUIStyle = .standard
}

extension EnvironmentValues {
    var marineUIStyle: MarineUIStyle {
        get { self[MarineUIStyleKey.self] }
        set { self[MarineUIStyleKey.self] = newValue }
    }
}
