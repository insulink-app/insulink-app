import 'package:flutter/material.dart';
import 'package:insulink/src/theme/accent_colors.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:insulink/src/theme/insulin_colors.dart';
import 'package:insulink/src/theme/stat_box_colors.dart';
import 'package:insulink/src/theme/status_colors.dart';

/// The app's light and dark Material 3 themes. Kept out of `main.dart` so the
/// shell there stays a thin wiring layer.
class AppTheme {
  const AppTheme._();

  /// Shared corner radius for every button, so the whole app matches.
  static const double buttonRadius = 14;

  /// Foreground (text/icon) on primary-coloured (indigo) buttons. White in both
  /// themes; change here to retint every filled/elevated button at once.
  static const Color onPrimary = Colors.white;

  static final RoundedRectangleBorder _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(buttonRadius),
  );

  static final FilledButtonThemeData _filledButtons = FilledButtonThemeData(
    style: FilledButton.styleFrom(shape: _buttonShape),
  );
  static final ElevatedButtonThemeData _elevatedButtons =
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(shape: _buttonShape),
      );

  /// [OutlinedButton] draws its label in `colorScheme.primary` and its rim in
  /// `colorScheme.outline`. Neither default works on the dark theme: the accent
  /// that fills a button well is too dark to read as text on a dark surface, and
  /// an unset `outline` falls back to white. Both are passed in per theme rather
  /// than bent globally, so the fill accent stays as it is. Null keeps the
  /// Material default (the light theme needs no correction).
  static OutlinedButtonThemeData _outlinedButtonsFor({
    Color? foreground,
    Color? rim,
  }) {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: _buttonShape,
        foregroundColor: foreground,
        side: rim == null ? null : BorderSide(color: rim),
      ),
    );
  }

  /// [TextButton]s ("Mehr anzeigen" and friends) carry no colour — the same call
  /// as [_iconButtonsFor], and for the same reason: a bare control reads better
  /// at full strength than tinted. Pass the theme's `onSurface`.
  ///
  /// A value must be passed either way. Material draws the label in
  /// `colorScheme.primary`, which is tuned to be a FILL behind white text and
  /// manages only ~4:1 as a label on a dark surface.
  static TextButtonThemeData _textButtonsFor(Color foreground) {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: _buttonShape,
        foregroundColor: foreground,
      ),
    );
  }

  /// [IconButton]s stay plain: no face, no rim, no accent. A tinted square face
  /// was tried to mark them as pressable and read as clutter on every app bar
  /// and dense row, and tinting the glyph made routine actions shout.
  ///
  /// Pass the theme's `onSurface`. It must be stated rather than left out:
  /// Material resolves an icon button's foreground to `onSurfaceVariant`, which
  /// this app deliberately sets to a muted tone for DECORATION — so omitting
  /// this would hand every control the colour that means "just information".
  static IconButtonThemeData _iconButtonsFor(Color foreground) {
    return IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: foreground),
    );
  }

  /// Modern, filled, borderless text fields with a soft rounded shape — the
  /// focused state gets a thin primary ring. One place styles every [TextField]
  /// in the app (auth, sport editors, …).
  static InputDecorationTheme _inputTheme(
    Color fill,
    Color primary,
    Color label,
  ) {
    OutlineInputBorder ring(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(buttonRadius),
      borderSide: BorderSide(color: color, width: width),
    );
    return InputDecorationTheme(
      filled: true,
      fillColor: fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: ring(Colors.transparent, 0),
      enabledBorder: ring(Colors.transparent, 0),
      focusedBorder: ring(primary, 1.6),
      // The floating label defaults to `primary` when focused, which reads as a
      // second accent in the field's corner. Keep it a plain neutral grey — the
      // muted scheme tone still leans blue, which the user didn't want here.
      floatingLabelStyle: TextStyle(color: label),
    );
  }

  /// Popup/overflow menus sit ON TOP of content, so they take the most raised
  /// surface rung — the one furthest from the page in both themes — to stand out
  /// as a floating layer rather than blend into the card beneath.
  static PopupMenuThemeData _popupMenu(Color color) => PopupMenuThemeData(
    color: color,
    elevation: 3,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  );

  /// An indigo-blue: the brand accent pulled a little toward the calm blue-grey
  /// of the surfaces, but kept saturated enough to read as a real accent rather
  /// than grey. Dark enough to carry white button labels.
  static final Color lightPrimary = const Color(0xFF45569F);

  /// The light theme's surface ladder: a faintly grey page with white boxes and
  /// a white navigation bar on it, so a card reads as a sheet lying on the page.
  /// From the box the ladder steps DOWN: anything that sits IN a box (badges,
  /// inputs) goes a shade deeper than the white it sits on, which is why
  /// "raised" is darker than its box, the inverse of the dark theme.
  ///
  /// An earlier ladder made the page the brightest thing (#FAFAFA) and the boxes
  /// grey; the boxes then read as holes in the page rather than as cards.
  ///
  /// [_lightSurfaceRaised] is what badges are made of. It MUST differ from
  /// [_lightSurface]: leaving it unset resolves it to `surface`, i.e. exactly the
  /// colour of the box the badge sits in, and every badge in the app vanishes.
  static const Color _lightBg = Color(0xFFF2F3F5);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightSurfaceHigh = Color(0xFFEDEFF2);
  static const Color _lightSurfaceRaised = Color(0xFFE4E7EC);

  /// Divider + box border ([OverviewSection]), the light twin of [_darkBorder]
  /// and kept close to [_lightSurface] for the same reason: a border far from its
  /// fill rings every card. Opaque, not a translucent black — a `Colors.black12`
  /// picks up whatever is behind it, so the same divider came out a different
  /// colour on the page than inside a box.
  static const Color _lightBorder = Color(0xFFE3E6EB);

  /// Rim for outlined controls. Set for the same reason as [_darkOutline]: left
  /// out, [ColorScheme] resolves `outline` to `onBackground` — pure black here,
  /// which puts a hard rule around every [OutlinedButton].
  static const Color _lightOutline = Color(0xFFB4B9C2);

  /// The light counterpart of [_darkMuted] — the tone for glyphs and labels that
  /// only inform. Darker than it looks it should be: this sits on a near-white
  /// page, where anything lighter stops being readable.
  static const Color _lightMuted = Color(0xFF5A6070);

  /// Danger and warning. On light one tone does both jobs — deep enough to fill a
  /// button behind white text AND to be read as a label on the page — so
  /// [StatusColors.danger] is simply the same value as the scheme's `error`.
  /// Dark has to split them; see [_darkError] / [_darkDanger].
  ///
  /// Drawn from the same red the app already speaks (`GlucoseColors`), so the
  /// product has ONE red family rather than Material's stock maroon next to it.
  static const Color _lightError = Color(0xFFC42108);
  static const Color _lightWarning = Color(0xFF9A5B00);
  static const Color _lightPositive = Color(0xFF0F6B34);

  static final ThemeData light = ThemeData(
    useMaterial3: true,
    primaryColor: Colors.black,
    colorScheme: ColorScheme.light(
      primary: lightPrimary,
      onPrimary: onPrimary,
      // ponytail: default secondary is teal — align it to the slate-blue brand
      // so chips/date-pickers stop tinting turquoise.
      secondary: lightPrimary,
      surface: _lightSurface,
      surfaceContainerHigh: _lightSurfaceHigh,
      surfaceContainerHighest: _lightSurfaceRaised,
      outline: _lightOutline,
      onSurfaceVariant: _lightMuted,
      error: _lightError,
      onError: Colors.white,
    ),
    filledButtonTheme: _filledButtons,
    elevatedButtonTheme: _elevatedButtons,
    outlinedButtonTheme: _outlinedButtonsFor(),
    textButtonTheme: _textButtonsFor(Colors.black),
    iconButtonTheme: _iconButtonsFor(Colors.black),
    inputDecorationTheme: _inputTheme(
      _lightSurfaceRaised,
      lightPrimary,
      const Color(0xFF757575),
    ),
    popupMenuTheme: _popupMenu(_lightSurfaceRaised),
    appBarTheme: const AppBarTheme(backgroundColor: _lightBg),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: _lightSurface,
    ),
    scaffoldBackgroundColor: _lightBg,
    dividerColor: _lightBorder,
    extensions: [
      GlucoseColors.standard,
      AccentColors(onSurface: lightPrimary),
      // The stat boxes keep the original brand indigo, decoupled from the
      // (later softened) primary — see StatBoxColors.
      const StatBoxColors(icon: Color(0xFF3F51B5), tintBase: Color(0xFF3F51B5)),
      const StatusColors(
        danger: _lightError,
        warning: _lightWarning,
        positive: _lightPositive,
      ),
      // Bolus is the deep brand indigo, basal the same hue with most of its
      // weight drained out. Measured against the light surface, which is white
      // since the boxes became white (it was #E8E8E8, where a first pass at
      // #9AA6D8 made only 1.94); this one holds 2.33 against the bolus on it.
      const InsulinColors(basal: Color(0xFF8894CE), bolus: Color(0xFF45569F)),
    ],
  );

  /// The indigo-blue [lightPrimary] lifted for the dark background: saturated
  /// enough to stay a clear brand accent, but softened from the old neon indigo
  /// so it sits ON the surface instead of glowing off it.
  ///
  /// This is tuned as a FILL (a button with white text on top). It is too dark
  /// to double as a foreground on a dark surface — see [darkAccent].
  static final Color darkPrimary = Color(0xFF5D73CC);

  /// A light tone of [darkPrimary], for drawing the accent ON a dark surface
  /// (outlined-button labels) rather than filling with it. Same hue, so the two
  /// read as one brand colour; light enough to clear 7:1 against the surface,
  /// where [darkPrimary] itself only manages ~4:1.
  static final Color darkAccent = Color(0xFF9DACEA);

  /// Dark surfaces take their hue from the insulink website's palette (`--bg`,
  /// `--surface`, `--surface-2`, `--border` in its `style.css`) so app and site
  /// stay related, but they are lifted a step and pulled well down in saturation:
  /// the site's near-black, strongly blue values make the accent glare on a phone
  /// held at arm's length in the dark, and leave too little separation for cards
  /// to read as cards. The result is grey with a blue lean, not blue-grey.
  static const Color _darkBg = Color(0xFF15181D);
  static const Color _darkSurface = Color(0xFF1F232A);
  static const Color _darkSurfaceHigh = Color(0xFF242933);
  static const Color _darkSurfaceRaised = Color(0xFF2A2F38);

  /// Kept close to [_darkSurface] on purpose: it is both the divider colour and
  /// the box border ([OverviewSection]), and a border much lighter than the fill
  /// draws a hard ring around every card. The boxes separate via their fill.
  static const Color _darkBorder = Color(0xFF2B3038);

  /// Border colour for outlined controls. Set explicitly because [ColorScheme]
  /// falls back to `onBackground` (white) when it is omitted, which rims every
  /// [OutlinedButton] in glaring white.
  static const Color _darkOutline = Color(0xFF464D5A);

  /// Foreground for anything that informs rather than invites a tap: the glyphs
  /// next to a statistic, secondary labels, units. The app reads the brand
  /// colour as "you can touch this", so decoration must NOT wear it — and
  /// [ColorScheme] otherwise resolves `onSurfaceVariant` to plain white, which
  /// gives a decorative glyph the same weight as the value it annotates.
  static const Color _darkMuted = Color(0xFFA6AEBF);

  /// The dark theme's status tones, split exactly like [darkPrimary] /
  /// [darkAccent] and for the same reason: [_darkError] is the FILL (a delete's
  /// confirm button, the nav badge) and only manages ~4:1 as a label, so error
  /// TEXT takes the lighter [_darkDanger] (~6.9:1) via [StatusColors].
  ///
  /// The hue comes from the red the app already speaks (`GlucoseColors`), so the
  /// product has ONE red family instead of Material's stock maroon beside it.
  static const Color _darkError = Color(0xFFE0533D);
  static const Color _darkDanger = Color(0xFFFF8A7A);
  static const Color _darkWarning = Color(0xFFFFB23E);
  static const Color _darkPositive = Color(0xFF5DD98C);

  static final ThemeData dark = ThemeData(
    useMaterial3: true,
    primaryColor: Colors.white,
    colorScheme: ColorScheme.dark(
      primary: darkPrimary,
      onPrimary: onPrimary,
      secondary: darkPrimary,
      surface: _darkSurface,
      surfaceContainerHigh: _darkSurfaceHigh,
      surfaceContainerHighest: _darkSurfaceRaised,
      outline: _darkOutline,
      onSurfaceVariant: _darkMuted,
      error: _darkError,
      onError: Colors.white,
    ),
    filledButtonTheme: _filledButtons,
    elevatedButtonTheme: _elevatedButtons,
    outlinedButtonTheme: _outlinedButtonsFor(
      foreground: darkAccent,
      rim: darkPrimary.withValues(alpha: 0.55),
    ),
    textButtonTheme: _textButtonsFor(Colors.white),
    iconButtonTheme: _iconButtonsFor(Colors.white),
    inputDecorationTheme: _inputTheme(
      _darkSurfaceRaised,
      darkPrimary,
      const Color(0xFF9E9E9E),
    ),
    popupMenuTheme: _popupMenu(_darkSurfaceRaised),
    appBarTheme: const AppBarTheme(backgroundColor: _darkBg),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: _darkSurface,
    ),
    scaffoldBackgroundColor: _darkBg,
    dividerColor: _darkBorder,
    extensions: [
      GlucoseColors.standard,
      AccentColors(onSurface: darkAccent),
      // The stat boxes keep the original brand indigo (icon #93A6FF on a #5A73F2
      // tint), decoupled from the softened primary — see StatBoxColors.
      const StatBoxColors(icon: Color(0xFF93A6FF), tintBase: Color(0xFF5A73F2)),
      const StatusColors(
        danger: _darkDanger,
        warning: _darkWarning,
        positive: _darkPositive,
      ),
      // The pair swaps weight on dark: the LIGHTER indigo is the loud one, and
      // basal steps down towards the surface instead of up off it.
      const InsulinColors(basal: Color(0xFF5C6BA6), bolus: Color(0xFF9DACEA)),
    ],
  );
}
