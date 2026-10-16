import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/injection/camera_tap_focus.dart';
import 'package:insulink/src/injection/meal_camera_deck.dart';
import 'package:insulink/src/injection/meal_camera_zoom.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The meal camera's chrome around [picture], black and white like the barcode
/// scanner: close at the top, the zoom and [MealCameraDeck] at the foot. A null
/// [onTorch] or [onManual] hides that control and a null [onShutter] dims it
/// (camera starting, or the camera opened just for a photo); with neither
/// shutter nor manual entry, while a photo is analysed, the foot goes.
class MealCameraFrame extends StatelessWidget {
  const MealCameraFrame({
    super.key,
    required this.picture,
    required this.zoomLabel,
    required this.torch,
    required this.onTorch,
    required this.onShutter,
    this.onManual,
  });

  final Widget picture;

  /// The current zoom ("0,5×") over the shutter; null hides it.
  final String? zoomLabel;
  final bool torch;
  final VoidCallback? onTorch;
  final VoidCallback? onShutter;
  final VoidCallback? onManual;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: const CloseButton(),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [picture, if (onShutter != null || onManual != null) _foot()],
      ),
    );
  }

  /// The controls at the foot over a black fade rising from the bottom edge,
  /// the camera apps' trick: white type and rings stay readable wherever a
  /// bright picture runs behind them.
  Widget _foot() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black54, Colors.black87],
            stops: [0, 0.45, 1],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 20,
              children: [
                if (zoomLabel case final label?) CameraZoomPill(label: label),
                MealCameraDeck(
                  onManual: onManual,
                  onShutter: onShutter,
                  onTorch: onTorch,
                  torch: torch,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The live picture, whole and not cropped, so the frame on screen is the frame
/// of the photo. It sits at the top like a camera app's viewfinder, with the
/// controls on the black below it; a tap on it focuses there.
class MealCameraPreview extends StatelessWidget {
  const MealCameraPreview({super.key, required this.camera});

  final CameraController camera;

  @override
  Widget build(BuildContext context) {
    return _TopPicture(
      child: CameraTapFocus(camera: camera, child: CameraPreview(camera)),
    );
  }
}

/// Full width at the top, under the status bar: the one place the live picture
/// and the frozen photo both sit, so the shot does not jump when it freezes.
class _TopPicture extends StatelessWidget {
  const _TopPicture({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(bottom: false, child: child),
    );
  }
}

/// The photo just taken, held still where the live picture was while the server
/// looks at it: darkened, a soft accent line sweeping over it like a scanner, and "Analysing" with
/// a small spinner at the foot.
class MealAnalysingOverlay extends StatefulWidget {
  const MealAnalysingOverlay({super.key, required this.photo});

  final Uint8List photo;

  @override
  State<MealAnalysingOverlay> createState() => _MealAnalysingOverlayState();
}

class _MealAnalysingOverlayState extends State<MealAnalysingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _TopPicture(
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
                child: ClipRect(
                  child: AnimatedBuilder(
                    animation: _sweep,
                    builder: (context, _) => _scanLine(context, _sweep.value),
                  ),
                ),
              ),
            ],
          ),
        ),
        _label(context),
      ],
    );
  }

  /// A glowing band at [progress] (0 top, 1 bottom) of the picture.
  Widget _scanLine(BuildContext context, double progress) {
    final accent = context.ink.accent;
    return Align(
      alignment: Alignment(0, progress * 2 - 1),
      child: Container(
        height: 90,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              accent.withValues(alpha: 0),
              accent.withValues(alpha: 0.45),
              accent.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 56),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 12,
            children: [
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
              LocaleText(
                'injection.photo.analysing',
                style: InkText.rowTitle.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
