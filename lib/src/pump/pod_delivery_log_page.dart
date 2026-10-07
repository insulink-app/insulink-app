import 'package:flutter/material.dart';
import 'package:insulink/src/pump/pod_delivery_summary.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/base/track_bar.dart';
import 'package:insulink/src/base/section_header.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_log_entry.dart';
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          InkSpace.panelMargin,
          12,
          InkSpace.panelMargin,
          24,
        ),
        children: [
          const PodDeliverySummary(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: SectionHeader(titleKey: 'pump.log.history'),
          ),
          if (entries.isEmpty)
            const EmptyState(
              icon: PhosphorIconsBold.listBullets,
              titleKey: 'pump.log.empty',
            )
          else
            _list(entries),
        ],
      ),
    );
  }

  /// Every delivery as a row of one panel, its bar measured against the
  /// largest amount in the list.
  Widget _list(List<PodLogEntry> entries) {
    final largest = entries.fold<double>(
      0,
      (max, entry) => entry.units > max ? entry.units : max,
    );
    return InkPanel.list(
      radius: InkRadius.tile,
      rows: [
        for (final entry in entries) _PodLogRow(entry: entry, largest: largest),
      ],
    );
  }
}

/// One delivery: a dot in its kind's colour, the kind over its time, a bar
/// against the largest amount, and the amount.
class _PodLogRow extends StatelessWidget {
  const _PodLogRow({required this.entry, required this.largest});

  final PodLogEntry entry;
  final double largest;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final color = _color(colors);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        spacing: 14,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                LocaleText(entry.labelKey, style: InkText.rowTitle),
                Text(
                  _clock(context),
                  style: InkText.label.copyWith(color: colors.muted),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: TrackBar(
              startFraction: 0,
              endFraction: largest <= 0 ? 0 : entry.units / largest,
              color: color,
              height: 6,
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              podUnits(context, entry.units),
              textAlign: TextAlign.end,
              style: InkText.row,
            ),
          ),
        ],
      ),
    );
  }

  /// Basal in the accent, a bolus in the bolus colour, priming and cannula
  /// (insulin that never reaches the user) muted.
  Color _color(InsulinkColors colors) {
    if (entry.labelKey == 'pump.log.kind.basal') {
      return colors.accent;
    }
    return entry.isDose ? colors.pace : colors.muted;
  }

  /// The time, as a span for an hour of basal and as a moment for a dose. Older
  /// than today gains its date, since most of the list is today.
  String _clock(BuildContext context) {
    final now = DateTime.now();
    final sameDay =
        entry.at.year == now.year &&
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
