# Design system (theme, colour roles, affordance)

Everything visual is defined in `lib/src/theme/`:
`app_theme.dart` (both `ThemeData`s), `accent_colors.dart` and `glucose_colors.dart`
(two `ThemeExtension`s). No widget invents a colour — if a value is needed that
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

## Two accents, because one colour cannot do both jobs

The brand indigo-blue has to serve two opposite purposes on a dark background, and
a single value loses one of them:

- **Fill** — a button with white text on top. Wants a mid tone.
- **Foreground** — a label or glyph drawn *on* a dark surface. Wants a light tone.

So there are two, same hue:

| Token | Dark | Light | Used for |
|---|---|---|---|
| `colorScheme.primary` | `#5D73CC` | `#45569F` | Fills only: filled/elevated buttons, solid badges, tints |
| `AccentColors.onSurface` (`context.accent`) | `#9DACEA` | `#45569F` | The accent drawn ON a surface |

On light they are the same colour — a deep indigo-blue on a near-white page is
legible either way. The split exists purely because dark forces it.

The indigo-blue is the old brand indigo pulled part-way toward the calm blue-grey
of the surfaces (statistic boxes): softened from the original neon, but kept
saturated enough to read as a real accent rather than grey. On dark it is lifted
a touch (`#5D73CC`) so it sits ON the surface instead of glowing off it.

Rejected alternative, for the record: the textbook Material 3 move is a light
`primary` plus a dark `onPrimary`, which fixes every foreground with one value
and zero call-site edits. It was tried and reverted — it turns every filled
button into light-indigo-with-dark-text, which is not the product's look.

## Three foreground tones

| Tone | Token | Means |
|---|---|---|
| Full | `onSurface` (white / black) | Primary text, and **bare controls** — `IconButton` and `TextButton` — at full strength |
| Accent | `context.accent` | Interactive affordances that carry the brand: outlined-button labels, chevrons, tappable banners, summary-tile glyphs |
| Muted | `onSurfaceVariant` (`#A6AEBF` / `#5A6070`) | Anything that only informs: glyphs beside a statistic, secondary labels, units |

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

Dark steps **up** from the page, light steps **down** — because in light the page
is the brightest thing on screen. (This matches how Material 3's own light scheme
is built, and it is why "raised" is *darker* than the box it sits in.)

| Rung | Dark | Light |
|---|---|---|
| Page / app bar | `#15181D` | `#FAFAFA` |
| Box (`surface`) | `#1F232A` | `#E8E8E8` |
| `surfaceContainerHigh` | `#242933` | `#E1E4E9` |
| `surfaceContainerHighest` (badges, inputs) | `#2A2F38` | `#D8DCE3` |
| Border / divider | `#2B3038` | `#B4B9C2` (`outline`) |

The dark neutrals take their **hue** from the insulink website
(`assets/css/style.css`: `--bg #0d1117`, `--surface #161b22`, …) so app and site
stay related, but they are lifted a rung and pulled well down in saturation. The
site's values are near-black and strongly blue; on a phone at arm's length that
made the accent glare and left too little separation for cards to read as cards.
Grey with a blue lean, not blue-grey.

`dividerColor` doubles as the box border (`OverviewSection`), so it must stay
close to `surface`. A border much lighter than its fill draws a hard ring around
every card.

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

## Reference contrast values (dark)

Measured against `surface #1F232A`, for calibrating future changes:

| Pair | Ratio |
|---|---|
| `primary #5D73CC` as a foreground | ~4.4:1 — the reason the accent exists |
| same at `alpha: 0.7` | ~2.9:1 — under even the 3:1 floor for graphics |
| `accent #9DACEA` as a foreground | ~7.6:1 |
| `primary` behind white text | ~4.1:1 |

Non-text/graphics need ≥3:1, normal text ≥4.5:1.
