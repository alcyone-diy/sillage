//
//  LocalFilePersistenceActor.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-16.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import OSLog

/// A Swift 6 actor that strictly serializes all read/write file I/O operations
/// on a given JSON file destination.
///
/// **Why an actor instead of `Task.detached`?**
/// `Task.detached` provides no mutual exclusion guarantees. If two concurrent downloads
/// finish simultaneously and spawn `Task.detached { write(...) }`, both tasks could read
/// the existing file state concurrently, construct diverged arrays, and race on write —
/// resulting in data corruption. An actor natively serializes all mutations onto its internal queue
/// in a memory-safe, lock-free manner under Swift 6 strict concurrency.
actor LocalFilePersistenceActor {

  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  /// - Parameters:
  ///   - encoder: `JSONEncoder` used for write operations.
  ///   - decoder: `JSONDecoder` used for read operations.
  init(
    encoder: JSONEncoder = LocalFilePersistenceActor.defaultEncoder(),
    decoder: JSONDecoder = LocalFilePersistenceActor.defaultDecoder()
  ) {
    self.encoder = encoder
    self.decoder = decoder
  }

  // MARK: - Read

  /// Reads and decodes a JSON file from the specified URL.
  /// - Returns: `nil` if the file does not exist. Throws an error if the file exists
  ///   but cannot be decoded.
  func load<T: Decodable & Sendable>(from url: URL) throws -> T? {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }
    let data = try Data(contentsOf: url)
    return try decoder.decode(T.self, from: data)
  }

  // MARK: - Write

  /// Encodes and writes a value to a JSON file at the specified URL.
  /// Writing uses atomic writing (`.atomic`) to prevent partially written files.
  func save<T: Encodable & Sendable>(_ value: T, to url: URL) throws {
    let data = try encoder.encode(value)
    try data.write(to: url, options: .atomic)
  }

  // MARK: - Delete

  /// Deletes the file at the specified URL. No-op if the file does not exist.
  func delete(at url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    try FileManager.default.removeItem(at: url)
  }

  // MARK: - Existence

  func fileExists(at url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
  }

  // MARK: - Default Configurations

  static func defaultEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }

  static func defaultDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
