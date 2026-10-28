import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The shutter while a photo is analysed: the same white ring, emptied, with a
/// turn-back arrow in it and its name underneath. The camera apps' own
/// convention, so the way back sits where the thumb took the photo, and the
/// foot gains no control of its own. The name hangs below the ring without
/// taking room, so the ring lands exactly on the shutter's spot.
class MealRetakeButton extends StatelessWidget {
  const MealRetakeButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: Locales.string(context, 'injection.photo.retake'),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black26,
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: const Icon(
                PhosphorIconsBold.arrowCounterClockwise,
                size: 30,
                color: Colors.white,
              ),
            ),
            Positioned(
              top: 84,
              child: LocaleText(
                'injection.photo.retake',
                maxLines: 1,
                style: InkText.label.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
