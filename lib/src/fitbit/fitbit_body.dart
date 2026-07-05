import 'package:flutter/material.dart';
import 'package:insulink/src/fitbit/fitbit_state.dart';
import 'package:insulink/src/fitbit/fitbit_status_box.dart';
import 'package:provider/provider.dart';

/// The Fitbit device page (Devices tab). Shows the connection box; connecting
/// grants Health Connect read access (the Fitbit is paired in the Fitbit app,
/// which syncs its data into Health Connect).
class FitbitBodyContent extends StatelessWidget {
  const FitbitBodyContent({super.key});

  @override
  Widget build(BuildContext context) {
    final fitbit = context.watch<FitbitState>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: FitbitStatusBox(fitbit: fitbit),
    );
  }
}
