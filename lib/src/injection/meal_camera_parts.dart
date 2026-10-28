import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/injection/camera_tap_focus.dart';
import 'package:insulink/src/injection/meal_camera_deck.dart';
import 'package:insulink/src/injection/meal_camera_zoom.dart';

/// The meal camera's chrome around [picture], black and white like the barcode
/// scanner: close at the top, the zoom and [MealCameraDeck] at the foot. A null
/// [onTorch] or [onManual] hides that control and a null [onShutter] dims it
/// (camera starting, or the camera opened just for a photo). While a photo is
/// analysed, [status] takes the zoom's place and [onRetake] the shutter's.
class MealCameraFrame extends StatelessWidget {
  const MealCameraFrame({
    super.key,
    required this.picture,
    required this.zoomLabel,
    required this.torch,
    required this.onTorch,
    required this.onShutter,
    this.onManual,
    this.onRetake,
    this.status,
  });

  final Widget picture;

  /// The current zoom ("0,5×") over the shutter; null hides it.
  final String? zoomLabel;
  final bool torch;
  final VoidCallback? onTorch;
  final VoidCallback? onShutter;
  final VoidCallback? onManual;
  final VoidCallback? onRetake;

  /// What the analysis is doing, shown above the deck instead of the zoom.
  final Widget? status;

  bool get _hasFoot =>
      onShutter != null || onManual != null || onRetake != null;

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
        children: [picture, if (_hasFoot) _foot()],
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
                if (status case final status?)
                  SizedBox(height: 32, child: Center(child: status))
                else if (zoomLabel case final label?)
                  CameraZoomPill(label: label),
                MealCameraDeck(
                  onManual: onManual,
                  onShutter: onShutter,
                  onRetake: onRetake,
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
    return MealTopPicture(
      child: CameraTapFocus(camera: camera, child: CameraPreview(camera)),
    );
  }
}

/// Full width at the top, under the status bar: the one place the live picture
/// and the frozen photo both sit, so the shot does not jump when it freezes.
class MealTopPicture extends StatelessWidget {
  const MealTopPicture({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(bottom: false, child: child),
    );
  }
}
