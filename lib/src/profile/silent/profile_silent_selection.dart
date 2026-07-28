import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/injection/biometric_auth.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/silent/profile_silent_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/theme/status_colors.dart';

/// Settings control for [ProfileSilentState]: a segmented pick between muting
/// nothing, only the alarm tones, or everything. Observes the provider so it
/// stays in sync with the overview indicator (which can also turn it off).
///
/// Only [SilentMode.all] is gated: it mutes every glucose alarm, which is safety
/// relevant, so it needs an explicit risk warning plus a biometric confirmation.
/// Muting the tones alone keeps the buzzing alarm on screen, so it is direct —
/// as is turning the mute back off.
class ProfileSilentSelection extends StatelessWidget {
  const ProfileSilentSelection({super.key});

  void _onPicked(
    BuildContext context,
    ProfileSilentState state,
    SilentMode mode,
  ) {
    if (mode != SilentMode.all) {
      state.setMode(mode);
      return;
    }
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
  /// failed/declined check leaves the previous mode in place.
  Future<void> _authThenMute(
    BuildContext context,
    ProfileSilentState state,
  ) async {
    final confirmed = await BiometricAuth().confirm(
      Locales.string(context, 'profile.silent.auth_reason'),
      allowDeviceCredential: true,
    );
    if (confirmed) {
      await state.setMode(SilentMode.all);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProfileSilentState>();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LocaleText(
          "profile.silent.description",
          style: TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            children: [
              for (final mode in SilentMode.values)
                Expanded(child: _segment(context, state, theme, mode)),
            ],
          ),
        ),
      ],
    );
  }

  /// One segment of the control. A muting segment fills in the error colour so
  /// the picked state reads as "alarms are held back", not as a neutral choice.
  Widget _segment(
    BuildContext context,
    ProfileSilentState state,
    ThemeData theme,
    SilentMode mode,
  ) {
    final selected = state.mode == mode;
    final fill = mode == SilentMode.off
        ? theme.colorScheme.onSurface
        : theme.colorScheme.error;
    return GestureDetector(
      onTap: () => _onPicked(context, state, mode),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? fill : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: LocaleText(
          'profile.silent.mode.${mode.name}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected
                ? theme.colorScheme.surface
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
