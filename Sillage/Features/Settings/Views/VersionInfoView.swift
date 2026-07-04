//
//  VersionInfoView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-23.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct VersionInfoView: View {
  @Environment(AppEnvironment.self) private var environment
  
  var body: some View {
    Form {
      Section(header: Text("App Information")) {
        HStack {
          Text("Version")
            .marineFont(.body)
          Spacer()
          Text(environment.metadata.version ?? "Unknown")
            .marineFont(.body)
            .foregroundStyle(.secondary)
        }
        .marineListCell()
        
        HStack {
          Text("Build")
            .marineFont(.body)
          Spacer()
          Text(environment.metadata.build ?? "Unknown")
            .marineFont(.body)
            .foregroundStyle(.secondary)
        }
        .marineListCell()
        
        HStack {
          Text("Git Hash")
            .marineFont(.body)
          Spacer()
          Text(environment.metadata.gitHash ?? "Unknown")
            .marineFont(.body)
            .foregroundStyle(.secondary)
        }
        .marineListCell()
        
        if let date = environment.metadata.compilationDate {
          HStack {
            Text("Compiled")
              .marineFont(.body)
            Spacer()
            Text(date.formatted(date: .abbreviated, time: .shortened))
              .marineFont(.body)
              .foregroundStyle(.secondary)
          }
          .marineListCell()
        }
      }
    }
    .navigationTitle("Version")
    .navigationBarTitleDisplayMode(.inline)
    .marineListBackground()
  }
}
