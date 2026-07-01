import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Subtly inline-editable number: shows [valueText], becomes a text field in
/// place on tap (no dialog), and on confirm/leave passes the parsed value,
/// clamped to [min]..[max], to [onSubmit]. [decimal] allows decimals (e.g.
/// weight).
class SportEditableNumber extends StatefulWidget {
  const SportEditableNumber({
    super.key,
    required this.valueText,
    required this.initial,
    required this.min,
    required this.max,
    required this.onSubmit,
    this.decimal = false,
    this.width = 96,
    this.style = const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
  });

  final String valueText;
  final double initial;
  final double min;
  final double max;
  final bool decimal;
  final double width;
  final TextStyle style;
  final void Function(double value) onSubmit;

  @override
  State<SportEditableNumber> createState() => _SportEditableNumberState();
}

class _SportEditableNumberState extends State<SportEditableNumber> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  /// Commit on blur ONLY when something was typed. A transient blur while the
  /// keyboard is still animating open (common for the FIRST field tapped) would
  /// otherwise commit empty text and close the field before the user types —
  /// explicit closes go through [onSubmitted]/[onTapOutside] instead.
  void _onFocusChange() {
    if (!_focus.hasFocus && _editing && _controller.text.trim().isNotEmpty) {
      _commit();
    }
  }

  /// Start EMPTY with the current value shown as a hint — so the first keystroke
  /// can never append to a prefill (which on Android happens when autofocus
  /// collapses the cursor to the end). Empty on commit ⇒ value unchanged.
  void _start() {
    _controller.clear();
    setState(() => _editing = true);
  }

  String get _hint => widget.decimal
      ? widget.initial.toStringAsFixed(1).replaceAll('.', ',')
      : widget.initial.round().toString();

  void _commit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      final parsed = double.tryParse(text.replaceAll(',', '.'));
      if (parsed != null) {
        HapticFeedback.selectionClick();
        widget.onSubmit(parsed.clamp(widget.min, widget.max).toDouble());
      }
    }
    if (mounted) {
      setState(() => _editing = false);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: _editing ? _field(context) : _text(context),
    );
  }

  /// Resting state: the value in a soft, tappable pill so it reads as editable.
  Widget _text(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: accent.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _start,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Text(
            widget.valueText,
            textAlign: TextAlign.center,
            style: widget.style,
          ),
        ),
      ),
    );
  }

  Widget _field(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: accent.withValues(alpha: 0.25)),
    );
    return TextField(
      controller: _controller,
      focusNode: _focus,
      autofocus: true,
      textAlign: TextAlign.center,
      cursorColor: accent,
      keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(widget.decimal ? r'[0-9.,]' : r'[0-9]'),
        ),
      ],
      style: widget.style.copyWith(color: accent),
      onSubmitted: (_) => _commit(),
      onTapOutside: (_) => _commit(),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: accent.withValues(alpha: 0.10),
        hintText: _hint,
        hintStyle: widget.style.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        enabledBorder: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
    );
  }
}
