import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/battery/profile_battery_segments.dart';
import 'package:insulink/src/profile/battery/profile_battery_state.dart';
import 'package:provider/provider.dart';

/// Settings control for [ProfileBatteryState]: one segmented row for the mode
/// (off / saving / extreme) and one for how long it runs (2 h / 8 h / for good).
///
/// Deliberately NOT gated behind a warning or a biometric check the way the hard
/// mute of silent mode is — the saver never touches alarms, so making it hard to
/// reach would only stop people using it. The per-mode hint below the rows says
/// what each level actually stops, because that is the part a label can't carry.
class ProfileBatterySelection extends StatelessWidget {
  const ProfileBatterySelection({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProfileBatteryState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LocaleText(
          'profile.battery.description',
          style: TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 10),
        ProfileBatterySegments(_modes(context, state)),
        const SizedBox(height: 14),
        LocaleText(
          'profile.battery.duration._',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        ProfileBatterySegments(_durations(context, state)),
        const SizedBox(height: 14),
        _hint(context, state),
      ],
    );
  }

  List<BatterySegment> _modes(BuildContext context, ProfileBatteryState state) {
    return [
      for (final mode in BatteryMode.values)
        (
          labelKey: 'profile.battery.mode.${mode.name}',
          selected: state.activeMode == mode,
          onTap: () => context.read<ProfileBatteryState>().setMode(mode),
        ),
    ];
  }

  /// The duration row stays visible but inert while the saver is off — a hidden
  /// row would make the choice look unavailable rather than not-yet-relevant.
  List<BatterySegment> _durations(
    BuildContext context,
    ProfileBatteryState state,
  ) {
    final enabled = state.activeMode != BatteryMode.off;
    return [
      for (final minutes in [
        ...ProfileBatteryState.windows,
        ProfileBatteryState.permanent,
      ])
        (
          labelKey: 'profile.battery.duration.${_durationKey(minutes)}',
          selected: enabled && state.windowMin == minutes,
          onTap: enabled
              ? () => context.read<ProfileBatteryState>().setWindow(minutes)
              : null,
        ),
    ];
  }

  /// Locale-key leaf for a window, so the JSON reads `h2`/`h8`/`permanent`
  /// instead of raw minute counts.
  String _durationKey(int minutes) {
    if (minutes == ProfileBatteryState.permanent) {
      return 'permanent';
    }
    return 'h${minutes ~/ 60}';
  }

  Widget _hint(BuildContext context, ProfileBatteryState state) {
    return LocaleText(
      'profile.battery.mode.${state.activeMode.name}_hint',
      style: TextStyle(
        fontSize: 13,
        height: 1.35,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
