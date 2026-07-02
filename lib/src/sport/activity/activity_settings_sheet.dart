import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/base/editor_sheet.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/sport/activity/health_import_button.dart';
import 'package:insulink/src/sport/activity/sport_activity_state.dart';
import 'package:insulink/src/profile/glucose/glucose_stepper_row.dart';
import 'package:insulink/src/profile/profile_settings.dart';
import 'package:insulink/src/sport/sport_editable_number.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:provider/provider.dart';

/// Set the stride length + body height (cm) and import data from Google Health.
/// The stride length feeds the distance estimate of the "Today" tiles; the
/// height feeds the BMI. Both are synced to the backend when the sheet closes.
Future<void> showActivitySettingsSheet(BuildContext context) async {
  await showModalBottomSheet(
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
  // Sync stride/height (part of the settings blob) once editing is done.
  if (context.mounted) {
    await ProfileSettings().push(context);
  }
}

class _ActivitySettingsSheet extends StatelessWidget {
  const _ActivitySettingsSheet();

  @override
  Widget build(BuildContext context) {
    final sport = context.watch<SportState>();
    final accent = Theme.of(context).colorScheme.primary;
    return EditorSheet(
      titleKey: 'sport.activity.settings',
      valueText: '',
      accent: accent,
      children: [
        GlucoseStepperRow(
          labelKey: 'sport.activity.stride',
          valueText: '${sport.strideCm} cm',
          accent: accent,
          onMinus: () => _bump(context, -5),
          onPlus: () => _bump(context, 5),
          valueChild: SportEditableNumber(
            valueText: '${sport.strideCm} cm',
            initial: sport.strideCm.toDouble(),
            min: 40,
            max: 120,
            onSubmit: (value) =>
                context.read<SportState>().setStrideCm(value.round()),
          ),
        ),
        const SizedBox(height: 16),
        GlucoseStepperRow(
          labelKey: 'sport.activity.height',
          valueText: '${sport.heightCm} cm',
          accent: accent,
          onMinus: () => _bumpHeight(context, -1),
          onPlus: () => _bumpHeight(context, 1),
          valueChild: SportEditableNumber(
            valueText: '${sport.heightCm} cm',
            initial: sport.heightCm.toDouble(),
            min: 100,
            max: 250,
            onSubmit: (value) =>
                context.read<SportState>().setHeightCm(value.round()),
          ),
        ),
        const SizedBox(height: 12),
        LocaleText(
          'sport.activity.estimate_note',
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
        const SizedBox(height: 6),
        LocaleText(
          'sport.activity.height_note',
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
        const SizedBox(height: 20),
        const HealthImportButton(),
      ],
    );
  }

  void _bump(BuildContext context, int delta) {
    HapticFeedback.selectionClick();
    final sport = context.read<SportState>();
    sport.setStrideCm(sport.strideCm + delta);
  }

  void _bumpHeight(BuildContext context, int delta) {
    HapticFeedback.selectionClick();
    final sport = context.read<SportState>();
    sport.setHeightCm(sport.heightCm + delta);
  }
}
