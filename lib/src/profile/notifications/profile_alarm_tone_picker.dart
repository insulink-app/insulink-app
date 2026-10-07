import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/base/segmented_toggle.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/cgm/service/alarms.dart';
import 'package:insulink/src/cgm/service/audio_output.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/notifications/alarm_tone.dart';
import 'package:insulink/src/profile/notifications/profile_alarm_tone_state.dart';

/// Per-alarm tone picker: one segmented row per alarm, tapping a style both
/// stores it and plays it, so the choice is made by ear. Played on the alarm
/// stream like the real thing, so the preview is as loud as the alarm will be.
class ProfileAlarmTonePicker extends StatefulWidget {
  const ProfileAlarmTonePicker({super.key});

  @override
  State<ProfileAlarmTonePicker> createState() => _ProfileAlarmTonePickerState();
}

class _ProfileAlarmTonePickerState extends State<ProfileAlarmTonePicker> {
  final ProfileAlarmToneState _state = ProfileAlarmToneState();
  final AudioPlayer _player = AudioPlayer();
  Map<AlarmSlot, AlarmTone>? _tones;

  @override
  void initState() {
    super.initState();
    _loadTones();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadTones() async {
    final tones = await _state.loadAll();
    if (mounted) {
      setState(() => _tones = tones);
    }
  }

  Future<void> _pick(AlarmSlot slot, AlarmTone tone) async {
    setState(() => _tones?[slot] = tone);
    await _state.save(slot, tone);
    await _player.stop();
    final asset = tone.assetFor(slot);
    if (asset == null) {
      return;
    }
    final headphones = await AudioOutput().headphonesConnected();
    await _player.play(
      AssetSource(asset),
      ctx: G7AlarmManager.alarmContext(headphones),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tones = _tones;
    if (tones == null) {
      return const SizedBox.shrink();
    }
    final colors = context.ink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _intro(colors),
        ),
        const SizedBox(height: 18),
        InkPanel.list(
          radius: InkRadius.tile,
          rows: [
            for (final slot in AlarmSlot.values)
              _slotBlock(context, colors, slot, tones[slot]!),
          ],
        ),
      ],
    );
  }

  /// One sentence on how to pick, then what the tones mean in three short
  /// lines, each led by its symbol.
  Widget _intro(InsulinkColors colors) {
    final style = InkText.body.copyWith(
      fontWeight: FontWeight.w400,
      color: colors.muted,
    );
    Widget meaning(IconData icon, String key) => Row(
      spacing: 14,
      children: [
        Icon(icon, size: 18, color: colors.accent),
        Expanded(
          child: LocaleText(key, style: style.copyWith(color: colors.text)),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        LocaleText('profile.alarmtone.description', style: style),
        const SizedBox(height: 2),
        meaning(PhosphorIconsBold.caretDown, 'profile.alarmtone.meaning_low'),
        meaning(PhosphorIconsBold.caretUp, 'profile.alarmtone.meaning_high'),
        meaning(
          PhosphorIconsBold.dotsThree,
          'profile.alarmtone.meaning_urgent',
        ),
      ],
    );
  }

  /// One alarm: a dot in its colour (low, high, or muted for a pre-warning)
  /// with its name, and the styles under it; a tap stores and plays a style.
  Widget _slotBlock(
    BuildContext context,
    InsulinkColors colors,
    AlarmSlot slot,
    AlarmTone picked,
  ) {
    final dot = switch (slot) {
      AlarmSlot.lowWarning || AlarmSlot.lowUrgent => colors.low,
      AlarmSlot.highWarning || AlarmSlot.highUrgent => colors.high,
      _ => colors.muted,
    };
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          Row(
            spacing: 12,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              Expanded(
                child: LocaleText(
                  slot.labelKey,
                  style: InkText.rowTitle.copyWith(fontSize: 17),
                ),
              ),
            ],
          ),
          SegmentedToggle<AlarmTone>(
            selected: picked,
            onChanged: (tone) => _pick(slot, tone),
            options: [
              for (final tone in AlarmTone.values)
                (value: tone, label: Locales.string(context, tone.labelKey)),
            ],
          ),
        ],
      ),
    );
  }
}
