//
//  StreamingMD5Validator.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-16.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CryptoKit

/// Utility for calculating MD5 checksums of files in streaming chunks (1 MB buffer)
/// to prevent Out-Of-Memory (OOM) crashes on large MBTiles files (multi-gigabytes).
nonisolated enum StreamingMD5Validator {
  private static let chunkSize = 1024 * 1024 // 1 MB buffer

  /// Computes the MD5 hex string of a file at `url` using iterative chunk reading.
  /// Yields execution cooperatively via `await Task.yield()` after each 1 MB chunk to prevent thread starvation.
  /// - Parameter url: File URL on disk.
  /// - Returns: Lowercase hex string of the MD5 checksum.
  /// - Throws: `CaasError.fileSystemError` if file handle cannot be opened or read.
  static func computeMD5(for url: URL) async throws(CaasError) -> String {
    let fileHandle: FileHandle
    do {
      fileHandle = try FileHandle(forReadingFrom: url)
    } catch {
      throw CaasError.fileSystemError(underlying: "Unable to open file at \(url.path) for MD5 computation: \(error.localizedDescription)")
    }
    defer {
      try? fileHandle.close()
    }

    var hasher = Insecure.MD5()

    while true {
      let chunk: Data
      do {
        guard let readData = try fileHandle.read(upToCount: chunkSize), !readData.isEmpty else {
          break
        }
        chunk = readData
      } catch {
        throw CaasError.fileSystemError(underlying: "Failed reading file chunk at \(url.path): \(error.localizedDescription)")
      }

      hasher.update(data: chunk)
      await Task.yield()
    }

    let digest = hasher.finalize()
    return digest.map { String(format: "%02hhx", $0) }.joined()
  }

  /// Verifies that the MD5 checksum of the file at `url` matches `expectedMD5` (case-insensitive).
  /// - Parameters:
  ///   - url: File URL on disk.
  ///   - expectedMD5: Expected MD5 hex string from the CAAS server response.
  /// - Throws: `CaasError.md5Mismatch` if hashes differ, or `CaasError.fileSystemError` on I/O failure.
  static func validateMD5(for url: URL, expectedMD5: String) async throws(CaasError) {
    let computed = try await computeMD5(for: url)
    guard computed.lowercased() == expectedMD5.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
      throw CaasError.md5Mismatch(expected: expectedMD5.lowercased(), actual: computed.lowercased())
    }
  }
}
