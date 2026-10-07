import 'package:flutter/material.dart';
import 'package:insulink/src/google_health/google_health_models.dart';
import 'package:insulink/src/google_health/sleep/sleep_stage_style.dart';
import 'package:insulink/src/google_health/sleep_hypnogram.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The night as one 12 px strip, each phase in its colour in the order it came,
/// with the moon and the time of falling asleep under its left end and the
/// time of waking and the sun under its right.
///
/// Phases shorter than the hypnogram's threshold are folded in the same way the
/// hypnogram folds them, so the strip and the chart below tell one story.
class SleepPhaseStrip extends StatelessWidget {
  const SleepPhaseStrip({super.key, required this.segments});

  final List<SleepSegment> segments;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final shown = mergeShortSleepSegments(
      segments,
      minMs: SleepHypnogram.mergeBelowMs,
    );
    final start = shown.first.startMs;
    final end = shown
        .map((segment) => segment.endMs)
        .reduce((latest, value) => value > latest ? value : latest);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 12,
            child: Row(
              spacing: 1,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final segment in shown)
                  Expanded(
                    flex: ((segment.endMs - segment.startMs) ~/ 60000).clamp(
                      1,
                      1 << 20,
                    ),
                    child: ColoredBox(color: segment.stage.colorIn(colors)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _time(context, colors, start, fellAsleep: true),
            const Spacer(),
            _time(context, colors, end, fellAsleep: false),
          ],
        ),
      ],
    );
  }

  Widget _time(
    BuildContext context,
    InsulinkColors colors,
    int ms, {
    required bool fellAsleep,
  }) {
    final clock = _clock(ms);
    final icon = fellAsleep
        ? Icon(PhosphorIconsBold.moon, size: 16, color: colors.sleepDeep)
        : Icon(PhosphorIconsBold.sun, size: 16, color: colors.high);
    final text = Text(
      clock,
      style: InkText.caption.copyWith(fontWeight: FontWeight.w700),
    );
    return Semantics(
      label: Locales.string(
        context,
        fellAsleep
            ? 'google_health.sleep_page.fell_asleep'
            : 'google_health.sleep_page.woke_up',
        params: [clock],
      ),
      excludeSemantics: true,
      child: Row(
        spacing: 6,
        children: fellAsleep ? [icon, text] : [text, icon],
      ),
    );
  }

  String _clock(int ms) {
    final time = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }
}
