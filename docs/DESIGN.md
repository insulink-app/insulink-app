# Design system (theme, colour roles, affordance)

Everything visual is defined in `lib/src/theme/`:
`insulink_colors.dart` (the design tokens), `app_theme.dart` (both `ThemeData`s,
built from the tokens) and the `ThemeExtension`s fed from them. No widget invents a colour — if a value is needed that
the scheme has no role for, the role is added here, not hard-coded at the call site.

## The one rule that explains most of the file

**A `ColorScheme` role you don't set does not fall back to something sensible —
it silently aliases to another role, and the alias is usually wrong.**

This cost several rounds of "why does that look broken". Verified against the
Flutter source (`packages/flutter/lib/src/material/color_scheme.dart`):

| Role left unset | Resolves to | What that produced here |
|---|---|---|
| `surfaceContainer*` | `surface` | Badges the exact colour of the card they sit in — **invisible** |
| `outline` | `onBackground` | Pure **white** (dark) / **black** (light) rims on every `OutlinedButton` |
| `onSurfaceVariant` | `onSurface` | Decorative glyphs at full white — same weight as the value they annotate |

And Material's component defaults pick roles you may not expect:

| Component | Default foreground | Consequence |
|---|---|---|
| `TextButton`, `OutlinedButton` | `colorScheme.primary` | The **fill** colour used as a label ⇒ ~4:1 on dark |
| `OutlinedButton` side | `colorScheme.outline` | See above |
| `IconButton` | `colorScheme.onSurfaceVariant` | A control wearing the tone that means "decoration" |

**Therefore: a role set in one theme must be set in the other.** Both schemes
currently set the same nine roles; keep that list symmetric. A quick check:

```bash
sed -n '/ColorScheme.light(/,/^    ),/p' lib/src/theme/app_theme.dart | grep -oE "^\s+[a-zA-Z]+:" | sort > /tmp/l
sed -n '/ColorScheme.dark(/,/^    ),/p'  lib/src/theme/app_theme.dart | grep -oE "^\s+[a-zA-Z]+:" | sort > /tmp/d
diff /tmp/l /tmp/d && echo "symmetric"
```

## Tokens, and one accent

Since the redesign (reference: `docs/redesign/`) every colour starts in
`InsulinkColors` (`insulink_colors.dart`, read as `context.insulinkColors`).
`AppTheme` builds both themes through **one** builder from those tokens, so a
role can no longer be set in one theme and missed in the other; the symmetry
check below still holds by construction.

| Token | Dark | Light | Used for |
|---|---|---|---|
| ground | `#0F1B26` | `#EDF2F6` | Page, app bar |
| panel | `#152432` | `#FFFFFF` | Panels, tiles, header buttons (`surface`) |
| line | `#26394B` | `#D3DEE7` | Dividers, empty segments |
| border | text at 7 % | text at 6 % | 1 px rim of tiles and buttons |
| text | `#EAF1F6` | `#0F1B26` | Primary text, glucose value (`onSurface`) |
| muted | `#97A9BA` | `#4D6175` | Labels, units, axes (`onSurfaceVariant`) |
| accent | `#9DAEFF` | `#3346C8` | `primary`, `context.accent`, icons, progress |
| onAccent | `#0F1B26` | `#FFFFFF` | `onPrimary` |
| accentSoft / accentText | accent at 16 % / `#C4CEFF` | accent at 10 % / `#2A3AA8` | Active tab, profile button |
| range / high / low | `#7CCB8F` / `#F4B740` / `#FF6B7F` | `#3B8A4F` / `#A86A00` / `#C8293F` | `GlucoseColors` and `StatusColors` |
| lowSoft | low at 14 % | low at 10 % | Warning banners |
| dock | `#1B2B3B` | `#FFFFFF` | Navigation capsule (with `dockShadow`, the only shadow) |

