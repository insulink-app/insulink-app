import 'package:flutter/material.dart';
import 'package:insulink/src/base/info_button.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/night/night_mode.dart';
import 'package:insulink/src/profile/notifications/notification_threshold_card.dart';
import 'package:insulink/src/profile/profile_segments.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The night mode topic: what it does, off / on / automatic, and for
/// automatic the pulse threshold plus what the detection sees right now.
class NightModeSection extends StatefulWidget {
  const NightModeSection({super.key});

  @override
  State<NightModeSection> createState() => _NightModeSectionState();
}

class _NightModeSectionState extends State<NightModeSection> {
  NightModeChoice _choice = NightModeChoice.off;
  bool _detected = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    const nightMode = NightMode();
    final choice = await nightMode.loadChoice();
    final detected = await nightMode.detected();
    if (mounted) {
      setState(() {
        _choice = choice;
        _detected = detected;
      });
    }
  }

  Future<void> _pick(NightModeChoice choice) async {
    await const NightMode().saveChoice(choice);
    if (mounted) {
      setState(() => _choice = choice);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = InkText.label.copyWith(color: context.ink.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileSegments([
          for (final choice in NightModeChoice.values)
            (
              labelKey: 'profile.night.mode.${choice.name}',
              selected: _choice == choice,
              fill: Theme.of(context).colorScheme.onSurface,
              onTap: () => _pick(choice),
            ),
        ]),
        if (_choice == NightModeChoice.auto) ...[
          const SizedBox(height: 14),
          const NotificationThresholdCard(NightMode.pulseThreshold),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: LocaleText(
                  _detected
                      ? 'profile.night.status.asleep'
                      : 'profile.night.status.awake',
                  style: muted,
                ),
              ),
              const InfoButton(
                titleKey: 'profile.night.mode.auto',
                bodyKey: 'profile.night.auto_hint',
              ),
            ],
          ),
        ],
      ],
    );
  }
}
