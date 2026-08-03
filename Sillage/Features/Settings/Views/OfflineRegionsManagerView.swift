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
import os

struct OfflineRegionsManagerView: View {
  @Environment(AppEnvironment.self) private var environment
  @Environment(\.marineTheme) private var marineTheme
  
  fileprivate struct RegionToDelete: Identifiable, Equatable {
    let id: String
    let name: String
  }
  
  @State private var regionToDelete: RegionToDelete?
  
  var body: some View {
    Group {
      if environment.offlineMapManager.downloadedRegions.isEmpty {
        ContentUnavailableView("No offline charts", systemImage: "map.slash")
      } else {
        List {
          Section {
            OfflineRegionsHeaderView()
          }
          
          Section {
            let activeDownloadIndex = environment.offlineMapManager.activeDownloadIndex
            
            ForEach(Array(environment.offlineMapManager.downloadedRegions.enumerated()), id: \.element.id) { index, region in
              let isActive = (index == activeDownloadIndex)
              
              OfflineRegionRowView(region: region, isActive: isActive)
                .swipeActions(edge: .trailing) {
                  Button {
                    regionToDelete = RegionToDelete(id: region.id, name: region.name)
                  } label: {
                    Label("Delete", systemImage: "trash")
                  }
                  .tint(.red)
                }
            }
          }
          .animation(.default, value: environment.offlineMapManager.downloadedRegions)
        }
        .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
        .marineListBackground()
      }
    }
    .navigationTitle("Offline Charts")
    .navigationBarTitleDisplayMode(.inline)
    .alert(
      "Delete Offline Chart?",
      isPresented: Binding(
        get: { regionToDelete != nil },
        set: { if !$0 { regionToDelete = nil } }
      ),
      presenting: regionToDelete
    ) { region in
      Button("Delete", role: .destructive) {
        Task {
          do {
            try await environment.offlineMapManager.deletePack(id: region.id)
          } catch {
            Logger.offline.error("Failed to delete offline chart \(region.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
          }
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: { region in
      Text("Are you sure you want to delete \"\(region.name)\"? This action cannot be undone.")
    }
    .sensoryFeedback(.warning, trigger: regionToDelete)
  }
}

private struct OfflineRegionsHeaderView: View {
  @Environment(AppEnvironment.self) private var environment
  
  var body: some View {
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
}

private struct OfflineRegionRowView: View {
  let region: OfflineRegionInfo
  let isActive: Bool
  
  var body: some View {
    let sizeStr = Int64(region.sizeInBytes).formatted(.byteCount(style: .file))
    
    HStack {
      VStack(alignment: .leading, spacing: 8) {
        VStack(alignment: .leading, spacing: 4) {
          Text(region.name)
            .marineFont(.body)
          
          if !region.isComplete {
            if isActive, let eta = region.estimatedTimeRemaining, eta > 0 {
              let etaStr = Duration.seconds(eta).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
              Text("\(sizeStr) / \(etaStr)")
                .marineFont(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            } else {
              Text("\(sizeStr) - Pending")
                .marineFont(.subheadline)
                .foregroundStyle(.secondary)
            }
          } else {
            Text(sizeStr)
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
  }
}
