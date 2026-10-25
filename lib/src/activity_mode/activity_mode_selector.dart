import 'dart:async';

import 'package:flutter/material.dart';
import 'package:insulink/src/activity_mode/activity_mode.dart';
import 'package:insulink/src/activity_mode/activity_mode_store.dart';
import 'package:insulink/src/base/segmented_toggle.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The activity mode chosen by hand, in the profile's activity section.
///
/// Kept off the overview and the pump page on purpose: a mode that changes how
/// insulin is dosed is a setting to reach for, not a control to brush past.
/// Auto follows the training detection and running workouts; the other three
/// pin a mode for [ActivityModeStore.manualFor]. Recovery is not offered: it
/// follows an endurance bout by itself, and Normal ends it early. Under the toggle one line says
/// which mode is in force and why, because under Auto the toggle cannot.
///
/// Re-reads storage every [_refreshEvery]: the detection that moves the mode
/// runs in the service isolate, where a widget has nothing to observe.
class ActivityModeSelector extends StatefulWidget {
  const ActivityModeSelector({super.key});

  @override
  State<ActivityModeSelector> createState() => _ActivityModeSelectorState();
}

class _ActivityModeSelectorState extends State<ActivityModeSelector> {
  static const _refreshEvery = Duration(seconds: 30);
  static const _store = ActivityModeStore();

  ActivityModeReading _reading = ActivityModeReading.normal;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _refresh = Timer.periodic(_refreshEvery, (_) => _load());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final reading = await _store.current(DateTime.now());
    if (mounted) {
      setState(() => _reading = reading);
    }
  }

  Future<void> _choose(ActivityMode? mode) async {
    await _store.choose(mode, DateTime.now());
    await _load();
  }

  /// Null is Auto: anything but a manual choice leaves Auto lit.
  ActivityMode? get _selected =>
      _reading.source == ActivityModeSource.manual ? _reading.mode : null;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Text(Locales.string(context, 'activity_mode._'), style: InkText.label),
        SegmentedToggle<ActivityMode?>(
          semanticsLabel: Locales.string(context, 'activity_mode._'),
          selected: _selected,
          onChanged: _choose,
          options: [
            (value: null, label: Locales.string(context, 'activity_mode.auto')),
            for (final mode in ActivityMode.values)
              if (mode != ActivityMode.recovery)
                (value: mode, label: _modeName(context, mode)),
          ],
        ),
        Text(
          _caption(context),
          style: InkText.caption.copyWith(color: context.ink.muted),
        ),
      ],
    );
  }

  String _modeName(BuildContext context, ActivityMode mode) =>
      Locales.string(context, 'activity_mode.${mode.name}');

  /// "Endurance: training detected", or for a manual choice when it lapses.
  String _caption(BuildContext context) {
    final until = _reading.until;
    final reason = Locales.string(
      context,
      'activity_mode.source.${_reading.source.name}',
      params: [if (until != null) _clock(context, until)],
    );
    return '${_modeName(context, _reading.mode)}: $reason';
  }

  String _clock(BuildContext context, DateTime at) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(at),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }
}
