//
//  MarineIcon.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-01.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

enum MarineIcon: String {
    // Entities
    case waypoint = "mappin.and.ellipse"
    case track = "point.topleft.down.curvedto.point.bottomright.up"
    case instruments = "barometer"
    case anchorAlarm = "location.viewfinder"
    case settings = "gearshape.fill"
    case offlineChart = "square.and.arrow.down.on.square"
    
    // Actions
    case add = "plus"
    case save = "checkmark"
    case close = "xmark"
    case delete = "trash"
    case edit = "pencil"
    case details = "info.circle"
    case share = "square.and.arrow.up"
    case menu = "line.3.horizontal"
    case record = "record.circle"
    
    // UI Elements
    case select = "checkmark.circle"
    case deselect = "xmark.circle"
    case cancelAction = "xmark.circle.fill"
    
    // Status
    case warning = "exclamationmark.triangle"
    case warningFill = "exclamationmark.triangle.fill"
    
    // Modes
    case gloveMode = "hand.raised.fill"
    
    // Tracking
    case trackingFree = "location"
    case trackingNorthUp = "location.fill"
    case trackingCourseUp = "location.north.line.fill"
}

extension Image {
    /// Initializes an image from the marine design system.
    init(marineIcon: MarineIcon) {
        // Anticipation : Si certaines icônes deviennent des assets custom (SVG) plus tard
        // on modifiera cette logique sans toucher au reste de l'application.
        self.init(systemName: marineIcon.rawValue)
    }
}
