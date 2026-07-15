import 'dart:async';

import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/google_health/health_permissions.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/sport/activity/health_importer.dart';
import 'package:insulink/src/sport/activity/sport_activity_state.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:insulink/src/theme/accent_colors.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Card that syncs the last ~90 days of Google Health data
/// (steps/distance/calories into the archive, weight into the history) — with
/// loading and result feedback.
///
/// The whole card is the control, so it carries the accent on a neutral surface,
/// like [TileLayoutButton] next to it. A neutral badge on a tinted card was
/// tried and read as two unrelated things.
class HealthImportButton extends StatefulWidget {
  const HealthImportButton({super.key});

  @override
  State<HealthImportButton> createState() => _HealthImportButtonState();
}

class _HealthImportButtonState extends State<HealthImportButton> {
  static const _confirmFor = Duration(seconds: 2);

  bool _busy = false;

  /// Set briefly after a successful import, to swap the trailing glyph for a
  /// checkmark.
  bool _imported = false;

  Timer? _revert;

  @override
  void dispose() {
    _revert?.cancel();
    super.dispose();
  }

  /// Asks before importing: this is an explicit tap, so a prompt is what the
  /// user just requested — unlike the Sport page's import-on-open, which stays
  /// silent (see [HealthPermissions]).
  ///
  /// The two outcomes are reported differently, because they ask different
  /// things of the user. Success needs no words: the numbers on the page behind
  /// this card have just changed, so the card only nods with a checkmark. A
  /// denial or a missing Health Connect is a dead end that has to be explained
  /// and acknowledged, so it gets a modal.
  Future<void> _run() async {
    setState(() => _busy = true);
    final sport = context.read<SportState>();
    final activity = context.read<SportActivityState>();
    await HealthPermissions().request();
    final result = await HealthImporter().import(sport, activity);
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (result == HealthImportResult.success) {
      _confirm();
      return;
    }
    Alert(
      type: AlertType.error,
      description: result == HealthImportResult.denied
          ? 'sport.health.denied'
          : 'sport.health.unavailable',
    ).show(context);
  }

  void _confirm() {
    setState(() => _imported = true);
    _revert?.cancel();
    _revert = Timer(_confirmFor, () {
      if (mounted) {
        setState(() => _imported = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.onSurface.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _busy ? null : _run,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(PhosphorIconsFill.heart, color: context.accent, size: 24),
              const SizedBox(width: 14),
              Expanded(child: _text(context, scheme)),
              const SizedBox(width: 10),
              _trailing(scheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _text(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LocaleText(
          'sport.health.import',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        LocaleText(
          'sport.health.subtitle',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _trailing(ColorScheme scheme) {
    if (_busy) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_imported) {
      return Icon(PhosphorIconsRegular.check, color: context.accent);
    }
    return Icon(PhosphorIconsRegular.arrowsClockwise, color: context.accent);
  }
}
