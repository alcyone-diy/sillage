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

  static var isRunningUnitTests: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  }

  private var pendingNotificationID: String?
  private var backingEnvironment: AppEnvironment?

  /// Single source of truth for `AppEnvironment`, owned by `AppDelegate` so headless background
  /// wake-ups (e.g. `handleEventsForBackgroundURLSession`, notification actions, CoreLocation)
  /// always have a live environment without relying on SwiftUI view mounting.
  /// Allocated lazily so unit test host launches never instantiate `AppEnvironment` unless accessed.
  var environment: AppEnvironment {
    if let backingEnvironment {
      return backingEnvironment
    }
    let created = AppEnvironment()
    backingEnvironment = created
    return created
  }

  override init() {
    super.init()
  }

  init(environment: AppEnvironment) {
    self.backingEnvironment = environment
    super.init()
  }

  func startOrRetryBootstrap() {
    Task { @MainActor [weak self] in
      await self?.bootstrapEnvironmentAndDrainNotifications()
    }
  }

  func bootstrapEnvironmentAndDrainNotifications() async {
    await environment.bootstrap()
    if case .ready(let container) = environment.state,
       let pendingID = pendingNotificationID {
      pendingNotificationID = nil
      container.appViewModel.handleNotification(identifier: pendingID)
    }
  }

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

    if !Self.isRunningUnitTests {
      startOrRetryBootstrap()
    }
    return true
  }

  func applicationWillTerminate(_ application: UIApplication) {
    guard !Self.isRunningUnitTests else { return }
    // Handle termination synchronously on MainActor: iOS kills the process immediately once
    // willTerminate returns, so async notification sequences would be cut off before executing.
    performTerminationWarning()
  }

  private func performTerminationWarning() {
    Logger.system.info("performTerminationWarning called.")
    guard let backingEnvironment, case .ready(let container) = backingEnvironment.state else { return }
    let trackService = container.trackRecordingService
    let isTracking: Bool = {
      switch trackService.state {
      case .recording, .paused, .waitingForFix: return true
      case .idle, .saving: return false
      }
    }()

    let isAnchoring = container.anchorViewModel.status != .inactive

    if isTracking || isAnchoring {
      let permissionService = container.permissionService
      let isCriticalAuthorized = permissionService.criticalAlertStatus == .enabled
      // Require explicit `.enabled` so `.unknown` during early app termination never sends an unauthorized `.timeSensitive` alert.
      let isTimeSensitiveAuthorized = permissionService.timeSensitiveStatus == .enabled
      let content = LocalNotificationService.makeNotificationContent(
        title: String(localized: "Sillage Terminated"),
        body: String(localized: "The application has been closed by iOS. Active services (like tracking or anchor watch) have been stopped."),
        identifier: NotificationIntent.appTerminated.rawValue,
        isCritical: true,
        isCriticalAuthorized: isCriticalAuthorized,
        isTimeSensitiveAuthorized: isTimeSensitiveAuthorized
      )

      // Note: This XPC call to UNUserNotificationCenter suffers from a race condition
      // during a crash or OOM kill (willTerminate is not even called for OOM).
      // This is a "Best Effort" for explicit user force-quits.
      let request = UNNotificationRequest(identifier: NotificationIntent.appTerminated.rawValue, content: content, trigger: nil)
      UNUserNotificationCenter.current().add(request) { error in
        if let error = error {
          Logger.system.error("Failed to send termination warning: \(error.localizedDescription, privacy: .public)")
        } else {
          Logger.system.info("Termination warning notification sent.")
        }
      }
    }
  }

  // MARK: - Background URLSession Events

  func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    Logger.caas.info("AppDelegate: handleEventsForBackgroundURLSession for \(identifier, privacy: .public)")
    let mainActorCompletion: @MainActor () -> Void = {
      completionHandler()
    }
    if identifier == GeoGarageChartDownloader.backgroundSessionIdentifier {
      environment.registerBackgroundURLSessionCompletionHandler(mainActorCompletion)
    } else {
      Logger.caas.warning("AppDelegate: Unrecognized background URLSession identifier \(identifier, privacy: .public); invoking completion handler immediately.")
      mainActorCompletion()
    }
  }

  // Ensures the notification banner and sound trigger even if the app is currently open and active on the screen.
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound, .badge]
  }

  func routeNotificationIdentifier(_ targetIdentifier: String) {
    if case .ready(let container) = environment.state {
      container.appViewModel.handleNotification(identifier: targetIdentifier)
    } else {
      pendingNotificationID = targetIdentifier
    }
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
      self?.routeNotificationIdentifier(targetIdentifier)
    }
  }
}
