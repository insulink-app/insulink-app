import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/base/editor_sheet.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/sport/activity/health_import_button.dart';
import 'package:insulink/src/sport/activity/sport_activity_state.dart';
import 'package:insulink/src/profile/glucose/glucose_stepper_row.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:provider/provider.dart';

/// Schrittlänge einstellen (cm) und Daten aus Google Health importieren. Die
/// Schrittlänge geht in die Distanzschätzung der „Heute"-Kacheln ein.
Future<void> showActivitySettingsSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: context.read<SportState>()),
        ChangeNotifierProvider.value(value: context.read<SportActivityState>()),
      ],
      child: const _ActivitySettingsSheet(),
    ),
  );
}

class _ActivitySettingsSheet extends StatelessWidget {
  const _ActivitySettingsSheet();

  @override
  Widget build(BuildContext context) {
    final sport = context.watch<SportState>();
    final accent = Theme.of(context).colorScheme.primary;
    return EditorSheet(
      titleKey: 'sport.activity.stride',
      valueText: '${sport.strideCm} cm',
      accent: accent,
      children: [
        GlucoseStepperRow(
          labelKey: 'sport.activity.stride',
          valueText: '${sport.strideCm} cm',
          accent: accent,
          onMinus: () => _bump(context, -5),
          onPlus: () => _bump(context, 5),
        ),
        const SizedBox(height: 12),
        LocaleText(
          'sport.activity.estimate_note',
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
        const SizedBox(height: 20),
        const HealthImportButton(),
        const SizedBox(height: 8),
        LocaleText(
          'sport.health.note',
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
      ],
    );
  }

  void _bump(BuildContext context, int delta) {
    HapticFeedback.selectionClick();
    final sport = context.read<SportState>();
    sport.setStrideCm(sport.strideCm + delta);
  }
}
