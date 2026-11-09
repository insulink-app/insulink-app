import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/theme/accent_colors.dart';
import 'package:intl/intl.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// The overview strip while a split bolus still has parts to give: how much is
/// left, until when, and the way to stop the rest. Renders nothing otherwise.
class SplitBolusCard extends StatelessWidget {
  const SplitBolusCard({super.key});

  /// Drops the parts not given yet. A part already on its way still lands.
  Future<void> _cancel(PodController controller) async {
    await controller.store.clearSplitBolus();
    controller.notifyRunningBolusChanged();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PodController>();
    final plan = controller.store.splitBolus;
    if (plan == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(PhosphorIconsFill.timer, size: 18, color: context.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocaleText(
                  'pump.split_bolus.title',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  Locales.string(
                    context,
                    'pump.split_bolus.remaining',
                    params: [
                      sportDecimal(plan.remainingUnits, 2),
                      DateFormat('HH:mm').format(plan.endsAt),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _cancel(controller),
            child: LocaleText('pump.split_bolus.cancel'),
          ),
        ],
      ),
    );
  }
}
