//
//  ChecklistSeeder.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import GRDB
import OSLog

/// Seeds essential built-in maritime checklist templates into the database.
public struct ChecklistSeeder: Sendable {
  nonisolated public static let defaultCategoriesSeedKey = "default_categories"
  nonisolated public static let defaultTemplatesSeedKey = "default_templates"

  nonisolated public static var initialCategories: [(id: String, name: String, icon: String?, sortOrder: Int)] {
    [
      ("safety_emergency", String(localized: "Safety & Emergency"), "exclamationmark.shield.fill", 0),
      ("navigation_maneuver", String(localized: "Navigation & Maneuver"), "steeringwheel", 1),
      ("routine", String(localized: "Routine"), "checklist", 2),
      ("engine_technical", String(localized: "Engine & Technical"), "wrench.and.screwdriver.fill", 3),
      ("wintering_maintenance", String(localized: "Wintering & Maintenance"), "snowflake", 4)
    ]
  }

  nonisolated public static func seedDefaultCategoriesIfNeeded(in db: Database) throws {
    let alreadySeeded = try Row.fetchOne(
      db,
      sql: "SELECT 1 FROM checklist_seeding_state WHERE id = ?",
      arguments: [defaultCategoriesSeedKey]
    ) != nil

    guard !alreadySeeded else {
      return
    }

    try seedDefaultCategories(in: db)
    try db.execute(
      sql: "INSERT OR IGNORE INTO checklist_seeding_state (id, seeded_at) VALUES (?, ?)",
      arguments: [defaultCategoriesSeedKey, Date()]
    )
  }

