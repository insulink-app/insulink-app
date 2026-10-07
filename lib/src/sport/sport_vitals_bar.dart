import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/cgm/glucose_trend_icon.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// Compact live-vitals strip for a training in progress — the strength routine
/// AND the endurance recording: current glucose (from the CGM pipeline, stained
/// by its target band and carrying the same trend arrow as the overview
/// headline) and live pulse (from the worn Fitbit, stained by its zone).
///
/// Reads the pulse from [GoogleHealthState] — its source-agnostic [latestHr] /
/// [hasLiveHr], fed by EITHER the UI band reader OR the service isolate's push.
/// It does NOT run its own band reader: during a training the foreground service
/// owns the single band link (see `CgmTaskHandler._startBackgroundHr`), so a
/// second reader here would fight it and read nothing.
class SportVitalsBar extends StatelessWidget {
  const SportVitalsBar({super.key}) : chips = false;

  /// The same two readings as two chips side by side, for the live training's
  /// panel (`docs/redesign/screens/30-training-live.png`): the glyph carries
  /// the colour, the number stays in the text colour with its unit muted.
  const SportVitalsBar.chips({super.key}) : chips = true;

  final bool chips;

  /// The palette the big overview readout uses, so a glanced-at value mid-set
  /// reads the same colour as on the overview page.
  GlucoseColors _colors(BuildContext context) =>
      Theme.of(context).extension<GlucoseColors>()!;

  /// ponytail: fixed pulse zones (normal / elevated / high) — there is no
  /// HR-zone setting yet; wire it up once the profile grows one.
  Color _pulseColor(BuildContext context, int bpm) {
    final colors = _colors(context);
    if (bpm < 100) {
      return colors.inRange;
    }
    if (bpm < 140) {
      return colors.high;
    }
    return colors.low;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controller = context.watch<CgmController>();
    final glucose = context.watch<ProfileGlucoseState>();
    final health = context.watch<GoogleHealthState>();
    final mgdl = controller.currentMgdl;
    // A stale (cached, not live) value is grey, matching the overview headline.
    final glucoseColor = (mgdl == null || controller.currentIsStale)
        ? context.ink.muted
        : _colors(context).forValue(mgdl, glucose);
    final trend = controller.displayTrendPerMin;
    // Keep the last known bpm on screen and grey it when it is no longer live —
    // same stale treatment as the glucose reading, rather than blinking to '–'.
    final bpm = health.latestHr;
    final pulseLive = health.hasLiveHr;
    if (chips) {
      return Row(
        spacing: 10,
        children: [
          Expanded(
            child: _chip(
              context,
              PhosphorIconsBold.drop,
              glucoseColor,
              mgdl == null ? '–' : glucose.format(mgdl),
              glucose.unit.label,
              trailing: mgdl != null && trend != null
                  ? GlucoseTrendIcon(
                      perMin: trend,
                      color: context.ink.text,
                      size: 18,
                    )
                  : null,
            ),
          ),
          Expanded(
            child: _chip(
              context,
              PhosphorIconsBold.heart,
              pulseLive ? context.ink.pulseHigh : context.ink.muted,
              bpm == null ? '–' : '$bpm',
              'bpm',
            ),
          ),
        ],
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _reading(
            PhosphorIconsBold.drop,
            glucoseColor,
            mgdl == null ? '–' : glucose.formatWithUnit(mgdl),
            trailing: mgdl != null && trend != null
                ? GlucoseTrendIcon(perMin: trend, color: glucoseColor, size: 22)
                : null,
          ),
          _reading(
            PhosphorIconsFill.heart,
            bpm == null
                ? scheme.onSurface.withValues(alpha: 0.3)
                : (pulseLive ? _pulseColor(context, bpm) : context.ink.muted),
            bpm == null ? '–' : '$bpm bpm',
          ),
        ],
      ),
    );
  }

  Widget _reading(IconData icon, Color color, String text, {Widget? trailing}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 4), trailing],
      ],
    );
  }

  /// One chip of the live panel: glyph, value, muted unit, optional trend.
  Widget _chip(
    BuildContext context,
    IconData icon,
    Color glyph,
    String value,
    String unit, {
    Widget? trailing,
  }) {
    final colors = context.ink;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: colors.ground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        spacing: 8,
        children: [
          Icon(icon, size: 18, color: glyph),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text.rich(
                  TextSpan(
                    text: value,
                    style: InkText.rowTitle.copyWith(fontSize: 17),
                    children: [
                      TextSpan(
                        text: ' $unit',
                        style: InkText.label.copyWith(color: colors.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
