import 'package:flutter/material.dart';
import 'package:insulink/src/profile/security/profile_security_state.dart';
import 'package:insulink/src/injection/bolus_delivery.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/base/button_loader.dart';

/// The bolus page's confirm button, gated by the device biometric. Reports how
/// the confirmed dose leaves through [onConfirmed]; a null [bolus] (invalid or
/// above the maximum) disables it.
class InjectionConfirmButton extends StatefulWidget {
  const InjectionConfirmButton({
    super.key,
    required this.bolus,
    required this.usesPump,
    required this.onConfirmed,
  });

  final double? bolus;

  /// Whether a paired pod delivers the dose rather than the user injecting.
  final bool usesPump;

  final void Function(BolusDeliveryResult outcome) onConfirmed;

  @override
  State<InjectionConfirmButton> createState() => _InjectionConfirmButtonState();
}

class _InjectionConfirmButtonState extends State<InjectionConfirmButton> {
  final ProfileSecurityState _security = ProfileSecurityState();
  bool _authenticating = false;

  /// Whether the bolus gate is switched on, read once when the page opens, so
  /// the button never promises a fingerprint prompt the setting turned off.
  bool _gated = true;

  /// Set when the biometric check was declined or failed. Deliberately sticky:
  /// this gates a bolus, so "it didn't work" stays on screen next to the retry
  /// until the user acts on it.
  bool _failed = false;

  /// Whether this bolus needs biometric confirmation. A zero bolus (carbs-only
  /// logging) is confirmed with a plain tap, and so is any bolus once the user
  /// has turned the gate off in the settings.
  bool get _needsAuth => (widget.bolus ?? 0) > 0 && _gated;

  @override
  void initState() {
    super.initState();
    _loadGate();
  }

  Future<void> _loadGate() async {
    final gated = await _security.isGuarded(GuardedAction.bolus);
    if (mounted) {
      setState(() => _gated = gated);
    }
  }

  Future<void> _confirm() async {
    if (!_needsAuth) {
      widget.onConfirmed(_outcome);
      return;
    }
    setState(() {
      _authenticating = true;
      _failed = false;
    });
    final confirmed = await _security.confirm(
      GuardedAction.bolus,
      Locales.string(context, 'injection.confirm.reason'),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _authenticating = false;
      _failed = !confirmed;
    });
    if (confirmed) {
      widget.onConfirmed(_outcome);
    }
  }

  /// How the confirmed dose leaves. EVERY confirmed dose comes through here,
  /// gated or not: the gate decides whether the user is asked, never whether
  /// the pod is.
  ///
  /// It does NOT wait for the pod: [BolusDispatcher] carries a handed over dose
  /// and the overview reports what became of it, including a refusal.
  BolusDeliveryResult get _outcome {
    final bolus = widget.bolus ?? 0;
    if (bolus <= 0 || !widget.usesPump) {
      return BolusDeliveryResult.loggedOnly(bolus);
    }
    return const BolusDeliveryResult.handedOver();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 14,
      children: [
        if (_failed) _failure(context),
        FilledButton.icon(
          onPressed: _authenticating || widget.bolus == null ? null : _confirm,
          icon: _authenticating
              ? const ButtonLoader()
              : Icon(
                  _needsAuth
                      ? PhosphorIconsBold.fingerprint
                      : PhosphorIconsBold.check,
                ),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58)),
          label: LocaleText(
            widget.usesPump
                ? 'injection.confirm.button_pump'
                : 'injection.confirm.button',
          ),
        ),
      ],
    );
  }

  /// Shown above the button once the biometric check fails, in the error
  /// colour, so the reason the bolus did not go through is impossible to miss.
  Widget _failure(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(PhosphorIconsBold.warning, size: 16, color: scheme.error),
        const SizedBox(width: 6),
        Flexible(
          child: LocaleText(
            'injection.confirm.failed',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.error,
            ),
          ),
        ),
      ],
    );
  }
}
