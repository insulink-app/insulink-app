import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:provider/provider.dart';

/// "4,43 E" in units the way the bolus figures write them.
String podUnits(BuildContext context, double units) => Locales.string(
  context,
  'injection.bolus.value',
  params: [sportDecimal(units, 2)],
);

/// What this pod has put out in total, split the way the pod itself splits it:
/// the sum large, a bar parted into basal and bolus, and both with their
/// figures under it.
///
/// Basal is here as a TOTAL rather than as rows, because it is a continuous drip:
/// listing every quarter hour would bury the doses the user actually chose. The
/// figure is the one the background watch booked, so a stretch the pod spent
/// suspended counts as the nothing it was.
class PodDeliverySummary extends StatelessWidget {
  const PodDeliverySummary({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final store = context.watch<PodController>().store;
    final basal = store.basalDeliveredTotal;
    final bolus = store.deliveryLog
        .where((entry) => entry.kind == PodDeliveryKind.bolus)
        .fold<double>(0, (sum, entry) => sum + entry.units);
    final total = basal + bolus;
    final unit = Locales.string(
      context,
      'injection.bolus.value',
      params: [''],
    ).trim();
    return InkPanel(
      radius: InkRadius.tile,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LocaleText(
            'pump.log.total',
            style: InkText.label.copyWith(color: colors.muted),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              text: sportDecimal(total, 2),
              style: InkText.bigValue.copyWith(fontSize: 40),
              children: [
                TextSpan(
                  text: ' $unit',
                  style: InkText.unit.copyWith(color: colors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _split(colors, basal, bolus),
          const SizedBox(height: 12),
          Row(
            spacing: 22,
            children: [
              _key(context, colors.accent, 'pump.log.kind.basal', basal),
              _key(context, colors.pace, 'pump.log.kind.bolus', bolus),
            ],
          ),
        ],
      ),
    );
  }

  /// Basal and bolus side by side, each as long as its share.
  Widget _split(InsulinkColors colors, double basal, double bolus) {
    final total = basal + bolus;
    Widget part(Color color, double share) => Expanded(
      flex: (share * 1000).round().clamp(1, 1000),
      child: Container(
        height: 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(5),
        ),
      ),
    );
    if (total <= 0) {
      return Container(
        height: 10,
        decoration: BoxDecoration(
          color: colors.line,
          borderRadius: BorderRadius.circular(5),
        ),
      );
    }
    return Row(
      spacing: 4,
      children: [
        if (basal > 0) part(colors.accent, basal / total),
        if (bolus > 0) part(colors.pace, bolus / total),
      ],
    );
  }

  Widget _key(
    BuildContext context,
    Color color,
    String labelKey,
    double units,
  ) {
    final colors = context.ink;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        LocaleText(
          labelKey,
          style: InkText.label.copyWith(color: colors.muted),
        ),
        Text(
          podUnits(context, units),
          style: InkText.label.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
