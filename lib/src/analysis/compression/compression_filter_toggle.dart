import 'package:flutter/material.dart';
import 'package:insulink/src/analysis/compression/night_compression_state.dart';
import 'package:insulink/src/profile/profile_toggle_row.dart';
import 'package:provider/provider.dart';

/// The compression filter on the profile's glucose page: the same switch as
/// the bed in the chart's app bar ([NightCompressionState]), with what it does
/// and what it leaves alone behind its ⓘ.
class CompressionFilterToggle extends StatelessWidget {
  const CompressionFilterToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final compression = context.watch<NightCompressionState>();
    return ProfileToggleRow(
      labelKey: NightCompressionState.hideSetting.labelKey,
      value: compression.hidden,
      onChanged: compression.setHidden,
      infoKey: 'profile.glucose.compression_hint',
    );
  }
}
