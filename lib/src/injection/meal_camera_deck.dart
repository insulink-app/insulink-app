import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:insulink/src/injection/meal_retake_button.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The meal camera's controls in one row at thumb height, laid out like a
/// camera app's: manual entry on the left, the shutter in the middle, the light
/// on the right. A null callback leaves its slot empty (no manual entry outside
/// the bolus flow, no light before the camera runs) and dims the shutter; an
/// empty slot keeps its height, so the row never shifts. With [onRetake] the shutter
/// turns into [MealRetakeButton], a short scale and fade between the two.
class MealCameraDeck extends StatelessWidget {
  const MealCameraDeck({
    super.key,
    required this.onManual,
    required this.onShutter,
    required this.onTorch,
    required this.torch,
    this.onRetake,
  });

  final VoidCallback? onManual;
  final VoidCallback? onShutter;
  final VoidCallback? onTorch;
  final bool torch;
  final VoidCallback? onRetake;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _manual()),
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween(begin: 0.85, end: 1.0).animate(animation),
              child: child,
            ),
          ),
          child: _centre(),
        ),
        Expanded(child: _light(context)),
      ],
    );
  }

  /// An empty side slot that still takes a side button's height, so the row,
  /// and the shutter in it, stays put while the light appears at camera start
  /// and while both sides go during an analysis.
  Widget _emptySlot() {
    return Visibility(
      visible: false,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: _DeckButton(
        icon: PhosphorIconsBold.lightning,
        labelKey: 'injection.photo.light',
        onPressed: () {},
      ),
    );
  }

  Widget _centre() {
    final retake = onRetake;
    if (retake != null) {
      return MealRetakeButton(key: const ValueKey('retake'), onPressed: retake);
    }
    return _ShutterButton(key: const ValueKey('shutter'), onPressed: onShutter);
  }

  Widget _manual() {
    final manual = onManual;
    if (manual == null) {
      return _emptySlot();
    }
    return _DeckButton(
      icon: PhosphorIconsBold.keyboard,
      labelKey: 'injection.photo.manual',
      onPressed: manual,
    );
  }

  Widget _light(BuildContext context) {
    final toggle = onTorch;
    if (toggle == null) {
      return _emptySlot();
    }
    return _DeckButton(
      icon: torch ? PhosphorIconsFill.lightning : PhosphorIconsBold.lightning,
      labelKey: 'injection.photo.light',
      tooltip: Locales.string(
        context,
        torch ? 'scan.torch_off' : 'scan.torch_on',
      ),
      lit: torch,
      onPressed: toggle,
    );
  }
}

/// A round side control of the deck: dark frosted glass with a light rim and a
/// white glyph, its name small underneath, readable over a bright picture as
/// well as on black. [lit] fills it white with a black glyph, so a running
/// light reads at a glance.
class _DeckButton extends StatelessWidget {
  const _DeckButton({
    required this.icon,
    required this.labelKey,
    required this.onPressed,
    this.tooltip,
    this.lit = false,
  });

  final IconData icon;
  final String labelKey;
  final VoidCallback onPressed;
  final String? tooltip;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip ?? Locales.string(context, labelKey),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Column(
          spacing: 8,
          children: [
            ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: lit ? Colors.white : Colors.black54,
                    border: Border.all(color: Colors.white38),
                  ),
                  child: Icon(
                    icon,
                    size: 24,
                    color: lit ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ),
            LocaleText(
              labelKey,
              style: InkText.label.copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// A white ring around a white disc, the camera apps' shutter. Dimmed while
/// [onPressed] is null.
class _ShutterButton extends StatelessWidget {
  const _ShutterButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: Locales.string(context, 'injection.photo.shutter'),
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: onPressed == null ? 0.35 : 1,
          child: Container(
            width: 76,
            height: 76,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
            ),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
