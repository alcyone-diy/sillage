//
//  ChecklistCategoryItem+UI.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-01.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

extension ChecklistCategoryItem {
  var displaySystemImage: String {
    if let icon, !icon.isEmpty {
      return icon
    }
    return "checklist"
  }
}
