//
//  TrackListView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-17.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

@MainActor
struct TrackListView: View {
    var body: some View {
        Section(header: Text("Saved Tracks")) {
            Text("Coming soon...")
                .foregroundStyle(.secondary)
                .marineListCell()
                .marineFont(.body)
        }
    }
}
