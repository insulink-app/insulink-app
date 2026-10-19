import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The meal camera's controls in one row at thumb height, laid out like a
/// camera app's: manual entry on the left, the shutter in the middle, the light
/// on the right. A null callback leaves its slot empty (no manual entry outside
/// the bolus flow, no light before the camera runs) and dims the shutter, so
/// the row never shifts while the camera starts.
class MealCameraDeck extends StatelessWidget {
  const MealCameraDeck({
    super.key,
    required this.onManual,
    required this.onShutter,
    required this.onTorch,
    required this.torch,
  });

  final VoidCallback? onManual;
  final VoidCallback? onShutter;
  final VoidCallback? onTorch;
  final bool torch;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _manual()),
        _ShutterButton(onPressed: onShutter),
        Expanded(child: _light(context)),
      ],
    );
  }

  Widget _manual() {
    final manual = onManual;
    if (manual == null) {
      return const SizedBox.shrink();
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
      return const SizedBox.shrink();
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
  const _ShutterButton({required this.onPressed});

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
