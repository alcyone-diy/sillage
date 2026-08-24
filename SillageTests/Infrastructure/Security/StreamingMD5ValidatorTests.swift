//
//  StreamingMD5ValidatorTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-16.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CryptoKit
@testable import Sillage

final class StreamingMD5ValidatorTests: XCTestCase {

  private var tempFiles: [URL] = []

  override func tearDown() {
    for url in tempFiles {
      try? FileManager.default.removeItem(at: url)
    }
    tempFiles.removeAll()
    super.tearDown()
  }

  private func createTempFile(with data: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dat")
    try data.write(to: url)
    tempFiles.append(url)
    return url
  }

  // MARK: - Compute MD5

  func testComputeMD5_matchesKnownDigest() async throws {
    let text = "Hello Marine Cartography"
    let data = text.data(using: .utf8)!
    let fileURL = try createTempFile(with: data)

    let expectedDigest = Insecure.MD5.hash(data: data).map { String(format: "%02hhx", $0) }.joined()
    let computedDigest = try await StreamingMD5Validator.computeMD5(for: fileURL)

    XCTAssertEqual(computedDigest, expectedDigest)
  }

  func testComputeMD5_multiChunkBuffer() async throws {
    // 2.5 MB of random data to ensure multiple 1 MB chunk iterations with Task.yield
    var buffer = [UInt8](repeating: 0, count: Int(2.5 * 1024 * 1024))
    for i in 0..<buffer.count {
      buffer[i] = UInt8(i % 256)
    }
    let data = Data(buffer)
    let fileURL = try createTempFile(with: data)

    let expectedDigest = Insecure.MD5.hash(data: data).map { String(format: "%02hhx", $0) }.joined()
    let computedDigest = try await StreamingMD5Validator.computeMD5(for: fileURL)

    XCTAssertEqual(computedDigest, expectedDigest, "Chunked streaming MD5 must match Insecure.MD5 whole-file hash")
  }

  func testComputeMD5_throwsFileSystemErrorOnMissingFile() async {
    let missingURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".missing")

    do {
      _ = try await StreamingMD5Validator.computeMD5(for: missingURL)
      XCTFail("Should have thrown CaasError.fileSystemError")
    } catch {
      guard case CaasError.fileSystemError = error else {
        XCTFail("Expected CaasError.fileSystemError, got \(error)")
        return
      }
    }
  }

  // MARK: - Validate MD5

  func testValidateMD5_succeedsOnMatchingHash_caseInsensitive() async throws {
    let data = "Validated Content".data(using: .utf8)!
    let fileURL = try createTempFile(with: data)
    let expectedDigest = Insecure.MD5.hash(data: data).map { String(format: "%02hhx", $0) }.joined()

    // Test with uppercase expected string to verify case-insensitivity
    do {
      try await StreamingMD5Validator.validateMD5(for: fileURL, expectedMD5: expectedDigest.uppercased())
    } catch {
      XCTFail("validateMD5 should succeed on matching hash: \(error)")
    }
  }

  func testValidateMD5_throwsMismatchOnWrongHash() async throws {
    let data = "Validated Content".data(using: .utf8)!
    let fileURL = try createTempFile(with: data)

    do {
      try await StreamingMD5Validator.validateMD5(for: fileURL, expectedMD5: "00000000000000000000000000000000")
      XCTFail("Should have thrown CaasError.md5Mismatch")
    } catch {
      guard case CaasError.md5Mismatch(let expected, let actual) = error else {
        XCTFail("Expected CaasError.md5Mismatch, got \(error)")
        return
      }
      XCTAssertEqual(expected, "00000000000000000000000000000000")
      XCTAssertFalse(actual.isEmpty)
    }
  }
}
