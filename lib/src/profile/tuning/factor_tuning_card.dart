import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_state.dart';
import 'package:insulink/src/profile/tuning/tuning_dose.dart';
import 'package:insulink/src/profile/tuning/tuning_glucose.dart';
import 'package:insulink/src/profile/tuning/tuning_model.dart';
import 'package:insulink/src/profile/tuning/factor_suggestion.dart';
import 'package:insulink/src/profile/tuning/settled_factors.dart';
import 'package:insulink/src/profile/tuning/factor_suggestion_row.dart';
import 'package:insulink/src/profile/tuning/tuning_controls.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:provider/provider.dart';

/// What the logged doses suggest for the correction factor, the carbohydrate
/// factor and the insulin duration.
///
/// The bolus counterpart of `BasalTuningCard`, and it keeps that card's rule:
/// **nothing is applied by the analysis**. Each proposal is shown beside the
/// setting in use and adopted only by a deliberate tap, because a few weeks of
/// doses do not justify software changing what a bolus calculator hands
/// somebody.
class FactorTuningCard extends StatefulWidget {
  const FactorTuningCard({super.key});

  @override
  State<FactorTuningCard> createState() => _FactorTuningCardState();
}

class _FactorTuningCardState extends State<FactorTuningCard> {

  /// The proposals from the last run, keyed by the setting they are about. Empty
  /// until the button is pressed, and an entry disappears as it is adopted.
  final Map<String, FactorSuggestion> _found = {};

  /// Settings the run could measure nothing for, so the card can say WHICH data
  /// is missing instead of leaving the user to wonder why only one row appeared.
  final List<String> _unmeasured = [];

  /// What to say when the run produced nothing to offer.
  String? _nothingKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TuningControls(
          descriptionKey: 'profile.tuning.factors.description',
          onGenerate: _generate,
        ),
        for (final entry in _found.entries) ...[
          const SizedBox(height: 12),
          FactorSuggestionRow(
            labelKey: 'profile.bolus.${entry.key}._',
            valueKey: 'profile.bolus.${entry.key}.value',
            suggestion: entry.value,
            onApply: () => _apply(entry.key, entry.value),
          ),
        ],
        ..._unmeasuredNotes(context),
        ..._nothingNote(context),
      ],
    );
  }

  /// One line per setting the data could not answer for, naming what it would
  /// take. The correction factor is the one that needs a dose with no food:
  /// inside a meal the food and the insulin cannot be told apart.
  List<Widget> _unmeasuredNotes(BuildContext context) {
    return [
      for (final setting in _unmeasured) ...[
        const SizedBox(height: 12),
        LocaleText(
          'profile.tuning.factors.missing.$setting',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ];
  }

  /// Only spoken when nothing was offered. A button that silently does nothing
  /// looks broken.
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

  /// Adopts one proposal, and drops it from the list: the setting now IS that
  /// number, so an offer to change it to itself would only invite a second tap.
  void _apply(String setting, FactorSuggestion suggestion) {
    final bolus = context.read<ProfileBolusState>();
    switch (setting) {
      case 'correction':
        bolus.setCorrectionFactor(suggestion.suggested);
      case 'carb':
        bolus.setCarbFactor(suggestion.suggested);
      case 'duration':
        bolus.setInsulinDurationH(suggestion.suggested);
    }
    setState(() => _found.remove(setting));
  }

  /// Solves the three settings TOGETHER, through [SettledFactors].
  ///
  /// They move each other: the carbohydrate factor is measured against the
  /// correction factor, and the insulin duration decides what counts as insulin
  /// acting in a window. Offering one round of that meant the user adopted three
  /// numbers, pressed again, and got a second round of changes. The fixed point
  /// is what a person pressing the button repeatedly would have arrived at, so
  /// it is what the button gives them the first time.
  void _generate() {
    final bolus = context.read<ProfileBolusState>();
    final settled = SettledFactors(
      windowsFor: _windowsFor,
      correctionFactor: bolus.correctionFactor,
      carbFactor: bolus.carbFactor,
      insulinDurationH: bolus.insulinDurationH,
    ).solve();
    setState(() {
      _found
        ..clear()
        ..addAll({
          for (final entry in settled.entries)
            if (entry.value.isChange) entry.key: entry.value,
        });
      _unmeasured
        ..clear()
        ..addAll(['correction', 'carb', 'duration']
            .where((setting) => !settled.containsKey(setting)));
      _nothingKey = _found.isNotEmpty || _unmeasured.isNotEmpty
          ? null
          : 'profile.tuning.factors.no_change';
    });
  }

  /// The dose windows in the last [TuningControls.windowDays]. Same sources as the basal tuning:
  /// the stored glucose archive, the meal log, and the durable record of what
  /// the automation added.
  List<TuningDose> _windowsFor(int insulinDurationH) {
    const window = Duration(days: TuningControls.windowDays);
    final now = DateTime.now();
    final archive = context.read<CgmController>().archiveSince(window);
    final pod = context.read<PodController>().store;
    debugPrint('factor tuning: ${archive.length} archived readings, '
        '${context.read<MealState>().meals.length} meals, '
        'insulin duration ${insulinDurationH}h');
    return TuningDoseFinder(
      model: TuningModel(insulinDuration: Duration(hours: insulinDurationH)),
    ).find(
      from: now.subtract(window),
      to: now,
      meals: context.read<MealState>().meals,
      // Through [TuningGlucose], NOT a direct lookup: the archive is keyed by
      // the minute a reading happened, and asking for an exact hour boundary or
      // dose time misses four times out of five.
      glucoseAt: TuningGlucose(archive).at,
      automationExcessAt: pod.automationExcessInHour,
    );
  }
}
