import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/profile/basal/basal_profile.dart';
import 'package:insulink/src/profile/basal/profile_basal_state.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_state.dart';
import 'package:insulink/src/profile/tuning/tuning_controls.dart';
import 'package:insulink/src/profile/tuning/basal_suggestion.dart';
import 'package:insulink/src/profile/tuning/tuning_hour.dart';
import 'package:insulink/src/profile/tuning/tuning_glucose.dart';
import 'package:insulink/src/profile/tuning/tuning_model.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:provider/provider.dart';

/// What the stored glucose suggests the basal profile could look like.
///
/// The result is written as **its own basal profile**, sitting beside the
/// others, NOT applied. Picking it is a separate, deliberate act in the basal
/// section, exactly like switching between a weekday and a weekend profile. A
/// button that changed the running basal would be software moving someone's
/// overnight insulin on the strength of a few quiet nights.
///
/// Generated on demand rather than on a schedule: the person asking has a reason
/// to ask, and a proposal that appears by itself is one nobody reads.
class BasalTuningCard extends StatefulWidget {
  const BasalTuningCard({super.key});

  @override
  State<BasalTuningCard> createState() => _BasalTuningCardState();
}

class _BasalTuningCardState extends State<BasalTuningCard> {
  /// What to say when the button produced no profile. Null while it did, because
  /// then the new profile appearing in the list above IS the answer.
  String? _nothingKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TuningControls(
          descriptionKey: 'profile.tuning.description',
          onGenerate: _generate,
        ),
        ..._nothingNote(context),
      ],
    );
  }

  /// Only spoken when nothing was created. A button that silently does nothing
  /// looks broken; one whose result appears in the list above needs no caption.
  List<Widget> _nothingNote(BuildContext context) {
    final key = _nothingKey;
    if (key == null) {
      return const [];
    }
    return [
      const SizedBox(height: 12),
      LocaleText(
        key,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ];
  }

  /// Runs the analysis and, when it found anything, saves it as a new profile.
  void _generate() {
    final basal = context.read<ProfileBasalState>();
    final suggestions = _analyse();
    final changes = suggestions.where((hour) => hour.isChange).toList();
    // Says which stage came up empty, because "not enough data" on its own
    // cannot tell a missing archive from an hour nobody has three days of.
    debugPrint(
      'basal tuning: ${TuningControls.windowDays}d -> ${suggestions.length} hours of day, '
      '${changes.length} changed, schedule running since '
      '${context.read<ProfileBasalState>().runningSince}',
    );
    if (changes.isNotEmpty) {
      _save(basal, changes);
    }
    setState(() {
      _nothingKey = changes.isNotEmpty
          ? null
          : suggestions.isNotEmpty
          ? 'profile.tuning.no_change'
          : _changedRecently()
          ? 'profile.tuning.since_change'
          : 'profile.tuning.not_enough';
    });
  }

  /// Whether the running schedule was changed inside the analysis period, which
  /// is the usual reason a freshly adopted proposal has nothing to say yet.
  bool _changedRecently() {
    final since = context.read<ProfileBasalState>().runningSince;
    return since != null &&
        since.isAfter(
          DateTime.now().subtract(
            const Duration(days: TuningControls.windowDays),
          ),
        );
  }

  /// The later of the two, and the window start when the schedule changed inside
  /// it.
  DateTime _later(DateTime start, DateTime? changedAt) =>
      changedAt != null && changedAt.isAfter(start) ? changedAt : start;

  /// Writes the proposal as a profile of its own, INACTIVE.
  ///
  /// Named with the window it came from and the day it was made, because a list
  /// of profiles called "Suggestion" three times over is useless.
  void _save(ProfileBasalState basal, List<HourSuggestion> changes) {
    final rates = List<double>.of(basal.active.rates);
    for (final hour in changes) {
      rates[hour.hour] = hour.suggested;
    }
    final now = DateTime.now();
    final name = Locales.string(context, 'profile.tuning.profile_name')
        .replaceFirst('#', '${TuningControls.windowDays}')
        .replaceFirst('#', '${now.day}.${now.month}.');
    basal.addInactiveProfile(
      BasalProfile(
        name: name,
        rates: rates,
        // No peaks. They are an input to the editor's curve GENERATOR, not a
        // description of these rates, and the ones on the profile this was
        // measured against describe a different day. Carrying them over would
        // attach a shape to hours that came from measurement. The editor does not
        // regenerate on open, so the measured rates stand; asking it to generate
        // there is asking for a curve INSTEAD of the measurement, and gets an
        // obviously flat one rather than a plausible-looking wrong one.
        peaks: const [],
        // The daily amount follows the hours rather than being held constant: a
        // profile that gave too little overnight needs more insulin, not the same
        // amount shuffled around the clock.
        dailyTotal: rates.fold<double>(0, (sum, rate) => sum + rate),
      ),
    );
  }

  /// The analysis itself, over the last [TuningControls.windowDays] of stored
  /// data. Every hour with
  /// readings at both ends counts; what food and bolus insulin did in it is
  /// measured by [TuningModel] and subtracted rather than disqualifying it.
  List<HourSuggestion> _analyse() {
    const window = Duration(days: TuningControls.windowDays);
    final bolus = context.read<ProfileBolusState>();
    final basal = context.read<ProfileBasalState>();
    final rates = basal.active.rates;
    final pod = context.read<PodController>().store;
    final now = DateTime.now();
    // Only hours the RUNNING schedule actually ran. What this measures is
    // glucose drifting under given rates, so hours from before the last change
    // describe a schedule that no longer exists: adding their drift to the rates
    // that already carry it is how pressing the button twice walked somebody's
    // basal away from them.
    final from = _later(now.subtract(window), basal.runningSince);
    final archive = context.read<CgmController>().archiveSince(window);
    debugPrint(
      'basal tuning: ${archive.length} archived readings, '
      '${context.read<MealState>().meals.length} meals',
    );
    final hours =
        TuningHourFinder(
          model: TuningModel(insulinDuration: bolus.insulinDuration),
        ).find(
          from: from,
          to: now,
          meals: context.read<MealState>().meals,
          // Through [TuningGlucose], NOT a direct lookup: the archive is keyed by
          // the minute a reading happened, and asking for an exact hour boundary or
          // dose time misses four times out of five.
          glucoseAt: TuningGlucose(archive).at,
          // From the durable record, not the loop journal and not the pod's own
          // ledger. The journal keeps one day; the ledger dies with the pod, and a
          // pod lives eighty hours, so anything resting on it was empty the morning
          // after a pod change.
          automationExcessAt: pod.automationExcessInHour,
        );
    return BasalSuggestion(
      correctionFactor: bolus.correctionFactor,
      carbFactor: bolus.carbFactor,
      currentRates: rates,
    ).from(hours);
  }
}
