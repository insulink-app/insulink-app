import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/localization/enum_locale_key.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Every decision the automation made, newest first.
///
/// Separate from the delivery log rather than merged into it, because the two
/// answer different questions. The delivery log says how much insulin left the
/// pod; this says what the automation was looking at when it asked for it. A
/// cycle runs every five minutes, so merged in they would bury the boluses.
///
/// Each row carries the glucose, the insulin on board and the rate, so a
/// decision can be checked afterwards rather than taken on trust. That is the
/// whole point of writing them down.
class PodLoopJournalPage extends StatelessWidget {
  const PodLoopJournalPage({super.key});

  static void open(BuildContext context) {
    final controller = context.read<PodController>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider<PodController>.value(
          value: controller,
          child: const PodLoopJournalPage(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cycles = context.watch<PodController>().store.loopCycles;
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('pump.loop.journal'),
      ),
      body: cycles.isEmpty
          ? const Center(
              child: EmptyState(
                icon: PhosphorIconsBold.repeat,
                titleKey: 'pump.loop.no_cycle',
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: cycles.length,
              separatorBuilder: (_, _) => const Divider(height: 18),
              itemBuilder: (_, index) => _LoopCycleRow(cycle: cycles[index]),
            ),
    );
  }
}

/// One decision: when, what it saw, what it asked for, and what held it back.
class _LoopCycleRow extends StatelessWidget {
  const _LoopCycleRow({required this.cycle});

  final PodLoopCycle cycle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _clock(),
          style: TextStyle(
            fontSize: 13,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _headline(context),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cycle.delivered ? scheme.onSurface : context.warning,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _inputs(context),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The rate and why, plus a mark when it never reached the pod. Observation
  /// mode and a failed command both land there, and neither may look like a
  /// delivery.
  String _headline(BuildContext context) {
    final reason =
        Locales.string(context, 'pump.loop.reason.${cycle.reason.localeKey}');
    final rate = '${cycle.unitsPerHour.toStringAsFixed(2)} U/h';
    if (!cycle.delivered) {
      return '$rate, $reason '
          '(${Locales.string(context, 'pump.loop.not_sent')})';
    }
    return '$rate, $reason';
  }

  /// What the decision was computed from. Without these the rate is a number
  /// nobody can check.
  String _inputs(BuildContext context) {
    final parts = <String>[
      if (cycle.mgdl != null)
        Locales.string(context, 'pump.loop.at_glucose')
            .replaceFirst('#', '${cycle.mgdl}')
            .replaceFirst('#', _trend()),
      Locales.string(context, 'pump.loop.on_board')
          .replaceFirst('#', cycle.iobUnits.toStringAsFixed(2)),
      Locales.string(context, 'pump.loop.schedule_was')
          .replaceFirst('#', cycle.scheduledUnitsPerHour.toStringAsFixed(2)),
      if (cycle.boundBy != null)
        Locales.string(
          context,
          'pump.loop.bound.${cycle.boundBy!.localeKey}',
        ),
    ];
    return parts.join(', ');
  }

  String _trend() {
    final trend = cycle.trendPerMinute;
    if (trend == null) {
      return '0.0';
    }
    return '${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(1)}';
  }

  String _clock() =>
      '${_two(cycle.at.hour)}:${_two(cycle.at.minute)}';

  String _two(int value) => value.toString().padLeft(2, '0');
}