  nonisolated public static func seedDefaultCategories(in db: Database) throws {
    let now = Date()
    for category in initialCategories {
      try db.execute(
        sql: """
        INSERT OR IGNORE INTO \(ChecklistCategoryRecord.databaseTableName) (id, name, icon, sort_order, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        arguments: [category.id, category.name, category.icon, category.sortOrder, now, now]
      )
    }
  }

  nonisolated public static func seedDefaultTemplatesIfNeeded(in db: Database) throws {
    try seedDefaultCategoriesIfNeeded(in: db)

    let alreadySeeded = try Row.fetchOne(
      db,
      sql: "SELECT 1 FROM checklist_seeding_state WHERE id = ?",
      arguments: [defaultTemplatesSeedKey]
    ) != nil

    guard !alreadySeeded else {
      return
    }

    let existingCategoryIds = try String.fetchAll(
      db,
      sql: "SELECT id FROM \(ChecklistCategoryRecord.databaseTableName) ORDER BY sort_order ASC, created_at ASC"
    )
    guard let fallbackCategoryId = existingCategoryIds.first else {
      Logger.checklist.warning("Skipping built-in checklist template seeding because no categories exist.")
      return
    }
    let existingCategorySet = Set(existingCategoryIds)
    let resolveCategoryId: (String) -> String = { preferredId in
      existingCategorySet.contains(preferredId) ? preferredId : fallbackCategoryId
    }

    Logger.checklist.info("Seeding built-in maritime checklists...")
    let now = Date()

    // 1. Pre-Departure Procedure
    let departureId = UUID()
    let departureTemplate = ChecklistTemplateRecord(
      id: departureId.uuidString,
      title: String(localized: "Pre-Departure Checklist"),
      description: String(localized: "Essential vessel and crew safety checks before leaving the berth or mooring."),
      category_id: resolveCategoryId("routine"),
      sort_order: 0,
      created_at: now,
      updated_at: now
    )
    try departureTemplate.insert(db)

    let departureItems: [(String, String?)] = [
      (
        String(localized: "Weather & Tides"),
        String(localized: "Review coastal forecast, gale warnings, and tidal stream times.")
      ),
      (
        String(localized: "Hull & Seacocks"),
        String(localized: "Inspect bilge levels, verify through-hull valves and seacocks.")
      ),
      (
        String(localized: "Engine & Fluid Levels"),
        String(localized: "Check engine oil, coolant levels, and alternator belt tension.")
      ),
      (
        String(localized: "Engine Raw Water Intake"),
        String(localized: "Verify seawater cooling intake valve is open.")
      ),
      (
        String(localized: "Electrical & Battery Banks"),
        String(localized: "Check house and engine start battery voltages (> 12.4V).")
      ),
      (
        String(localized: "Navigation Lights & Electronics"),
        String(localized: "Test masthead, steaming, and port/starboard navigation lights.")
      ),
      (
        String(localized: "Safety Equipment & Lifejackets"),
        String(localized: "Verify PFDs/harnesses, flares, and VHF channel 16 radio.")
      ),
      (
        String(localized: "LPG & Galley Gas Shutoff"),
        String(localized: "Confirm galley gas isolation solenoid or valve is shut.")
      )
    ]
    try insertTemplateItems(departureItems, templateId: departureId, in: db)

    // 2. Anchoring Procedure
    let anchorId = UUID()
    let anchorTemplate = ChecklistTemplateRecord(
      id: anchorId.uuidString,
      title: String(localized: "Anchoring Checklist"),
      description: String(localized: "Standard anchoring procedure and safety radius verification."),
      category_id: resolveCategoryId("navigation_maneuver"),
      sort_order: 1,
      created_at: now,
      updated_at: now
    )
    try anchorTemplate.insert(db)

    let anchorItems: [(String, String?)] = [
      (
        String(localized: "Seabed & Chart Survey"),
        String(localized: "Confirm holding ground nature (sand, mud) and charted hazards.")
      ),
      (
        String(localized: "Swinging Room & Depth"),
        String(localized: "Calculate swing radius including high/low water tidal variance.")
      ),
      (
        String(localized: "Rode Scope Determination"),
        String(localized: "Pay out minimum 4:1 chain scope (5:1 in windy conditions).")
      ),
      (
        String(localized: "Windlass Pre-check"),
        String(localized: "Test electric windlass controls and engage clutch securely.")
      ),
      (
        String(localized: "Snubber / Chain Hook"),
        String(localized: "Attach chain snubber to take load off the windlass gypsy.")
      ),
      (
        String(localized: "Drop Point & Anchor Alarm"),
        String(localized: "Record anchor drop coordinate and activate Sillage anchor watch.")
      )
    ]
    try insertTemplateItems(anchorItems, templateId: anchorId, in: db)

    // 3. Man Overboard (MOB) Emergency
    let mobId = UUID()
    let mobTemplate = ChecklistTemplateRecord(
      id: mobId.uuidString,
      title: String(localized: "Man Overboard (MOB)"),
      description: String(localized: "Critical emergency procedure for crew recovery at sea."),
      category_id: resolveCategoryId("safety_emergency"),
      sort_order: 2,
      created_at: now,
      updated_at: now
    )
    try mobTemplate.insert(db)

    let mobItems: [(String, String?)] = [
      (
        String(localized: "Raise Vocal Alarm"),
        String(localized: "Shout 'Man Overboard!' and appoint a dedicated visual spotter.")
      ),
      (
        String(localized: "Deploy Flotation Gear"),
        String(localized: "Throw horseshoe buoy, Danbuoy, and strobe light immediately.")
      ),
      (
        String(localized: "Press MOB Button"),
        String(localized: "Trigger MOB waypoint on GPS/plotter to record recovery datum.")
      ),
      (
        String(localized: "Propeller Safety & Engine"),
        String(localized: "Start engine; confirm trailing lines are clear of propeller.")
      ),
      (
        String(localized: "Initiate Recovery Maneuver"),
        String(localized: "Begin Williamson Turn or Quick-Stop maneuver back to casualty.")
      ),
      (
        String(localized: "Broadcast Distress Call"),
        String(localized: "Transmit VHF DSC Alert and Mayday call on Channel 16.")
      )
    ]
    try insertTemplateItems(mobItems, templateId: mobId, in: db)

    // 4. Heavy Weather / Reefing Preparation
    let weatherId = UUID()
    let weatherTemplate = ChecklistTemplateRecord(
      id: weatherId.uuidString,
      title: String(localized: "Heavy Weather & Reefing"),
      description: String(localized: "Safety measures and sail plan reduction for rising sea state and squalls."),
      category_id: resolveCategoryId("navigation_maneuver"),
      sort_order: 3,
      created_at: now,
      updated_at: now
    )
    try weatherTemplate.insert(db)

    let weatherItems: [(String, String?)] = [
      (
        String(localized: "Crew Harnesses & Jackstays"),
        String(localized: "Crew wear PFDs, tether to deck jacklines; clip-on safety lines.")
      ),
      (
        String(localized: "Hatches & Companionway"),
        String(localized: "Close and latch all foredeck hatches and companionway washboards.")
      ),
      (
        String(localized: "Secure Deck & Below"),
        String(localized: "Lash down dinghy, stow loose gear, and secure galley equipment.")
      ),
      (
        String(localized: "Reef Sail Plan"),
        String(localized: "Tuck in reef 1 or 2 before boat becomes over-canvassed.")
      ),
      (
        String(localized: "Check Bilge & Pumping"),
        String(localized: "Test manual and electric bilge pumps for immediate readiness.")
      )
    ]
    try insertTemplateItems(weatherItems, templateId: weatherId, in: db)

    try db.execute(
      sql: "INSERT OR IGNORE INTO checklist_seeding_state (id, seeded_at) VALUES (?, ?)",
      arguments: [defaultTemplatesSeedKey, now]
    )

    Logger.checklist.info("Seeding completed: 4 built-in maritime checklists created.")
  }

  nonisolated private static func insertTemplateItems(
    _ items: [(String, String?)],
    templateId: UUID,
    in db: Database
  ) throws {
    for (index, item) in items.enumerated() {
      let itemRecord = ChecklistTemplateItemRecord(
        id: UUID().uuidString,
        template_id: templateId.uuidString,
        sort_order: index,
        title: item.0,
        detail: item.1
      )
      try itemRecord.insert(db)
    }
  }
}
