import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/notifications/notification_threshold_card.dart';
import 'package:insulink/src/profile/notifications/notification_toggle.dart';
import 'package:insulink/src/pump/loop/loop_micro_bolus_settings.dart';

/// The micro-bolus settings inside the profile's automated-delivery section.
///
/// Every setting is always shown, switched on or not, so a user can set the
/// limits first and only then turn the feature on.
class LoopMicroBolusSection extends StatelessWidget {
  const LoopMicroBolusSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LocaleText(
          'profile.loop.micro_bolus',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const LocaleText(
          'profile.loop.micro_bolus.description',
          style: TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 12),
        for (final toggle in LoopMicroBolusSettings.toggles)
          NotificationToggle(toggle),
        for (final threshold in LoopMicroBolusSettings.thresholds) ...[
          const SizedBox(height: 10),
          NotificationThresholdCard(threshold),
        ],
      ],
    );
  }
}
