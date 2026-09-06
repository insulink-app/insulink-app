import 'package:flutter/material.dart';
import 'package:insulink/src/connections/connections_body.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/theme/brand_tints.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Whether the automation is running, on the overview.
///
/// The mode changes what the pump does with every basal minute, so it does not
/// belong only on a device sub-page. Someone glancing at the overview should be
/// able to tell whether software is dosing them.
///
/// **Being OFF is stated as loudly as being on.** This used to render nothing at
/// all for an automation that was never engaged, on the grounds that it was the
/// resting state. It is not: a pod user who believes the loop is running when it
/// is not will read every flat line on the chart as the automation working. The
/// off state is therefore an amber panel like every other "this is not what you
/// probably assume" strip in the app, and tapping it goes to the switch.
class PodLoopOverviewLine extends StatelessWidget {
  const PodLoopOverviewLine({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PodController>().store;
    final stop = store.loopStop;
    if (store.loopMode == PodLoopMode.engaged) {
      return _engaged(context, store);
    }
    return _panel(
      context,
      icon: PhosphorIconsFill.warning,
      color: context.warning,
      background: context.warning.withValues(alpha: 0.15),
      title: Locales.string(
        context,
        stop == null
            ? 'pump.loop.overview.off'
            : 'pump.loop.overview.stopped',
      ),
    );
  }

  /// Running: the same shape, in the brand tint rather than amber, so the two
  /// states read as one thing in two positions rather than as a warning that
  /// appears out of nowhere.
  ///
  /// **The rate is the point of this panel.** "The automation is on" says nothing
  /// about what it is doing to you; the number it has the pod running does. Only
  /// the automation's OWN rate is shown: between its rates the pod is back on the
  /// user's schedule, and putting that number here would read as something the
  /// automation had decided.
  Widget _engaged(BuildContext context, PodStore store) {
    final scheme = Theme.of(context).colorScheme;
    return _panel(
      context,
      icon: PhosphorIconsBold.repeat,
      color: scheme.onSurfaceVariant,
      background: scheme.tintPanel,
      title: Locales.string(context, 'pump.loop.overview.engaged'),
      value: _automatedRate(store),
    );
  }

  /// The rate the automation has the pod running, or null while none of its
  /// rates covers this moment.
  String? _automatedRate(PodStore store) {
    final running = store.temporaryBasal;
    if (running == null ||
        !running.automated ||
        !running.covers(DateTime.now())) {
      return null;
    }
    return '${running.unitsPerHour.toStringAsFixed(2)} U/h';
  }

  /// One line, deliberately. This sits on the overview between the pod's life bar
  /// and its reservoir, and a two-line panel there pushed everything below it off
  /// the first screen. What a stopped automation stopped FOR is a sentence long
  /// and lives on the pump page, one tap through the caret.
  Widget _panel(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required Color background,
    required String title,
    String? value,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openPumpPage(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: scheme.onSurface,
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(
                  PhosphorIconsBold.caretRight,
                  size: 14,
                  color: scheme.onSurface.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
