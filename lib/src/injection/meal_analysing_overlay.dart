import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:insulink/src/injection/food_contour_painter.dart';
import 'package:insulink/src/injection/food_contours.dart';
import 'package:insulink/src/injection/meal_analysing_label.dart';
import 'package:insulink/src/injection/meal_camera_parts.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The photo just taken, held still where the live picture was while the server
/// looks at it: darkened, a soft accent line sweeping over it like a scanner,
/// the food's own outlines ([FoodContours]) lighting up wherever the line
/// passes, and [MealAnalysingLabel] at the foot. The line eases
/// into each turn, and both it and the glow fade just before the top and
/// bottom, so the turns stay quiet while the rest of the plate lights fully. Reduced motion
/// stops the line and keeps the outlines softly lit.
class MealAnalysingOverlay extends StatefulWidget {
  const MealAnalysingOverlay({super.key, required this.photo});

  final Uint8List photo;

  @override
  State<MealAnalysingOverlay> createState() => _MealAnalysingOverlayState();
}

class _MealAnalysingOverlayState extends State<MealAnalysingOverlay>
    with SingleTickerProviderStateMixin {
  /// Height of the scan line's glowing band.
  static const double _lineHeight = 90;

  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  late final Animation<double> _position = CurvedAnimation(
    parent: _sweep,
    curve: Curves.easeInOutSine,
  );
  ui.Image? _outlines;

  @override
  void initState() {
    super.initState();
    _findOutlines();
  }

  Future<void> _findOutlines() async {
    final contours = await FoodContours.fromJpeg(widget.photo);
    final outlines = await contours.toImage();
    if (!mounted) {
      outlines.dispose();
      return;
    }
    setState(() => _outlines = outlines);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    _outlines?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        MealTopPicture(
          child: Stack(
            children: [
              Image.memory(
                widget.photo,
                width: double.infinity,
                fit: BoxFit.fitWidth,
                gaplessPlayback: true,
              ),
              const Positioned.fill(child: ColoredBox(color: Colors.black38)),
              Positioned.fill(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _sweep,
                    builder: (context, _) => _scan(context),
                  ),
                ),
              ),
            ],
          ),
        ),
        const MealAnalysingLabel(),
      ],
    );
  }

  /// The band and, once found, the outlines it lights, both at the same
  /// height so the glow on the food follows the line exactly.
  Widget _scan(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final top = _position.value * (height - _lineHeight);
        final presence = math.sqrt(math.sin(math.pi * _position.value));
        return Stack(
          children: [
            if (!still)
              Positioned(
                top: top,
                left: 0,
                right: 0,
                height: _lineHeight,
                child: _band(context, presence),
              ),
            if (_outlines case final outlines?)
              Positioned.fill(
                child: CustomPaint(
                  painter: FoodContourPainter(
                    outlines: outlines,
                    accent: context.ink.accent,
                    lineCenter: still ? null : (top + _lineHeight / 2) / height,
                    intensity: presence,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// The glowing band, dimmer near the turns ([presence] 0 at the top and
  /// bottom, 1 in the middle) but never gone, so the motion stays readable.
  Widget _band(BuildContext context, double presence) {
    final accent = context.ink.accent;
    final alpha = 0.45 * (0.35 + 0.65 * presence);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0),
            accent.withValues(alpha: alpha),
            accent.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}
