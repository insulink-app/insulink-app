import 'package:flutter/material.dart';
import 'package:insulink/src/localization/enum_locale_key.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Whether the automation is running, on the overview.
///
/// The mode changes what the pump does with every basal minute, so it does not
/// belong only on a device sub-page. Someone glancing at the overview should be
/// able to tell whether software is dosing them.
///
/// It renders nothing in the ordinary case of an automation that was never
/// turned on, with one exception: an automation that stopped ITSELF still shows,
/// because that is precisely the state a user is most likely to be wrong about.
/// The notification says it once; this keeps saying it until they act.
class PodLoopOverviewLine extends StatelessWidget {
  const PodLoopOverviewLine({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PodController>().store;
    final mode = store.loopMode;
    final stop = store.loopStop;
    if (mode == PodLoopMode.off) {
      return stop == null ? const SizedBox.shrink() : _stopped(context, stop);
    }
    return _running(context, store, mode);
  }

  Widget _running(BuildContext context, PodStore store, PodLoopMode mode) {
    final scheme = Theme.of(context).colorScheme;
    return _line(
      context,
      icon: PhosphorIconsBold.repeat,
      color: scheme.onSurfaceVariant,
      text: _label(context, store, mode),
    );
  }

  /// The mode, plus the rate it is actually running when there is one. A mode on
  /// its own does not say whether anything is happening.
  String _label(BuildContext context, PodStore store, PodLoopMode mode) {
    final name = Locales.string(context, 'pump.loop.mode.${mode.name}');
    final prefix = Locales.string(context, 'pump.loop.title');
    final running = store.temporaryBasal;
    if (mode != PodLoopMode.engaged ||
        running == null ||
        !running.automated ||
        !running.covers(DateTime.now())) {
      return '$prefix: $name';
    }
    return '$prefix: $name, ${running.unitsPerHour.toStringAsFixed(2)} U/h';
  }

  Widget _stopped(BuildContext context, PodLoopStop stop) {
    return _line(
      context,
      icon: PhosphorIconsBold.warning,
      color: context.warning,
      text: Locales.string(context, 'pump.loop.stopped.${stop.localeKey}'),
    );
  }

  Widget _line(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
