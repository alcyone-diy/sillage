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
- **Localization:** All UI strings must use `String(localized:)`. Logs and developer comments must stay in English.

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