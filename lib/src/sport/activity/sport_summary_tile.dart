import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/accent_colors.dart';
import 'package:insulink/src/theme/brand_tints.dart';

/// A single summary "box": glyph + label + big value (optional unit), tappable.
/// Used both in the Sport tab's activity card and on the overview.
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
  });

  final IconData icon;
  final String labelKey;
  final String value;
  final String? unit;
  final VoidCallback? onTap;

  /// When true the glyph beats like a heartbeat (used by the heart-rate tile
  /// while a live BLE pulse is streaming).
  final bool pulse;

  /// Optional daily-goal progress in 0..1. When set, the box background fills
  /// from the left in proportion to how close today is to the goal (brighter
  /// once reached).
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tintPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.tintLine),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            if (progress != null) _fill(scheme),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _glyph(context),
                  const SizedBox(width: 12),
                  Expanded(child: _text(context, scheme)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The proportional background fill, anchored to the left edge and filling the
  /// full tile height.
  Widget _fill(ColorScheme scheme) {
    final value = progress!.clamp(0.0, 1.0);
    final reached = value >= 1.0;
    return Positioned.fill(
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value,
        child: ColoredBox(
          color: scheme.primary.withValues(alpha: reached ? 0.22 : 0.13),
        ),
      ),
    );
  }

  /// The tile's glyph, deliberately bare — no badge behind it.
  ///
  /// This tile is itself the control: its tinted face, border and progress fill
  /// already say "press me". A badge inside it adds a second, competing shape —
  /// filled it looked like a button parked on a button, neutral it punched a
  /// grey hole through the tint. So the glyph carries itself instead: sized to
  /// hold its own against the 28px value beside it, and weighted with the
  /// accent. The fixed slot keeps every tile's text in one column.
  Widget _glyph(BuildContext context) {
    Widget glyph = Icon(icon, size: 26, color: context.accent);
    if (pulse) {
      glyph = _HeartbeatBadge(child: glyph);
    }
    return SizedBox(width: 34, height: 40, child: Center(child: glyph));
  }

  Widget _text(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          Locales.string(context, labelKey),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 3),
              Text(
                unit!,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
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
