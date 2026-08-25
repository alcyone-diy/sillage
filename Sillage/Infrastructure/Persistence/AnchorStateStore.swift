//
//  AnchorStateStore.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-07.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import os

/// State container representing the persistent anchor watch session state.
public struct AnchorSessionData: Codable, Sendable, Equatable {
  public var activeWatch: AnchorWatch?
  public var status: AnchorStatus
  public var triggerReason: AnchorTriggerReason?

  public init(
    activeWatch: AnchorWatch? = nil,
    status: AnchorStatus = .inactive,
    triggerReason: AnchorTriggerReason? = nil
  ) {
    self.activeWatch = activeWatch
    self.status = status
    self.triggerReason = triggerReason
  }
}

public protocol AnchorStateStoreProtocol: Sendable {
  func loadSession() -> AnchorSessionData
  func saveSession(_ session: AnchorSessionData)
}

private actor DiskWriter {
  func write(_ data: Data, to url: URL) {
    do {
      try data.write(to: url, options: .atomic)
    } catch {
      Logger.anchor.error("Failed to write anchor session state to disk: \(error.localizedDescription, privacy: .public)")
    }
  }
}

public final class AnchorStateStore: AnchorStateStoreProtocol, @unchecked Sendable {
  private let fileURL: URL
  private let stateLock: OSAllocatedUnfairLock<AnchorSessionData>
  private let diskWriter = DiskWriter()

  public init(fileManager: FileManager = FileManager()) {
    let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
    let appSupportDir = urls.first?.appendingPathComponent("Sillage", isDirectory: true) ?? fileManager.temporaryDirectory
    
    try? fileManager.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
    let url = appSupportDir.appendingPathComponent("anchor_session.json")
    self.fileURL = url

    var initialData = AnchorSessionData()
    if fileManager.fileExists(atPath: url.path),
       let data = try? Data(contentsOf: url),
       let decoded = try? JSONDecoder().decode(AnchorSessionData.self, from: data) {
      initialData = decoded
    }
    self.stateLock = OSAllocatedUnfairLock(initialState: initialData)
  }

  public func loadSession() -> AnchorSessionData {
    stateLock.withLock { $0 }
  }

  public func saveSession(_ session: AnchorSessionData) {
    stateLock.withLock { $0 = session }
    let url = fileURL
    let writer = diskWriter
    do {
      let data = try JSONEncoder().encode(session)
      Task.detached(priority: .medium) {
        await writer.write(data, to: url)
      }
    } catch {
      Logger.anchor.error("Failed to encode anchor session state: \(error.localizedDescription, privacy: .public)")
    }
  }
}
