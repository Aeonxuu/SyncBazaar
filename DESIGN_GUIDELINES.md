# SyncBazaar — UI/UX Design Guidelines

Reference this file whenever redesigning or restyling a SyncBazaar screen. It captures the UI/UX laws, numeric tokens, and component patterns established during the POS redesign (product grid, variant picker modal, payment method selector, bazaar selector). Treat existing widgets referenced here as the canonical examples — when in doubt, open the file and copy the pattern rather than inventing a new one.

This file describes *intent*. Token values live in code (`lib/core/constants/colors.dart`, `motion.dart`) — if this doc and the code disagree, the code is correct and this file is stale and should be updated.

---

## 1. How to use this doc

1. Before redesigning a screen, skim Section 2 (laws) and pick the 2-3 most relevant to the screen's actual problem. Don't try to apply all of them to everything — that's how you get over-designed UI.
2. Reuse the numeric tokens in Sections 3-6 instead of picking new numbers. Consistency across screens matters more than any single screen looking slightly better.
3. Check Section 7 (component recipes) for a widget that already solves the problem. Most "new" UI needs in this app are a variant of something already built.
4. Before calling a redesign done, run through the Section 9 checklist.

---

## 2. UI/UX Laws to apply

Each law below includes *why it matters* and *where it already shows up in this app*, so it's concrete instead of textbook-abstract.

### Fitts's Law
Bigger, closer targets are faster and easier to hit. Primary actions get the largest tap area; destructive/secondary actions can be smaller.
- Applied: `_QtyStepperButton` uses 26x26 squares (not tiny icons); `_PaymentMethodOption` enforces a 44px minimum height because it sits right before checkout; `PosProductCard`'s "Add to cart" is a full-width button, not just a hope that the whole card is tappable.

### Hick's Law
More choices, presented at once, take longer to decide between. Reduce the visible choice set or give it structure (tabs, grouping) instead of one long flat list.
- Applied: the master inventory's All / Active / Draft / Archived / Out of stock filter is a single-row underline tab bar (`_StatusTabs`) rather than a wrapping cluster of chips — one linear scan instead of a 2D one. (POS had the same pattern for brand filtering until brands were removed on 2026-08-02.)

### Jakob's Law (+ internal consistency)
Users spend most of their time on *other* apps, so match well-known patterns (search bars, card grids, stepper buttons) rather than inventing new interaction models. The corollary that matters more day-to-day: **be consistent with your own app first.** A screen that looks like a different product is worse than a screen that's merely plain.
- Applied: we intentionally kept `AppColors.primary` (purple) as the POS accent instead of copying a green reference screenshot's palette — matching the rest of SyncBazaar beat matching the reference image.
- Applied: Color and Size option buttons in the variant modal were originally two different widgets (`ChoiceChip` vs. a custom button) with two different visual languages. Merged into one `SelectableOptionButton` — same control, same rules, now shared app-wide.

### Recognition over recall
Showing all valid options beats hiding them behind a menu the user has to open and remember to check.
- Applied: Payment method used to be a `DropdownButtonFormField`. With only 2-4 methods, that's an unnecessary open-then-pick step. Replaced with always-visible `_PaymentMethodOption` tiles.

### Miller's Law / Chunking
Group related information together and don't split obviously-related data into more separate lines than necessary.
- Applied: Bazaar cards merged separate "Start:" / "Finish:" lines into one `Aug 1 – Aug 5` line.

### Von Restorff Effect (isolation effect)
The one item that looks different is the one people notice first. Use a genuinely distinct treatment (not just a shade) for the thing that must stand out — usually the "selected" state.
- Applied: selected variant/payment options flip to a completely different color (yellow fill + purple text), not a darker tint of the unselected color, so the active choice is unmistakable at a glance.

### Aesthetic-Usability Effect
Clean, uncluttered interfaces are *perceived* as easier to use even before a user does anything — first impressions bias the rest of the experience.
- Applied: flat cards with a hairline border read as more trustworthy/modern than the old heavy-drop-shadow + gradient-button combo, independent of any functional change.

### Nielsen's Visibility of System Status
The interface should always make it obvious what's happening and why something is (or isn't) available.
- Applied: disabled bazaar cards used to show a full-strength purple gradient button that just silently didn't respond to taps — a real bug in disguise. Fixed by making the button visibly muted *and* changing its label to explain why ("Starts Aug 24" / "Bazaar ended") instead of always saying "Open POS".
- Applied: search bar shows a quiet "N bazaars found" line so filtering has visible feedback.

### Proximity / Common Region (Gestalt)
Things that are visually grouped (via spacing or a shared background) are read as related; ungrouped items are read as unrelated even if they're logically connected.
- Applied: Subtotal / Discount / Total are boxed together in a shaded "Detail Payment" card, separated from the scrollable cart list above it.

---

## 3. Color palette

Defined in `lib/core/constants/colors.dart`. Add new *semantic* colors here rather than hardcoding hex values inline when a color will be reused.

| Token | Hex | Use for |
| --- | --- | --- |
| `AppColors.primary` | `#6C4AB6` | Brand purple. Primary buttons, selected/active text, links, focus borders. |
| `AppColors.primaryLight` | `#EDE7F6` | Flat fill for **unselected** option buttons (see Section 7). Never used as a border. |
| `AppColors.accent` | `#FFC107` | Brand yellow. Flat fill for **selected** option buttons. Reserve for selection state — don't use decoratively elsewhere or it stops meaning "selected". |
| `AppColors.background` | `#F8F9FA` | App/page background, behind cards. |
| `AppColors.surface` | `#FEFEFE` | Card and input surfaces sitting on top of the background. |
| `AppColors.text` | `#212529` | Primary text color (used instead of pure black). |
| `AppColors.error` | `#DC3545` | Errors, destructive actions, "ended" status. |

