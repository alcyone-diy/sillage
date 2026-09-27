//
//  ChecklistService+Environment.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

private struct ChecklistServiceKey: EnvironmentKey {
  static let defaultValue: (any ChecklistServiceProtocol)? = nil
}

public extension EnvironmentValues {
  var checklistService: (any ChecklistServiceProtocol)? {
    get { self[ChecklistServiceKey.self] }
    set { self[ChecklistServiceKey.self] = newValue }
  }
}
