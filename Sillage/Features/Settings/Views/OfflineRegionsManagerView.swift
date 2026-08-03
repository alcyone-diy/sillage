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
          Section {
            VStack(alignment: .leading, spacing: 8) {
              if environment.offlineMapManager.totalPendingDownloads > 0 {
                Text("\(environment.offlineMapManager.totalPendingDownloads) downloads pending")
                  .marineFont(.headline)
                
                if let eta = environment.offlineMapManager.totalEstimatedTimeRemaining, eta > 0 {
                  Text("Total time: \(Duration.seconds(eta).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated)))")
                    .marineFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
                
                if let progress = environment.offlineMapManager.globalDownloadProgress {
                  ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                } else {
                  ProgressView()
                    .controlSize(.small)
                }
              } else {
                let totalMaps = environment.offlineMapManager.downloadedRegions.count
                let totalSize = environment.offlineMapManager.totalDownloadedSize
                
                Text("\(totalMaps) offline charts")
                  .marineFont(.headline)
                
                Text("Total size: \(totalSize.formatted(.byteCount(style: .file)))")
                  .marineFont(.subheadline)
                  .foregroundStyle(.secondary)
              }
            }
            .marineListCell()
          }
          
          Section {
            let activeDownloadIndex = environment.offlineMapManager.activeDownloadIndex
            
            ForEach(Array(environment.offlineMapManager.downloadedRegions.enumerated()), id: \.element.id) { index, region in
              let isActive = (index == activeDownloadIndex)
              
              HStack {
                VStack(alignment: .leading, spacing: 8) {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(region.name)
                      .marineFont(.headline)
                    
                    if !region.isComplete {
                      if isActive, let eta = region.estimatedTimeRemaining, eta > 0 {
                        let sizeStr = Int64(region.sizeInBytes).formatted(.byteCount(style: .file))
                        let etaStr = Duration.seconds(eta).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
                        Text("\(sizeStr) / \(etaStr)")
                          .marineFont(.subheadline)
                          .foregroundStyle(.secondary)
                          .monospacedDigit()
                      } else {
                        let sizeStr = Int64(region.sizeInBytes).formatted(.byteCount(style: .file))
                        Text("\(sizeStr) - Pending")
                          .marineFont(.subheadline)
                          .foregroundStyle(.secondary)
                      }
                    } else {
                      Text(Int64(region.sizeInBytes).formatted(.byteCount(style: .file)))
                        .marineFont(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                  }
                  
                  if !region.isComplete && isActive {
                    if let progress = region.progress {
                      ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                    } else {
                      ProgressView()
                    }
                  }
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
        }
        .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
        .marineListBackground()
      }
    }
    .navigationTitle("Offline Charts")
    .navigationBarTitleDisplayMode(.inline)
  }
}
