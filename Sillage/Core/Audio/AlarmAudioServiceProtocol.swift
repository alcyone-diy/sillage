//
//  AlarmAudioServiceProtocol.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-07.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Cross-cutting port governing progressive anchor alarm audio playback and session pre-warming.
@MainActor
public protocol AlarmAudioServiceProtocol: AnyObject, Sendable {
  func prepareAudioSession()
  func startSiren()
  func stopSiren()
}
