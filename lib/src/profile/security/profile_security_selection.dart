import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/profile_toggle_row.dart';
import 'package:insulink/src/profile/security/profile_security_state.dart';

/// Settings control for [ProfileSecurityState]: one switch per action that can
/// ask for the fingerprint.
///
/// Every switch is loaded once and then kept in memory, because a gate the user
/// just turned off has to read as off immediately, while the storage write is
/// still in flight.
class ProfileSecuritySelection extends StatefulWidget {
  const ProfileSecuritySelection({super.key, this.security});

  /// Injectable for tests; the app leaves it null and gets the real gate.
  final ProfileSecurityState? security;

  @override
  State<ProfileSecuritySelection> createState() =>
      _ProfileSecuritySelectionState();
}

class _ProfileSecuritySelectionState extends State<ProfileSecuritySelection> {
  late final ProfileSecurityState _security =
      widget.security ?? ProfileSecurityState();

  final Map<GuardedAction, bool> _guards = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final action in GuardedAction.values) {
      _guards[action] = await _security.isGuarded(action);
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _set(GuardedAction action, bool guarded) async {
    setState(() => _guards[action] = guarded);
    await _security.setGuarded(action, guarded);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LocaleText(
          'profile.security.description',
          style: TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 12),
        for (final action in GuardedAction.values)
          ProfileToggleRow(
            labelKey: action.labelKey,
            value: _guards[action] ?? action.defaultOn,
            onChanged: (guarded) => _set(action, guarded),
          ),
      ],
    );
  }
}
