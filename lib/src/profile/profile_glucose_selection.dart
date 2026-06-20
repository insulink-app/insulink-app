import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/profile_glucose_state.dart';
import 'package:provider/provider.dart';

/// Accent per range, conveying severity at a glance: target = healthy green,
/// low alarms = hypo red, high alarms = hyper amber.
const _targetColor = Color(0xFF2E9E5B);
const _lowColor = Color(0xFFE0533D);
const _highColor = Color(0xFFE8A13A);

/// Unit picker + target-range and alarm-threshold editors. All values are kept
/// in mg/dL internally; labels are rendered in the chosen unit.
///
/// The ranges are NOT inline sliders anymore: a slider embedded in the scrolling
/// settings list grabs vertical drags and shifts a thumb by accident. Each range
/// is a tappable card that opens a focused bottom-sheet editor (slider + steppers)
/// where dragging is safe because nothing scrolls behind it.
class ProfileGlucoseSelection extends StatelessWidget {
  const ProfileGlucoseSelection({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ProfileGlucoseState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LocaleText(
          'profile.unit',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        _SegmentedUnit(state: s),
        const SizedBox(height: 24),
        _RangeCard(
          state: s,
          accent: _targetColor,
          labelKey: 'profile.glucose.target',
          lowLabelKey: 'profile.glucose.target_low',
          highLabelKey: 'profile.glucose.target_high',
          low: s.targetLow,
          high: s.targetHigh,
          onChanged: s.setTargetRange,
        ),
        const SizedBox(height: 12),
        _RangeCard(
          state: s,
          accent: _lowColor,
          labelKey: 'profile.glucose.alarms_low',
          lowLabelKey: 'profile.glucose.urgent_low',
          highLabelKey: 'profile.glucose.low',
          low: s.urgentLow,
          high: s.low,
          onChanged: s.setLowAlarms,
        ),
        const SizedBox(height: 12),
        _RangeCard(
          state: s,
          accent: _highColor,
          labelKey: 'profile.glucose.alarms_high',
          lowLabelKey: 'profile.glucose.high',
          highLabelKey: 'profile.glucose.urgent_high',
          low: s.high,
          high: s.urgentHigh,
          onChanged: s.setHighAlarms,
        ),
      ],
    );
  }
}

/// iOS-style segmented control for the unit.
class _SegmentedUnit extends StatelessWidget {
  const _SegmentedUnit({required this.state});

