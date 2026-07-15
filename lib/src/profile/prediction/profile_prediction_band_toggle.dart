import 'package:flutter/material.dart';
import 'package:insulink/src/profile/prediction/profile_prediction_state.dart';
import 'package:insulink/src/profile/profile_toggle_row.dart';
import 'package:provider/provider.dart';

/// Draw the forecast as its uncertainty band instead of a bare line. Purely a
/// display choice — the band is already in every fetched curve, so nothing is
/// re-fetched and the chart rebuilds from the state change alone.
///
/// Disabled while the prediction overlay itself is off: there would be nothing
/// to band.
class ProfilePredictionBandToggle extends StatelessWidget {
  const ProfilePredictionBandToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProfilePredictionState>();
    return ProfileToggleRow(
      labelKey: 'profile.prediction.band',
      value: state.band && state.enabled,
      onChanged: state.enabled ? state.setBand : null,
    );
  }
}
