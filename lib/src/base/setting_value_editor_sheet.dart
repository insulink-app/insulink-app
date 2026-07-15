import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/base/circle_icon_button.dart';
import 'package:insulink/src/base/editor_sheet.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/base/setting_fill_bar.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Focused editor for one integer setting: a fill preview, a [Slider] for quick
/// adjustment, and a stepper for precise control. Lives in a modal bottom sheet
/// so dragging never competes with the settings list scroll.
class SettingValueEditorSheet extends StatefulWidget {
  const SettingValueEditorSheet({
    super.key,
    required this.labelKey,
    required this.valueKey,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String labelKey, valueKey;
  final int value, min, max, step;
  final void Function(int) onChanged;

  @override
  State<SettingValueEditorSheet> createState() =>
      _SettingValueEditorSheetState();
}

class _SettingValueEditorSheetState extends State<SettingValueEditorSheet> {
  late int _value = widget.value;

  void _apply(int value) {
    final clamped = value.clamp(widget.min, widget.max);
    setState(() => _value = clamped);
    widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return EditorSheet(
      titleKey: widget.labelKey,
      valueText: Locales.string(context, widget.valueKey, params: ['$_value']),
      accent: accent,
      children: [
        SettingFillBar(
          value: _value,
          min: widget.min,
          max: widget.max,
          color: accent,
          height: 10,
        ),
        const SizedBox(height: 6),
        _slider(accent),
        const SizedBox(height: 12),
        _stepper(accent),
      ],
    );
  }

  Widget _slider(Color accent) {
    final divisions = (widget.max - widget.min) ~/ widget.step;
    return Slider(
      min: widget.min.toDouble(),
      max: widget.max.toDouble(),
      divisions: divisions,
      value: _value.toDouble().clamp(
        widget.min.toDouble(),
        widget.max.toDouble(),
      ),
      activeColor: accent,
      inactiveColor: accent.withValues(alpha: 0.18),
      onChanged: _onSlide,
    );
  }

  void _onSlide(double raw) {
    final rounded = raw.round();
    // Haptic tick per stepped change while dragging (like the chart).
    if (rounded != _value) {
      HapticFeedback.selectionClick();
    }
    _apply(rounded);
  }

  Widget _stepper(Color accent) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleIconButton(
          icon: PhosphorIconsRegular.minus,
          accent: accent,
          onTap: () => _apply(_value - widget.step),
        ),
        SizedBox(
          width: 96,
          child: Text(
            '$_value',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ),
        CircleIconButton(
          icon: PhosphorIconsRegular.plus,
          accent: accent,
          onTap: () => _apply(_value + widget.step),
        ),
      ],
    );
  }
}
