//
//  MBTileFile.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

public struct MBTileFile: Identifiable, Sendable {
  public let id: UUID
  public let filename: String
  public let fileURL: URL
  public let fileSize: Measurement<UnitInformationStorage>?

  public nonisolated init(id: UUID = UUID(), filename: String, fileURL: URL, fileSize: Measurement<UnitInformationStorage>?) {
    self.id = id
    self.filename = filename
    self.fileURL = fileURL
    self.fileSize = fileSize
  }
}