### Status colors
⚠️ **Promoted to `AppColors` on 2026-08-16**, as the previous version of this note asked. Twelve files had each declared their own copy and two had already drifted: upcoming was `#8A6100` in the orders badge against `#B45309` everywhere else, and ended was grey there against the error red everywhere else. Use the tokens; don't re-declare the hex.

| Status | Token | Hex |
| --- | --- | --- |
| Ongoing / success | `AppColors.statusOngoing` | `#2E7D32` green |
| Upcoming / warning | `AppColors.statusUpcoming` | `#B45309` amber |
| Ended / error | `AppColors.statusEnded` | `AppColors.error` `#DC3545` — the existing red, not a new one |

Status badges use the status color at **12% opacity** as the fill (`statusColor.withValues(alpha: 0.12)` — `withOpacity` is deprecated) with the full-strength color as the text — never a solid-color badge background, it's too loud for a small label.

### Neutral grays (ad hoc, used for backgrounds/borders — not full brand tokens)
| Hex | Use for |
| --- | --- |
| `AppColors.inputFill` `#F0F1F4` | **Text input, dropdown trigger and photo-well fill.** Neutral gray. Replaced the old purple-tinted `#F5F1FB` — see the callout below. Also used for neutral pill backgrounds. |
| `AppColors.border` `#EDEDF1` | Hairline rules and flat-card borders. |
| `#F7F7F9` | Very light gray for boxed sub-sections (Detail Payment card) and disabled card backgrounds. |
| `#EAEAEF` / `#EDEDF1` | Hairline borders on flat cards/inputs. |

### Icon weight — `Icon.weight` does nothing in this app
Flutter bundles Material Icons as a **static** font. `Icon(weight: ...)`, `grade`, and `opticalSize` only drive variable-font axes, so they silently have no effect here. To make an icon read thinner, the only levers that work are:
1. **The outlined set** (`Icons.delete_outline`, `Icons.edit_outlined`) — thinner than filled or rounded.
2. **Size** — stroke weight scales with the glyph. A 24px icon's ~2px stroke becomes ~1.4px at 17px.
3. **Colour** — a lighter colour (`Colors.black38`) reads as a lighter stroke even at the same size.

Standing sizes: **17px** for trailing row actions and dialog close buttons, **18-19px** for toolbar/button icons, **28-30px** for empty-state illustrations.

### Text color hierarchy
Don't use pure black. Layer opacity/shade to build hierarchy — darkest for primary content, lightest for disabled:
- Primary text: `AppColors.text` or `Colors.black87`
- Secondary/meta text: `Colors.black54`
- Muted/caption text: `Colors.black45`
- Placeholder/hint text: `Colors.black38`
- Disabled text: `Colors.black26`–`Colors.black38`

### Input fills are neutral, not purple
⚠️ **Correction, 2026-08-02**: text inputs used to be filled with `#F5F1FB`, a purple-tinted gray, and the product form's photo well used `AppColors.primaryLight` outright. But `primaryLight` is defined below as the **unselected** fill in the selection color rule — so ordinary text fields carried a faint "option you can pick" signal, and the purple family stopped being a reliable cue for brand and selection. Inputs are now neutral `#F0F1F4`. Keep purple for brand, selection, and emphasis readouts (e.g. the product form's "Total stock" summary, which is deliberately the only purple fill left in that dialog).

Input fill depth, in order: `AppColors.surface` `#FEFEFE` (dialog/card) → `#F7F7F9` (boxed sub-section panel) → `#F0F1F4` (input on a surface). An input **nested inside** a `#F7F7F9` panel inverts to white instead, so the two never read as the same depth.

### The selection color rule (important, applies app-wide going forward)
Whenever you build a binary/multi-choice option control (chips, toggle buttons, segmented options):
- **Unselected**: flat `AppColors.primaryLight` fill, **no border**, `AppColors.text` label.
- **Selected**: flat `AppColors.accent` fill, `AppColors.primary` label, bold weight.
- **Disabled**: same fill as unselected, label dimmed to `Colors.black38`. Never mute the *whole* element (see Section 8, "don't blanket-dim disabled things") — the option should stay legible even if it can't be tapped.
- The color *swap* (not a border, not a checkmark) is what communicates selection.

⚠️ Known caveat: purple text on yellow is borderline on WCAG contrast for small text. Bold weight helps. If it's ever hard to read on a real screen, that's worth revisiting — this was an explicit user color choice, not an oversight.

---

### Selection colour: the POS payment tiles are inverted (2026-08-03)
The rule above (unselected `primaryLight`, selected `accent` with a `primary` label) still governs `SelectableOptionButton` everywhere — POS colour/size chips, the product form's status picker. The **payment method tiles are the one deliberate exception**: selected is a solid `AppColors.primary` fill with `AppColors.accent` content. Same two colours, opposite assignment. A filled tile carries more weight than a tinted one, and the payment method is the last thing checked before a sale is committed.

⚠️ Be aware this means one screen signals "selected" two ways — an amber size chip and a purple payment tile sit in the same checkout flow. It was an explicit product decision, not drift. Don't invert anything *else* without the same deliberate call, or the exception becomes the rule and the rule stops meaning anything.

## 4. Spacing scale

Written as literal numbers at the call site. There was an `AppSpacing` class in
`lib/core/constants/spacing.dart`, but nothing ever used it — it was deleted on
2026-08-02 rather than left as a token vocabulary the code didn't speak. If you
reintroduce it, adopt it everywhere in the same change; a half-adopted token set
is worse than none.

