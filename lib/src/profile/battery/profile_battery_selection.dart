import 'package:flutter/material.dart';
import 'package:insulink/src/injection/biometric_auth.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/battery/profile_battery_state.dart';
import 'package:insulink/src/profile/profile_duration_row.dart';
import 'package:insulink/src/profile/profile_segments.dart';
import 'package:provider/provider.dart';

/// Settings control for [ProfileBatteryState]: one segmented row for the level
/// (off / saving / extreme) and the shared duration row below it.
///
/// Switching a level ON requires the device fingerprint (PIN/pattern fallback) —
/// it quietly stops background work the user may be relying on, so it must be a
/// deliberate, owner-only action. Switching it OFF and changing the duration of a
/// level that was already confirmed are direct: neither reduces what the app
/// does. The per-level hint says what each one actually stops, because that is
/// the part a label can't carry.
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
        ProfileSegments(_levels(context, state)),
        const SizedBox(height: 14),
        ProfileDurationRow(
          windowMin: state.window.windowMin,
          enabled: state.activeMode != BatteryMode.off,
          onPicked: (minutes) =>
              context.read<ProfileBatteryState>().setWindow(minutes),
        ),
        const SizedBox(height: 14),
        _hint(context, state),
      ],
    );
  }

  List<ProfileSegment> _levels(
    BuildContext context,
    ProfileBatteryState state,
  ) {
    return [
      for (final mode in BatteryMode.values)
        (
          labelKey: 'profile.battery.mode.${mode.name}',
          selected: state.activeMode == mode,
          fill: null,
          onTap: () => _pick(context, mode),
        ),
    ];
  }

  /// Turning the saver off is immediate; turning it on needs the fingerprint. A
  /// failed or declined check leaves the previous level in place.
  Future<void> _pick(BuildContext context, BatteryMode mode) async {
    final state = context.read<ProfileBatteryState>();
    if (mode == BatteryMode.off) {
      await state.setMode(BatteryMode.off);
      return;
    }
    final reason = Locales.string(context, 'profile.battery.auth_reason');
    if (await BiometricAuth().confirm(reason, allowDeviceCredential: true)) {
      await state.setMode(mode);
    }
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
