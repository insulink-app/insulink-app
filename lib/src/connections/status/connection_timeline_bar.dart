import 'package:flutter/material.dart';
import 'package:insulink/src/connections/status/connection_timeline.dart';
import 'package:insulink/src/connections/status/connection_timeline_strip.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sensor/info/sensor_format.dart';
import 'package:insulink/src/theme/status_colors.dart';

/// One device's row: what it is, when it was last heard from, and a strip of the
/// window with every stretch of silence left pale.
///
/// The strip is drawn rather than charted. A line chart of a boolean says
/// nothing a filled bar does not, and this is the one question the page exists
/// for: where are the holes. Pointing at a slice names the half hour it stands
/// for, on the line under the strip.
class ConnectionTimelineBar extends StatefulWidget {
  const ConnectionTimelineBar({
    super.key,
    required this.device,
    required this.timeline,
  });

  final DeviceConnection device;

  /// The window the strip covers, so each slice can name its own half hour.
  final ConnectionTimeline timeline;

  @override
  State<ConnectionTimelineBar> createState() => _ConnectionTimelineBarState();
}

class _ConnectionTimelineBarState extends State<ConnectionTimelineBar> {
  /// The slice being described, or null for none. Kept after a tap rather than
  /// cleared on release: reading it is the whole point, and it survives exactly
  /// until the next slice is picked.
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, scheme),
          const SizedBox(height: 8),
          if (widget.device.isKnown) _strip() else _emptyStrip(context, scheme),
          const SizedBox(height: 4),
          _sliceLine(scheme),
        ],
      ),
    );
  }

  Widget _strip() {
    return ConnectionTimelineStrip(
      covered: widget.device.covered,
      selected: _selected,
      onSelect: (index) => setState(() => _selected = index),
    );
  }

  /// The half hour the pointer is on. Always occupies its line, empty or not, so
  /// the rows do not jump as the finger moves along the strip.
  Widget _sliceLine(ColorScheme scheme) {
    final index = _selected;
    return SizedBox(
      height: 15,
      child: Text(
        index == null ? '' : _sliceText(index),
        style: TextStyle(
          fontSize: 11,
          color: scheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  String _sliceText(int index) {
    final from = widget.timeline.bucketStart(index);
    return Locales.string(
      context,
      widget.device.covered[index]
          ? 'connections.status.slice_covered'
          : 'connections.status.slice_gap',
      params: [_clock(from), _clock(from.add(ConnectionTimeline.bucket))],
    );
  }

  String _clock(DateTime time) =>
      '${twoDigits(time.hour)}:${twoDigits(time.minute)}';

  Widget _header(BuildContext context, ColorScheme scheme) {
    return Row(
      children: [
        Icon(widget.device.icon, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        LocaleText(
          widget.device.labelKey,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        Text(
          _contactText(context),
          style: TextStyle(fontSize: 12, color: _contactColor(context, scheme)),
        ),
      ],
    );
  }

  /// How long ago the device was last reached, or that it never was.
  String _contactText(BuildContext context) {
    final last = widget.device.lastContact;
    if (last == null) {
      return Locales.string(context, 'connections.status.never');
    }
    final ago = widget.timeline.now.difference(last);
    return Locales.string(
      context,
      'connections.status.last_contact',
      params: [formatSensorDuration(ago.inSeconds.clamp(0, 1 << 30))],
    );
  }

  /// Amber once the newest bucket is empty: the device is silent RIGHT NOW,
  /// which is the only part of the strip the user can still act on.
  Color _contactColor(BuildContext context, ColorScheme scheme) {
    final covered = widget.device.covered;
    final silentNow = covered.isNotEmpty && !covered.last;
    if (widget.device.lastContact == null || silentNow) {
      return context.warning;
    }
    return scheme.onSurface.withValues(alpha: 0.6);
  }

  /// A device that was never set up gets a flat grey bar and says so, rather
  /// than a full-width outage it never had.
  Widget _emptyStrip(BuildContext context, ColorScheme scheme) {
    return Container(
      height: 14,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(2),
      ),
      child: LocaleText(
        'connections.status.not_set_up',
        style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
