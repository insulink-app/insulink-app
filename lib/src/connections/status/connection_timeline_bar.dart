import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
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
    this.detailKey,
  });

  final DeviceConnection device;

  /// The paired device under the name ("Dexcom G7"), as the connections page
  /// says it; null for none.
  final String? detailKey;

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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, scheme),
          const SizedBox(height: 14),
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
      height: 18,
      child: Text(
        index == null ? '' : _sliceText(index),
        style: InkText.caption.copyWith(color: context.ink.muted),
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

  /// The device glyph in an accent disc, its name over the paired device,
  /// and how long ago it was last heard from on the right.
  Widget _header(BuildContext context, ColorScheme scheme) {
    final colors = context.ink;
    final detail = widget.detailKey;
    return Row(
      spacing: 14,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.accent.withValues(alpha: 0.12),
          ),
          child: Icon(widget.device.icon, size: 20, color: colors.accent),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              LocaleText(
                widget.device.labelKey,
                style: InkText.rowTitle.copyWith(fontSize: 17),
              ),
              if (detail != null)
                LocaleText(
                  detail,
                  style: InkText.label.copyWith(color: colors.muted),
                ),
            ],
          ),
        ),
        Text(
          _contactText(context),
          style: InkText.label.copyWith(color: _contactColor(context, scheme)),
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
    return context.ink.muted;
  }

  /// A device that was never set up gets a flat grey bar and says so, rather
  /// than a full-width outage it never had.
  Widget _emptyStrip(BuildContext context, ColorScheme scheme) {
    return Container(
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.ink.line,
        borderRadius: BorderRadius.circular(3),
      ),
      child: LocaleText(
        'connections.status.not_set_up',
        style: InkText.caption.copyWith(color: context.ink.muted),
      ),
    );
  }
}
