//
//  MarineListCellModifier.swift
//  Alcyone Sillage
//

import SwiftUI

struct MarineListCellModifier: ViewModifier {
    @Environment(\.marineUIStyle) private var marineUIStyle

    func body(content: Content) -> some View {
        content
            .frame(minHeight: marineUIStyle == .gloveMode ? 60 : nil)
            .contentShape(Rectangle())
    }
}

extension View {
    func marineListCell() -> some View {
        self.modifier(MarineListCellModifier())
    }
}
