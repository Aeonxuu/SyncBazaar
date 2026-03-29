---
name: "SyncBazaar UI Guardrails"
description: "Use when building or editing SyncBazaar Flutter UI, layouts, forms, dialogs, navigation, and tablet screens. Enforces design tokens, spacing, component consistency, and role-aware UX."
applyTo: "lib/**/*.dart"
---
# SyncBazaar UI Guardrails

## Design Tokens
- Colors
  - primary: #6C4AB6
  - accent: #FFC107
  - background: #FEFEFE
  - surface: #F8F9FA or #FFFFFF
  - text: #212529
  - error: #DC3545
- Typography
  - Use Inter from google_fonts (Roboto fallback)
  - Heading: SemiBold, 20-24
  - Body: Regular, 14-16
  - Button: Medium, 14-16

## Layout Rules
- Tablet-first, landscape-only interaction model.
- Left NavigationRail stays persistent and uses primary purple.
- Main page background stays slightly darker than cards.
- Cards use no border, radius 8-12, subtle shadow only.
- Keep consistent content padding and section gaps.

## Component Rules
- Primary button: filled primary, white text, radius around 8.
- Secondary button: outline or text style with primary color.
- Danger button: error red for destructive actions.
- Inputs: outlined TextFormField, radius 8, floating labels.
- Dialogs: card styling + clear Cancel/Confirm actions.

## Feature-Specific UX Constraints
- Dashboard style is reference for all other screens.
- Pre-Bazaar: two primary cards side-by-side on wide tablets, stacked on narrow widths.
- POS: split layout (about 70/30), card tap opens variant/quantity popup.
- Orders: role-scoped visibility and confirmation before status changes.

## Engineering Constraints
- Reuse shared widgets before adding new one-off styles.
- Keep UI, state, data, and sync boundaries separated.
- Do not call AI APIs directly from client.
- Keep AI Assist widgets backend-ready through injectable text/data props.
