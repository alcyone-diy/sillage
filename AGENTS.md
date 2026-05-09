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
- **PROHIBITED (State):** `Combine`, `ObservableObject`, and `@Published` are strictly forbidden.
- **Locking & Synchronization:** Use Swift 6 `actor` to encapsulate isolated state. GCD (`DispatchQueue`), `NSLock`, and raw `os_unfair_lock` are strictly forbidden.
  - *Exception:* If a synchronous lock is absolutely required in a non-isolated context (e.g., inside a `deinit` for a resource token), you must use `OSAllocatedUnfairLock` (iOS 16+).
- **Indentation:** Strictly **2 spaces**.
- **Localization:** Rely on SwiftUI's native LocalizedStringKey for literals (e.g., `Text("Hello")`). Only use `String(localized:)` when passing localized strings to non-view variables, ViewModels, or custom components that don't accept LocalizedStringKey. Logs and developer comments must stay in English.

## 3. Error Handling & Idiomatic Swift
- **No Forced Unwrapping:** Use `if let` or `guard let`. The `!` operator is banned.
- **Nil Over Defaults:** If data is invalid (e.g., negative radius, failed parsing, invalid SOG, invalid coordinates), return `nil`. 
- **PROHIBITED (Dummy Values):** Never return "dummy" values like `0`, `-1`, or `""` for invalid states. Force the caller to handle the optionality.
  - *Framework Warning:* Beware of Apple's APIs returning dummy values for invalid states (e.g., `CLLocation` returning `-1.0` for invalid course or speed). These must be caught at the service boundary and mapped strictly to `nil`.
- **Strict Logging & Centralization:** The `print()` function is formally banned anywhere in the app. You must exclusively use `os.Logger` (`OSLog`). All loggers MUST be defined as static properties within the single source of truth: `Sillage/Core/Logger+Sillage.swift`. Always check this file to use an existing category before creating a new one. Local instantiation of `Logger` is strictly forbidden. Furthermore, you must explicitly manage log privacy (e.g., `\(variable, privacy: .public)`) for interpolated non-PII variables to prevent the macOS/iOS Console from silently masking critical diagnostic data with `<private>`.

## 4. Physical Units (Measurement API)
- **Strict Typing:** It is **formally forbidden** to use `Double` or `Float` to represent physical quantities.
- **Mandatory Usage:** You must use `Foundation.Measurement`.
    - Distance: `Measurement<UnitLength>`
    - Speed: `Measurement<UnitSpeed>`
    - Angles: `Measurement<UnitAngle>`
- **No Manual Math Conversions:** Never use raw mathematical formulas (e.g., `* .pi / 180`) to convert degrees, radians, or knots. Rely entirely on the `Foundation.Measurement` conversion pipeline.
- **High-Frequency Performance:** In high-frequency loops (e.g., `didUpdateLocations` or NMEA parsing), avoid `.converted(to:)` to prevent unnecessary CPU overhead. Instead, pre-calculate threshold values during initialization as `Measurement` objects in the exact base unit provided by the sensor (e.g., `metersPerSecond`). Wrap the incoming raw sensor value into a `Measurement` once, and compare the `Measurement` objects directly. **Never extract `.value` to raw `Double`**, as strict type safety must be maintained even in performance-critical code.

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

## 7. Architecture & Domain-Driven Design (DDD)
- **Architecture:** MVVM is mandatory for all SwiftUI views.
- **Strict Framework Isolation:** Third-party or Apple Framework types (e.g., `CLLocation`, `CLHeading`, `CBMPeripheral`) must **never** leak into the UI or Domain streams. They must be intercepted at the Service boundary and mapped to pure Swift Domain structs (e.g., `MarineFix`).
- **DDD Strictness:** Business terms like `Route`, `Navigation`, `Track`, and `Waypoint` are strictly forbidden in UI navigation code. Use terms like `CommandDestination` and `commandPath` to prevent cognitive collision with the ship's actual routing engine.

## 8. UX & Animations
- **No Pop Glitches:** When popping views from a `NavigationStack`, use iOS 17's `withAnimation(..., completion:)` to clear the stack only after the dismiss animation finishes.

## 9. Legal & Security
- **Licenses:** Any recommended library must be checked for App Store compatibility (no GPL contagion). Map/Data sources must display their license in the UI (MIT, BSD, ODbL).
- **Remote Maps:** Distant map sources must be gated by a local token verification.

## 10. Location & Background Execution
- **Dynamic Background Privileges:** Never hardcode `allowsBackgroundLocationUpdates = true` permanently. Use the RAII/Token pattern (`BackgroundLocationToken`) to dynamically acquire and release background location privileges only when a session (like Track Recording or Anchor Alarm) is actively running.
- **Continuous Tracking:** Always set `pausesLocationUpdatesAutomatically = false` and `showsBackgroundLocationIndicator = true` when acquiring the background token to guarantee iOS does not silently kill the GPS thread when the device is asleep.
- **Throttling & Battery Conservation:** `kCLDistanceFilterNone` is strictly forbidden. Always apply a sensible `distanceFilter` to prevent CPU and battery drain from stationary GPS micro-fluctuations. This filter must be dynamically adjustable by the Domain layer depending on the context (e.g., setting 5-10 meters for active sailing, or 1 meter for an anchor watch). The Location/Infrastructure service must not know the business context; it only applies the requested filter in meters.
- **Memory Safety:** The token object must support an explicit `invalidate()` method to terminate the background session, while also enforcing a fallback cancellation in its `deinit` to prevent GPS battery leaks.

## 11. Agent Behavior
- **Responses:** Do not generate long blocks of code unnecessarily. Focus on architectural decisions, logical diagrams, and clear, concise specifications.

## 12. Sensor Data & UI Awareness
- **No Silent Filtering:** Services (like Location, NMEA) must never silently drop degraded data (e.g., GPS points with poor accuracy). Emit all raw/degraded states to the domain. The ViewModel is responsible for interpreting this degradation and updating the UI to warn the user explicitly (e.g., "Fix Lost", "Poor Accuracy polygon").
