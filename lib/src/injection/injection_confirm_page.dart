import 'package:flutter/material.dart';
import 'package:insulink/src/profile/security/profile_security_state.dart';
import 'package:insulink/src/injection/bolus_delivery.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/accent_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/theme/brand_tints.dart';

/// Confirmation step before a bolus is delivered: a summary of carbs, glucose
/// and the (possibly edited) bolus, confirmed with the device biometric. Pops
/// `true` once biometric auth succeeds.
class InjectionConfirmPage extends StatefulWidget {
  const InjectionConfirmPage({
    super.key,
    required this.carbs,
    required this.glucoseMgdl,
    required this.bolus,
    this.delivery,
    this.deliveredLastHour = 0,
  });

  final double carbs;
  final int glucoseMgdl;
  final double bolus;

  /// How the bolus reaches the body. Null, or one reporting no pump, keeps the
  /// original behaviour: the user injects and the app only records it.
  final BolusDelivery? delivery;

  /// Insulin already given within the past hour, checked against the rolling
  /// limit before a pod is asked to deliver.
  final double deliveredLastHour;

  @override
  State<InjectionConfirmPage> createState() => _InjectionConfirmPageState();
}

class _InjectionConfirmPageState extends State<InjectionConfirmPage> {
  final ProfileSecurityState _security = ProfileSecurityState();
  bool _authenticating = false;

  /// Whether the bolus gate is switched on, read once when the page opens. The
  /// page reads it itself rather than asking and finding out, because the hint
  /// and the button carry a fingerprint on them and must not promise a prompt
  /// that the setting has turned off.
  bool _gated = true;

  /// Set when the biometric check was declined or failed. Deliberately sticky:
  /// this page gates a bolus, so "it didn't work" has to stay on screen next to
  /// the retry until the user acts on it, rather than time out on its own.
  bool _failed = false;

  /// Set when a pump was asked to deliver and did not, or could not say whether
  /// it did. Sticky for the same reason and carries the pod's own wording, since
  /// "reservoir too low" and "we lost the confirmation" need different reactions.
  BolusDeliveryResult? _pumpOutcome;

  /// Whether this bolus needs biometric confirmation. A zero bolus (carbs-only
  /// logging) is confirmed with a plain tap, and so is any bolus once the user
  /// has turned the gate off in the settings.
  bool get _needsAuth => widget.bolus > 0 && _gated;

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

  /// Whether the pod will be asked to deliver rather than the user injecting.
  bool get _usesPump => widget.delivery?.usesPump ?? false;

  /// A pod outcome that the user still has to acknowledge before the meal is
  /// logged without its insulin.
  bool get _awaitingAcknowledgement => _pumpOutcome?.needsAttention ?? false;

  Future<void> _confirm() async {
    if (_awaitingAcknowledgement) {
      Navigator.of(context).pop(_pumpOutcome);
      return;
    }
    if (!_needsAuth) {
      await _runDelivery();
      return;
    }
    setState(() {
      _authenticating = true;
      _failed = false;
      _pumpOutcome = null;
    });
    final ok = await _security.confirm(
      GuardedAction.bolus,
      Locales.string(context, 'injection.confirm.reason'),
    );
    if (!mounted) {
      return;
    }
    if (!ok) {
      setState(() {
        _authenticating = false;
        _failed = true;
      });
      return;
    }
    await _runDelivery();
  }

