import 'package:flutter/material.dart';
import 'package:insulink/src/injection/biometric_auth.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/accent_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Confirmation step before a bolus is delivered: a summary of carbs, glucose
/// and the (possibly edited) bolus, confirmed with the device biometric. Pops
/// `true` once biometric auth succeeds.
class InjectionConfirmPage extends StatefulWidget {
  const InjectionConfirmPage({
    super.key,
    required this.carbs,
    required this.glucoseMgdl,
    required this.bolus,
  });

  final double carbs;
  final int glucoseMgdl;
  final double bolus;

  @override
  State<InjectionConfirmPage> createState() => _InjectionConfirmPageState();
}

class _InjectionConfirmPageState extends State<InjectionConfirmPage> {
  final BiometricAuth _auth = BiometricAuth();
  bool _authenticating = false;

  /// Set when the biometric check was declined or failed. Deliberately sticky:
  /// this page gates a bolus, so "it didn't work" has to stay on screen next to
  /// the retry until the user acts on it, rather than time out on its own.
  bool _failed = false;

  /// Whether this bolus needs biometric confirmation. A zero bolus (carbs-only
  /// logging) is confirmed with a plain tap.
  bool get _needsAuth => widget.bolus > 0;

  Future<void> _confirm() async {
    if (!_needsAuth) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _authenticating = true;
      _failed = false;
    });
    final ok = await _auth.confirm(
      Locales.string(context, 'injection.confirm.reason'),
    );
    if (!mounted) {
      return;
    }
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _authenticating = false;
      _failed = true;
    });
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
              if (_failed)
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
                    : Icon(
                        _needsAuth
                            ? PhosphorIconsRegular.fingerprint
                            : PhosphorIconsRegular.check,
                      ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                label: LocaleText('injection.confirm.button'),
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
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Icon(PhosphorIconsRegular.syringe, color: context.accent, size: 30),
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
            PhosphorIconsRegular.forkKnife,
            'injection.carbs',
            '${widget.carbs.toStringAsFixed(0)} g',
          ),
          Divider(color: scheme.onSurface.withValues(alpha: 0.08), height: 1),
          _row(
            context,
            PhosphorIconsRegular.syringe,
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
        Icon(PhosphorIconsRegular.warning, size: 16, color: scheme.error),
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
          PhosphorIconsRegular.fingerprint,
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
}
