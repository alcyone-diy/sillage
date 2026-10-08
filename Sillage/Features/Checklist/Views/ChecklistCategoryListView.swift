//
//  ChecklistCategoryListView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Displays the catalog of available maritime checklist categories.
@MainActor
public struct ChecklistCategoryListView: View {
  @Environment(\.marineTheme) private var marineTheme
  private let checklistService: any ChecklistServiceProtocol

  public init(checklistService: any ChecklistServiceProtocol) {
    self.checklistService = checklistService
  }

  public var body: some View {
    List {
      // Body content will be populated in next steps
    }
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .marineListBackground()
    .navigationTitle("Checklist Categories")
    .navigationBarTitleDisplayMode(.inline)
  }
}
