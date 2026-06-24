import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/base/editor_sheet.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/glucose_range_bar.dart';
import 'package:insulink/src/profile/glucose_stepper_row.dart';
import 'package:insulink/src/profile/profile_glucose_state.dart';

/// Focused editor for one range: a band preview, a [RangeSlider] for quick
/// adjustment, and per-thumb steppers for precise control. Lives in a modal
/// bottom sheet so dragging never competes with the settings list scroll.
class GlucoseRangeEditorSheet extends StatefulWidget {
  const GlucoseRangeEditorSheet({
    super.key,
    required this.state,
    required this.accent,
    required this.titleKey,
    required this.lowLabelKey,
    required this.highLabelKey,
    required this.low,
    required this.high,
    required this.onChanged,
    this.onTest,
  });

  final ProfileGlucoseState state;
  final Color accent;
  final String titleKey, lowLabelKey, highLabelKey;
  final int low, high;
  final void Function(int low, int high) onChanged;

  /// When set, an "Alarm testen" button is shown that previews this alarm's
  /// notification + tone. Null for the target range (which isn't an alarm).
  final VoidCallback? onTest;

  @override
  State<GlucoseRangeEditorSheet> createState() =>
      _GlucoseRangeEditorSheetState();
}

class _GlucoseRangeEditorSheetState extends State<GlucoseRangeEditorSheet> {
  static const _min = ProfileGlucoseState.minMgdl;
  static const _max = ProfileGlucoseState.maxMgdl;
  static const _step = ProfileGlucoseState.step;

  late int _low = widget.low;
  late int _high = widget.high;

  void _apply(int low, int high) {
    setState(() {
      _low = low;
      _high = high;
    });
    widget.onChanged(low, high);
  }

  void _bump(bool upper, int delta) {
    if (upper) {
      _apply(_low, (_high + delta).clamp(_low, _max));
    } else {
      _apply((_low + delta).clamp(_min, _high), _high);
    }
  }

  @override
  Widget build(BuildContext context) {
    return EditorSheet(
      titleKey: widget.titleKey,
      valueText:
          '${widget.state.format(_low)} – ${widget.state.formatWithUnit(_high)}',
      accent: widget.accent,
      children: [
        GlucoseRangeBar(
          low: _low,
          high: _high,
          color: widget.accent,
          height: 10,
        ),
        const SizedBox(height: 6),
        _slider(),
        const SizedBox(height: 12),
        _steppers(),
        if (widget.onTest != null) ...[
          const SizedBox(height: 32),
          _testButton(),
        ],
      ],
    );
  }

  Widget _testButton() {
    return OutlinedButton.icon(
      onPressed: widget.onTest,
      icon: const Icon(Icons.notifications_active_outlined, size: 18),
      label: LocaleText('profile.glucose.test_alarm'),
      style: OutlinedButton.styleFrom(
        foregroundColor: widget.accent,
        side: BorderSide(color: widget.accent),
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _slider() {
    const divisions = (_max - _min) ~/ _step;
    return RangeSlider(
      min: _min.toDouble(),
      max: _max.toDouble(),
      divisions: divisions,
      values: RangeValues(
        _low.toDouble().clamp(_min.toDouble(), _max.toDouble()),
        _high.toDouble().clamp(_min.toDouble(), _max.toDouble()),
      ),
      activeColor: widget.accent,
      inactiveColor: widget.accent.withValues(alpha: 0.18),
      onChanged: _onSlide,
    );
  }

  void _onSlide(RangeValues values) {
    final low = values.start.round();
    final high = values.end.round();
    // Haptic tick per stepped change while dragging (like the chart).
    if (low != _low || high != _high) {
      HapticFeedback.selectionClick();
    }
    _apply(low, high);
  }

  Widget _steppers() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlucoseStepperRow(
          labelKey: widget.lowLabelKey,
          valueText: widget.state.formatWithUnit(_low),
          accent: widget.accent,
          onMinus: () => _bump(false, -_step),
          onPlus: () => _bump(false, _step),
        ),
        const SizedBox(height: 14),
        GlucoseStepperRow(
          labelKey: widget.highLabelKey,
          valueText: widget.state.formatWithUnit(_high),
          accent: widget.accent,
          onMinus: () => _bump(true, -_step),
          onPlus: () => _bump(true, _step),
        ),
      ],
    );
  }
}
