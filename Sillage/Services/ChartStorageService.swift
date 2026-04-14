//
//  ChartStorageService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

public actor ChartStorageService {
  public init() {}

  public func discoverMBTiles() async -> [MBTileFile] {
    let fileManager = FileManager.default

    guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
      return []
    }

    let chartsDirectory = documentsDirectory.appendingPathComponent("Charts")

    var isDirectory: ObjCBool = false
    let exists = fileManager.fileExists(atPath: chartsDirectory.path, isDirectory: &isDirectory)

    if !exists || !isDirectory.boolValue {
      do {
        try fileManager.createDirectory(at: chartsDirectory, withIntermediateDirectories: true, attributes: nil)
      } catch {
        // Return empty if we cannot create the charts directory
        return []
      }
    }

    do {
      let files = try fileManager.contentsOfDirectory(at: chartsDirectory, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles)

      var mbtilesFiles: [MBTileFile] = []

      for fileURL in files {
        if fileURL.pathExtension.lowercased() == "mbtiles" {
          let filename = fileURL.lastPathComponent

          var fileSizeMeasurement: Measurement<UnitInformationStorage>? = nil
          if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
             let fileSizeInBytes = resourceValues.fileSize {
            fileSizeMeasurement = Measurement(value: Double(fileSizeInBytes), unit: .bytes)
          }

          let mbtile = MBTileFile(filename: filename, fileURL: fileURL, fileSize: fileSizeMeasurement)
          mbtilesFiles.append(mbtile)
        }
      }

      return mbtilesFiles
    } catch {
      return []
    }
  }
}
