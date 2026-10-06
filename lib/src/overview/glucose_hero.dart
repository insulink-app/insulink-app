import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:insulink/src/cgm/glucose_trend_icon.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/overview/glucose_display_format.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/insulink_colors.dart';
import 'package:insulink/src/theme/insulink_text_styles.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// The current glucose value, large and open on the page: the number with its
/// trend arrow beside it, and underneath the unit and the trend in words.
///
/// Value and arrow share one colour ([GlucoseDisplayFormat.tone]).
class GlucoseHero extends StatelessWidget {
  const GlucoseHero({
    super.key,
    required this.mgdl,
    required this.trendPerMin,
    this.stale = false,
  });

  final int? mgdl;
  final double? trendPerMin;

  /// The value/trend are NOT from a fresh live reading (cached on launch or from
  /// the synced archive), so they are muted to read as not-live.
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final glucose = context.watch<ProfileGlucoseState>();
    final color = GlucoseDisplayFormat(
      glucose,
    ).tone(context.insulinkColors, mgdl, stale: stale);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _valueRow(glucose, color),
        const SizedBox(height: 16),
        _captionRow(context, glucose, color),
      ],
    );
  }

  /// No value yet (just after a re-login/restore) shows a spinner where the
  /// number goes, while the chart below still shows the known history.
  Widget _valueRow(ProfileGlucoseState glucose, Color color) {
    final value = mgdl;
    if (value == null) {
      return const SizedBox(
        height: 100,
        child: Center(child: CupertinoActivityIndicator(radius: 18)),
      );
    }
    return Row(
      spacing: 10,
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              GlucoseDisplayFormat(glucose).value(value),
              style: InsulinkTextStyles.glucoseValue.copyWith(color: color),
            ),
          ),
        ),
        if (trendPerMin != null) _arrow(color),
      ],
    );
  }

  Widget _arrow(Color color) {
    final direction = GlucoseTrendDirection.of(trendPerMin!);
    return Transform.rotate(
      angle: direction.degrees * math.pi / 180,
      child: Icon(PhosphorIconsBold.arrowRight, size: 84, color: color),
    );
  }

  Widget _captionRow(
    BuildContext context,
    ProfileGlucoseState glucose,
    Color color,
  ) {
    final muted = context.insulinkColors.muted;
    return DefaultTextStyle.merge(
      style: TextStyle(fontSize: 15, color: muted),
      child: Row(
        children: [
          Text(glucose.unit.label),
          const Spacer(),
          if (mgdl != null && trendPerMin != null)
            _trendText(context, glucose, color),
        ],
      ),
    );
  }

  /// "Stable +0,3 per min.", with the trend word bold in the value colour.
  Widget _trendText(
    BuildContext context,
    ProfileGlucoseState glucose,
    Color color,
  ) {
    final slug = GlucoseTrendDirection.of(trendPerMin!).slug;
    final rate = GlucoseDisplayFormat(glucose).rate(trendPerMin!);
    final perMin = Locales.string(
      context,
      'overview.trend.per_min',
      params: [rate],
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: Locales.string(context, 'overview.trend.$slug'),
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
          TextSpan(text: ' $perMin'),
        ],
      ),
    );
  }
}
