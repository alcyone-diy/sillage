//
//  TrackDetailView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-20.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

@MainActor
struct TrackDetailView: View {
  let sessionId: TrackSession.ID
  
  var body: some View {
    VStack {
      Text(sessionId).marineFont(.title)
    }
    .navigationTitle("Track Detail")
    .navigationBarTitleDisplayMode(.inline)
  }
}
