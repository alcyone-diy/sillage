# Agent Rules for Alcyone Sillage

## 1. Core Philosophy: The Marine Environment
This is not a standard land-based app. The UI must be usable in rough seas, with wet fingers, vibrations, and high glare. 
- **Safety First:** Precision and reliability over aesthetics.
- **Fitts's Law:** Large touch targets (Glove Mode) are mandatory for critical actions.
- **Progressive Disclosure:** Display only what is vital for the current context.

## 2. Technical Stack & Swift 6 Standards
- **Target:** iOS 17+.
- **Concurrency:** Strict Swift 6 Concurrency. Use `@MainActor` for all UI-related ViewModels. Prefer `Task` over `Timer`.
- **State Management:** Use the `@Observable` framework.
- **PROHIBITED:** `Combine`, `ObservableObject`, and `@Published` are strictly forbidden.
- **Indentation:** Strictly **2 spaces**.
- **Localization:** Rely on SwiftUI's native LocalizedStringKey for literals (e.g., `Text("Hello")`). Only use `String(localized:)` when passing localized strings to non-view variables, ViewModels, or custom components that don't accept LocalizedStringKey. Logs and developer comments must stay in English.

## 3. Error Handling & Idiomatic Swift
- **No Forced Unwrapping:** Use `if let` or `guard let`. The `!` operator is banned.
- **Nil Over Defaults:** If data is invalid (e.g., negative radius, failed parsing, invalid SOG, invalid coordinates), return `nil`. 
- **PROHIBITED:** Never return "dummy" values like `0`, `-1`, or `""` for invalid states. Force the caller to handle the optionality.

## 4. Physical Units (Measurement API)
- **Strict Typing:** It is **formally forbidden** to use `Double` or `Float` to represent physical quantities.
- **Mandatory Usage:** You must use `Foundation.Measurement`.
    - Distance: `Measurement<UnitLength>`
    - Speed: `Measurement<UnitSpeed>`
    - Angles: `Measurement<UnitAngle>`
- **Conversion:** Use `.converted(to:)` only for display purposes.

## 5. Design System (MarineTheme)
- **Anti-Hardcoding:** No hardcoded frames or font sizes.
- **Typography:** Use the custom `.marineFont(_ style: MarineTextStyle)` modifier.
- **Lists:** Every `List` or `Form` row must apply `.marineListCell()`.
- **Buttons:** Use `MarineButtonStyle()` or `MarineFABStyle()`.
- **Scaling:** Ensure all elements respect `marineTheme.isGloveMode` (min target 66pt).

## 6. MapLibre & GIS Rules
- **Thread Safety:** All map updates (Layers/Sources) must occur on the `@MainActor`.
- **Defensive Layering:** Always verify if a source/layer exists before modification to prevent crashes during style reloads.
- **Offline-First:** Prioritize local `.mbtiles` files in the `Charts/` directory.

## 7. Architecture & Domain-Driven Design
- **Architecture:** MVVM is mandatory for all SwiftUI views.
- **DDD Strictness:** Business terms like `Route`, `Navigation`, `Track`, and `Waypoint` are strictly forbidden in UI navigation code. Use terms like `CommandDestination` and `commandPath` to prevent cognitive collision with the ship's actual routing engine.

## 8. UX & Animations
- **No Pop Glitches:** When popping views from a `NavigationStack`, use iOS 17's `withAnimation(..., completion:)` to clear the stack only after the dismiss animation finishes.

## 9. Legal & Security
- **Licenses:** Any recommended library must be checked for App Store compatibility (no GPL contagion). Map/Data sources must display their license in the UI (MIT, BSD, ODbL).
- **Remote Maps:** Distant map sources must be gated by a local token verification.

## 10. Agent Behavior
- **Responses:** Do not generate long blocks of code unnecessarily. Focus on architectural decisions, logical diagrams, and clear, concise specifications.