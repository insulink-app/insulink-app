import 'package:flutter/material.dart';

import 'package:insulink/src/base/device_lifespan.dart';
import 'package:insulink/src/base/segment_bar.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_colors.dart';
import 'package:insulink/src/theme/insulink_text_styles.dart';
import 'package:insulink/src/theme/status_colors.dart';

/// How much life a worn device has left, as one rectangle per remaining unit:
/// one per day normally, switching to one per HOUR over the final 24 h so the
/// last day stays meaningful. Remaining units are filled with the accent colour,
/// elapsed ones greyed out.
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
        SizedBox(height: overview ? 8 : 6),
        overview ? _overviewSegments(context, life) : _segmentBar(scheme, life),
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
              ? InsulinkTextStyles.row
              : TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
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
    final normalColor = overview
        ? context.insulinkColors.muted
        : scheme.onSurface;
    return Text(
      _remainingText(context, life),
      style: TextStyle(
        fontSize: overview ? 14 : 12,
        fontWeight: overview ? FontWeight.normal : FontWeight.w600,
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
  /// most. It keeps its own wording, because "past its rated life" is worth
  /// saying whichever unit the number is in.
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

  /// The overview's segments: 6 px, accent for what is left, line for the rest.
  /// The final day keeps the day segments and fills the last one by the share
  /// of that day still left, instead of switching to 24 hour segments.
  Widget _overviewSegments(BuildContext context, DeviceLifespan life) {
    final colors = context.insulinkColors;
    if (life.hoursMode) {
      return _lastDaySegments(colors, life);
    }
    return SegmentBar.count(
      total: life.totalDays,
      filled: life.filledSegments,
      fill: colors.accent,
      empty: colors.line,
    );
  }

  Widget _lastDaySegments(InsulinkColors colors, DeviceLifespan life) {
    return SizedBox(
      height: 6,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var day = 0; day < life.totalDays; day++) ...[
            if (day > 0) const SizedBox(width: 4),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: ColoredBox(
                  color: colors.line,
                  child: FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: day == 0 ? life.lastDayFraction : 0,
                    child: ColoredBox(color: colors.accent),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _segmentBar(ColorScheme scheme, DeviceLifespan life) {
    final gap = life.hoursMode ? 2.0 : 4.0;
    return Row(
      children: [
        for (var index = 0; index < life.totalSegments; index++) ...[
          if (index > 0) SizedBox(width: gap),
          Expanded(
            child: _segment(scheme, filled: index < life.filledSegments),
          ),
        ],
      ],
    );
  }

  Widget _segment(ColorScheme scheme, {required bool filled}) {
    return Container(
      height: 9,
      decoration: BoxDecoration(
        color: filled
            ? scheme.primary
            : scheme.onSurface.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
