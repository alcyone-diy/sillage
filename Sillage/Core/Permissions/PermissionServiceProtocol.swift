//
//  PermissionServiceProtocol.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-06.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

@MainActor
public protocol PermissionServiceProtocol: AnyObject {
    var locationStatus: PermissionStatus { get }
    var notificationStatus: PermissionStatus { get }
    var motionStatus: PermissionStatus { get }
    
    func requestLocationAuthorization() async
    func requestNotificationAuthorization() async -> Bool
    func requestCriticalNotificationAuthorization() async -> Bool
    func requestMotionAuthorization() async
    func openSystemSettings()
}
