import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// A single summary tile: glyph + label + big value (optional unit), tappable.
/// Used in the Sport tab, the nutrition tab and on the overview.
class SportSummaryTile extends StatelessWidget {
  const SportSummaryTile({
    super.key,
    required this.icon,
    required this.labelKey,
    required this.value,
    this.unit,
    this.onTap,
    this.progress,
    this.pulse = false,
    this.unavailable = false,
  });

  final IconData icon;
  final String labelKey;
  final String value;
  final String? unit;
  final VoidCallback? onTap;

  /// When true the box is greyed out and non-interactive, and [value] holds a
  /// short "not available" note instead of a number — used for a Google Health
  /// metric the user enabled while Google Health is disconnected.
  final bool unavailable;

  /// When true the glyph beats like a heartbeat (used by the heart-rate tile
  /// while a live BLE pulse is streaming).
  final bool pulse;

  /// Optional daily-goal progress in 0..1. When set, the tile fills from the
  /// left in proportion to how close today is to the goal.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Opacity(
      opacity: unavailable ? 0.45 : 1.0,
      child: Material(
        color: colors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: unavailable ? null : onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 92),
            child: Stack(
              alignment: AlignmentDirectional.centerStart,
              children: [
                if (progress != null) _fill(colors),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    spacing: 14,
                    children: [
                      _glyph(colors),
                      Expanded(child: _text(context, colors)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The goal progress: a soft accent area from the left edge, closed by a
  /// 2 px accent line where it ends.
  Widget _fill(InsulinkColors colors) {
    return Positioned.fill(
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress!.clamp(0.0, 1.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.accentSoft,
            border: Border(right: BorderSide(color: colors.accent, width: 2)),
          ),
        ),
      ),
    );
  }

  /// The tile's glyph, deliberately bare — no badge behind it.
  ///
  /// This tile is itself the control: its face, rim and progress fill already
  /// say "press me". A badge inside it adds a second, competing shape — filled
  /// it looked like a button parked on a button, neutral it punched a hole
  /// through the face. So the glyph carries itself in the accent instead.
  Widget _glyph(InsulinkColors colors) {
    Widget glyph = Icon(icon, size: 26, color: colors.accent);
    if (pulse) {
      glyph = _HeartbeatBadge(child: glyph);
    }
    return glyph;
  }

  Widget _text(BuildContext context, InsulinkColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        Text(
          Locales.string(context, labelKey),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: colors.muted),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          spacing: 4,
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: InkText.bigValue,
              ),
            ),
            if (unit != null)
              Text(
                unit!,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.muted,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Scales its child with a continuous double-thump heartbeat (the classic
/// lub-dub), mimicking a pulse. Self-driving (repeats forever) — the parent shows
/// it only while a live heart rate is streaming.
class _HeartbeatBadge extends StatefulWidget {
  const _HeartbeatBadge({required this.child});

  final Widget child;

  @override
  State<_HeartbeatBadge> createState() => _HeartbeatState();
}

class _HeartbeatState extends State<_HeartbeatBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  // Two quick thumps early in the cycle, then rest — the classic lub-dub.
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.18), weight: 12),
    TweenSequenceItem(tween: Tween(begin: 1.18, end: 1.0), weight: 12),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.12), weight: 12),
    TweenSequenceItem(tween: Tween(begin: 1.12, end: 1.0), weight: 12),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 52),
  ]).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}
