import 'package:flutter/material.dart';

import 'package:insulink/src/base/device_lifespan.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
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

  /// On the overview the header matches the other section titles (large + bold,
  /// full-strength) with a greyed value on the right; on a device page it keeps
  /// the original compact look (greyed title, full-strength value).
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
        const SizedBox(height: 6),
        _segmentBar(scheme, life),
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
              ? const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
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
        ? scheme.onSurface.withValues(alpha: 0.6)
        : scheme.onSurface;
    return Text(
      _remainingText(context, life),
      style: TextStyle(
        fontSize: 12,
        fontWeight: overview ? FontWeight.normal : FontWeight.w600,
        color: life.expired
            ? context.danger
            : life.inGrace
            ? context.warning
            : normalColor,
      ),
    );
  }

  String _remainingText(BuildContext context, DeviceLifespan life) {
    if (life.expired) {
      return Locales.string(context, 'sensor.value.expired');
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
