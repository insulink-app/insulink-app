import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_log_entry.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Opens the delivery log, carrying the pump controller across the route so the
/// page reads the same store the device page does.
///
/// The store is re-read first: its getters are served from a cache that is PER
/// ISOLATE, and basal is booked in the background service. Without this the log
/// listed only what had been booked when the app started, so a phone that had
/// been open a while showed no basal at all.
Future<void> openPodDeliveryLog(BuildContext context) async {
  final controller = context.read<PodController>();
  final navigator = Navigator.of(context);
  await controller.store.reload();
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider<PodController>.value(
        value: controller,
        child: const PodDeliveryLogPage(),
      ),
    ),
  );
}

/// The icon in the pump page header that opens the log.
class PodDeliveryLogButton extends StatelessWidget {
  const PodDeliveryLogButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => openPodDeliveryLog(context),
      tooltip: Locales.string(context, 'pump.log._'),
      icon: const Icon(PhosphorIconsBold.listBullets, size: 22),
    );
  }
}

/// What this pod has delivered, newest first, on a page of its own.
///
/// Deliberately the POD's log, not the meal log: it lists what the pump actually
/// put out, including the priming and cannula volumes that never reach the user
/// and that no meal record will ever mention. That is what makes the reservoir
/// add up.
class PodDeliveryLogPage extends StatelessWidget {
  const PodDeliveryLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = PodLogEntry.timeline(context.watch<PodController>().store);
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('pump.log._'),
      ),
      body: Column(
        children: [
          const PodDeliverySummary(),
          Expanded(
            child: entries.isEmpty ? _empty() : _list(context, entries),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return const Center(
      child: EmptyState(
        icon: PhosphorIconsBold.listBullets,
        titleKey: 'pump.log.empty',
      ),
    );
  }

  Widget _list(BuildContext context, List<PodLogEntry> entries) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: entries.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: scheme.onSurface.withValues(alpha: 0.06)),
      itemBuilder: (_, index) => _PodLogRow(entry: entries[index]),
    );
  }
}

/// What this pod has put out in total, split the way the pod itself splits it.
///
/// Basal is here as a TOTAL rather than as rows, because it is a continuous drip:
/// listing every quarter hour would bury the doses the user actually chose. The
/// figure is the one the background watch booked, so a stretch the pod spent
/// suspended counts as the nothing it was.
class PodDeliverySummary extends StatelessWidget {
  const PodDeliverySummary({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PodController>().store;
    final basal = store.basalDeliveredTotal;
    final bolus = store.deliveryLog
        .where((entry) => entry.kind == PodDeliveryKind.bolus)
        .fold<double>(0, (sum, entry) => sum + entry.units);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _line(scheme, 'pump.log.basal_total', basal, bold: false),
          const SizedBox(height: 4),
          _line(scheme, 'pump.log.bolus_total', bolus, bold: false),
          Divider(height: 14, color: scheme.onSurface.withValues(alpha: 0.06)),
          _line(scheme, 'pump.log.total', basal + bolus, bold: true),
        ],
      ),
    );
  }

  Widget _line(
    ColorScheme scheme,
    String labelKey,
    double units, {
    required bool bold,
  }) {
    final weight = bold ? FontWeight.bold : FontWeight.normal;
    return Row(
      children: [
        Expanded(
          child: LocaleText(
            labelKey,
            style: TextStyle(
              fontSize: 13,
              fontWeight: weight,
              color: bold
                  ? scheme.onSurface
                  : scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        Text(
          '${units.toStringAsFixed(2)} U',
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

/// One line of the history: when, what for, and how much.
class _PodLogRow extends StatelessWidget {
  const _PodLogRow({required this.entry});

  final PodLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _clock(context),
            style: TextStyle(
              fontSize: 13,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LocaleText(
              entry.labelKey,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${entry.units.toStringAsFixed(2)} U',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: entry.isDose ? scheme.onSurface : context.warning,
            ),
          ),
        ],
      ),
    );
  }

  /// The time, as a span for an hour of basal and as a moment for a dose. Older
  /// than today gains its date, since most of the list is today.
  String _clock(BuildContext context) {
    final now = DateTime.now();
    final sameDay = entry.at.year == now.year &&
        entry.at.month == now.month &&
        entry.at.day == now.day;
    final start = '${_two(entry.at.hour)}:${_two(entry.at.minute)}';
    final time = entry.spansAnHour
        ? Locales.string(context, 'pump.log.hour_span')
            .replaceFirst('#', start)
            .replaceFirst('#', '${_two((entry.at.hour + 1) % 24)}:00')
        : start;
    if (sameDay) {
      return time;
    }
    return Locales.string(context, 'pump.log.dated')
        .replaceFirst('#', '${_two(entry.at.day)}.${_two(entry.at.month)}.')
        .replaceFirst('#', time);
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}
