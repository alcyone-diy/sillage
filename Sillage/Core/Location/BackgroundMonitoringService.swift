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

@MainActor
public protocol BackgroundMonitoringToken: AnyObject {
    /// Stops the session: releases background GPS and removes distance filters.
    func invalidate()
}

@MainActor
public protocol BackgroundMonitoringService {
    /// Starts a monitoring session with a distance filter.
    func startMonitoring(
        ownerIdentifier: String,
        distanceFilter: Measurement<UnitLength>
    ) -> any BackgroundMonitoringToken
}