  /// Hands the confirmed dose over and closes. EVERY confirmed dose comes
  /// through here, gated or not: the gate decides whether the user is asked,
  /// never whether the pod is. A dose that skipped the question because the
  /// user switched the fingerprint off is still a dose.
  ///
  /// It does NOT wait for the pod. The pod takes seconds to answer and minutes to
  /// deliver, and the user has already confirmed — what they want next is their
  /// overview, not a spinner. [BolusDispatcher] carries the dose from here and
  /// the overview reports what became of it, including a refusal.
  Future<void> _runDelivery() async {
    final delivery = widget.delivery;
    if (widget.bolus <= 0 || delivery == null || !delivery.usesPump) {
      Navigator.of(context).pop(BolusDeliveryResult.loggedOnly(widget.bolus));
      return;
    }
    Navigator.of(context).pop(const BolusDeliveryResult.handedOver());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('injection.confirm.title'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              _bolusHero(context),
              const SizedBox(height: 24),
              _details(context),
              const Spacer(),
              if (_pumpOutcome != null)
                _pumpFailure(context, _pumpOutcome!)
              else if (_failed)
                _failure(context)
              else if (_needsAuth)
                _hint(context),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _authenticating ? null : _confirm,
                icon: _authenticating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_buttonIcon),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                label: LocaleText(_buttonLabelKey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The headline: the bolus as a large number in a primary-tinted card.
  Widget _bolusHero(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: scheme.tintPanel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.tintLine),
      ),
      child: Column(
        children: [
          Icon(PhosphorIconsBold.syringe, color: context.accent, size: 30),
          const SizedBox(height: 10),
          LocaleText(
            'injection.bolus',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              text: widget.bolus.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 46,
                fontWeight: FontWeight.bold,
                color: context.accent,
                height: 1,
              ),
              children: [
                TextSpan(
                  text: ' ${Locales.string(context, 'injection.bolus.unit')}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: context.accent.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _details(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 18),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: [
          _row(
            context,
            PhosphorIconsBold.forkKnife,
            'injection.carbs',
            '${widget.carbs.toStringAsFixed(0)} g',
          ),
          Divider(color: scheme.onSurface.withValues(alpha: 0.08), height: 1),
          _row(
            context,
            PhosphorIconsBold.syringe,
            'injection.glucose',
            '${widget.glucoseMgdl} mg/dL',
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String labelKey,
    String value,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: LocaleText(
              labelKey,
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// Takes the hint's place once the biometric check fails, in the error colour:
  /// same spot, directly above the button that is now a retry, so the reason the
  /// bolus did not go through is impossible to miss and does not disappear.
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

  /// Small hint reminding the user the confirm uses biometrics.
  Widget _hint(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          PhosphorIconsBold.fingerprint,
          size: 16,
          color: scheme.onSurface.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: LocaleText(
            'injection.confirm.reason',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }

  IconData get _buttonIcon {
    if (_awaitingAcknowledgement) {
      return PhosphorIconsBold.notePencil;
    }
    if (_needsAuth) {
      return PhosphorIconsBold.fingerprint;
    }
    return PhosphorIconsBold.check;
  }

  /// The button changes meaning once a pod outcome is on screen: it no longer
  /// confirms a dose, it logs the meal without one.
  String get _buttonLabelKey {
    if (_awaitingAcknowledgement) {
      return 'injection.confirm.log_without_bolus';
    }
    if (_usesPump) {
      return 'injection.confirm.button_pump';
    }
    return 'injection.confirm.button';
  }

  /// The pod's own outcome, in the error colour, in the same place the biometric
  /// failure uses. An unknown outcome gets its own wording because the reaction
  /// differs: a refusal means no insulin, an unknown means go and look at the pod.
  Widget _pumpFailure(BuildContext context, BolusDeliveryResult outcome) {
    final scheme = Theme.of(context).colorScheme;
    final headlineKey = outcome.status == BolusDeliveryStatus.unknown
        ? 'injection.confirm.pump_unknown'
        : 'injection.confirm.pump_refused';
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(PhosphorIconsBold.warning, size: 16, color: scheme.error),
            const SizedBox(width: 6),
            Flexible(
              child: LocaleText(
                headlineKey,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.error,
                ),
              ),
            ),
          ],
        ),
        if (outcome.detail != null) ...[
          const SizedBox(height: 4),
          Text(
            outcome.detail!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
