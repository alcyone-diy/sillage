//
//  ShareSheet.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-23.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import OSLog
import SwiftUI
import UIKit

/// Technical Design Choice: ShareSheet UIViewControllerRepresentable
///
/// 1. **Immediate Temporary File Cleanup:**
///    When files are exported for sharing (e.g. GPX traces), they reside in the system's temporary directory.
///    The `completionWithItemsHandler` ensures that once the user finishes sharing or dismisses the share sheet,
///    the temporary file on disk is removed promptly to avoid storage buildup.
///
/// 2. **SwiftUI Integration:**
///    Provides standard presentation via `.sheet(item:)` while preserving native iOS sharing capabilities (AirDrop, Files, Mail).
public struct ShareSheet: UIViewControllerRepresentable {
  public let activityItems: [Any]
  public var applicationActivities: [UIActivity]? = nil
  public var onDismiss: (() -> Void)? = nil

  public init(
    activityItems: [Any],
    applicationActivities: [UIActivity]? = nil,
    onDismiss: (() -> Void)? = nil
  ) {
    self.activityItems = activityItems
    self.applicationActivities = applicationActivities
    self.onDismiss = onDismiss
  }

  public func makeUIViewController(context: Context) -> UIActivityViewController {
    let controller = UIActivityViewController(
      activityItems: activityItems,
      applicationActivities: applicationActivities
    )
    controller.completionWithItemsHandler = { [activityItems] _, _, _, _ in
      // Cleanup temporary files created for sharing to avoid storage leakage
      for item in activityItems {
        if let url = item as? URL {
          try? FileManager.default.removeItem(at: url)
          Logger.storage.debug("🧹 Cleaned up temporary share file: \(url.lastPathComponent, privacy: .public)")
        }
      }
      onDismiss?()
    }
    return controller
  }

  public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
