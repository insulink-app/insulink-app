import 'package:flutter/material.dart';
import 'package:insulink/src/connections/connections_body.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/theme/insulink_colors.dart';
import 'package:insulink/src/theme/insulink_text_styles.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Whether the automation is running, as the last row of the overview's
/// devices panel.
///
/// The mode changes what the pump does with every basal minute, so it does not
/// belong only on a device sub-page. Someone glancing at the overview should be
/// able to tell whether software is dosing them.
///
/// **Being OFF is stated as loudly as being on.** This used to render nothing at
/// all for an automation that was never engaged, on the grounds that it was the
/// resting state. It is not: a pod user who believes the loop is running when it
/// is not will read every flat line on the chart as the automation working. The
/// off state therefore carries an amber dot and amber text, and tapping the row
/// goes to the switch.
class PodLoopOverviewLine extends StatelessWidget {
  const PodLoopOverviewLine({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PodController>().store;
    final colors = context.insulinkColors;
    if (store.loopMode == PodLoopMode.engaged) {
      return _row(
        context,
        dot: colors.range,
        text: colors.text,
        title: Locales.string(context, 'pump.loop.overview.engaged'),
        value: _automatedRate(context, store),
      );
    }
    final key = store.loopStop == null
        ? 'pump.loop.overview.off'
        : 'pump.loop.overview.stopped';
    return _row(
      context,
      dot: colors.high,
      text: colors.high,
      title: Locales.string(context, key),
    );
  }

  /// **The rate is the point of this row.** "The automation is on" says nothing
  /// about what it is doing to you; the number it has the pod running does. Only
  /// the automation's OWN rate is shown: between its rates the pod is back on the
  /// user's schedule, and putting that number here would read as something the
  /// automation had decided. Null while none of its rates covers this moment.
  String? _automatedRate(BuildContext context, PodStore store) {
    final running = store.temporaryBasal;
    if (running == null ||
        !running.automated ||
        !running.covers(DateTime.now())) {
      return null;
    }
    return Locales.string(
      context,
      'pump.loop.overview.rate',
      params: [sportDecimal(running.unitsPerHour, 2)],
    );
  }

  /// One line, deliberately. What a stopped automation stopped FOR is a sentence
  /// long and lives on the pump page, one tap through the chevron.
  Widget _row(
    BuildContext context, {
    required Color dot,
    required Color text,
    required String title,
    String? value,
  }) {
    final colors = context.insulinkColors;
    return InkWell(
      onTap: () => openPumpPage(context),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            spacing: 10,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: InsulinkTextStyles.row.copyWith(
                    fontWeight: FontWeight.w600,
                    color: text,
                  ),
                ),
              ),
              if (value != null) Text(value, style: InsulinkTextStyles.row),
              Icon(PhosphorIconsBold.caretRight, size: 18, color: colors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
