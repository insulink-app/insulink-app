import 'package:flutter/material.dart';
import 'package:insulink/src/localization/enum_locale_key.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/loop/loop_journal_page.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/theme/accent_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:insulink/src/pump/pod_controller.dart';

/// What the automation last decided, in one line.
///
/// The rate on its own says nothing that can be checked. Shown next to the
/// glucose it was computed from and the ceiling that held it back, it can be:
/// a user who sees a rate lower than expected can read why in the same line
/// instead of trusting that something sensible happened.
class PodLoopCycleLine extends StatelessWidget {
  const PodLoopCycleLine({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cycles = context.watch<PodController>().store.loopCycles;
    if (cycles.isEmpty) {
      return LocaleText(
        'pump.loop.no_cycle',
        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
      );
    }
    return InkWell(
      onTap: () => PodLoopJournalPage.open(context),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _describe(context, cycles.first),
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
          Icon(PhosphorIconsBold.caretRight, size: 14, color: context.accent),
        ],
      ),
    );
  }

  String _describe(BuildContext context, PodLoopCycle cycle) {
    final line = Locales.string(context, 'pump.loop.last')
        .replaceFirst('#', _clock(cycle.at))
        .replaceFirst('#', cycle.unitsPerHour.toStringAsFixed(2))
        .replaceFirst(
          '#',
          Locales.string(context, 'pump.loop.reason.${cycle.reason.localeKey}'),
        );
    final bound = cycle.boundBy;
    if (bound == null) {
      return line;
    }
    return '$line ${Locales.string(context, 'pump.loop.bound.${bound.localeKey}')}';
  }

  String _clock(DateTime at) =>
      '${_two(at.hour)}:${_two(at.minute)}';

  String _two(int value) => value.toString().padLeft(2, '0');
}
