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
import OSLog

@MainActor
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

  weak var chartDownloader: GeoGarageChartDownloader? {
    didSet {
      if let pending = pendingBackgroundCompletion {
        chartDownloader?.setBackgroundCompletionHandler(pending)
        pendingBackgroundCompletion = nil
      }
    }
  }

  private var pendingBackgroundCompletion: (@MainActor () -> Void)?

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    // Registers TileProxyProtocol globally (URLSession.shared / NSURLConnection) as a fallback
    // alongside the explicit MLNNetworkConfiguration.sessionConfiguration injection in AppEnvironment.
    // TileProxyProtocol.canInit(with:) strictly filters for "tiles.geogarage.com" and skips
    // requests already tagged by TileProxyManager.
    URLProtocol.registerClass(TileProxyProtocol.self)

    // Critical: The delegate must be assigned before the app finishes launching
    // so that iOS knows how to route foreground notifications.
    UNUserNotificationCenter.current().delegate = self
    return true
  }

  // MARK: - Background URLSession Events

  func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    Logger.caas.info("AppDelegate: handleEventsForBackgroundURLSession for \(identifier, privacy: .public)")
    if identifier == GeoGarageChartDownloader.backgroundSessionIdentifier {
      let mainActorCompletion: @MainActor () -> Void = {
        completionHandler()
      }
      if let chartDownloader {
        chartDownloader.setBackgroundCompletionHandler(mainActorCompletion)
      } else {
        pendingBackgroundCompletion = mainActorCompletion
      }
    } else {
      completionHandler()
    }
  }

  // Ensures the notification banner and sound trigger even if the app is currently open and active on the screen.
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound, .badge]
  }

  // Handles the user tapping on a notification or pressing an action button
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let identifier = response.notification.request.identifier
    let actionIdentifier = response.actionIdentifier
    let targetIdentifier = (actionIdentifier != UNNotificationDefaultActionIdentifier && actionIdentifier != UNNotificationDismissActionIdentifier) ? actionIdentifier : identifier

    await MainActor.run { [weak self] in
      guard let self = self else { return }
      if let appViewModel = self.appViewModel {
        appViewModel.handleNotification(identifier: targetIdentifier)
      } else {
        self.pendingNotificationID = targetIdentifier
      }
    }
  }
}