| Value | Use for |
| --- | --- |
| 8 | Tight gaps (icon-to-label, chip spacing). |
| 12 | Default gap between related controls. |
| 16 | Card internal padding, grid gutters, gap between form fields. |
| 20 | Gap between a section heading and the block it introduces. |
| 24 | Page-level padding; section break inside a form or dialog. |
| 32 | Rare — large section breaks only. |

Values of **2-6** are also common, but only *inside* a single component — the gap
between a label and its input, or between two lines of a stacked text cell. They
are not part of the layout scale, so don't reach for them to separate blocks.

Other spacing values in active use (not yet tokenized, but consistent by convention):
- **Page padding**: 24 for a full top-level screen (e.g. "Select Active Bazaar"), 12-16 for a dense split-panel screen (e.g. the POS working view).
- **Card padding**: 16.
- **Grid gutters**: 12-16 (`mainAxisSpacing`/`crossAxisSpacing`).
- **Compact chip padding** (Color swatches, dense grids): 8 horizontal / 6 vertical.
- **Standard button/chip padding**: 14 horizontal / 10 vertical.
- **Stepper button size**: 26x26 fixed square.
- **Minimum interactive tap target**: 44px tall for anything checkout-critical or otherwise important to get right on a touch screen (Fitts's Law).

### One gutter per screen, equal in both axes
⚠️ **Added 2026-08-02.** The dashboard used three gaps for the same job: a 12px grid gutter between KPI cards, 16px between the two cards below them, and 8px between those two groups — plus a page frame of 24 horizontal against 16 vertical. Unequal gutters don't read as hierarchy, they read as misalignment; Gestalt proximity only groups a set of tiles when the spacing between them is uniform. Pick **one** value for a screen (16 on the dashboard, held in a `_dashboardGutter` const) and use it for every gap between blocks, horizontal and vertical alike. Page padding is `EdgeInsets.all(24)` — symmetric, not `symmetric(horizontal: 24, vertical: 16)`.

### Grid tiles: size them with `mainAxisExtent`, not `childAspectRatio`
`childAspectRatio` derives tile *height* from column *width*, so the same card grows taller as the window widens. On the dashboard that meant a KPI card 102px tall at a 1000px window and 151px at 1440 — with content of a constant 84px, its 16px top padding sat against 31-80px of dead space underneath, and the amount changed as you resized. Card padding must not be a function of the viewport. Use `mainAxisExtent: <fixed height>`, and give the card `mainAxisAlignment: MainAxisAlignment.spaceBetween` so any slack lands *between* the label and the value instead of pooling at the bottom. Keep a small `SizedBox` between them as a floor — `spaceBetween` splits the slack around it, so the two never collide if the card is ever placed somewhere with no spare height.

### Button sizing tiers — don't default every button to "big"
⚠️ **Explicit correction, 2026-07-31**: an early pass made secondary controls (filter toggles) as large as primary buttons. Fitts's Law says targets should be sized to how important and how *precisely/frequently* they're used — it is not a blanket argument for making every button big. A control used occasionally, with low precision cost if missed, should be small. Match the tier to the role:

| Tier | Examples | Sizing |
| --- | --- | --- |
| **Primary CTA** | "Add to cart", "Finish"/checkout, "Open POS" | Generous: 14h/10v+ padding, often full-width, ≥44px tall. This is the one tier where big is correct. |
| **Secondary action button** | "Cancel", dialog actions | Standard: 14h/10v padding, auto-width (not full-width), ~38-40px tall. |
| **Selection control** (chip/toggle you pick from a small set) | Color/Size variant buttons, payment method tiles | Compact-standard: 14h/10v or tighter (8h/6v) depending on how many sit in a row — see Section 3's selection color rule. |
| **Tag / filter / status badge** | Status badges, the bazaar status filter cycle button, stock-count pill | Small, content-sized: ~10h/6v padding, 12px text, ~13-14px icon, radius 6-8. Never full-width, never stretched to match a nearby input's height. |

Rule of thumb: if a control's job is to *filter, tag, or label* rather than to *commit an action*, it should look closer to a badge than a button.

## 5. Corner radius scale

Pick the smallest radius on this list that still reads as "rounded enough" — don't default to the largest one.

⚠️ **Tightened 2026-08-02.** Cards, search bars and filter chips were sitting at 12-16 and reading soft; they came down a step. Nothing in a normal screen should exceed **10** now — the larger values are reserved for modals, which sit above everything and earn a little more shape.

| Radius | Use for |
| --- | --- |
| 6 | Status badges and small tags — anything the size of a word. |
| 8 | **The default.** Buttons, inputs, dropdown triggers, search bars, filter chips, quantity steppers, boxed sub-sections. When unsure, use this. |
| 10 | Cards, list rows, panels, thumbnails, payment method tiles, popup menus. |
| 14 | **Modals only** — dialogs and the date picker. Nothing inline. |
| 16 | The login panel only — the largest single surface in the app. Don't extend this to anything else. |
| 20 | Pill-shaped chips (POS Color swatches) — only when the shape is meant to read as a "chip," not a "button." |

Rule of thumb: radius should track how *big and how far forward* a surface is. A modal floats above the page and gets 14; a card sits on the page and gets 10; a control inside the card gets 8; a label inside the control gets 6.

### Nested corners: `inner = outer − gap`

The table gives a *starting* radius. When one rounded element sits inside another, the inner one's radius is no longer a free choice — it is determined:

```
inner radius = outer radius − the gap between them
```

Two arcs offset by a constant distance are concentric, so the space around the corner keeps an even width. Break it and the error shows up exactly where the eye is most sensitive: give the inner element the *same* radius and the gap pinches at the corner; give it a *larger* one and the inner curve bulges past its container, which reads as a mistake even to people who can't name it.

The practical consequence is that only two of the three numbers are yours to pick. Choose the gap from what the content needs to breathe, then derive the radius — don't reach for 8 out of habit and leave the corner wrong.

**Worked example — the POS product card** (`pos_product_card.dart`, which names all three as constants so the relation can't drift):

| | Value | Why |
| --- | --- | --- |
| Card | 10 | The scale's card radius. Was 16. |
| Gap to the Add button | 6 | The tightest gutter that still gives the name and price room on a 150-190px tile. |
| Add button | **4** | Not chosen — `10 − 6`. |

A full-bleed control inside a small card can't also have the default 8: that would force a 2px gutter. The button yields, because it is the element the rule derives.

Corollary: **the gap has to be the same on both axes.** The card previously inset its details 10 horizontally and 8 vertically, so its bottom corners had two different gaps and no single radius could satisfy both.

## 6. Typography hierarchy

Uses the app theme's `Inter` text theme (`lib/core/theme/app_theme.dart`). Don't invent one-off `TextStyle`s when a theme style + `.copyWith(color: ...)` will do.

| Role | Style | Notes |
| --- | --- | --- |
| Page title | `headlineSmall` | `fontWeight: w700`. |
| Page subtitle/caption | `bodyMedium` | `color: Colors.black45`. |
| Card/section title | `titleMedium` | `fontWeight: w700`. |
| Primary body content | `bodyMedium` | Default weight unless it's a price/total (then `w600`-`w700`). |
| Secondary/meta text | `bodySmall` | `color: Colors.black45` or `black54`. |
| Money/price emphasis | `bodyMedium` or `titleMedium` | `fontWeight: w700`, colored `AppColors.primary` when it should draw the eye (line totals, grand total). |

**Number formatting rule**: every number the user reads comes from `lib/core/utils/formatters.dart` — `formatPeso` (`PHP 12,495.00`), `formatAmount` (`12,495.00`), `formatCount` (`12,495`). Never `toStringAsFixed(2)`, and never a fresh `NumberFormat` at the top of a file.

⚠️ **Consolidated 2026-08-03.** The rule previously said "use `NumberFormat('#,##0.00')`", and eleven files each obeyed it by declaring their own copy — while the POS, the orders table and the post-bazaar payout summary skipped it entirely, so the same amount read `PHP 12,495.00` on the dashboard and `PHP 12495.00` at the till. A formatting rule that has to be re-implemented per file *will* drift; give it one home and import it. `toStringAsFixed` is still correct for ratios and percentages — it is money and counts that must go through the helper.

**Format at display, not at serialisation.** The pre-bazaar approval payload used to `jsonEncode` a price that had already been through `toStringAsFixed(2)`, and the approvals table printed the resulting string verbatim. Put the raw number in the payload and format it where it is rendered — otherwise the display rule silently exempts anything that travels as data.

---

## 7. Component recipes (copy these, don't reinvent)

Reference implementations live in `lib/ui/screens/pos/`. Names below are the actual widgets — grep for them.

- **Selectable option button** (`SelectableOptionButton` in `lib/ui/widgets/`): the canonical implementation of the Section 3 selection color rule, with press-scale feedback and an animated fill/text-color transition. One widget, many configurations — POS Color chips (tight padding), POS Size grid buttons (radius 8, standard padding), the product form's status picker. **Use this for any new chip/toggle**; do not write a second one.
- **Form dropdown** (`AppDropdown` in `lib/ui/widgets/`): the dashboard's `_BazaarFilterDropdown` behaviour — menu pinned to the trigger's exact width, check mark on the current value inside the open menu, `AnimatedRotation` chevron, open-state border — shaped as a form input (same fill, radius and 44px height as the text fields beside it). Prefer this over `DropdownButtonFormField`, which can't mark the current value in its menu, can't react to being open, and sizes its menu independently of the field.
- **Form field** (`_FormField` in `inventory_screen.dart`): label, optional trailing link, input, and the field's own error message bundled in one widget, with the error revealed via `AnimatedSize`. Errors belong *next to the input*, never in a SnackBar. Invalid inputs also get a red outline so they're findable at a glance rather than only described in text.
- **Multi-step screen or dialog** (`_ProductFormDialog`, `PreBazaarScreen`): numbered markers in the header, a full-width body for the current step, and one persistent footer holding Back / secondary / primary. Prefer this over showing later steps as greyed-out panels beside the active one — a locked panel spends layout on something the user can't use and reads as broken rather than as "not yet". Completed steps are tappable to revisit; forward movement is what validation gates, and the step itself should say what's still missing rather than rejecting a tap.
- **Multi-step dialog specifics** (`_ProductFormDialog`): a numbered stepper in the header, shown *only* when there is more than one step. Completed steps are tappable to go back; steps ahead are not, because forward movement is what validation gates. The one primary button owns both "Continue" and "Save", and its label says which. Problems that belong to the whole step rather than one field go in a `_StepErrorBanner` inside the body, not a SnackBar.
- **Payment/choice tile with icon** (`_PaymentMethodOption`): same color rule as above, plus a leading icon, used when recognition-over-recall beats a dropdown (≤ ~5 options).
- **Flat card with status** (`_BazaarCard`): hairline border, no drop shadow, status badge at 12% opacity, primary CTA whose label and enabled-state both reflect *why* it is or isn't actionable.
- **Product grid card** (`PosProductCard`): image → title → muted meta line → price (accent-colored) + count pill → full-width secondary CTA. The whole card is also tappable (same action as the button) — redundant, not conflicting, affordance.
- **Quantity stepper** (`QuantityStepper` in `lib/ui/widgets/`): `[ − n + ]` in one bordered control at a **fixed width**, so a column of them aligns down a list no matter how many digits each row shows. Two loose `IconButton`s shift horizontally as the number beside them grows — that misalignment is the reason this exists. Each end disables at its limit rather than silently clamping. (POS still uses its own `_QtyStepperButton` pair — minus grey, plus purple — for the single in-cart counter; adopt `QuantityStepper` there if the two ever need to match.)
- **Search bar**: single field, no separate label above it (the placeholder already says what it's for), hairline-bordered surface fill, optional quiet result-count caption underneath. Cap width (e.g. `maxWidth: 480`) on wide screens instead of letting it stretch edge-to-edge.
- **Numeric readout that changes** (`_NumericCrossfade`): fade-only crossfade (no scale) when a price/quantity updates in place — confirms the change registered without distracting from the value the user is trying to read.
- **List item entrance** (`_CartItemEntrance`): fade + grow-from-top when a new row is added to a list the user is actively watching (e.g. cart). Keyed by object identity so it plays once on insert, not on every mutation of the same item.
- **Boxed sub-total section** (Detail Payment pattern): light gray (`#F7F7F9`) rounded container grouping a set of related summary rows, with a dashed rule (`_DashedDivider`) before the grand total.
- **Chart** (`_SalesLineChart` in `average_daily_sales_card.dart`): built on `fl_chart` (`fl_chart: ^1.2.0`) — never hand-roll bars out of `Container`/`Row` again. Purple line + vertical purple-to-transparent fill below it, light `#ECECF2` checkered grid, `AppMotion.entrance` draw-in, tap/hover tooltip. Four rules any new chart must follow:
  1. **Axis intervals must be uniform.** `0, 5k, 10k, 20k, 30k…` draws equal pixel gaps for unequal amounts and misreports the data. Pick one step (e.g. 10,000) and keep it.
  2. **Never clip data to a fixed max.** Compute `maxY = max(designBaseline, roundUpToInterval(dataMax))` so a spike above the intended range extends the axis instead of being cut off.
  3. **Smooth lines need `preventCurveOverShooting: true`.** Cubic interpolation between sharp swings bulges past the real values and can dip below zero, implying numbers that never happened.
  4. **Anchor the window to real calendar days.** A "last N days" window with fixed weekday labels mislabels itself on every day but one — derive the window from the actual weekday (see `_buildDailySalesForFilter`).
- **Manage-list dialog** (`_CategoryManagerDialog` in `inventory_screen.dart`): the pattern for any "manage a small set of named things" modal. Header (title + quiet count + `×`) / hairline / scrollable rows / hairline / create field + Add button. Rows carry a secondary line stating the *consequence* of the row's destructive action ("12 products"), renaming happens **inline in the row**, and the list is driven off cubit state so mutations refresh in place. No footer "Close" button — the `×`, the barrier and Esc already close it, and a third route to "do nothing" competes with the one action that matters.
- **Quiet row action icon** (`_CategoryRowAction`): rests at `Colors.black38`, animates to its semantic colour (`AppColors.primary` for edit, `AppColors.error` for delete) on hover over `AppMotion.feedback`. Keeps a list of rows from looking hazardous while still warning at the moment of intent.
- **Descriptive-analytics card** (`AnalyzeCard` + `DashboardAnalyticsService`): the pattern for "what happened" panels. Structure is *provenance line → one headline figure → a 2x2 grid of supporting facts → one health bar*, and each layer answers a different question, which is what stops it reading as a list.
  1. **Say what the numbers rest on**, in the card's `subtitle`: "Based on 308 recorded sales across all bazaars". This is the honest substitute for a disclaimer — it states the source and the scope in one line.
  2. **One figure gets the headline.** Pick the single number the reader can act on without further arithmetic (here: average order value) and give it `headlineSmall`; everything else is `bodyMedium`. Von Restorff only works if exactly one thing is loud.
  3. **Every fact is label / value / evidence**, in fixed positions — never a sentence. A sentence buries its number mid-clause and forces reading; three stacked lines put every value at the same x and weight so the eye scans down a column.
  4. **Cap it at 4-6 figures.** The usual dashboard guidance is 5-7 metrics per view, and the KPI row above already spends four of them. Extra candidates belong in an ordered fallback list, not on screen.
  5. **Don't restate the KPI row.** Totals live up there; this card owns the *breakdowns* — the average behind the total, what sold, where, how it was paid for.
  6. **Degenerate stats must yield their slot.** "Top bazaar" filtered to one bazaar just restates the filter, so the service builds an ordered candidate list and takes the first N that are meaningful. The grid stays full without ever printing a non-finding.
  7. **Withhold a comparison you can't make.** A percent change against an empty baseline computes as "+100%" and reads as growth. Return `null` and render nothing.
- **Section card with a subtitle** (`DashboardSectionCard`): title, optional one-line `subtitle` (period, scope, or record count), optional `trailing`. Put the period in `subtitle` rather than as the first line of `child` — a dashboard where each card states its window in a different place makes the reader re-learn the layout per card. The card also hands `child` the real remaining height when the caller pins one, so a child that lays itself out from `constraints.maxHeight` works inside it.

- **Grouped side navigation** (`SideNavigationRail`): primary navigation for an app with more than a handful of destinations. Structure is *brand + collapse toggle → grouped destinations → session footer*.
  1. **Group by when in the job a destination is needed**, not alphabetically or by how the code is organised. SyncBazaar's runs `Dashboard / Notifications` (unlabelled — where you land), then `BAZAAR` (Preparations → Sales → Documentation, in the order a bazaar actually happens), `RECORDS`, `MANAGE`. Ordering a group chronologically is itself information: it tells a new employee what comes next without documenting it.
  2. **Keep groups to 2-4 items** and give each a heading. Ten identically-weighted rows have no hierarchy — the eye has nowhere to land, so the whole list gets re-read on every visit.
  3. **Headings are conditional.** Role gating can leave a group with one item, and a heading over one row is a label, not a group. Render it only at two or more; the spacing still carries the grouping.
  4. **Collapsed, swap headings for dividers.** There is no room for text, and without a boundary the collapsed rail is one undifferentiated column of icons.
  5. **Collapsed, every row needs a tooltip.** An icon alone is recall, not recognition.
  6. **Counts go at the row's trailing edge**, not pinned to the icon — the chips then line up in a column, so "is anything waiting?" is one glance rather than a scan. Collapsed, the count becomes a dot at the icon's top-right, which is where people already look for one. Never render a zero.
  7. **Actions stay out of the destination list.** Logout sits in the footer, visually distinct, so a mis-tap in the nav can't end the session.
- **Animating a container's width** (`SideNavigationRail`): lay the child out at its *destination* width inside an `OverflowBox` and wrap it in `ClipRect`. An `AnimatedContainer` passes its interpolating width down as a real constraint, so any child with a fixed-width floor overflows for the length of the animation — visible as overflow stripes in debug and as squashed content in release. Clipping also reads better: labels slide in rather than compress.

- **KPI card that reveals a detail section** (`DashboardKpiCard.onTap`/`isExpanded` in the Dashboard): a summary number doubles as the toggle for its own detail view, instead of showing the detail permanently or adding a separate "view details" button. Detail section is hidden by default, revealed via `AnimatedSize` (use `AppMotion.entrance`), and the card shows a small chevron + a highlighted border while expanded so the connection between "this number" and "that section below" stays visible (don't hide a toggle with no visual affordance).

---

## 8. Motion tokens

Defined in `lib/core/constants/motion.dart`. Use these instead of ad hoc `Duration`/`Curve` values.

| Token | Value | Use for |
| --- | --- | --- |
| `AppMotion.feedback` | 140ms | Press-scale feedback (`AnimatedScale` to `0.97`, or `0.985` for large cards). |
| `AppMotion.small` | 180ms | Color/size/opacity state transitions, numeric crossfades. |
| `AppMotion.entrance` | 220ms | New-item entrance animations (fade + grow). |
| `AppMotion.easeOut` | `Cubic(0.23, 1.0, 0.32, 1.0)` | Default for anything entering or responding to input — strong, not the weak built-in `Curves.easeOut`. |
| `AppMotion.easeInOut` | `Cubic(0.77, 0.0, 0.175, 1.0)` | On-screen movement/morphing (rarely needed so far). |

### Before adding any animation, run this gate (in order) — most candidates should fail it:
1. **Frequency** — seen 100+ times/day (keyboard actions, core nav)? Never animate. Tens of times/day (hover, list nav)? Keep it barely-there or skip it. Occasional (modals, cart changes)? Fine to animate normally. Rare/first-time (success, empty states)? This is the only place a little extra delight is earned.
2. **Purpose** — must be one of: feedback, spatial consistency, state indication, preventing a jarring/teleporting change, or (rare-only) delight. "It looks cool" is not a purpose.
3. **Speed** — stay under ~300ms for UI. Press feedback 100-160ms, small popovers/dropdowns 150-250ms, modals 200-500ms.
4. **Function** — never animate data the user is actively trying to read (numbers, charts) for style; a fade-only crossfade is about the ceiling for that case.

Only animate `transform` and `opacity`-equivalent properties where possible (`AnimatedScale`, `AnimatedOpacity`, `FadeTransition`, `SizeTransition`) — cheap, and consistent with how the rest of the app already animates.

---

## 9. Pre-ship checklist for a redesign

1. Re-used existing color/spacing/radius/motion tokens instead of inventing new ones (Sections 3-6, 8)?
2. Reused an existing component recipe (Section 7) if one already fits, instead of a one-off?
3. Disabled states still communicate *why*, and don't blanket-dim information the user needs to read (Section 8, Nielsen callout)?
4. `flutter analyze` run — no new warnings/errors beyond the pre-existing baseline?
5. `flutter build web` succeeds?
6. Said explicitly that the change hasn't been visually verified in a browser, if it hasn't — don't claim a look/feel result you haven't actually seen rendered.

---

## 10. Anti-patterns (avoid these — all were real mistakes fixed this cycle)

- **Mixing widget languages for the same concept.** Don't style one selectable option as a `ChoiceChip` and a conceptually identical one as a custom bordered button. Pick one control and reuse it.
- **Gradients on functional buttons.** They read as dated next to flat cards; use a solid `AppColors.primary` fill instead.
- **A disabled button that still looks fully active.** If `onPressed` is `null`, the button's color must visibly change too — don't let a decorative wrapper (e.g. a gradient `Container`) ignore the enabled state.
- **Blanket `Opacity` over an entire disabled element.** If the element contains information the user needs (a status badge, a date), only mute the *interactive* part (the button), not the informational part.
- **A label above a self-explanatory placeholder.** If the hint text already says what the field is for, a caption above it is redundant — cut one.
- **A dropdown for ≤5 options that would fit as visible chips.** Prefer recognition over recall unless the option list is long or rarely changed.
- **Reusing a hidden/rare accent color as if it were a semantic token.** `AppColors.accent` means "selected" now — don't also use it as a random highlight elsewhere, or selection stops being visually unique (Von Restorff only works if the treatment stays rare).
- **Oversizing secondary controls.** A filter/tag/toggle is not a checkout button — giving it the same padding, font size, and prominence as a primary CTA makes the whole screen feel bulkier and buries the actual primary action. See the button sizing tiers table in Section 4.
- **`InputDecoration.prefixText` / `suffixText` for a unit or currency.** Flutter's `_AffixText` fades these to **opacity 0** until the field is focused or has content — so a "PHP" marker disappears exactly when it's most useful, on an empty field. Use `prefixIcon` with a `Text` child and `prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0)`, and drop `contentPadding.left` to 0 so the spacing comes from the prefix widget.
- **A tinted panel wrapped around fields that are already boxed.** Two containers to say one thing. On a step made of nothing but inputs, the panel adds weight without adding grouping — use a heading plus a hairline rule between groups instead (see `_buildOptionGroup`). Reserve `#F7F7F9` panels for grouping content that *isn't* already visually contained.
- **A link-sized button sitting under full-height inputs.** An "Add value" text button with 8h/6v padding next to 44px fields reads as debris rather than a control. Give a button that acts on a list of fields a real body — a fill, radius 8, ~12h/12v — so it belongs to the same family, and align its left edge with the column it extends.
- **Repeating a column's meaning as placeholder text in every row.** "Value", "Value", "Value" down a list, or a cryptic `+ 0`, is noise; label the columns once above the rows and let the placeholders show real examples.
- **SnackBars for form validation.** They appear at the bottom of the *screen* — away from the dialog, away from the offending field, gone in four seconds, and they never mark which input to fix. Use `_FormField`'s inline error, or a `_StepErrorBanner` for step-level problems.
- **A wizard with invisible steps.** The old product form silently turned "Save" into "Next", twice, with no indication that two more screens existed. If a flow has steps, show them.
- **`TextFormField.initialValue` inside a rebuilt, unkeyed list.** Deleting row 1 of 3 leaves row 2's text sitting in row 1 — Flutter reuses elements by index. Give each editable row a controller owned by its *model object*, not by its position.
- **Controllers created in a `showDialog` closure.** They're never disposed, so every open leaks a set. Long forms belong in a real `StatefulWidget` with a `dispose()`.
- **A modal stacked on a modal to edit one field.** Renaming a list item used to push a second `AlertDialog` over the category manager just to hold one `TextField`. Edit in place in the row instead — the second modal costs an extra open/close round trip and hides the list the user is working against.
- **Popping and re-pushing a dialog to refresh it.** The old category manager called `Navigator.pop` then re-opened itself after every rename/delete, so the surface flashed away and back and lost its scroll position. Drive the dialog off cubit/bloc state and let it rebuild in place.
- **A "Manage X" surface that can't create an X.** The category manager had edit and delete but no add — the only way to create a category was to open the *Add Product* dialog. If a screen is named "manage", it owns the whole lifecycle.
- **A grid tile whose height is derived from its width.** See the `mainAxisExtent` rule in Section 4. Symptom: padding looks right on the machine you designed on and wrong on every other screen size, always with the excess at the bottom of the card.
- **Measuring layout by eye when you can measure it in a test.** Every spacing claim in this pass — the 12/12 gutters that turned out to be fine, the 31-80px of variable dead space that turned out to be the real fault, the Analyze card's 381px natural height — came from a throwaway `testWidgets` that printed `tester.getRect(...)`. Guessing at a fix for a spacing complaint usually fixes the wrong number.

- **Dressing deterministic output as AI.** The dashboard's Analyze card had a brain icon, a "Regenerate insights" button, thumbs up/down, and a footer asking the reader to review "AI-generated content ... for inaccuracies or biases" — wrapped around counts and sums over the sales table. Every one of those affordances was a lie about where the numbers came from, and the feedback buttons collected opinions on arithmetic. If a figure is computed, say what it was computed from; a provenance line ("Based on 308 recorded sales") is the honest version of a disclaimer. Removed 2026-08-02.
- **Naming a screen after the smallest thing it holds.** "Location" managed venues *plus* the incentive and buffer percentages that come off the payout *plus* the payment methods the POS offers there. Anyone hunting for "where do I enable GCash" was never going to look under a word that sounds like an address. Renamed to "Venues & Terms" 2026-08-03. When you rename a section, grep for prose that *points* at it — two other screens said "Configure it in Location section", which the rename would otherwise have turned into a dead reference.
- **An action in one place and its result in another.** Settings had a "Sync now" button while the status of that same sync lived in the top bar, so you pressed here and watched there. The status line is the obvious thing to press; putting the action on it removed both the round trip and a duplicate entry point.
- **`late final` for an object whose only guaranteed read is `dispose()`.** A spinner's `AnimationController` was a `late final` field initialiser and only touched when animating — so on a screen that never animated, `dispose()` was the first read and constructed a controller against an already-deactivated element ("Looking up a deactivated widget's ancestor is unsafe"). Build anything you will dispose in `initState`.

- **A bespoke dialog next to a shared one that already solved it.** The POS's Confirm Sale was hand-rolled and reproduced, verbatim, all three faults `confirmation_dialog.dart` had been rewritten to remove — **Cancel red and Confirm green** (the alarming colour on the safe choice), both buttons equal-width and full-bleed, and icons on a two-word decision. Before writing a dialog, check whether `showConfirmationDialog` covers it; if it genuinely does not — a checkout needs a summary, not a sentence — copy its *structure* (header / hairline / body / hairline / footer, radius 14, quiet Cancel, primary right, `autofocus` on the primary) rather than starting from `Dialog`. Fixed 2026-08-03.
- **A confirmation that confirms nothing.** The old one showed a total and nothing else. At a till the arithmetic is not what goes wrong — the payment method is. A confirm step should read back what is actually being committed, or it is just a speed bump.
- **Assuming a button is as wide as its padding.** Material's defaults make an `ElevatedButton` far wider than `horizontal padding × 2 + text`; "Confirm sale" measured 224px against an expected ~139. A two-button footer sized by arithmetic will overflow. Measure it in a test and pin the dialog width.

- **A bordered button for a once-a-shift action.** "Back to Bazaar Selection" was an outlined purple button sitting at the same visual weight as the search field next to it. Leaving a bazaar happens once a shift; searching happens constantly. It is now a breadcrumb — and the space it freed went to naming the bazaar you are selling at, which the panel had never shown.
- **A hard `crossAxisCount` on a resizable panel.** Four columns looks right at the width you tuned it on and clips the card's button on a laptop. Compute the count from a minimum readable card width and floor the tile height (see the `mainAxisExtent` rule in Section 4).
- **Two summary rows printing the same number.** Once the order-level discount went, "Subtotal" and "Total Payment" were the same figure stacked two rows apart. If a breakdown has nothing left to break down, it is not a breakdown — replace it with something the total does not already say (here, the item and unit count).

- **A flat navigation list.** Ten destinations at one weight, one size and one colour, in no particular order. Every visit costs a full re-read because nothing tells you where to look. Group them, and order the groups by the workflow rather than by the codebase.
- **A hardcoded badge over a real, unread store.** The nav bell showed `isAdminOrOwner ? 2 : 1` and opened a SnackBar with invented text, while the `NotificationService` that `SyncService` had always been writing to had no reader anywhere in the app. A count is a promise that something is waiting; a fabricated one teaches people to ignore every badge you ever show them. Fixed 2026-08-03.
- **Deriving an id from `list.length`.** `NotificationService` numbered new notices `_notifications.length + 1`, which repeats as soon as anything but an append touches the list. Use a monotonic counter.
- **A chrome bar kept alive by one control.** Once notifications moved into the rail, the 64px top bar held a single sync chip — and two constructor parameters (`user`, `onLogout`) that its `build` never referenced. If a container is down to one child, fold the child in and delete the container.

- **A percent change with no baseline.** The Average Daily Sales card's trend pill read a flat `+100.0%` because `_percentChange` returned a literal `100` whenever the previous period held no transactions — a fallback constant wearing the clothes of a measurement, and one that never moved no matter what the sales did. Same family as the fabricated fallbacks above. If a comparison has no baseline, render nothing; if the surface looks empty without it, the metric was decoration. Pill and computation removed 2026-08-03.
- **A trend indicator that describes the chart it is sitting on.** The same pill compared *this week against last week* while the chart underneath drew *Monday to Friday of this week* — two different questions, with nothing on the card saying which one the pill answered. A reader will always attribute a number in a chart's header to the line below it. Either the indicator says something the chart cannot, or it does not belong there.

- **Hardcoded sample data as an empty-state fallback.** The same card fell back to four invented sentences — "₱120,450", "Sneaker Model X", "62% of transactions" — whenever the real list came back empty, so a brand-new account saw fabricated figures rendered exactly like real ones. Ship an empty state that names what's missing and what will fill it. Never fill a card with numbers the user could mistake for their own.
- **Prose where a stat belongs.** Seven full sentences at one weight, each with its number buried mid-clause, inside a 180px scroller. There is nothing to scan and no hierarchy. Split every fact into label / value / evidence and let the values line up.
- **Repeating the summary row inside the detail panel.** The card's first two lines restated the "Total Sale" and "Today's Sale" KPI cards sitting directly above it. A panel below a summary should own what the summary *can't* show.
- **Assuming a `Column` child has bounded height.** A `Column` passes its non-flexible children `maxHeight: infinity` even when the Column itself is pinned to a fixed size. A child that branches on `constraints.maxHeight.isFinite` will therefore take the unbounded path and overflow the parent by however much it guessed wrong. If a container accepts a caller-set height, it has to hand the child the real remainder (`Expanded`) — see `DashboardSectionCard`.
- **A fixed height shared by two side-by-side cards, left to guesswork.** Pick it from the taller card's *measured* natural height at the narrowest width the layout runs at, let the other card stretch to fill, and pin it with a widget test. Guessing low silently pushes content behind a scroller; guessing high leaves dead space.

- **One button doing what a cycling toggle could do more compactly.** When a control picks one value from a small, ordered set (e.g. a status filter), a single button that cycles through the states on tap is often smaller and just as fast as a row of separate toggle buttons — consider it before reaching for N buttons.

- **Picking an inner element's corner radius by habit instead of deriving it.** The POS product card's Add button was radius 8 — the default for buttons — inside a radius-16 card with an uneven 10/8 inset. Three numbers, none of them agreeing. When something rounded sits inside something else rounded, the inner radius is `outer − gap` (Section 5); reaching for the default leaves the corner visibly wrong. Name all three as constants so the relation survives the next spacing tweak, and measure the *rendered* gap in a test rather than trusting the constants to still be wired up. Fixed 2026-08-03.
