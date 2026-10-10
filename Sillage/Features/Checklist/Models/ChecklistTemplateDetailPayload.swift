//
//  ChecklistTemplateDetailPayload.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-10.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Encapsulates navigation parameters for inspecting, executing, or editing a checklist template.
///
/// Payload identity (`Equatable` and `Hashable`) is defined exclusively by `templateId` and `startEditable`.
/// The optional `template` snapshot acts solely as transient fast-path data to eliminate initial UI latency,
/// ensuring that in-memory mutations do not alter the navigation stack identity in SwiftUI.
public struct ChecklistTemplateDetailPayload: Hashable, Sendable {
  public let templateId: UUID?
  public let template: ChecklistTemplate?
  public let startEditable: Bool

  public init(
    templateId: UUID? = nil,
    template: ChecklistTemplate? = nil,
    startEditable: Bool = false
  ) {
    self.templateId = templateId ?? template?.id
    self.template = template
    self.startEditable = startEditable
  }

  public init(_ template: ChecklistTemplate, startEditable: Bool = false) {
    self.templateId = template.id
    self.template = template
    self.startEditable = startEditable
  }

  public static func == (lhs: ChecklistTemplateDetailPayload, rhs: ChecklistTemplateDetailPayload) -> Bool {
    lhs.templateId == rhs.templateId && lhs.startEditable == rhs.startEditable
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(templateId)
    hasher.combine(startEditable)
  }
}
