//
//  MessageServiceTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-19.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

@MainActor
final class MessageServiceTests: XCTestCase {
  
  private var sut: MessageService!
  
  override func setUp() {
    super.setUp()
    sut = MessageService()
  }
  
  override func tearDown() {
    sut = nil
    super.tearDown()
  }
  
  func testPostNewMessage() throws {
    // Given
    XCTAssertTrue(sut.messages.isEmpty)
    
    // When
    let message = AppMessage(
      title: "Test Network",
      detail: "Connection lost",
      severity: .error,
      category: .network,
      intent: .none,
      isDismissable: false
    )
    sut.post(message)
    
    // Then
    XCTAssertEqual(sut.messages.count, 1)
    
    let addedMessage = try XCTUnwrap(sut.messages.first)
    XCTAssertEqual(addedMessage.title, "Test Network")
    XCTAssertEqual(addedMessage.detail, "Connection lost")
    XCTAssertEqual(addedMessage.severity, .error)
    XCTAssertEqual(addedMessage.category, .network)
    XCTAssertEqual(addedMessage.intent, .none)
    XCTAssertFalse(addedMessage.isDismissable)
  }

  func testPostUpdatesExistingMessageAndMovesToTop() {
    // Given
    let messageId = UUID()
    let initialMessage = AppMessage(
      id: messageId,
      title: "Initial Title",
      detail: "Initial body",
      severity: .info,
      category: .system
    )
    sut.post(initialMessage)
    
    // Add another message so the initial message shifts to index 1
    sut.post(AppMessage(title: "Another", detail: "Body", severity: .info, category: .weather))
    
    XCTAssertEqual(sut.messages.count, 2)
    XCTAssertEqual(sut.messages[1].id, messageId) // Initial message is now at index 1
    
    // When
    let updatedMessage = AppMessage(
      id: messageId,
      title: "Updated Title",
      detail: "Updated body",
      severity: .warning,
      category: .system,
      intent: .openSettings(target: .geoGarage),
      isDismissable: false
    )
    sut.post(updatedMessage)
    
    // Then
    XCTAssertEqual(sut.messages.count, 2)
    // The message should be promoted to index 0
    let messageInStore = sut.messages[0]
    XCTAssertEqual(messageInStore.id, messageId)
    XCTAssertEqual(messageInStore.title, "Updated Title")
    XCTAssertEqual(messageInStore.severity, .warning)
    XCTAssertEqual(messageInStore.intent, .openSettings(target: .geoGarage))
    XCTAssertFalse(messageInStore.isDismissable)
  }
  

  
  func testPostExceedsMaxMessageCount() {
    // Given
    let firstMessage = AppMessage(title: "First", detail: "First message", severity: .info, category: .system)
    sut.post(firstMessage)
    
    // When
    for i in 1...50 {
      sut.post(AppMessage(title: "Msg \(i)", detail: "Body \(i)", severity: .info, category: .system))
    }
    
    // Then
    XCTAssertEqual(sut.messages.count, 50)
    XCTAssertFalse(sut.messages.contains(where: { $0.id == firstMessage.id }))
  }
  
  func testMaxMessageCountProtectsNonDismissableMessages() {
    // Given
    let criticalMessage = AppMessage(
      title: "Critical",
      detail: "Do not evict",
      severity: .error,
      category: .system,
      isDismissable: false
    )
    sut.post(criticalMessage)
    
    // When: Add 50 info messages (dismissable)
    for i in 1...50 {
      sut.post(AppMessage(title: "Msg \(i)", detail: "Body \(i)", severity: .info, category: .system, isDismissable: true))
    }
    
    // Then: The oldest message (the critical one) must NOT be evicted.
    // Instead, the oldest info message must be evicted.
    // Total count remains 50.
    XCTAssertEqual(sut.messages.count, 50)
    XCTAssertTrue(sut.messages.contains(where: { $0.id == criticalMessage.id }))
    
    // When 2: Flood with 100 critical errors
    for i in 1...100 {
      sut.post(AppMessage(title: "Crit \(i)", detail: "Body \(i)", severity: .error, category: .system, isDismissable: false))
    }
    
    // Then 2:
    // The first 49 new critical messages will evict the remaining 49 info messages.
    // The next 51 critical messages will exceed the limit because nothing is dismissable.
    // Total should be 101 (1 original + 100 new).
    XCTAssertEqual(sut.messages.count, 101)
    XCTAssertTrue(sut.messages.contains(where: { $0.id == criticalMessage.id }))
  }


  
  func testListMessagesReflectsAdditionsInLIFO() {
    // Given
    sut.post(AppMessage(title: "Msg 1", detail: "Body 1", severity: .info, category: .weather))
    sut.post(AppMessage(title: "Msg 2", detail: "Body 2", severity: .warning, category: .anchor))
    
    // Then (LIFO: Msg 2 is first, Msg 1 is second)
    XCTAssertEqual(sut.messages.count, 2)
    XCTAssertEqual(sut.messages[0].title, "Msg 2")
    XCTAssertEqual(sut.messages[1].title, "Msg 1")
  }
  
  func testRemoveMessageByUUID() {
    // Given
    sut.post(AppMessage(title: "Msg to remove", detail: "Body", severity: .info, category: .network))
    sut.post(AppMessage(title: "Msg to keep", detail: "Body", severity: .info, category: .network))
    
    XCTAssertEqual(sut.messages.count, 2)
    let messageToRemove = sut.messages[1] // Msg to remove is now at index 1 due to LIFO
    let messageToKeep = sut.messages[0]   // Msg to keep is at index 0
    
    // When
    sut.removeMessage(id: messageToRemove.id)
    
    // Then
    XCTAssertEqual(sut.messages.count, 1)
    XCTAssertEqual(sut.messages.first?.id, messageToKeep.id)
  }
  
  func testClearByCategory() {
    // Given
    sut.post(AppMessage(title: "Net 1", detail: "Body", severity: .info, category: .network))
    sut.post(AppMessage(title: "Weather 1", detail: "Body", severity: .info, category: .weather))
    sut.post(AppMessage(title: "Net 2", detail: "Body", severity: .info, category: .network))
    
    XCTAssertEqual(sut.messages.count, 3)
    
    // When
    sut.clear(category: .network)
    
    // Then
    XCTAssertEqual(sut.messages.count, 1)
    XCTAssertEqual(sut.messages.first?.category, .weather)
  }
  

  
  func testUpdateMessagePutsItAtTheTop() {
    let msg1 = AppMessage(title: "Msg1", detail: "Detail1", severity: .info, category: .system)
    let msg2 = AppMessage(title: "Msg2", detail: "Detail2", severity: .info, category: .system)
    sut.post(msg1)
    sut.post(msg2)
    
    XCTAssertEqual(sut.messages.first?.id, msg2.id)
    
    let msg1Updated = AppMessage(id: msg1.id, title: "Msg1", detail: "Detail1 Updated", severity: .info, category: .system)
    sut.post(msg1Updated)
    
    XCTAssertEqual(sut.messages.first?.id, msg1.id)
    XCTAssertEqual(sut.messages.first?.detail, "Detail1 Updated")
  }
  
  func testSeverityComparison() {
    // Then
    XCTAssertTrue(AppMessageSeverity.info < AppMessageSeverity.warning)
    XCTAssertTrue(AppMessageSeverity.warning < AppMessageSeverity.error)
    XCTAssertTrue(AppMessageSeverity.info < AppMessageSeverity.error)
    XCTAssertFalse(AppMessageSeverity.error < AppMessageSeverity.warning)
  }
}
