import 'package:flutter/material.dart';
import 'package:insulink/main.dart';
import 'package:insulink/src/base/restore_offer_card.dart';
import 'package:insulink/src/injection/biometric_auth.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/profile_settings.dart';
import 'package:insulink/src/profile/remote_review/remote_settings_review.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Asks the user to confirm the account settings [RemoteSettingsReview] is
/// holding back, naming what they touch. Renders nothing while nothing is held.
///
/// Taking them over asks for the fingerprint or the device PIN where the phone
/// has one, whatever the guard switches say: those switches are among the held
/// settings themselves. Turning them down pushes this phone's settings back to
/// the account, so the same change is not offered again at the next start.
class RemoteSettingsCard extends StatefulWidget {
  const RemoteSettingsCard({super.key});

  @override
  State<RemoteSettingsCard> createState() => _RemoteSettingsCardState();
}

class _RemoteSettingsCardState extends State<RemoteSettingsCard> {
  static const _review = RemoteSettingsReview();

  List<RemoteSettingsGroup> _groups = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final groups = await _review.groups();
    if (mounted) {
      setState(() => _groups = groups);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_groups.isEmpty) {
      return const SizedBox.shrink();
    }
    return RestoreOfferCard(
      icon: PhosphorIconsBold.shieldWarning,
      titleKey: 'settings_review.title',
      detail: _groups
          .map((group) => Locales.string(context, group.labelKey))
          .join(', '),
      hintKey: 'settings_review.hint',
      secondaryLabelKey: 'settings_review.discard',
      onSecondary: _busy ? null : _discard,
      primaryLabelKey: 'settings_review.apply',
      onPrimary: _busy ? null : _apply,
    );
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    if (!await _confirmed()) {
      setState(() => _busy = false);
      return;
    }
    await _review.apply();
    if (mounted) {
      InsulinkApp.reload(context);
    }
  }

  Future<bool> _confirmed() async {
    final auth = BiometricAuth();
    if (!await auth.canAuthenticate() || !mounted) {
      return true;
    }
    return auth.confirm(
      Locales.string(context, 'settings_review.reason'),
      allowDeviceCredential: true,
    );
  }

  Future<void> _discard() async {
    setState(() => _busy = true);
    await _review.discard();
    if (!mounted) {
      return;
    }
    await ProfileSettings().push(context);
    if (mounted) {
      setState(() {
        _busy = false;
        _groups = const [];
      });
    }
  }
}
