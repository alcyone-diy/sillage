//
//  NotificationIntent.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

public enum NotificationIntent: String {
    case barometerDrop = "sillage.barometer.drop"
    case anchorDragging = "sillage.anchor.dragging"
    case anchorGPSDegraded = "sillage.anchor.gps_degraded"
    case appTerminated = "sillage.app.terminated"
    case anchorActionSilence = "sillage.anchor.action.silence"
}

