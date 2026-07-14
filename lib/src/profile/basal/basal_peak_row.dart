import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/base/circle_icon_button.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/basal/basal_profile.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// One row of the curve generator: a single [BasalPeak] with buttons to shift
/// its hour left/right (or type it directly), a slider for its height, and a
/// delete action. Every change calls [onChanged] so the preview regenerates.
class BasalPeakRow extends StatelessWidget {
  const BasalPeakRow({
    super.key,
    required this.peak,
    required this.onChanged,
    required this.onDelete,
  });

  final BasalPeak peak;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  void _shift(int delta) {
    peak.hour = (peak.hour + delta) % 24;
    onChanged();
  }

  void _typeHour(BuildContext context) {
    final controller = TextEditingController(text: '${peak.hour.round()}');
    Alert(
      icon: PhosphorIconsRegular.clock,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LocaleText(
            'profile.basal.peak_hour',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(suffixText: ':00'),
          ),
        ],
      ),
      cancelButton: true,
      confirmButtonText: 'alert.done',
      callback: () {
        final entered = int.tryParse(controller.text);
        if (entered != null) {
          peak.hour = entered.clamp(0, 23).toDouble();
          onChanged();
        }
      },
    ).show(context);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        CircleIconButton(
          icon: PhosphorIconsRegular.caretLeft,
          accent: accent,
          onTap: () => _shift(-1),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => _typeHour(context),
          child: Container(
            width: 62,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${peak.hour.round().toString().padLeft(2, '0')}:00',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        CircleIconButton(
          icon: PhosphorIconsRegular.caretRight,
          accent: accent,
          onTap: () => _shift(1),
        ),
        Expanded(
          child: Slider(
            min: 0.2,
            max: 2.0,
            value: peak.weight.clamp(0.2, 2.0),
            activeColor: accent,
            inactiveColor: accent.withValues(alpha: 0.18),
            onChanged: (value) {
              peak.weight = value;
              HapticFeedback.selectionClick();
              onChanged();
            },
          ),
        ),
        IconButton(
          icon: const Icon(PhosphorIconsRegular.trash),
          onPressed: onDelete,
        ),
      ],
    );
  }
}
