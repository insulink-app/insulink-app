import 'package:flutter/material.dart';
import 'package:insulink/src/base/stepped_slider.dart';
import 'package:insulink/src/base/grab_handle.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/basal/profile_basal_state.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/protocol/pod_basal_program.dart';
import 'package:insulink/src/pump/protocol/pod_temp_basal_command.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:provider/provider.dart';

/// Sets a temporary basal rate: a percentage of the scheduled rate, for a whole
/// number of half hours.
///
/// Expressed as a PERCENTAGE rather than in U/h because that is the decision the
/// user is actually making — "less than usual for a while" — and because it stays
/// meaningful across the day as the schedule changes underneath it.
void openTempBasalSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const PodTempBasalSheet(),
  );
}

class PodTempBasalSheet extends StatefulWidget {
  const PodTempBasalSheet({super.key});

  @override
  State<PodTempBasalSheet> createState() => _PodTempBasalSheetState();
}

class _PodTempBasalSheetState extends State<PodTempBasalSheet> {
  /// Percent of the scheduled rate. 0 stops basal entirely, which is the common
  /// case before sport.
  int _percent = 100;
  int _minutes = 60;

  static const int _maxPercent = 200;
  static const int _percentStep = 10;

  /// The rate the pod would run, from the scheduled rate at this moment.
  double get _rate {
    final profile = context.read<ProfileBasalState>().active;
    final scheduled = profile.rates[DateTime.now().hour];
    final raw = scheduled * _percent / 100;
    // Snap to the step the pod meters in, so the sheet never promises a rate the
    // command would refuse.
    return (raw / 0.05).round() * 0.05;
  }

  Future<void> _apply() async {
    final controller = context.read<PodController>();
    final navigator = Navigator.of(context);
    try {
      await controller.setTemporaryBasal(
        PodTempBasalRate(unitsPerHour: _rate, minutes: _minutes),
      );
    } on PodBasalProgramException {
      return;
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GrabHandle(),
          const SizedBox(height: 20),
          LocaleText(
            'pump.temp.title',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          LocaleText(
            'pump.temp.body',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          _percentRow(context, scheme),
          const SizedBox(height: 16),
          _durationRow(context, scheme),
          const SizedBox(height: 20),
          _summary(context, scheme),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: context.watch<PodController>().isBusy ? null : _apply,
            child: LocaleText('pump.temp.apply'),
          ),
        ],
      ),
    );
  }

  Widget _percentRow(BuildContext context, ColorScheme scheme) {
    return _sliderRow(
      scheme: scheme,
      labelKey: 'pump.temp.percent',
      value: '$_percent %',
      slider: SteppedSlider(
        value: _percent.toDouble(),
        min: 0,
        max: _maxPercent.toDouble(),
        steps: _maxPercent ~/ _percentStep,
        onChanged: (value) => setState(() => _percent = value.round()),
      ),
    );
  }

  Widget _durationRow(BuildContext context, ColorScheme scheme) {
    final slots = PodTempBasalRate.maxSlots;
    return _sliderRow(
      scheme: scheme,
      labelKey: 'pump.temp.duration',
      value: Locales.string(context, 'pump.temp.duration_value')
          .replaceFirst('#', '${_minutes ~/ 60}')
          .replaceFirst('#', '${_minutes % 60}'),
      slider: SteppedSlider(
        value: (_minutes ~/ PodTempBasalRate.minutesPerSlot).toDouble(),
        min: 1,
        max: slots.toDouble(),
        steps: slots - 1,
        onChanged: (value) => setState(
          () => _minutes = value.round() * PodTempBasalRate.minutesPerSlot,
        ),
      ),
    );
  }

  Widget _sliderRow({
    required ColorScheme scheme,
    required String labelKey,
    required String value,
    required Widget slider,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            LocaleText(labelKey, style: const TextStyle(fontSize: 14)),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
        slider,
      ],
    );
  }

  /// What the pod will actually run, so the percentage is never the last word —
  /// the number that reaches the body is shown before it is sent.
  Widget _summary(BuildContext context, ColorScheme scheme) {
    final rate = _rate;
    final stopped = rate <= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        stopped
            ? Locales.string(context, 'pump.temp.summary_stop')
            : Locales.string(
                context,
                'pump.temp.summary',
              ).replaceFirst('#', rate.toStringAsFixed(2)),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: stopped ? context.warning : scheme.onSurface,
        ),
      ),
    );
  }
}