**One accent.** The app used to split the brand colour into a mid-tone FILL
(`primary`, white text on top) and a lighter FOREGROUND (`context.accent`),
because on dark one value could not do both. The redesign gives that up on
purpose: `primary` IS the accent, and what sits on it takes `onPrimary`, which on
dark is the dark ground colour. Every filled button is therefore light indigo
with dark content on dark. The consequence for call sites: **never put a literal
`Colors.white` on a `primary` fill**, use `onPrimary` or the button's own
foreground.

The font is **Atkinson Hyperlegible Next**, bundled in `assets/fonts/` (400, 600,
700, 800; OFL). Every `TextTheme` role carries `FontFeature.tabularFigures()`,
and inline styles inherit it through the default text style, so ticking numbers
do not jitter.

## Redesign building blocks

The overview (reference: `docs/redesign/`) is built from these; reuse them
before drawing a new bar or button.

| Widget | File | What it is |
|---|---|---|
| `SegmentBar` | `base/segment_bar.dart` | Rounded segments with gaps: range scale, time in range, device days (`.count`) |
| `HeaderIconButton` | `base/header_icon_button.dart` | 44 px round header button, optional status dot ringed in `ground` |
| `FloatingDock` | `base/floating_dock.dart` | Tab capsule plus the round bolus button |
| `DockTabs` | `base/dock_tabs.dart` | The tabs in the capsule: one pill that springs between them and follows a horizontal drag |
| `TabTransition` | `base/tab_transition.dart` | Fade plus a short slide from the tab's side on every tab change |
| `DeviceAttention` | `connections/device_attention.dart` | Which devices need the user; the header dot and the devices page rows both read it |
| `GlucoseHero` | `overview/glucose_hero.dart` | Value, rotated trend arrow, unit and trend words |
| `RangeScale` | `overview/range_scale.dart` | 40 to 250 mg/dL scale split at the user's targets, knob on the value |
| `OverviewDevices` | `overview/overview_devices.dart` | Sensor, pod and reservoir, automation row, in one panel |
| `InsulinkTextStyles` | `theme/insulink_text_styles.dart` | The spec's type roles (value 124/800, stat 30/800, …) |

Three things that are not obvious:

- **The redesign's type roles are NOT on the `TextTheme`.** Material draws its
  own widgets from those roles (`headlineSmall` is every dialog title,
  `bodyLarge` every text field), so mapping 30/800 onto them would blow up
  dialogs and inputs. They live in `InsulinkTextStyles` instead.
- **The dock sits in the scaffold's navigation slot, not over the body.** The
  page ends where the dock starts, so no tab's last rows can hide behind it
  (every tab pads its own scroll view, and `extendBody` would have needed all
  nine of them changed). The fade the content runs out into is only painted
  32 px above the slot, behind an `IgnorePointer`.
- **A `DecoratedBox` without a child has no height.** In a `Row` it gets its
  width from `Expanded` but collapses to 0 px tall unless the row stretches its
  children; `SegmentBar` sets `CrossAxisAlignment.stretch` for exactly this
  (`test/base/segment_bar_test.dart`).

Numbers on the overview are German notation (`GlucoseDisplayFormat`,
`sportDecimal`), like the Sport tiles. `ProfileGlucoseState.format` keeps its
plain format because the home-screen widget, fed from the service isolate,
reads it too.

## Three foreground tones

| Tone | Token | Means |
|---|---|---|
| Full | `onSurface` (white / black) | Primary text, and **bare controls** — `IconButton` and `TextButton` — at full strength |
| Accent | `context.accent` | Interactive affordances that carry the brand: outlined-button labels, chevrons, tappable banners, summary-tile glyphs |
| Muted | `onSurfaceVariant` (`#97A9BA` / `#4D6175`) | Anything that only informs: glyphs beside a statistic, secondary labels, units |

