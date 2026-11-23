//
//  LegalDocument.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Lightweight, stable identifier for legal documents used in `CommandDestination`
/// so navigation paths remain small, `Hashable`, and `Sendable` without carrying document text.
public enum LegalDocumentID: String, CaseIterable, Hashable, Sendable {
  case navigationWarning
  case sillageLicense
  case mapLibre
  case openSeaMap
  case geoGarage
  case grdb
  case swiftClocks
  case swiftConcurrencyExtras
  case xctestDynamicOverlay
}

struct LegalDocument: Identifiable, Sendable {
  let id: LegalDocumentID
  let title: LocalizedStringResource
  let content: String?
  let filename: String?
  let fileExtension: String?

  init(
    id: LegalDocumentID,
    title: LocalizedStringResource,
    content: String? = nil,
    filename: String? = nil,
    fileExtension: String? = nil
  ) {
    self.id = id
    self.title = title
    self.content = content
    self.filename = filename
    self.fileExtension = fileExtension
  }

  static let thirdPartyDocumentIDs: [LegalDocumentID] = [
    .mapLibre,
    .openSeaMap,
    .geoGarage,
    .grdb,
    .swiftClocks,
    .swiftConcurrencyExtras,
    .xctestDynamicOverlay,
  ]

  static func document(for id: LegalDocumentID) -> LegalDocument {
    switch id {
    case .navigationWarning:
      LegalDocument(
        id: .navigationWarning,
        title: "Maritime Navigation Warning",
        content: String(localized: "WARNING: \(AppConstants.appName) is an electronic navigational aid designed for situational awareness only. It must not be used as the primary means of navigation. This application does not replace official government charts, official notices to mariners, or prudent seamanship. The captain of the vessel assumes all responsibility and liability for the safety of the ship and its crew. Never rely on a single source of information and always maintain a proper visual lookout.")
      )
    case .sillageLicense:
      LegalDocument(
        id: .sillageLicense,
        title: "\(AppConstants.appName) (MIT License)",
        filename: "License_MIT",
        fileExtension: "txt"
      )
    case .mapLibre:
      LegalDocument(
        id: .mapLibre,
        title: "MapLibre GL Native (BSD 2-Clause License)",
        filename: "License_MapLibre",
        fileExtension: "txt"
      )
    case .openSeaMap:
      LegalDocument(
        id: .openSeaMap,
        title: "OpenSeaMap (ODbL)",
        filename: "License_OpenSeaMap",
        fileExtension: "txt"
      )
    case .geoGarage:
      LegalDocument(
        id: .geoGarage,
        title: "GeoGarage Terms of Use",
        filename: "License_GeoGarage",
        fileExtension: "txt"
      )
    case .grdb:
      LegalDocument(
        id: .grdb,
        title: "GRDB",
        filename: "License_GRDB",
        fileExtension: "txt"
      )
    case .swiftClocks:
      LegalDocument(
        id: .swiftClocks,
        title: "swift-clocks",
        filename: "License_swift-clocks",
        fileExtension: "txt"
      )
    case .swiftConcurrencyExtras:
      LegalDocument(
        id: .swiftConcurrencyExtras,
        title: "swift-concurrency-extras",
        filename: "License_swift-concurrency-extras",
        fileExtension: "txt"
      )
    case .xctestDynamicOverlay:
      LegalDocument(
        id: .xctestDynamicOverlay,
        title: "xctest-dynamic-overlay",
        filename: "License_xctest-dynamic-overlay",
        fileExtension: "txt"
      )
    }
  }
}
