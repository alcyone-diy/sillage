# Agent Rules for Alcyone Sillage

## Core Philosophy: The Marine Environment
This is not a standard land-based app. The UI must be usable in rough seas, with wet fingers, vibrations, and high glare. Accessibility and "Fitts's Law" are paramount.

## Code Conventions & Localization
- **Indentation:** Strictly use 2 spaces for indentation across all files.
- **UI Localization:** All user-facing strings must be localizable (e.g., using `String(localized:)` or SwiftUI's implicit `LocalizedStringKey`). The only currently supported language is English, but the architecture must support localization via `Sillage/Localizable.xcstrings`.
- **Logs:** Logs (console, `os.Logger`, error reporting) must **NEVER** be translated. Keep them in English.

## The Two UI Modes (Standard vs. Glove Mode)
The app implements two distinct themes via a centralized Design System:
1. **Standard Mode:** Default iOS metrics (44pt touch targets).
2. **Glove Mode:** Enhanced metrics for maritime use (66pt minimum touch targets, bumped font tiers).

### Mandatory Implementation Rules

#### 1. Design System Location
All UI tokens and modifiers are located in `Sillage/DesignSystem/`. 
- **NEVER** use hardcoded sizes (e.g., `.frame(width: 60)`) for interactive elements.
- **NEVER** use standard `.font(.body)` directly for labels.

#### 2. Typography
Use the custom `.marineFont(_ baseStyle: Font.TextStyle)` modifier. 
- It automatically handles font tier bumping when `Glove Mode` is active.
- Example: `Text("SOG").marineFont(.caption)`

#### 3. Buttons & Interaction
- **Standard Buttons:** Always apply `.buttonStyle(MarineButtonStyle())`.
- **Floating Action Buttons (FABs):** Always apply `.buttonStyle(MarineFABStyle(backgroundColor: ...))`.
- These styles use `@ScaledMetric` to ensure they respect both "Glove Mode" base values and native iOS Accessibility/Dynamic Type.

#### 4. List & Forms
- Every row in a `List` or `Form` must use `.marineListCell()`.
- This ensures the `minHeight` scales to the current `MarineTheme.minTouchTarget`.

#### 5. Theme Injection
- The theme is propagated via the SwiftUI Environment: `@Environment(\.marineTheme) var marineTheme`.
- The source of truth is `AppViewModel.marineTheme`, computed from `isGloveModeEnabled`.

## Proactive Verification
Before submitting any UI code, check:
- "Does this element scale when `marineTheme.isGloveMode` is true?"
- "Is the touch target at least 66x66pt in Glove Mode?"
- "Am I using `@ScaledMetric` for any new spacing or sizing logic?"
- "Are all user-facing strings localizable?"
- "Are all logs strictly non-translated?"
- "Is the indentation exactly 2 spaces?"