import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/prediction/profile_prediction_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/theme/brand_tints.dart';

/// Forecast-horizon picker: two tappable rows (30 / 60 min) with a check on the
/// active one — the same list style as the language picker.
class ProfilePredictionHorizon extends StatelessWidget {
  const ProfilePredictionHorizon({super.key});

  static const _horizons = [30, 60];

  void _select(
    BuildContext context,
    ProfilePredictionState state,
    int minutes,
  ) {
    state.setHorizon(minutes);
    context.read<CgmController>().refreshPrediction();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProfilePredictionState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final minutes in _horizons) _row(context, state, minutes),
      ],
    );
  }

  Widget _row(BuildContext context, ProfilePredictionState state, int minutes) {
    final scheme = Theme.of(context).colorScheme;
    final selected = state.horizon == minutes;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected
            ? scheme.tintSelected
            : scheme.onSurface.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: selected
              ? BorderSide(color: scheme.primary, width: 1.5)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _select(context, state, minutes),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: LocaleText(
                    'profile.prediction.min_$minutes',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? scheme.primary : null,
                    ),
                  ),
                ),
                if (selected)
                  Icon(PhosphorIconsRegular.check, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
