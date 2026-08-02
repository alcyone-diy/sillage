//
//  AppDelegate.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import UIKit
import UserNotifications
import MapLibre

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    private var pendingNotificationID: String?
    
    weak var appViewModel: AppViewModel? {
        didSet {
            if let pendingID = pendingNotificationID {
                Task { @MainActor [weak self] in
                    self?.appViewModel?.handleNotification(identifier: pendingID)
                }
                self.pendingNotificationID = nil
            }
        }
    }
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        // CRITICAL FIX: MapLibre's C++ core (mbgl::HTTPFileSource) hardcodes 
        // [NSURLSessionConfiguration defaultSessionConfiguration] and ignores MLNNetworkConfiguration.
        // Therefore, URLProtocol.registerClass is MANDATORY for custom schemes.
        // This does NOT pollute the app's global networking because canInit(with:) strictly
        // filters for "sillage-geo" schemes, letting regular http/https pass through instantly.
        URLProtocol.registerClass(TileProxyProtocol.self)
        
        // Critical: The delegate must be assigned before the app finishes launching
        // so that iOS knows how to route foreground notifications.
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    
    // Ensures the notification banner and sound trigger even if the app is currently open and active on the screen.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }
    
    // Handles the user tapping on a notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        
        if let appViewModel = self.appViewModel {
            Task { @MainActor in
                appViewModel.handleNotification(identifier: identifier)
            }
        } else {
            self.pendingNotificationID = identifier
        }
        
        completionHandler()
    }
}
