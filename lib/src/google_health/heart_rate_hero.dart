import 'package:flutter/material.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// The live pulse at the top of the heart-rate page: the heart in a tinted disc
/// and "Aktuell" over the bpm large. Live from either source, this isolate's
/// band reader or the service's push; a tap restarts the local reader only
/// when nothing streams from anywhere.
class HeartRateHero extends StatelessWidget {
  const HeartRateHero({super.key});

  @override
  Widget build(BuildContext context) {
    final health = context.watch<GoogleHealthState>();
    final monitor = health.liveHrMonitor;
    final colors = context.ink;
    return ListenableBuilder(
      listenable: monitor,
      builder: (context, _) {
        final live = health.hasLiveHr;
        final bpm = health.latestHr;
        return InkWell(
          onTap: live || monitor.isRunning ? null : monitor.start,
          borderRadius: BorderRadius.circular(InkRadius.panel),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              spacing: 16,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.accentSoft,
                  ),
                  child: Icon(
                    PhosphorIconsBold.heart,
                    size: 26,
                    color: live ? colors.accent : colors.muted,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Locales.string(context, 'google_health.hr_now'),
                      style: InkText.label.copyWith(color: colors.muted),
                    ),
                    Text.rich(
                      TextSpan(
                        text: live && bpm != null ? '$bpm' : '–',
                        style: InkText.bigValue.copyWith(fontSize: 52),
                        children: [
                          TextSpan(
                            text: ' bpm',
                            style: InkText.section.copyWith(
                              color: colors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
