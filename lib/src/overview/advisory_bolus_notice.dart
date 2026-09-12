import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Says that insulin went out while the app was not involved: the user tapped
/// the button on a pre-warning or a high alarm, and the SERVICE delivered it.
///
/// The notification that reported it can be swiped away, silenced, or never
/// seen at all, and the app may not even have been running. Insulin that was
/// given has to be visible where the user actually looks, so it is repeated
/// here and stays until tapped away.
///
/// Same quiet panel as [StoppedBolusNotice], not an amber mode banner: this is
/// a fact to be told once, not a state to be ended.
class AdvisoryBolusNotice extends StatelessWidget {
  const AdvisoryBolusNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CgmController>();
    final delivery = controller.advisoryDelivery;
    if (delivery == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: controller.dismissAdvisoryDelivery,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  PhosphorIconsBold.syringe,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _message(context, delivery.units, delivery.at),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "2.50 U delivered from the notification at 03:14." The time matters: the
  /// user may be reading this hours later.
  String _message(BuildContext context, double units, DateTime at) {
    return Locales.string(context, 'overview.advisory_bolus')
        .replaceFirst('#', units.toStringAsFixed(2))
        .replaceFirst(
          '#',
          '${at.hour.toString().padLeft(2, '0')}:'
              '${at.minute.toString().padLeft(2, '0')}',
        );
  }
}
