import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/measurement_row.dart';
import 'package:insulink/src/base/section_header.dart';
import 'package:insulink/src/base/stat_strip.dart';
import 'package:insulink/src/hba1c/hba1c_current_card.dart';
import 'package:insulink/src/hba1c/hba1c_entry.dart';
import 'package:insulink/src/hba1c/hba1c_entry_sheet.dart';
import 'package:insulink/src/hba1c/hba1c_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/activity/activity_bar_chart.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// HbA1c history in the weight page's layout: the newest result, the two
/// figures every lab report prints beside it, the course over time and every
/// reading (newest first) in one panel. "+" notes a new one.
///
/// No time-range picker, unlike the weight page: an HbA1c is measured every few
/// months, so the whole history is a handful of readings and any window would
/// just hide some of them. Bars rather than a line for the same reason: a dozen
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
          : _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final state = context.watch<Hba1cState>();
    final readings = state.entries;
    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
      children: [
        Hba1cCurrentCard(latest: readings.last, previous: state.previous),
        const SizedBox(height: 22),
        _facts(context, readings.last),
        if (readings.length >= 2) ...[
          const SizedBox(height: 10),
          _chartCard(context, readings),
        ],
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: SectionHeader(titleKey: 'hba1c.history'),
        ),
        InkPanel.list(rows: _rows(context, state)),
      ],
    );
  }

  /// The same result in IFCC units and as the average glucose it stands for.
  /// Both are pure functions of the percentage (see [Hba1cEntry]).
  Widget _facts(BuildContext context, Hba1cEntry latest) {
    return StatStrip(
      cells: [
        (
          label: Locales.string(context, 'hba1c.mmol_per_mol'),
          value: sportDecimal(latest.mmolPerMol, 0),
          unit: 'mmol/mol',
        ),
        (
          label: Locales.string(context, 'hba1c.average_glucose'),
          value: sportDecimal(latest.averageGlucoseMgDl, 0),
          unit: 'mg/dL',
        ),
      ],
    );
  }

  Widget _chartCard(BuildContext context, List<Hba1cEntry> readings) {
    return InkPanel(
      radius: InkRadius.tile,
      padding: const EdgeInsets.fromLTRB(12, 18, 16, 12),
      child: SizedBox(
        height: 200,
        child: ActivityBarChart<Hba1cEntry>(
          days: readings,
          date: (entry) => entry.time,
          value: (entry) => entry.percent,
          label: (entry) => '${sportDecimal(entry.percent, 1)} %',
          color: context.ink.accent,
          baseline: _baselinePercent,
          decimals: 1,
        ),
      ),
    );
  }

  List<Widget> _rows(BuildContext context, Hba1cState state) {
    final readings = state.entries;
    return [
      for (var index = readings.length - 1; index >= 0; index--)
        MeasurementRow(
          value: readings[index].percent,
          time: readings[index].time,
          unit: '%',
          framed: false,
          previous: index > 0 ? readings[index - 1].percent : null,
          deleteConfirmKey: 'hba1c.delete_confirm',
          onDelete: () => state.remove(readings[index]),
          onEdit: () => showHba1cEntrySheet(context, existing: readings[index]),
        ),
    ];
  }
}
