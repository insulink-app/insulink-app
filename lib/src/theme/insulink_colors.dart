import 'package:flutter/material.dart';

/// The design tokens of the redesign: the one place every colour of the app
/// starts from. `app_theme.dart` feeds `ColorScheme` and the older extensions
/// ([GlucoseColors], [AccentColors], [StatusColors], …) from these, so a token
/// changed here moves the whole app. Values and roles: `docs/DESIGN.md`.
///
/// Read with `context.ink` (`insulink_theme.dart`).
@immutable
class InsulinkColors extends ThemeExtension<InsulinkColors> {
  const InsulinkColors({
    required this.ground,
    required this.panel,
    required this.panelRaised,
    required this.line,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.accentText,
    required this.range,
    required this.high,
    required this.low,
    required this.highSoft,
    required this.lowSoft,
    required this.dock,
    required this.sleepDeep,
    required this.sleepLight,
    required this.sleepRem,
    required this.sleepRestless,
    required this.pulseHigh,
    required this.pace,
    required this.dockShadow,
  });

  /// Page background.
  final Color ground;

  /// Panels, tiles and header buttons.
  final Color panel;

  /// Cards inside a sheet and buttons on a panel: one step up from [panel].
  final Color panelRaised;

  /// Dividers and empty segments.
  final Color line;

  /// The fine 1 px rim around tiles and buttons.
  final Color border;

  /// Primary text, the glucose value and its trend arrow.
  final Color text;

  /// Labels, units and axes.
  final Color muted;

  /// Bolus button, icons and progress.
  final Color accent;

  /// Content drawn on [accent].
  final Color onAccent;

  /// Active tab, profile button and progress area.
  final Color accentSoft;

  /// Text drawn on [accentSoft].
  final Color accentText;

  /// Glucose in the target range.
  final Color range;

  /// Glucose above the target range.
  final Color high;

  /// Glucose below the target range.
  final Color low;

  /// Background of a notice banner (a temporary basal rate).
  final Color highSoft;

  /// Background of a low warning banner and of a danger button.
  final Color lowSoft;

  /// The floating navigation capsule.
  final Color dock;

  /// Sleep stages: deep, light, REM and restless (awake is [low]). One set for
  /// both themes, as the redesign gives only one.
  final Color sleepDeep;
  final Color sleepLight;
  final Color sleepRem;
  final Color sleepRestless;

  /// Pulse above the user's "elevated" threshold. Violet on purpose, not red or
  /// amber, so a raised pulse does not read as a warning. Light takes a deeper
  /// violet than the spec's dark value to stay readable on white.
  final Color pulseHigh;

  /// Speed in a training's chart: teal, apart from glucose (accent) and the
  /// pulse (violet), and neither red nor green.
  final Color pace;

  /// The only shadow in the app, under the navigation capsule and bolus button.
  final List<BoxShadow> dockShadow;

  static const dark = InsulinkColors(
    ground: Color(0xFF0F1B26),
    panel: Color(0xFF152432),
    panelRaised: Color(0xFF1A2C3D),
    line: Color(0xFF26394B),
    border: Color(0x12EAF1F6),
    text: Color(0xFFEAF1F6),
    muted: Color(0xFF97A9BA),
    accent: Color(0xFF9DAEFF),
    onAccent: Color(0xFF0F1B26),
    accentSoft: Color(0x299DAEFF),
    accentText: Color(0xFFC4CEFF),
    range: Color(0xFF7CCB8F),
    high: Color(0xFFF4B740),
    low: Color(0xFFFF6B7F),
    highSoft: Color(0x1FF4B740),
    lowSoft: Color(0x24FF6B7F),
    dock: Color(0xFF1B2B3B),
    sleepDeep: Color(0xFF8C7BFF),
    sleepLight: Color(0xFF5BC0F8),
    sleepRem: Color(0xFF2ED8B6),
    sleepRestless: Color(0xFFF06292),
    pulseHigh: Color(0xFFC9A7FF),
    pace: Color(0xFF2ED8B6),
    dockShadow: [
      BoxShadow(
        color: Color(0x73000000),
        offset: Offset(0, 12),
        blurRadius: 32,
      ),
    ],
  );

