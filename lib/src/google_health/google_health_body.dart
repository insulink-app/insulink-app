import 'package:flutter/material.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/google_health/google_health_status_box.dart';
import 'package:provider/provider.dart';

/// The Google Health device page (Devices tab). Shows the connection box; connecting
/// grants Health Connect read access (the Google Health is paired in the Google Health app,
/// which syncs its data into Health Connect).
class GoogleHealthBodyContent extends StatelessWidget {
  const GoogleHealthBodyContent({super.key});

  @override
  Widget build(BuildContext context) {
    final health = context.watch<GoogleHealthState>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: GoogleHealthStatusBox(health: health),
    );
  }
}
