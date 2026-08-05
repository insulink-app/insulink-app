import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/profile_mode_window.dart';
import 'package:insulink/src/profile/profile_segments.dart';

/// How long a mode runs: the offered windows plus "until switched off".
///
/// Shared by silent mode and the battery saver — both are modes you switch on for
/// a while, and both offer the same choice, so it is one widget and one set of
/// locale keys (`profile.duration.*`).
///
/// Stays visible but inert while its mode is off ([enabled] false): hiding the
/// row would make the choice look unavailable rather than not-yet-relevant.
class ProfileDurationRow extends StatelessWidget {
  const ProfileDurationRow({
    super.key,
    required this.windowMin,
    required this.enabled,
    required this.onPicked,
  });

  /// The currently picked window in minutes, or [ProfileModeWindow.permanent].
  final int windowMin;

  final bool enabled;
  final ValueChanged<int> onPicked;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocaleText(
          'profile.duration._',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        ProfileSegments(_segments()),
      ],
    );
  }

  List<ProfileSegment> _segments() {
    return [
      for (final minutes in [
        ...ProfileModeWindow.options,
        ProfileModeWindow.permanent,
      ])
        (
          labelKey: 'profile.duration.${_key(minutes)}',
          selected: enabled && windowMin == minutes,
          fill: null,
          onTap: enabled ? () => onPicked(minutes) : null,
        ),
    ];
  }

  /// Locale-key leaf for a window, so the JSON reads `h2`/`h8`/`permanent`
  /// instead of raw minute counts.
  String _key(int minutes) {
    if (minutes == ProfileModeWindow.permanent) {
      return 'permanent';
    }
    return 'h${minutes ~/ 60}';
  }
}
