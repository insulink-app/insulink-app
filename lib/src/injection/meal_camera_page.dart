import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_dialog.dart';
import 'package:insulink/src/injection/meal_camera_parts.dart';
import 'package:insulink/src/injection/photo_estimate.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Opens the meal camera and returns the estimate of the photo taken there, or
/// null when the user backed out.
Future<PhotoEstimate?> photographMeal(BuildContext context) {
  return Navigator.of(context).push<PhotoEstimate>(
    MaterialPageRoute(builder: (_) => const MealCameraPage()),
  );
}

/// Full-screen camera for the bolus calculator, in the barcode scanner's look:
/// the live picture, close and torch at the top, a hint and a round shutter at
/// the foot.
///
/// After the shutter the photo stays on screen under [MealAnalysingOverlay]
/// while the server estimates it, instead of a spinner popup over a page the
/// user no longer looks at. A failed estimate, or one that saw no food, says so
/// and hands back the live picture for another try.
///
/// The capture runs at [ResolutionPreset.high] (720p): a JPEG of a few hundred
/// kB, well under the server's 2 MB cap, and plenty for the model.
class MealCameraPage extends StatefulWidget {
  const MealCameraPage({super.key});

  @override
  State<MealCameraPage> createState() => _MealCameraPageState();
}

class _MealCameraPageState extends State<MealCameraPage> {
  CameraController? _camera;
  Uint8List? _photo;
  bool _torch = false;

  @override
  void initState() {
    super.initState();
    _openCamera();
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  /// Starts the back camera. No camera, or the permission refused, says so and
  /// leaves the page.
  Future<void> _openCamera() async {
    try {
      final camera = CameraController(
        await _backCamera(),
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await camera.initialize();
      if (!mounted) {
        return await camera.dispose();
      }
      setState(() => _camera = camera);
    } catch (_) {
      await _fail('injection.photo.no_camera', leave: true);
    }
  }

  /// The back camera, else whichever there is. Throws when there is none.
  Future<CameraDescription> _backCamera() async {
    final cameras = await availableCameras();
    return cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
  }

  Future<void> _toggleTorch() async {
    final next = !_torch;
    await _camera?.setFlashMode(next ? FlashMode.torch : FlashMode.off);
    setState(() => _torch = next);
  }

  /// Freezes the shot on screen and asks the server about it.
  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || _photo != null) {
      return;
    }
    final photo = await (await camera.takePicture()).readAsBytes();
    if (!mounted) {
      return;
    }
    setState(() => _photo = photo);
    final estimate = await PhotoEstimate.request(context, photo);
    if (!mounted) {
      return;
    }
    if (estimate == null || !estimate.hasFood) {
      return _fail(
        estimate == null ? 'injection.photo.failed' : 'injection.photo.no_food',
      );
    }
    Navigator.of(context).pop(estimate);
  }

  /// Says what went wrong, then either leaves or goes back to the live picture
  /// once the dialog is closed.
  Future<void> _fail(String messageKey, {bool leave = false}) async {
    if (!mounted) {
      return;
    }
    await InkDialog(
      icon: PhosphorIconsBold.warningCircle,
      tone: InkDialogTone.danger,
      titleKey: messageKey,
    ).show(context);
    if (!mounted) {
      return;
    }
    if (leave) {
      return Navigator.of(context).pop();
    }
    setState(() => _photo = null);
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photo;
    return MealCameraFrame(
      torch: _torch,
      onTorch: _camera == null || photo != null ? null : _toggleTorch,
      onShutter: _camera == null || photo != null ? null : _capture,
      picture: photo != null
          ? MealAnalysingOverlay(photo: photo)
          : _camera == null
          ? const SizedBox.shrink()
          : MealCameraPreview(camera: _camera!),
    );
  }
}