  static const light = InsulinkColors(
    ground: Color(0xFFEDF2F6),
    panel: Color(0xFFFFFFFF),
    panelRaised: Color(0xFFF5F8FB),
    line: Color(0xFFD3DEE7),
    border: Color(0x0F0F1B26),
    text: Color(0xFF0F1B26),
    muted: Color(0xFF4D6175),
    accent: Color(0xFF3346C8),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0x1A3346C8),
    accentText: Color(0xFF2A3AA8),
    range: Color(0xFF3B8A4F),
    high: Color(0xFFA86A00),
    low: Color(0xFFC8293F),
    highSoft: Color(0x1AA86A00),
    lowSoft: Color(0x1AC8293F),
    dock: Color(0xFFFFFFFF),
    sleepDeep: Color(0xFF8C7BFF),
    sleepLight: Color(0xFF5BC0F8),
    sleepRem: Color(0xFF2ED8B6),
    sleepRestless: Color(0xFFF06292),
    pulseHigh: Color(0xFF7B4FCC),
    pace: Color(0xFF0B7F6A),
    dockShadow: [
      BoxShadow(
        color: Color(0x1F0F1B26),
        offset: Offset(0, 10),
        blurRadius: 28,
      ),
    ],
  );

  @override
  InsulinkColors copyWith({
    Color? ground,
    Color? panel,
    Color? panelRaised,
    Color? line,
    Color? border,
    Color? text,
    Color? muted,
    Color? accent,
    Color? onAccent,
    Color? accentSoft,
    Color? accentText,
    Color? range,
    Color? high,
    Color? low,
    Color? highSoft,
    Color? lowSoft,
    Color? dock,
    Color? sleepDeep,
    Color? sleepLight,
    Color? sleepRem,
    Color? sleepRestless,
    Color? pulseHigh,
    Color? pace,
    List<BoxShadow>? dockShadow,
  }) {
    return InsulinkColors(
      ground: ground ?? this.ground,
      panel: panel ?? this.panel,
      panelRaised: panelRaised ?? this.panelRaised,
      line: line ?? this.line,
      border: border ?? this.border,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentSoft: accentSoft ?? this.accentSoft,
      accentText: accentText ?? this.accentText,
      range: range ?? this.range,
      high: high ?? this.high,
      low: low ?? this.low,
      highSoft: highSoft ?? this.highSoft,
      lowSoft: lowSoft ?? this.lowSoft,
      dock: dock ?? this.dock,
      sleepDeep: sleepDeep ?? this.sleepDeep,
      sleepLight: sleepLight ?? this.sleepLight,
      sleepRem: sleepRem ?? this.sleepRem,
      sleepRestless: sleepRestless ?? this.sleepRestless,
      pulseHigh: pulseHigh ?? this.pulseHigh,
      pace: pace ?? this.pace,
      dockShadow: dockShadow ?? this.dockShadow,
    );
  }

  @override
  InsulinkColors lerp(ThemeExtension<InsulinkColors>? other, double t) {
    if (other is! InsulinkColors) {
      return this;
    }
    Color blend(Color from, Color to) => Color.lerp(from, to, t)!;
    return InsulinkColors(
      ground: blend(ground, other.ground),
      panel: blend(panel, other.panel),
      panelRaised: blend(panelRaised, other.panelRaised),
      line: blend(line, other.line),
      border: blend(border, other.border),
      text: blend(text, other.text),
      muted: blend(muted, other.muted),
      accent: blend(accent, other.accent),
      onAccent: blend(onAccent, other.onAccent),
      accentSoft: blend(accentSoft, other.accentSoft),
      accentText: blend(accentText, other.accentText),
      range: blend(range, other.range),
      high: blend(high, other.high),
      low: blend(low, other.low),
      highSoft: blend(highSoft, other.highSoft),
      lowSoft: blend(lowSoft, other.lowSoft),
      dock: blend(dock, other.dock),
      sleepDeep: blend(sleepDeep, other.sleepDeep),
      sleepLight: blend(sleepLight, other.sleepLight),
      sleepRem: blend(sleepRem, other.sleepRem),
      sleepRestless: blend(sleepRestless, other.sleepRestless),
      pulseHigh: blend(pulseHigh, other.pulseHigh),
      pace: blend(pace, other.pace),
      dockShadow: BoxShadow.lerpList(dockShadow, other.dockShadow, t)!,
    );
  }
}
