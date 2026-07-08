//
//  OfflineRegionsManagerView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct OfflineRegionsManagerView: View {
  @Environment(AppEnvironment.self) private var environment
  @Environment(\.marineTheme) private var marineTheme
  
  var body: some View {
    Group {
      if environment.offlineMapManager.downloadedRegions.isEmpty {
        ContentUnavailableView("No offline charts", systemImage: "map.slash")
      } else {
        List {
          ForEach(environment.offlineMapManager.downloadedRegions) { region in
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text(region.name)
                  .marineFont(.headline)
                Text(Int64(region.sizeInBytes).formatted(.byteCount(style: .file)))
                  .marineFont(.subheadline)
                  .foregroundStyle(.secondary)
              }
              Spacer()
            }
            .marineListCell()
            .swipeActions(edge: .trailing) {
              Button(role: .destructive) {
                environment.offlineMapManager.deletePack(id: region.id)
              } label: {
                Label("Delete", systemImage: "trash")
              }
            }
          }
        }
        .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
        .marineListBackground()
      }
    }
    .navigationTitle("Offline Charts")
    .navigationBarTitleDisplayMode(.inline)
  }
}
