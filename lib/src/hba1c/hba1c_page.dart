import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/base/measurement_row.dart';
import 'package:insulink/src/hba1c/hba1c_current_card.dart';
import 'package:insulink/src/hba1c/hba1c_entry.dart';
import 'package:insulink/src/hba1c/hba1c_entry_sheet.dart';
import 'package:insulink/src/hba1c/hba1c_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/sport/activity/activity_bar_chart.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// HbA1c history: the newest result with its derived figures, the course over
/// time, and every reading (newest first). "+" notes a new one.
///
/// No time-range picker, unlike the weight page: an HbA1c is measured every few
/// months, so the whole history is a handful of readings and any window would
/// just hide some of them. Bars rather than a line for the same reason — a dozen
/// separate lab results are discrete events, not a sampled curve.
class Hba1cPage extends StatelessWidget {
  const Hba1cPage({super.key});

  /// Where the bars start. The non-diabetic reference range floors around 4 %, so
  /// nothing measurable falls below it and the axis loses no information.
  static const _baselinePercent = 4.0;

  @override
  Widget build(BuildContext context) {
    final entries = context.watch<Hba1cState>().entries;
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('hba1c._'),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'hba1c-add',
        onPressed: () => showHba1cEntrySheet(context),
        child: const Icon(PhosphorIconsBold.plus),
      ),
      body: entries.isEmpty
          ? const EmptyState(
              icon: PhosphorIconsBold.testTube,
              titleKey: 'hba1c.empty',
            )
          : _history(context),
    );
  }

  Widget _history(BuildContext context) {
    final state = context.watch<Hba1cState>();
    final readings = state.entries;
    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
      children: [
        Hba1cCurrentCard(latest: readings.last, previous: state.previous),
        const SizedBox(height: 20),
        if (readings.length >= 2) ...[
          _chartCard(context, readings),
          const SizedBox(height: 24),
        ],
        LocaleText(
          'hba1c.history',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        for (var index = readings.length - 1; index >= 0; index--)
          MeasurementRow(
            value: readings[index].percent,
            time: readings[index].time,
            unit: '%',
            previous: index > 0 ? readings[index - 1].percent : null,
            deleteConfirmKey: 'hba1c.delete_confirm',
            onDelete: () => state.remove(readings[index]),
            onEdit: () =>
                showHba1cEntrySheet(context, existing: readings[index]),
          ),
      ],
    );
  }

  Widget _chartCard(BuildContext context, List<Hba1cEntry> readings) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 20, 16, 12),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: SizedBox(
        height: 200,
        child: ActivityBarChart<Hba1cEntry>(
          days: readings,
          date: (entry) => entry.time,
          value: (entry) => entry.percent,
          label: (entry) => '${sportDecimal(entry.percent, 1)} %',
          color: Theme.of(context).colorScheme.primary,
          // Not zero: an HbA1c never goes below ~4 %, so 0-based bars would put
          // every result at nearly the same height and hide the very change the
          // page exists to show.
          baseline: _baselinePercent,
          decimals: 1,
        ),
      ),
    );
  }
}
