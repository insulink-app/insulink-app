import 'dart:async';

import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';

/// Live "last / next update" line. The G7 reports a new glucose value every
/// ~5 minutes, so this shows when the last one arrived and counts down to the
/// next expected one, ticking once a second on its own (without rebuilding the
/// chart). [lastUpdate] is the wall-clock time of the latest reading.
class OverviewUpdateStatus extends StatefulWidget {
  const OverviewUpdateStatus({super.key, required this.lastUpdate});

  final DateTime? lastUpdate;

  @override
  State<OverviewUpdateStatus> createState() => _OverviewUpdateStatusState();
}

class _OverviewUpdateStatusState extends State<OverviewUpdateStatus> {
  /// G7 EGV cadence — a new value roughly every 5 minutes.
  static const _intervalSec = 300;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String _hms(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// "3 min 21 s" / "45 s" for a non-negative duration.
  static String _span(Duration d) {
    final s = d.inSeconds;
    if (s < 60) return '$s s';
    return '${s ~/ 60} min ${s % 60} s';
  }

  @override
  Widget build(BuildContext context) {
    final last = widget.lastUpdate;
    final grey = TextStyle(fontSize: 12, color: Colors.grey[400]);
    if (last == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(Locales.string(context, 'update.none'), style: grey),
      );
    }

    final now = DateTime.now();
    final ago = now.difference(last);
    final next = last.add(const Duration(seconds: _intervalSec));
    final rem = next.difference(now);

    final String nextLabel;
    final Color nextColor;
    if (rem.isNegative) {
      // Past the expected slot — the reading is late (skipped/poor signal).
      nextLabel = Locales.string(
        context,
        'update.next_overdue',
        params: [_span(-rem)],
      );
      nextColor = Colors.orangeAccent;
    } else {
      nextLabel = Locales.string(
        context,
        'update.next_in',
        params: [_span(rem)],
      );
      nextColor = Colors.grey[300]!;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Locales.string(
              context,
              'update.last',
              params: [_hms(last), _span(ago)],
            ),
            style: grey,
          ),
          Text(nextLabel, style: TextStyle(fontSize: 12, color: nextColor)),
        ],
      ),
    );
  }
}
