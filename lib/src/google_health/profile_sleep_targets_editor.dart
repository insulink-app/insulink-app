import 'package:flutter/material.dart';

import '../localization/locale_text.dart';
import '../profile/glucose/glucose_stepper_row.dart';
import '../sport/sport_editable_number.dart';
import 'sleep_targets_state.dart';

/// The profile "Sleep" topic: min/max steppers for each sleep target window
/// (time to deep sleep, deep sleep, restlessness, interruptions), all in
/// minutes. Each change persists locally via [SleepTargets.save]; the backend
/// sync piggybacks on the profile page's push-on-leave (the blob rides
/// ProfileSettings). The sleep detail page reads the same targets for its bars.
class ProfileSleepTargetsEditor extends StatefulWidget {
  const ProfileSleepTargetsEditor({super.key});

  @override
  State<ProfileSleepTargetsEditor> createState() =>
      _ProfileSleepTargetsEditorState();
}

class _ProfileSleepTargetsEditorState extends State<ProfileSleepTargetsEditor> {
  static const _step = 5;
  static const _cap = 720;

  SleepTargets? _targets;

  @override
  void initState() {
    super.initState();
    SleepTargets.load().then((targets) {
      if (mounted) {
        setState(() => _targets = targets);
      }
    });
  }

  void _apply(SleepTargets next) {
    setState(() => _targets = next);
    next.save();
  }

  @override
  Widget build(BuildContext context) {
    final targets = _targets;
    if (targets == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _metric('google_health.sleep_stats.time_to_solid', targets.timeToSolid,
            (range) => targets.copyWith(timeToSolid: range)),
        _metric('google_health.sleep_stats.deep', targets.deep,
            (range) => targets.copyWith(deep: range)),
        _metric('google_health.sleep_stats.interruption', targets.interruption,
            (range) => targets.copyWith(interruption: range)),
      ],
    );
  }

  Widget _metric(
    String labelKey,
    SleepTargetRange range,
    SleepTargets Function(SleepTargetRange) apply,
  ) {
    final accent = Theme.of(context).colorScheme.primary;
    void setMin(int value) =>
        _apply(apply(SleepTargetRange(value.clamp(0, range.max), range.max)));
    void setMax(int value) => _apply(
        apply(SleepTargetRange(range.min, value.clamp(range.min, _cap))));
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LocaleText(labelKey,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          GlucoseStepperRow(
            labelKey: 'google_health.sleep_stats.min',
            valueText: '${range.min} min',
            accent: accent,
            onMinus: () => setMin(range.min - _step),
            onPlus: () => setMin(range.min + _step),
            valueChild: _field('${range.min} min', range.min, 0, range.max, setMin),
          ),
          const SizedBox(height: 10),
          GlucoseStepperRow(
            labelKey: 'google_health.sleep_stats.max',
            valueText: '${range.max} min',
            accent: accent,
            onMinus: () => setMax(range.max - _step),
            onPlus: () => setMax(range.max + _step),
            valueChild: _field('${range.max} min', range.max, range.min, _cap, setMax),
          ),
        ],
      ),
    );
  }

  /// Tap-to-type value with a comfortable width so the "N min" label isn't
  /// clipped; the enclosing stepper keeps the +/- buttons for fine steps.
  Widget _field(String text, int value, int min, int max, void Function(int) onSet) {
    return SportEditableNumber(
      valueText: text,
      initial: value.toDouble(),
      min: min.toDouble(),
      max: max.toDouble(),
      width: 108,
      onSubmit: (parsed) => onSet(parsed.round()),
    );
  }
}
