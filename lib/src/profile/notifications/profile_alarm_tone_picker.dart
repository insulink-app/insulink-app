import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/service/alarms.dart';
import 'package:insulink/src/cgm/service/audio_output.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/notifications/alarm_tone.dart';
import 'package:insulink/src/profile/notifications/profile_alarm_tone_state.dart';
import 'package:insulink/src/profile/profile_segments.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LocaleText(
          "profile.alarmtone.description",
          style: TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 14),
        for (final slot in AlarmSlot.values)
          ..._slotRow(context, slot, tones[slot]!),
      ],
    );
  }

  /// One alarm's row. A picked "off" is painted in the error colour, like
  /// silent mode's muting choices, so a muted alarm reads as held back rather
  /// than as just another style.
  List<Widget> _slotRow(
    BuildContext context,
    AlarmSlot slot,
    AlarmTone picked,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return [
      LocaleText(
        slot.labelKey,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      ProfileSegments([
        for (final tone in AlarmTone.values)
          (
            labelKey: tone.labelKey,
            selected: tone == picked,
            fill: tone == AlarmTone.off ? scheme.error : null,
            onTap: () => _pick(slot, tone),
          ),
      ]),
      const SizedBox(height: 14),
    ];
  }
}
