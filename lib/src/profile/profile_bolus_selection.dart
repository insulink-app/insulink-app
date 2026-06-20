import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/profile_bolus_state.dart';
import 'package:provider/provider.dart';

/// The two bolus-calculator factors (correction + carb ratio).
///
/// Like the glucose ranges, these are NOT inline sliders: a slider in the
/// scrolling settings list grabs vertical drags and shifts the value by
/// accident. Each factor is a tappable card that opens a focused bottom-sheet
/// editor (slider + steppers) where dragging is safe.
class ProfileBolusSelection extends StatelessWidget {
  const ProfileBolusSelection({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ProfileBolusState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FactorCard(
          labelKey: 'profile.bolus.correction',
          valueKey: 'profile.bolus.correction.value',
          value: s.correctionFactor,
          min: ProfileBolusState.minCorrection,
          max: ProfileBolusState.maxCorrection,
          step: ProfileBolusState.correctionStep,
          onChanged: s.setCorrectionFactor,
        ),
        const SizedBox(height: 12),
        _FactorCard(
          labelKey: 'profile.bolus.carb',
          valueKey: 'profile.bolus.carb.value',
          value: s.carbFactor,
          min: ProfileBolusState.minCarb,
          max: ProfileBolusState.maxCarb,
          step: ProfileBolusState.carbStep,
          onChanged: s.setCarbFactor,
        ),
      ],
    );
  }
}

/// A tappable summary of one factor — label, current value and a fill
/// visualization. Opens [_FactorEditorSheet] on tap.
class _FactorCard extends StatelessWidget {
  const _FactorCard({
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

  void _openEditor(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FactorEditorSheet(
        labelKey: labelKey,
        valueKey: valueKey,
        value: value,
        min: min,
        max: max,
        step: step,
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final valueLabel = Locales.string(context, valueKey, params: ['$value']);
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
                    valueLabel,
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
              _FillBar(value: value, min: min, max: max, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// A horizontal track (min..max) filled from the start up to [value].
class _FillBar extends StatelessWidget {
  const _FillBar({
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    this.height = 8,
  });

  final int value, min, max;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final frac = ((value - min) / (max - min)).clamp(0.0, 1.0);
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, c) {
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
                left: 0,
                top: 0,
                bottom: 0,
                width: (frac * c.maxWidth).clamp(4.0, c.maxWidth),
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

/// Focused editor for one factor: a fill preview, a [Slider] for quick
/// adjustment, and a stepper for precise control. Lives in a modal bottom sheet
/// so dragging never competes with the settings list scroll.
class _FactorEditorSheet extends StatefulWidget {
  const _FactorEditorSheet({
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
  State<_FactorEditorSheet> createState() => _FactorEditorSheetState();
}

class _FactorEditorSheetState extends State<_FactorEditorSheet> {
  late int _value = widget.value;

  void _apply(int v) {
    v = v.clamp(widget.min, widget.max);
    setState(() => _value = v);
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final divisions = (widget.max - widget.min) ~/ widget.step;
    final valueLabel = Locales.string(
      context,
      widget.valueKey,
      params: ['$_value'],
    );
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
                  widget.labelKey,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  valueLabel,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _FillBar(
              value: _value,
              min: widget.min,
              max: widget.max,
              color: accent,
              height: 10,
            ),
            const SizedBox(height: 6),
            Slider(
              min: widget.min.toDouble(),
              max: widget.max.toDouble(),
              divisions: divisions,
              value: _value.toDouble().clamp(
                widget.min.toDouble(),
                widget.max.toDouble(),
              ),
              activeColor: accent,
              inactiveColor: accent.withValues(alpha: 0.18),
              onChanged: (v) => _apply(v.round()),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _circleButton(accent, Icons.remove, () => _apply(_value - widget.step)),
                SizedBox(
                  width: 96,
                  child: Text(
                    '$_value',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _circleButton(accent, Icons.add, () => _apply(_value + widget.step)),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
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

  Widget _circleButton(Color accent, IconData icon, VoidCallback onTap) {
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
