import 'package:flutter/material.dart';

import 'package:insulink/src/base/device_lifespan.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/theme/status_colors.dart';

/// How much life a worn device has left, as one segment per day of its
/// lifetime: days still ahead in the accent colour, the day under way filled
/// by the share of it left, elapsed days greyed out.
///
/// Shared by the CGM sensor and the Omnipod pod, which differ only in their
/// lifetime and their title — a pod's 80 h reads as three rated days plus an
/// eight-hour grace window, which is exactly the model [DeviceLifespan] already
/// describes.
class DeviceLifespanBar extends StatelessWidget {
  const DeviceLifespanBar({
    super.key,
    required this.start,
    required this.sessionLengthSec,
    this.overview = false,
    this.overviewTitleKey = 'sensor.label',
    this.pageTitleKey = 'sensor.life.title',
  });

  final DateTime start;
  final int sessionLengthSec;

  /// On the overview it takes the redesign's panel look (bold row title, muted
  /// value, thin accent segments); on a device page it keeps the original
  /// compact look (greyed title, full-strength value).
  final bool overview;

  /// Names the device in the overview header. The remaining-time wording itself
  /// is device-neutral ("# days left"), so only the title differs.
  final String overviewTitleKey;

  /// Names the row on a device page.
  final String pageTitleKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final life = DeviceLifespan(
      start: start,
      sessionLengthSec: sessionLengthSec,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, scheme, life),
        const SizedBox(height: 8),
        _segments(context, life),
      ],
    );
  }

  Widget _header(
    BuildContext context,
    ColorScheme scheme,
    DeviceLifespan life,
  ) {
    return Row(
      children: [
        LocaleText(
          overview ? overviewTitleKey : pageTitleKey,
          style: overview
              ? InkText.row
              : InkText.label.copyWith(color: context.ink.muted),
        ),
        const Spacer(),
        _remainingLabel(context, scheme, life),
      ],
    );
  }

  Widget _remainingLabel(
    BuildContext context,
    ColorScheme scheme,
    DeviceLifespan life,
  ) {
    final normalColor = overview ? context.ink.muted : context.ink.text;
    final style = overview ? InkText.label : InkText.row;
    return Text(
      _remainingText(context, life),
      style: style.copyWith(
        color: life.expired
            ? context.danger
            : life.inGrace
            ? context.warning
            : normalColor,
      ),
    );
  }

  /// The remaining time, in the coarsest unit that still says something.
  ///
  /// Minutes come BEFORE the grace check on purpose. A device usually spends its
  /// last hour inside the grace window, and that branch counts in hours, so the
  /// grace wording would have swallowed the minutes exactly where they matter
  /// most. Grace is told by the warning colour alone; a "grace period" word
  /// did not fit the pump's box.
  String _remainingText(BuildContext context, DeviceLifespan life) {
    if (life.expired) {
      return Locales.string(context, 'sensor.value.expired');
    }
    if (life.minutesMode) {
      final key = life.inGrace
          ? 'sensor.life.grace_minutes'
          : 'sensor.life.remaining_minutes';
      return Locales.string(context, key, params: ['${life.minutesLeft}']);
    }
    if (life.inGrace) {
      return Locales.string(
        context,
        'sensor.life.grace',
        params: ['${life.graceHoursLeft}'],
      );
    }
    final key = life.hoursMode
        ? 'sensor.life.remaining_hours'
        : 'sensor.life.remaining';
    return Locales.string(context, key, params: ['${life.filledSegments}']);
  }

  /// 6 px day segments, accent for what is left, line for the rest, on the
  /// overview and the device pages alike. The day under way is filled by the
  /// share of it still left, so the bar shrinks through the day instead of
  /// jumping a whole segment at midnight of the session.
  Widget _segments(BuildContext context, DeviceLifespan life) {
    final colors = context.ink;
    return SizedBox(
      height: 6,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: [
          for (var day = 0; day < life.totalDays; day++)
            Expanded(child: _daySegment(colors, life.dayFraction(day))),
        ],
      ),
    );
  }

  Widget _daySegment(InsulinkColors colors, double fraction) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: ColoredBox(
        color: colors.line,
        child: FractionallySizedBox(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: fraction,
          child: ColoredBox(color: colors.accent),
        ),
      ),
    );
  }
}