  final ProfileGlucoseState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Expanded(child: _segment(theme, GlucoseUnit.mgdl, 'profile.unit.mgdl')),
          Expanded(child: _segment(theme, GlucoseUnit.mmol, 'profile.unit.mmol')),
        ],
      ),
    );
  }

  Widget _segment(ThemeData theme, GlucoseUnit unit, String labelKey) {
    final selected = state.unit == unit;
    return GestureDetector(
      onTap: () => state.setUnit(unit),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: LocaleText(
          labelKey,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// A tappable summary of one low/high range — label, current values and a band
/// visualization. Opens [_RangeEditorSheet] on tap.
class _RangeCard extends StatelessWidget {
  const _RangeCard({
    required this.state,
    required this.accent,
    required this.labelKey,
    required this.lowLabelKey,
    required this.highLabelKey,
    required this.low,
    required this.high,
    required this.onChanged,
  });

  final ProfileGlucoseState state;
  final Color accent;
  final String labelKey, lowLabelKey, highLabelKey;
  final int low, high;
  final void Function(int low, int high) onChanged;

  void _openEditor(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RangeEditorSheet(
        state: state,
        accent: accent,
        titleKey: labelKey,
        lowLabelKey: lowLabelKey,
        highLabelKey: highLabelKey,
        low: low,
        high: high,
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openEditor(context),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LocaleText(
                      labelKey,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${state.format(low)} – ${state.formatWithUnit(high)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _RangeBar(low: low, high: high, color: accent, height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// A horizontal track (min..max) with the selected [low]..[high] band filled in.
class _RangeBar extends StatelessWidget {
  const _RangeBar({
    required this.low,
    required this.high,
    required this.color,
    this.height = 8,
  });

  final int low, high;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const min = ProfileGlucoseState.minMgdl;
    const max = ProfileGlucoseState.maxMgdl;
    double frac(int v) => ((v - min) / (max - min)).clamp(0.0, 1.0);
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final left = frac(low) * w;
          final right = frac(high) * w;
          return Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
              ),
              Positioned(
                left: left,
                top: 0,
                bottom: 0,
                width: (right - left).clamp(4.0, w),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Focused editor for one range: a band preview, a [RangeSlider] for quick
/// adjustment, and per-thumb steppers for precise control. Lives in a modal
/// bottom sheet so dragging never competes with the settings list scroll.
class _RangeEditorSheet extends StatefulWidget {
  const _RangeEditorSheet({
    required this.state,
    required this.accent,
    required this.titleKey,
    required this.lowLabelKey,
    required this.highLabelKey,
    required this.low,
    required this.high,
    required this.onChanged,
  });

  final ProfileGlucoseState state;
  final Color accent;
  final String titleKey, lowLabelKey, highLabelKey;
  final int low, high;
  final void Function(int low, int high) onChanged;

  @override
  State<_RangeEditorSheet> createState() => _RangeEditorSheetState();
}

class _RangeEditorSheetState extends State<_RangeEditorSheet> {
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
      _apply(
        _low,
        (_high + delta).clamp(_low, ProfileGlucoseState.maxMgdl),
      );
    } else {
      _apply(
        (_low + delta).clamp(ProfileGlucoseState.minMgdl, _high),
        _high,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.state;
    const min = ProfileGlucoseState.minMgdl;
    const max = ProfileGlucoseState.maxMgdl;
    const divisions = (max - min) ~/ ProfileGlucoseState.step;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                LocaleText(
                  widget.titleKey,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${s.format(_low)} – ${s.formatWithUnit(_high)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: widget.accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _RangeBar(low: _low, high: _high, color: widget.accent, height: 10),
            const SizedBox(height: 6),
            RangeSlider(
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: divisions,
              values: RangeValues(
                _low.toDouble().clamp(min.toDouble(), max.toDouble()),
                _high.toDouble().clamp(min.toDouble(), max.toDouble()),
              ),
              activeColor: widget.accent,
              inactiveColor: widget.accent.withValues(alpha: 0.18),
              onChanged: (v) => _apply(v.start.round(), v.end.round()),
            ),
            const SizedBox(height: 12),
            _StepperRow(
              labelKey: widget.lowLabelKey,
              valueText: s.formatWithUnit(_low),
              accent: widget.accent,
              onMinus: () => _bump(false, -ProfileGlucoseState.step),
              onPlus: () => _bump(false, ProfileGlucoseState.step),
            ),
            const SizedBox(height: 14),
            _StepperRow(
              labelKey: widget.highLabelKey,
              valueText: s.formatWithUnit(_high),
              accent: widget.accent,
              onMinus: () => _bump(true, -ProfileGlucoseState.step),
              onPlus: () => _bump(true, ProfileGlucoseState.step),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: widget.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: LocaleText(
                  'alert.done',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One labelled value with – / + buttons that step by the configured mg/dL step.
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.labelKey,
    required this.valueText,
    required this.accent,
    required this.onMinus,
    required this.onPlus,
  });

  final String labelKey;
  final String valueText;
  final Color accent;
  final VoidCallback onMinus, onPlus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: LocaleText(
            labelKey,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        _circleButton(Icons.remove, onMinus),
        SizedBox(
          width: 96,
          child: Text(
            valueText,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        _circleButton(Icons.add, onPlus),
      ],
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: accent.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: accent),
        ),
      ),
    );
  }
}
