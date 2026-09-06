import 'package:flutter/material.dart';
import 'package:insulink/src/base/bouncy_scroll_behavior.dart';
import 'package:insulink/src/base/day_section_header.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/pump/loop/loop_cycle_card.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Every decision the automation made, newest first, under a heading per day.
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
      body: cycles.isEmpty ? _empty() : _list(cycles),
    );
  }

  Widget _empty() {
    return const Center(
      child: EmptyState(
        icon: PhosphorIconsBold.repeat,
        titleKey: 'pump.loop.no_cycle',
      ),
    );
  }

  /// A day of cycles is 288 rows, so the list is built lazily. The day headings
  /// ride in the same list rather than in sticky sections: at most two of them
  /// fit in what the journal keeps, and a sticky header for two is machinery
  /// nobody would notice.
  Widget _list(List<PodLoopCycle> cycles) {
    return ScrollConfiguration(
      behavior: const BouncyScrollBehavior(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        itemCount: cycles.length,
        itemBuilder: (_, index) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_startsNewDay(cycles, index))
              DaySectionHeader(day: cycles[index].at, first: index == 0),
            PodLoopCycleCard(cycle: cycles[index]),
          ],
        ),
      ),
    );
  }

  /// True when [index] falls on a different calendar day than the cycle before.
  bool _startsNewDay(List<PodLoopCycle> cycles, int index) {
    if (index == 0) {
      return true;
    }
    return !_sameDay(cycles[index].at, cycles[index - 1].at);
  }

  bool _sameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}
