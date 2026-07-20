import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/injection/biometric_auth.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/silent/profile_silent_state.dart';
import 'package:insulink/src/profile/profile_toggle_row.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/theme/status_colors.dart';

/// Settings toggle for [ProfileSilentState]. Observes the provider so it stays
/// in sync with the overview indicator (which can also turn it off).
///
/// Enabling silent mode mutes every glucose alarm, which is safety relevant, so
/// it's gated behind an explicit risk warning — turning it back OFF is direct.
class ProfileSilentToggle extends StatelessWidget {
  const ProfileSilentToggle({super.key});

  void _onChanged(BuildContext context, ProfileSilentState state, bool value) {
    if (!value) {
      state.setSilent(false);
      return;
    }
    // Switching ON: confirm via a danger-styled alert before muting alarms.
    Alert(
      icon: PhosphorIconsFill.warning,
      iconColor: context.danger,
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LocaleText(
              "profile.silent.warning.title",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            LocaleText(
              "profile.silent.warning.body",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
          ],
        ),
      ),
      cancelButton: true,
      confirmButtonText: "profile.silent.warning.confirm",
      confirmButtonColor: Theme.of(context).colorScheme.error,
      callback: () => _authThenMute(context, state),
    ).show(context);
  }

  /// After the risk warning is confirmed, require the device fingerprint (PIN
  /// fallback when none is enrolled) before actually muting — muting silences
  /// life-critical alarms, so it must be a deliberate, owner-only action. A
  /// failed/declined check leaves silent mode OFF; the toggle reflects that.
  Future<void> _authThenMute(
    BuildContext context,
    ProfileSilentState state,
  ) async {
    final ok = await BiometricAuth().confirm(
      Locales.string(context, 'profile.silent.auth_reason'),
      allowDeviceCredential: true,
    );
    if (ok) {
      await state.setSilent(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProfileSilentState>();
    return ProfileToggleRow(
      labelKey: "profile.silent.description",
      value: state.silent,
      onChanged: (value) => _onChanged(context, state, value),
      activeColor: Theme.of(context).colorScheme.error,
    );
  }
}
