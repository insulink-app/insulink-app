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

  void _onFocusChange() {
    if (!_focus.hasFocus && _editing) {
      _commit();
    }
  }

  void _start() {
    _controller.text = widget.decimal
        ? widget.initial.toStringAsFixed(1)
        : widget.initial.round().toString();
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    setState(() => _editing = true);
  }

  void _commit() {
    final parsed = double.tryParse(_controller.text.replaceAll(',', '.'));
    if (parsed != null) {
      HapticFeedback.selectionClick();
      widget.onSubmit(parsed.clamp(widget.min, widget.max).toDouble());
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
      child: _editing ? _field(context) : _text(),
    );
  }

  Widget _text() {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _start,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          widget.valueText,
          textAlign: TextAlign.center,
          style: widget.style,
        ),
      ),
    );
  }

  Widget _field(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return TextField(
      controller: _controller,
      focusNode: _focus,
      autofocus: true,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(widget.decimal ? r'[0-9.,]' : r'[0-9]'),
        ),
      ],
      style: widget.style,
      onSubmitted: (_) => _commit(),
      onTapOutside: (_) => _focus.unfocus(),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 6),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: accent.withValues(alpha: 0.4)),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: accent),
        ),
      ),
    );
  }
}
