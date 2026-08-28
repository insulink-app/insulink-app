import 'package:flutter/material.dart';
import 'package:insulink/src/overview/stop_bolus_button.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_running_bolus.dart';
import 'package:insulink/src/theme/accent_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The card the overview shows while the pod works through a bolus: how much is
/// out, how much is left, and the way to stop it.
///
/// Stateless — the redraw is driven by [OverviewRunningBolus], which owns the
/// one-second ticker, because progress comes from the clock and nothing else
/// would move it.
class RunningBolusCard extends StatelessWidget {
  const RunningBolusCard({
    super.key,
    required this.controller,
    required this.bolus,
  });

  final PodController controller;
  final PodRunningBolus bolus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, scheme, now),
          const SizedBox(height: 12),
          _bar(context, scheme, bolus.progress(now)),
          const SizedBox(height: 4),
          _footer(context, scheme, now),
        ],
      ),
    );
  }

  /// The label on the left, the running count on the right — the count set large
  /// because it is the one thing being watched.
  Widget _header(BuildContext context, ColorScheme scheme, DateTime now) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Icon(PhosphorIconsFill.syringe, size: 18, color: context.accent),
        const SizedBox(width: 8),
        Expanded(
          child: LocaleText(
            'pump.bolus.running',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
          ),
        ),
        Text(
          bolus.deliveredUnits(now).toStringAsFixed(2),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            height: 1,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: scheme.onSurface,
          ),
        ),
        Text(
          ' / ${bolus.programmedUnits.toStringAsFixed(2)} U',
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// Time left on the left, the way out on the right. The stop is a quiet text
  /// button rather than a full-width bar: it is there for the rare case, and a
  /// control the width of the card would read as the thing to press.
  Widget _footer(BuildContext context, ColorScheme scheme, DateTime now) {
    return Row(
      children: [
        Text(
          Locales.string(context, 'pump.bolus.remaining')
              .replaceFirst('#', _countdown(bolus.remaining(now))),
          style: TextStyle(
            fontSize: 12,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: scheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        if (controller.isBusy)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else
          StopBolusButton(controller: controller),
      ],
    );
  }

  String _countdown(Duration left) {
    final minutes = left.inMinutes;
    final seconds = left.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _bar(BuildContext context, ColorScheme scheme, double progress) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        children: [
          Container(
            height: 8,
            color: scheme.onSurface.withValues(alpha: 0.12),
          ),
          AnimatedFractionallySizedBox(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            widthFactor: progress.clamp(0.0, 1.0),
            alignment: Alignment.centerLeft,
            child: Container(height: 8, color: context.accent),
          ),
        ],
      ),
    );
  }

}
