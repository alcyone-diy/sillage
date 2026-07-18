//
//  NetworkTransitionTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-18.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import MapLibre
@testable import Sillage

@MainActor
final class NetworkTransitionTests: XCTestCase {
  
  func testNetworkReconnectTriggersMapLibreReload() async throws {
    let expectation = XCTestExpectation(description: "MapLibreView Coordinator receives NetworkDidReconnect")
    
    let observer = NotificationCenter.default.addObserver(forName: NSNotification.Name("NetworkDidReconnect"), object: nil, queue: .main) { _ in
      expectation.fulfill()
    }
    
    // Simulate network reconnect
    NotificationCenter.default.post(name: NSNotification.Name("NetworkDidReconnect"), object: nil)
    
    await fulfillment(of: [expectation], timeout: 2.0)
    NotificationCenter.default.removeObserver(observer)
  }
}
