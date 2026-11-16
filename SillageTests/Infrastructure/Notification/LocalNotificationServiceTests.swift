//
//  LocalNotificationServiceTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-15.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import UserNotifications
@testable import Sillage

@MainActor
final class LocalNotificationServiceTests: XCTestCase {

  func testNotificationCategories_silenceActionIsDestructiveWithoutAuthenticationRequired() {
    let categories = LocalNotificationService.notificationCategories()
    let draggingCategory = categories.first { $0.identifier == NotificationIntent.anchorDragging.rawValue }

    XCTAssertNotNil(draggingCategory)
    let silenceAction = draggingCategory?.actions.first { $0.identifier == NotificationIntent.anchorActionSilence.rawValue }
    XCTAssertNotNil(silenceAction)
    XCTAssertTrue(silenceAction?.options.contains(.destructive) == true)
    XCTAssertFalse(silenceAction?.options.contains(.authenticationRequired) == true)
  }

  func testMakeNotificationContent_criticalAnchorDragging_usesCriticalInterruptionAndCustomSoundWhenAuthorized() {
    let content = LocalNotificationService.makeNotificationContent(
      title: "Dragging",
      body: "Out of radius",
      identifier: NotificationIntent.anchorDragging.rawValue,
      isCritical: true,
      isCriticalAuthorized: true,
      isTimeSensitiveAuthorized: true
    )

    XCTAssertEqual(content.categoryIdentifier, NotificationIntent.anchorDragging.rawValue)
    XCTAssertEqual(content.interruptionLevel, .critical)
    XCTAssertEqual(
      content.sound,
      UNNotificationSound.criticalSoundNamed(
        UNNotificationSoundName("AnchorAlarm_CleanEscalation_27s.wav"),
        withAudioVolume: 1.0
      )
    )
  }

  func testMakeNotificationContent_criticalAnchorDragging_fallsBackToTimeSensitiveWhenCriticalUnavailable() {
    let content = LocalNotificationService.makeNotificationContent(
      title: "Dragging",
      body: "Out of radius",
      identifier: NotificationIntent.anchorDragging.rawValue,
      isCritical: true,
      isCriticalAuthorized: false,
      isTimeSensitiveAuthorized: true
    )

    XCTAssertEqual(content.interruptionLevel, .timeSensitive)
    XCTAssertEqual(content.sound, UNNotificationSound(named: UNNotificationSoundName("AnchorAlarm_CleanEscalation_27s.wav")))
  }

  func testMakeNotificationContent_appTerminated_usesTimeSensitiveWhenCriticalUnavailable() {
    let content = LocalNotificationService.makeNotificationContent(
      title: "Sillage Terminated",
      body: "Stopped",
      identifier: NotificationIntent.appTerminated.rawValue,
      isCritical: true,
      isCriticalAuthorized: false,
      isTimeSensitiveAuthorized: true
    )

    XCTAssertEqual(content.interruptionLevel, .timeSensitive)
    XCTAssertEqual(content.sound, UNNotificationSound.default)
  }

  func testMakeNotificationContent_fallsBackToActiveWhenNeitherCriticalNorTimeSensitiveEnabled() {
    let content = LocalNotificationService.makeNotificationContent(
      title: "GPS Degraded",
      body: "Low accuracy",
      identifier: NotificationIntent.anchorGPSDegraded.rawValue,
      isCritical: true,
      isCriticalAuthorized: false,
      isTimeSensitiveAuthorized: false
    )

    XCTAssertEqual(content.interruptionLevel, .active)
    XCTAssertEqual(content.sound, UNNotificationSound.default)
  }

  func testMakeNotificationContent_standardNotification_usesActiveInterruptionLevel() {
    let content = LocalNotificationService.makeNotificationContent(
      title: "Weather",
      body: "Pressure drop",
      identifier: NotificationIntent.barometerDrop.rawValue,
      isCritical: false,
      isCriticalAuthorized: true,
      isTimeSensitiveAuthorized: true
    )

    XCTAssertEqual(content.interruptionLevel, .active)
    XCTAssertEqual(content.sound, UNNotificationSound.default)
  }
}
