//
//  AppBootstrapInfrastructureTests.swift
//  SillageTests
//
//  Created by Alcyone on 2026-11-26.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Testing
@testable import Sillage

@Suite("AppBootstrapInfrastructure")
struct AppBootstrapInfrastructureTests {

  private final class DummyURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { false }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
  }

  private func makeIsolatedDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("AppBootstrapInfraTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test("prepareChartsDirectory and writeReadMeIfMissing create Charts folder and preserve existing ReadMe")
  func prepareChartsAndReadMeInIsolatedTempDir() throws {
    let fm = FileManager.default
    let rootDir = try makeIsolatedDirectory()
    defer { try? fm.removeItem(at: rootDir) }

    try AppBootstrapInfrastructure.prepareChartsDirectory(in: rootDir, fileManager: fm)
    let chartsURL = rootDir.appendingPathComponent("Charts", isDirectory: true)
    var isDir: ObjCBool = false
    #expect(fm.fileExists(atPath: chartsURL.path, isDirectory: &isDir))
    #expect(isDir.boolValue == true)

    // Calling a second time is idempotent.
    try AppBootstrapInfrastructure.prepareChartsDirectory(in: rootDir, fileManager: fm)
    #expect(fm.fileExists(atPath: chartsURL.path))

    let readmeURL = rootDir.appendingPathComponent("\(AppConstants.appName)_ReadMe.txt")
    AppBootstrapInfrastructure.writeReadMeIfMissing(at: readmeURL, fileManager: fm)
    let generatedContent = try String(contentsOf: readmeURL, encoding: .utf8)
    #expect(generatedContent.contains("Charts"))

    // Existing ReadMe must not be overwritten.
    try "custom-note".write(to: readmeURL, atomically: true, encoding: .utf8)
    AppBootstrapInfrastructure.writeReadMeIfMissing(at: readmeURL, fileManager: fm)
    let preservedContent = try String(contentsOf: readmeURL, encoding: .utf8)
    #expect(preservedContent == "custom-note")
  }

  @Test("removeGPXExportsDirectoryIfPresent removes GPXExports without touching sibling files")
  func removeGPXExportsDirectoryInIsolatedTempDir() throws {
    let fm = FileManager.default
    let tempRoot = try makeIsolatedDirectory()
    defer { try? fm.removeItem(at: tempRoot) }

    let gpxExportsDir = tempRoot.appendingPathComponent("GPXExports", isDirectory: true)
    try fm.createDirectory(at: gpxExportsDir, withIntermediateDirectories: true)
    let exportedFile = gpxExportsDir.appendingPathComponent("track.gpx")
    try "<gpx/>".write(to: exportedFile, atomically: true, encoding: .utf8)

    let siblingFile = tempRoot.appendingPathComponent("keep_me.txt")
    try "keep".write(to: siblingFile, atomically: true, encoding: .utf8)

    AppBootstrapInfrastructure.removeGPXExportsDirectoryIfPresent(in: tempRoot, fileManager: fm)

    #expect(fm.fileExists(atPath: gpxExportsDir.path) == false)
    #expect(fm.fileExists(atPath: siblingFile.path) == true)

    // Calling again when absent is a safe no-op.
    AppBootstrapInfrastructure.removeGPXExportsDirectoryIfPresent(in: tempRoot, fileManager: fm)
  }

  @Test("registerTileProxyProtocol inserts TileProxyProtocol at index 0 idempotently")
  func registerTileProxyProtocolIdempotency() {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [DummyURLProtocol.self]

    AppBootstrapInfrastructure.registerTileProxyProtocol(in: config)
    #expect(config.protocolClasses?.first == TileProxyProtocol.self)
    #expect(config.protocolClasses?.contains(where: { $0 == DummyURLProtocol.self }) == true)
    let countAfterFirst = config.protocolClasses?.filter { $0 == TileProxyProtocol.self }.count
    #expect(countAfterFirst == 1)

    // Second registration must not duplicate TileProxyProtocol.
    AppBootstrapInfrastructure.registerTileProxyProtocol(in: config)
    let countAfterSecond = config.protocolClasses?.filter { $0 == TileProxyProtocol.self }.count
    #expect(countAfterSecond == 1)
    #expect(config.protocolClasses?.first == TileProxyProtocol.self)
  }
}
