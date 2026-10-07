import 'package:flutter/material.dart';
import 'package:insulink/src/base/relative_day.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/base/confirm_delete.dart';
import 'package:insulink/src/sport/logbook/workout_metrics_chart.dart';
import 'package:insulink/src/sport/logbook/workout_session_title.dart';
import 'package:insulink/src/sport/logbook/workout_set_list.dart';
import 'package:insulink/src/sport/logbook/workout_summary_card.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Detail of a completed routine: date header, the summary comparison, the
/// glucose/heart-rate chart and the logged sets per exercise. Sets are editable
/// in place (see [WorkoutSetList]); the whole entry is deletable via the app bar.
class WorkoutSessionDetailPage extends StatelessWidget {
  const WorkoutSessionDetailPage({super.key, required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final training = context.watch<TrainingState>();
    // Re-read the live session so in-place edits reflect immediately (the passed
    // one is a snapshot from the log list).
    final current = training.sessions.firstWhere(
      (other) => other.id == session.id,
      orElse: () => session,
    );
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: Text(workoutSessionTitle(context, current)),
        actions: [
          IconButton(
            icon: const Icon(PhosphorIconsBold.trash),
            onPressed: () => confirmDelete(
              context,
              messageKey: 'sport.logbook.delete_confirm',
              onConfirm: () {
                context.read<TrainingState>().removeSession(current.id);
                Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(
          InkSpace.panelMargin,
          4,
          InkSpace.panelMargin,
          96,
        ),
        children: [
          _header(context, scheme, current),
          const SizedBox(height: 16),
          WorkoutSummaryCard(session: current),
          const SizedBox(height: 20),
          WorkoutMetricsChart(session: current),
          const SizedBox(height: 8),
          WorkoutSetList(session: current),
        ],
      ),
    );
  }

  Widget _header(
    BuildContext context,
    ColorScheme scheme,
    WorkoutSession session,
  ) {
    final locale = MaterialLocalizations.of(context);
    final started = DateTime.fromMillisecondsSinceEpoch(session.startedAtMs);
    final time = locale.formatTimeOfDay(
      TimeOfDay.fromDateTime(started),
      alwaysUse24HourFormat: true,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '${RelativeDay(started).label(context)}, $time',
        style: InkText.label.copyWith(fontSize: 15, color: context.ink.muted),
      ),
    );
  }
}
