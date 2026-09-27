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
  nonisolated public static func seedDefaultTemplatesIfNeeded(in db: Database) throws {
    let existingSystemCount = try ChecklistTemplateRecord
      .filter(ChecklistTemplateRecord.Columns.is_system == true)
      .fetchCount(db)

    guard existingSystemCount == 0 else {
      return
    }

    Logger.checklist.info("Seeding built-in maritime checklists...")
    let now = Date()

    // 1. Pre-Departure Procedure
    let departureId = UUID()
    let departureTemplate = ChecklistTemplateRecord(
      id: departureId.uuidString,
      title: "Pre-Departure Checklist",
      description: "Essential vessel and crew safety checks before leaving the berth or mooring.",
      category: ChecklistCategory.routine.rawValue,
      is_system: true,
      sort_order: 0,
      created_at: now,
      updated_at: now
    )
    try departureTemplate.insert(db)

    let departureItems: [(String, String?)] = [
      ("Weather & Tides", "Review coastal forecast, gale warnings, and tidal stream times."),
      ("Hull & Seacocks", "Inspect bilge levels, verify through-hull valves and seacocks."),
      ("Engine & Fluid Levels", "Check engine oil, coolant levels, and alternator belt tension."),
      ("Engine Raw Water Intake", "Verify seawater cooling intake valve is open."),
      ("Electrical & Battery Banks", "Check house and engine start battery voltages (> 12.4V)."),
      ("Navigation Lights & Electronics", "Test masthead, steaming, and port/starboard navigation lights."),
      ("Safety Equipment & Lifejackets", "Verify PFDs/harnesses, flares, and VHF channel 16 radio."),
      ("LPG & Galley Gas Shutoff", "Confirm galley gas isolation solenoid or valve is shut.")
    ]
    for (index, item) in departureItems.enumerated() {
      let itemRecord = ChecklistTemplateItemRecord(
        id: UUID().uuidString,
        template_id: departureId.uuidString,
        sort_order: index,
        title: item.0,
        detail: item.1
      )
      try itemRecord.insert(db)
    }

    // 2. Anchoring Procedure
    let anchorId = UUID()
    let anchorTemplate = ChecklistTemplateRecord(
      id: anchorId.uuidString,
      title: "Anchoring Checklist",
      description: "Standard anchoring procedure and safety radius verification.",
      category: ChecklistCategory.navigationManeuver.rawValue,
      is_system: true,
      sort_order: 1,
      created_at: now,
      updated_at: now
    )
    try anchorTemplate.insert(db)

    let anchorItems: [(String, String?)] = [
      ("Seabed & Chart Survey", "Confirm holding ground nature (sand, mud) and charted hazards."),
      ("Swinging Room & Depth", "Calculate swing radius including high/low water tidal variance."),
      ("Rode Scope Determination", "Pay out minimum 4:1 chain scope (5:1 in windy conditions)."),
      ("Windlass Pre-check", "Test electric windlass controls and engage clutch securely."),
      ("Snubber / Chain Hook", "Attach chain snubber to take load off the windlass gypsy."),
      ("Drop Point & Anchor Alarm", "Record anchor drop coordinate and activate Sillage anchor watch.")
    ]
    for (index, item) in anchorItems.enumerated() {
      let itemRecord = ChecklistTemplateItemRecord(
        id: UUID().uuidString,
        template_id: anchorId.uuidString,
        sort_order: index,
        title: item.0,
        detail: item.1
      )
      try itemRecord.insert(db)
    }

    // 3. Man Overboard (MOB) Emergency
    let mobId = UUID()
    let mobTemplate = ChecklistTemplateRecord(
      id: mobId.uuidString,
      title: "Man Overboard (MOB)",
      description: "Critical emergency procedure for crew recovery at sea.",
      category: ChecklistCategory.safetyEmergency.rawValue,
      is_system: true,
      sort_order: 2,
      created_at: now,
      updated_at: now
    )
    try mobTemplate.insert(db)

    let mobItems: [(String, String?)] = [
      ("Raise Vocal Alarm", "Shout 'Man Overboard!' and appoint a dedicated visual spotter."),
      ("Deploy Flotation Gear", "Throw horseshoe buoy, Danbuoy, and strobe light immediately."),
      ("Press MOB Button", "Trigger MOB waypoint on GPS/plotter to record recovery datum."),
      ("Propeller Safety & Engine", "Start engine; confirm trailing lines are clear of propeller."),
      ("Initiate Recovery Maneuver", "Begin Williamson Turn or Quick-Stop maneuver back to casualty."),
      ("Broadcast Distress Call", "Transmit VHF DSC Alert and Mayday call on Channel 16.")
    ]
    for (index, item) in mobItems.enumerated() {
      let itemRecord = ChecklistTemplateItemRecord(
        id: UUID().uuidString,
        template_id: mobId.uuidString,
        sort_order: index,
        title: item.0,
        detail: item.1
      )
      try itemRecord.insert(db)
    }

    // 4. Heavy Weather / Reefing Preparation
    let weatherId = UUID()
    let weatherTemplate = ChecklistTemplateRecord(
      id: weatherId.uuidString,
      title: "Heavy Weather & Reefing",
      description: "Safety measures and sail plan reduction for rising sea state and squalls.",
      category: ChecklistCategory.navigationManeuver.rawValue,
      is_system: true,
      sort_order: 3,
      created_at: now,
      updated_at: now
    )
    try weatherTemplate.insert(db)

    let weatherItems: [(String, String?)] = [
      ("Crew Harnesses & Jackstays", "Crew wear PFDs, tether to deck jacklines; clip-on safety lines."),
      ("Hatches & Companionway", "Close and latch all foredeck hatches and companionway washboards."),
      ("Secure Deck & Below", "Lash down dinghy, stow loose gear, and secure galley equipment."),
      ("Reef Sail Plan", "Tuck in reef 1 or 2 before boat becomes over-canvassed."),
      ("Check Bilge & Pumping", "Test manual and electric bilge pumps for immediate readiness.")
    ]
    for (index, item) in weatherItems.enumerated() {
      let itemRecord = ChecklistTemplateItemRecord(
        id: UUID().uuidString,
        template_id: weatherId.uuidString,
        sort_order: index,
        title: item.0,
        detail: item.1
      )
      try itemRecord.insert(db)
    }

    Logger.checklist.info("Seeding completed: 4 built-in maritime checklists created.")
  }
}
