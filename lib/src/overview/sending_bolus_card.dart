import 'package:flutter/material.dart';
import 'package:insulink/src/injection/bolus_dispatcher.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/accent_colors.dart';
import 'package:provider/provider.dart';

/// The overview strip while a confirmed dose is on its way to the pod.
///
/// This is the spinner the injection sheet used to hold the user hostage with.
/// Moving it here is the point: the dose is confirmed, the sheet is closed, and
/// the wait happens where the user can still see everything else.
///
/// Shaped like the running-bolus card that replaces it a moment later, so the one
/// turns into the other rather than the screen jumping.
class SendingBolusCard extends StatelessWidget {
  const SendingBolusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final units = context.watch<BolusDispatcher>().sendingUnits;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LocaleText(
              'pump.bolus.sending',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
            ),
          ),
          if (units != null)
            Text(
              Locales.string(
                context,
                'pump.bolus.units',
              ).replaceFirst('#', units.toStringAsFixed(2)),
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
