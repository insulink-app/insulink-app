import 'dart:async';

import 'package:flutter/material.dart';
import 'package:insulink/src/activity_mode/activity_mode_selector.dart';
import 'package:insulink/src/activity_mode/activity_mode_settings.dart';

/// The hand choice on the overview, shown only when the user asked for it in
/// the profile and the activity mode is on at all. Renders nothing otherwise,
/// so the overview is unchanged for everyone else.
///
/// The answer is held, not read inside a FutureBuilder: the overview rebuilds
/// with every reading, and a fresh read each time would blank the selector and
/// restart its own refresh. It is re-read when the overview rebuilds (at most
/// every [_recheckAfter]) and on a timer, so a switch flipped in the profile
/// shows up on the way back without a provider for two booleans.
class ActivityModeOverviewSelector extends StatefulWidget {
  const ActivityModeOverviewSelector({super.key});

  @override
  State<ActivityModeOverviewSelector> createState() =>
      _ActivityModeOverviewSelectorState();
}

class _ActivityModeOverviewSelectorState
    extends State<ActivityModeOverviewSelector> {
  static const _recheckAfter = Duration(seconds: 2);
  static const _recheckEvery = Duration(seconds: 30);

  bool _shown = false;
  DateTime? _readAt;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
    _timer = Timer.periodic(_recheckEvery, (_) => _read());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    _readAt = DateTime.now();
    final shown =
        await ActivityModeSettings.enabled.load() &&
        await ActivityModeSettings.onOverview.load();
    if (mounted && shown != _shown) {
      setState(() => _shown = shown);
    }
  }

  void _recheck() {
    final readAt = _readAt;
    if (readAt == null || DateTime.now().difference(readAt) > _recheckAfter) {
      unawaited(_read());
    }
  }

  @override
  Widget build(BuildContext context) {
    _recheck();
    if (!_shown) {
      return const SizedBox.shrink();
    }
    return const Padding(
      padding: EdgeInsets.fromLTRB(4, 4, 4, 14),
      child: ActivityModeSelector(),
    );
  }
}
