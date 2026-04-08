//
//  UTType+MBTiles.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import UniformTypeIdentifiers

extension UTType {
  /// Custom Uniform Type Identifier for `.mbtiles` files
  static var mbtiles: UTType {
    // "com.alcyone.sillage.mbtiles" should be registered in Info.plist
    // conforming to "public.data" with the extension "mbtiles".
    UTType(exportedAs: "com.alcyone-sillage.app.mbtiles")
  }
}
