import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/profile/prediction/profile_prediction_state.dart';
import 'package:insulink/src/profile/profile_toggle_row.dart';
import 'package:provider/provider.dart';

/// Enable/disable the glucose-prediction overlay. Toggling immediately asks the
/// controller for a fresh forecast (or drops it) so the change shows without
/// waiting for the next reading.
class ProfilePredictionToggle extends StatelessWidget {
  const ProfilePredictionToggle({super.key});

  void _onChanged(BuildContext context, ProfilePredictionState state, bool value) {
    state.setEnabled(value);
    context.read<CgmController>().refreshPrediction();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProfilePredictionState>();
    return ProfileToggleRow(
      labelKey: 'profile.prediction.description',
      value: state.enabled,
      onChanged: (value) => _onChanged(context, state, value),
    );
  }
}
