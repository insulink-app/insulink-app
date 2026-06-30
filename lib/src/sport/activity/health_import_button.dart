import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/activity/health_importer.dart';
import 'package:insulink/src/sport/activity/sport_activity_state.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:provider/provider.dart';

/// Knopf, der Daten aus Google Health (Health Connect) zieht — Schritte,
/// Distanz, Kalorien (heute) und Gewicht (Verlauf) — mit Lade- und Ergebnis-
/// Rückmeldung.
class HealthImportButton extends StatefulWidget {
  const HealthImportButton({super.key});

  @override
  State<HealthImportButton> createState() => _HealthImportButtonState();
}

class _HealthImportButtonState extends State<HealthImportButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final sport = context.read<SportState>();
    final activity = context.read<SportActivityState>();
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
    return OutlinedButton.icon(
      onPressed: _busy ? null : _run,
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync),
      label: LocaleText('sport.health.import'),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    );
  }
}
