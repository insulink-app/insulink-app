import 'dart:async';

import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:intl/intl.dart';

/// Shown in place of the searching loader while a fresh sensor warms up: a ring
/// filling over the warm-up, the minutes left in it, and the time the first
/// value is due. Repaints by itself every 30 s, since a warming sensor delivers
/// nothing that would.
class OverviewWarmupView extends StatefulWidget {
  const OverviewWarmupView({
    super.key,
    required this.start,
    required this.endsAt,
  });

  final DateTime start;
  final DateTime endsAt;

  @override
  State<OverviewWarmupView> createState() => _OverviewWarmupViewState();
}

class _OverviewWarmupViewState extends State<OverviewWarmupView> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  double get _progress {
    final total = widget.endsAt.difference(widget.start).inSeconds;
    final done = DateTime.now().difference(widget.start).inSeconds;
    return total <= 0 ? 1 : (done / total).clamp(0.0, 1.0);
  }

  int get _minutesLeft =>
      (widget.endsAt.difference(DateTime.now()).inSeconds / 60).ceil().clamp(
        0,
        999,
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ring(colors),
          const SizedBox(height: 24),
          LocaleText(
            'overview.warmup.title',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          LocaleText(
            'overview.warmup.hint',
            params: [DateFormat('HH:mm').format(widget.endsAt)],
            style: TextStyle(fontSize: 13, color: colors.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// The warm-up as a filling ring with the minutes left in its middle.
  Widget _ring(InsulinkColors colors) {
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: _progress,
            strokeWidth: 8,
            color: colors.accent,
            backgroundColor: colors.line,
          ),
          Center(
            child: LocaleText(
              'overview.warmup.minutes',
              params: ['$_minutesLeft'],
              style: InkText.bigValue.copyWith(fontSize: 26),
            ),
          ),
        ],
      ),
    );
  }
}
