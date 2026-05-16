//
//  LegalDocument.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

struct LegalDocument: Identifiable {
  let id = UUID()
  let title: LocalizedStringResource
  let content: String?
  let filename: String?
  let fileExtension: String?

  init(title: LocalizedStringResource, content: String? = nil, filename: String? = nil, fileExtension: String? = nil) {
    self.title = title
    self.content = content
    self.filename = filename
    self.fileExtension = fileExtension
  }
}
