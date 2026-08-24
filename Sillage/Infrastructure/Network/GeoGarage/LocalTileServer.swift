//
//  LocalTileServer.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-16.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Network
import OSLog
import os

/// Minimal, high-performance local HTTP tile server using Network.framework.
/// Binds to loopback `127.0.0.1` on a dynamic TCP port, queries `SQLCipherMBTilesReaderProtocol` in RAM,
/// and serves MapLibre with strict connection closure (no Keep-Alive, zero socket leaks).
actor LocalTileServer: LocalTileServerProtocol {

  private var listener: NWListener?
  private let reader: SQLCipherMBTilesReaderProtocol
  private let preferredPort: UInt16?
  private var boundPort: UInt16?

  init(
    reader: SQLCipherMBTilesReaderProtocol,
    port: UInt16? = nil
  ) {
    self.reader = reader
    self.preferredPort = port
  }

  deinit {
    listener?.cancel()
  }

  // MARK: - Start

  func start() async throws -> UInt16 {
    if let boundPort {
      return boundPort
    }

    let port: NWEndpoint.Port
    if let preferred = preferredPort, let specifiedPort = NWEndpoint.Port(rawValue: preferred) {
      port = specifiedPort
    } else {
      port = .any
    }

    let tcpOptions = NWProtocolTCP.Options()
    tcpOptions.noDelay = true

    let parameters = NWParameters(tls: nil, tcp: tcpOptions)
    parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: port)
    parameters.allowLocalEndpointReuse = true

    let listener = try NWListener(using: parameters)

    return try await withCheckedThrowingContinuation { continuation in
      let continuationState = OSAllocatedUnfairLock<CheckedContinuation<UInt16, any Error>?>(initialState: continuation)

      listener.stateUpdateHandler = { [weak self] state in
        guard let self else { return }
        switch state {
        case .ready:
          if let localPort = listener.port?.rawValue {
            let pendingContinuation = continuationState.withLock { cont in
              let c = cont
              cont = nil
              return c
            }
            Task {
              await self.setBoundPort(localPort)
              pendingContinuation?.resume(returning: localPort)
            }
          }
        case .failed(let error):
          Logger.caas.error("LocalTileServer listener failed: \(error.localizedDescription, privacy: .public)")
          let pendingContinuation = continuationState.withLock { cont in
            let c = cont
            cont = nil
            return c
          }
          pendingContinuation?.resume(throwing: error)
        case .cancelled:
          Logger.caas.info("LocalTileServer listener cancelled.")
        default:
          break
        }
      }

      listener.newConnectionHandler = { [weak self] connection in
        guard let self else { return }
        Task {
          await self.handleNewConnection(connection)
        }
      }

      self.listener = listener
      listener.start(queue: .global(qos: .userInteractive))
    }
  }

  private func setBoundPort(_ port: UInt16) {
    self.boundPort = port
    Logger.caas.info("LocalTileServer started on http://127.0.0.1:\(port, privacy: .public)")
  }

  // MARK: - Stop

  func stop() async {
    listener?.cancel()
    listener = nil
    boundPort = nil
    await reader.close()
    Logger.caas.info("LocalTileServer stopped and reader closed.")
  }

  // MARK: - Connection Handling

  private func handleNewConnection(_ connection: NWConnection) {
    connection.start(queue: .global(qos: .userInteractive))

    connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self] content, _, _, error in
      guard let self else {
        connection.cancel()
        return
      }

      if let error {
        Logger.caas.debug("LocalTileServer connection receive error: \(error.localizedDescription, privacy: .public)")
        connection.cancel()
        return
      }

      guard let content, let requestString = String(data: content, encoding: .utf8) else {
        self.sendNoContentAndClose(connection: connection)
        return
      }

      Task {
        await self.processHTTPRequest(requestString, connection: connection)
      }
    }
  }

  private func processHTTPRequest(_ requestString: String, connection: NWConnection) async {
    // Parse GET request line e.g. "GET /tiles/12/2048/1360 HTTP/1.1" or "GET /tiles/12/2048/1360.png"
    guard let firstLine = requestString.components(separatedBy: "\r\n").first,
          firstLine.hasPrefix("GET ") else {
      sendNoContentAndClose(connection: connection)
      return
    }

    let parts = firstLine.split(separator: " ")
    guard parts.count >= 2 else {
      sendNoContentAndClose(connection: connection)
      return
    }

    let path = String(parts[1])
    guard let coords = parseTileCoordinates(from: path) else {
      sendNoContentAndClose(connection: connection)
      return
    }

    guard let tileData = await reader.tile(z: coords.z, x: coords.x, y: coords.y), !tileData.isEmpty else {
      sendNoContentAndClose(connection: connection)
      return
    }

    sendTileDataAndClose(tileData, connection: connection)
  }

  // MARK: - Path Parsing

  private func parseTileCoordinates(from path: String) -> (z: Int, x: Int, y: Int)? {
    var cleanPath = path
    if let queryIndex = cleanPath.firstIndex(of: "?") {
      cleanPath = String(cleanPath[..<queryIndex])
    }
    if cleanPath.hasSuffix(".png") || cleanPath.hasSuffix(".jpg") || cleanPath.hasSuffix(".jpeg") {
      cleanPath = (cleanPath as NSString).deletingPathExtension
    }

    let segments = cleanPath.split(separator: "/").map { String($0) }
    let numericSegments = segments.filter { Int($0) != nil }
    guard numericSegments.count >= 3,
          let z = Int(numericSegments[numericSegments.count - 3]),
          let x = Int(numericSegments[numericSegments.count - 2]),
          let y = Int(numericSegments[numericSegments.count - 1]) else {
      return nil
    }

    return (z, x, y)
  }

  // MARK: - Response Senders

  private nonisolated func sendTileDataAndClose(_ data: Data, connection: NWConnection) {
    let header = "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
    guard let headerData = header.data(using: .utf8) else {
      connection.cancel()
      return
    }

    var fullPayload = headerData
    fullPayload.append(data)

    connection.send(content: fullPayload, completion: .contentProcessed { _ in
      connection.cancel()
    })
  }

  private nonisolated func sendNoContentAndClose(connection: NWConnection) {
    let response = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    let data = response.data(using: .utf8)
    connection.send(content: data, completion: .contentProcessed { _ in
      connection.cancel()
    })
  }
}
