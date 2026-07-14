import 'package:flutter/material.dart';
import 'package:insulink/src/google_health/health_permissions.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/activity/health_importer.dart';
import 'package:insulink/src/sport/activity/sport_activity_state.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Branded card that syncs the last ~90 days of Google Health data
/// (steps/distance/calories into the archive, weight into the history) — with
/// loading and result feedback.
class HealthImportButton extends StatefulWidget {
  const HealthImportButton({super.key});

  @override
  State<HealthImportButton> createState() => _HealthImportButtonState();
}

class _HealthImportButtonState extends State<HealthImportButton> {
  bool _busy = false;

  /// Asks before importing: this is an explicit tap, so a prompt is what the
  /// user just requested — unlike the Sport page's import-on-open, which stays
  /// silent (see [HealthPermissions]).
  Future<void> _run() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final sport = context.read<SportState>();
    final activity = context.read<SportActivityState>();
    await HealthPermissions().request();
    final result = await HealthImporter().import(sport, activity);
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    messenger.showSnackBar(
      SnackBar(content: Text(Locales.string(context, _messageKey(result)))),
    );
  }

  String _messageKey(HealthImportResult result) => switch (result) {
    HealthImportResult.success => 'sport.health.imported',
    HealthImportResult.denied => 'sport.health.denied',
    HealthImportResult.unavailable => 'sport.health.unavailable',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _busy ? null : _run,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _badge(scheme),
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

  Widget _badge(ColorScheme scheme) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
      child: Icon(PhosphorIconsFill.heart, color: scheme.onPrimary, size: 22),
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
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
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
    return Icon(PhosphorIconsRegular.arrowsClockwise, color: scheme.primary);
  }
}
