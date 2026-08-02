//
//  BackgroundMonitoringService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

public struct WatchdogConfiguration: Sendable {
    public let identifier: String
    public let title: String
    public let body: String
    public let timeout: TimeInterval
    
    public init(identifier: String, title: String, body: String, timeout: TimeInterval) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.timeout = timeout
    }
}

@MainActor
public protocol BackgroundMonitoringToken: AnyObject {
    /// Stoppe la session : libère le GPS en arrière-plan, retire les filtres de distance et annule le watchdog.
    func invalidate()
}

@MainActor
public protocol BackgroundMonitoringService {
    /// Démarre une session de monitoring avec un filtre de distance et un Watchdog optionnel.
    func startMonitoring(
        ownerIdentifier: String,
        distanceFilter: Measurement<UnitLength>,
        watchdog: WatchdogConfiguration?
    ) -> any BackgroundMonitoringToken
}