A control **without a container of its own** (`IconButton`, `TextButton`) takes
the Full tone, not the accent: tinting it made routine actions shout, and the
light accent read as washed-out as a label. A control that *has* a container
(`OutlinedButton`'s rim, a tinted card) can carry the accent, because the accent
then belongs to a shape rather than floating in the text.

The load-bearing half is **muted vs. everything else**. Before this split, a
decorative glyph and a control looked identical, and users could not tell what
was pressable. Never give decoration the accent.

`onSurface.withValues(alpha: 0.6)` is an older muted idiom still in use for
secondary *text*. It is fine; `onSurfaceVariant` is preferred for new code.

## Status colours, and the one red family

`StatusColors` (`status_colors.dart`) carries what `ColorScheme` has no honest
role for. Read as `context.danger` / `context.warning` / `context.positive`.

| Need | Token | Why not a scheme role |
|---|---|---|
| Error **text** | `context.danger` | `colorScheme.error` is a FILL (delete's confirm button, nav badge) and only makes ~4:1 as a label on dark — the same trap `primary` falls into |
| Amber: off-nominal | `context.warning` | No role exists. An overdue reading, a sensor in its grace period |
| Green: went well | `context.positive` | No role exists. A weight trending down, a success alert |

Both the reds and the green are drawn from the family the app already speaks in
`GlucoseColors`, so the product has **one** red rather than Material's stock
maroon standing next to the chart's red. They are still separate tokens on
purpose: `GlucoseColors` is the *language of glucose*, read by the chart and the
readouts — a delete button borrowing its red would tie two unrelated meanings
together, and a change to one would silently move the other.

The rule at a call site: **does the colour fill a shape, or draw on one?** Fill →
`colorScheme.error`. Draw (label, glyph, an `Alert`'s `iconColor`) → `context.danger`.

## Brand tints

`BrandTints` (`brand_tints.dart`) — an extension on `ColorScheme`, not a
`ThemeExtension`, because a tint is computed (`primary` over whatever is beneath)
and needs a name, not a per-theme value.

| Token | Alpha | For |
|---|---|---|
| `scheme.tintPanel` | 0.08 | A panel/card/chip washed with the brand colour |
| `scheme.tintSelected` | 0.14 | The chosen row of a selection |
| `scheme.tintLine` | 0.20 | A tinted rim |

Nine different alphas were in use for those three ideas, each guessed locally.
That is the ground the badge problem grew on: with no shared value, "a faint
tinted card" meant something different on every page and the icon on top had
nothing stable to contrast against.

**A scale is not a tint.** A progress fill that brightens toward its goal, or a
button dimmed to half while disabled, carries information in its alpha — leave
those alone.

## Shape language

| Silhouette | Meaning | Example |
|---|---|---|
| Filled **circle**, neutral | The row's identity — never pressable | `SportLeadingBadge`, `EmptyState`, `FoodProductCard` |
| Filled **circle**, `primary` | A control that happens to be round | `drink_add_row` quick-add (the `InkWell` wraps the circle itself) |
| Bare glyph | Information, or a tile that is itself the control | `SportSummaryTile`, stat rows |
| Filled rounded-rect + label | The obvious button | `FilledButton`, `cardio_section` start buttons |

Two things were tried and **rejected** — don't reintroduce them:

- **Tinted square faces with rims on every `IconButton`** (via `iconButtonTheme`).
  It marks controls unambiguously and reads as clutter on app bars and dense rows.
  The theme now sets only the icon-button *colour*, no face.
- **A badge inside `SportSummaryTile`.** That tile is already a control (tinted
  face, border, progress fill). A badge inside it is a second competing shape:
  filled it looked like a button parked on a button, neutral it punched a grey
  hole through the tint. The glyph goes bare there.

## Surface ladders

Dark steps **up** from the page, light puts white panels on a faintly blue-grey
page and steps **down** from the panel. Both fall out of one rule: the
`surfaceContainer*` rungs are mixed from `panel` toward `line` (35 % and 70 %),
which is lighter than the panel on dark and deeper on light.

| Rung | Dark | Light |
|---|---|---|
| Page / app bar (ground) | `#0F1B26` | `#EDF2F6` |
| Panel (`surface`) | `#152432` | `#FFFFFF` |
| `surfaceContainerHigh` | `#1B2B3B` | `#F0F3F7` |
| `surfaceContainerHighest` (badges, inputs, popups) | `#213344` | `#E0E8EE` |
| Divider (line) | `#26394B` | `#D3DEE7` |
| `outline` (line 40 % toward muted) | `#536677` | `#9DACB9` |

`dividerColor` doubles as the `OverviewSection` border; the redesign drops that
border on panels (only tiles keep the faint `border` token).

## Rules for call sites

- **Never hard-code a colour.** `Colors.grey[500]` on the light page is 2.6:1 —
  it fails legibility outright, and it cannot follow the theme. All of them were
  converted to `onSurfaceVariant`. The remaining `Colors.white` uses are
  legitimate: camera overlays and map markers sit on foreign content.
- **Don't restate what the theme already says.** A local
  `styleFrom(foregroundColor: …, side: …)` silently beats the theme — this is why
  the injection page's `OutlinedButton` ignored a global fix
  (`injection_products_tab.dart`). Pass only what is genuinely local (size, shape).
- **Pair `primary` with `onPrimary`**, never with a literal `Colors.white`. The
  app does this consistently; it is what would make a future scheme change safe.
- Icons come from **Phosphor**, `Regular` weight — except `todayTileIcon` /
  `nutritionTileIcon`, which are `Bold`. Those glyphs are drawn bare with no badge
  behind them, where a thin stroke washes out. Weight, not colour, is the lever
  for "make it clearer without making it louder".

## Notices: no snackbars

**Do not add a `SnackBar`.** They were all removed (2026-07-15) and none should
come back. A snackbar is one gesture for five different situations: it covers the
content, it times out whether or not it was read, and it appears far from whatever
the user just touched.

Replacing them is not a search-and-replace — each site gets the vessel its own
message needs. Three questions decide it:

1. **Is it an event, or a standing condition?** A denied permission or a missing
   Health Connect stays true until the user changes something in system settings.
   That is *state*: it belongs in the UI that shows state, and it must survive
   leaving and reopening the page. `GoogleHealthState.connectFailure` is the
   pattern — the state records it, the status box renders it in place of its hint.
2. **Must it be read and answered?** Then it waits for the user: use `Alert`
   (`lib/src/alert/alert.dart`, `AlertType.error`), which the app already has.
   That's for dead ends carrying information the user needs in order to act — a
   failed NFC activation with the driver's error text, a denied import.
3. **Otherwise it is a confirmation, and it belongs ON the control** the user just
   pressed — nothing to read, nothing to dismiss, and the page stays uncovered.
   Swap the button's own icon/label for a checkmark on a `Timer` (~2 s) and revert;
   cancel the timer in `dispose`. See `_CopyLogButton` (`developer_log_panel.dart`).

Two more rules that fell out of doing it:

- **A success often needs no message at all.** After the health import, the
  numbers on the page behind the card have already changed — that IS the feedback.
  The card only nods with a checkmark.
- **Safety-relevant failures are sticky, never timed.** The bolus confirmation's
  biometric failure replaces the hint above the button in `colorScheme.error` and
  stays until the user retries (`injection_confirm_page.dart`). A bolus that did
  not go through must not be reported by something that disappears on its own.

Where the five went: `injection_confirm_page` (sticky inline error),
`libre3_scan_flow` (`Alert`), `google_health_status_box` (state, rendered inline),
`health_import_button` (checkmark on success / `Alert` on failure),
`developer_log_panel` (self-confirming button).

## Reference contrast values

Measured for calibrating future changes (WCAG; text ≥4.5:1, graphics ≥3:1):

| Pair | Dark | Light |
|---|---|---|
| accent on panel | 7.5:1 | 7.4:1 |
| onAccent on accent | 8.2:1 | 7.4:1 |
| muted on ground | 7.2:1 | 5.7:1 |
| low on ground | 6.4:1 | 4.8:1 |
| high on ground | 9.7:1 | **3.9:1** |
| range on ground | 9.0:1 | **3.8:1** |

The light `high` and `range` tokens clear the graphics floor but not the text
floor on the page. They are fine for the chart, bars and large numbers; as
`context.warning` / `context.positive` small TEXT they are under 4.5:1.

## Insulin has its own two colours

`InsulinColors` (`context.insulin.basal` / `.bolus`), a role of its own rather
than borrowed from anywhere else. `GlucoseColors` is the language of glucose and
must not move when insulin does, and the accent already means "this is a control
you can press". Insulin is neither: it is data, with exactly two kinds that have
to be told apart at a glance.

Both come from the brand indigo, because insulin is not a warning. **Bolus** is
the stronger of the two, a dose someone chose arriving all at once. **Basal** is
the quieter one, the background drip the boluses stand on. The pair swaps weight
between themes: on dark the LIGHTER indigo is the loud one.

| | basal | bolus | basal vs surface | bolus vs surface | basal vs bolus |
|---|---|---|---|---|---|
| light | `#8894CE` | `#45569F` | 2.93 | 6.81 | 2.33 |
| dark | `#5C6BA6` | `#9DACEA` | 3.08 | 7.15 | 2.32 |

Measured against each theme's **surface**, which in light is white since the
boxes became white. On the earlier `#E8E8E8` boxes a first pass at `#9AA6D8` for
light basal made only 1.94, which is why the surface, not paper white, is what
gets measured.

`test/theme/insulin_colors_test.dart` pins all three relationships, including
that neither value is one of the glucose tones.

## The insulin chart borrows the glucose chart's language

The two are stacked and share one time axis, so anything that differs between
them reads as "two unrelated pictures". Three things had to be copied exactly
rather than approximated:

| | value | why |
|---|---|---|
| left axis strip | `24` | must equal the glucose chart's `reservedSize`, or the plot areas start at different x and every bar sits BESIDE its glucose |
| gridlines | `blueGrey`, `0.4`, dash `[8, 4]` | fl_chart's `defaultGridLine`, which is what the chart above draws. Solid divider-coloured lines at `1.0` were the first attempt and looked like another chart |
| scrub + tooltip | dashed `[4, 4]` at `onSurface` 0.35; pill in `inverseSurface` | one gesture across the pair should look like one gesture |

The bars are hand-painted rather than handed to `BarChart`, and that is not
preference: `BarChart` lays groups out in the order given and spaces them evenly.
A group's `x` is a label, not a position, so bars drawn that way sit at even
intervals no matter when the insulin went in, and a chart claiming a shared time
axis would be showing something else.

**Basal and bolus are different SHAPES, not just different colours.** Basal is an
hour the pump spent delivering, so it is a band covering that hour; a bolus is a
moment, so it is a narrower bar standing in front of the band. This is what makes
the ordinary case legible: a dose almost always lands inside an hour that was also
running basal, and it reads as having happened DURING that hour rather than
colliding with it. Two equal bars fighting for the same pixels could only be read
wrong.

Hit-testing follows the shapes: a band is hit anywhere inside its hour, a spike
within `bolusReach` of itself, and the bolus wins where both are hit. Measuring to
the band's START instead was a real bug: a point at :55, plainly inside the hour,
selected a bolus given at :20.

**Selection follows the shapes too.** A bolus is a moment and is in the window or
out of it. An hour of basal is a stretch, so it belongs on screen whenever any
part of it OVERLAPS the window. Requiring its start to be inside was the second
bug of the same kind: a window opening at 09:30 dropped the 09:00 hour entirely,
so a band whose remainder was plainly visible vanished at the left edge.

A clipped band is drawn at its FULL height, because that is the rate the hour ran,
with a square corner and no separating gap on the cut side: a rounded corner says
"the band ends here", and this one runs on past the edge. The legend answers a
different question and counts only the share on screen, pro rata, which within an
hour is exact rather than an approximation because the pump runs one rate through
it.

## Not every page wants the fading pinned header

`PinnedHeaderScroll` suits a box that is only ever READ: it dissolves as the
detail list takes its place, and past half transparency it stops accepting
touches (`IgnorePointer`). The pump page's top holds the automation switch, so it
uses a plain scroll instead. A control that fades while you scroll towards the
list underneath it is distracting, and one that silently stops being tappable is
worse.
