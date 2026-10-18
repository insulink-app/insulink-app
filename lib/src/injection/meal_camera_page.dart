import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_dialog.dart';
import 'package:insulink/src/injection/meal_camera_parts.dart';
import 'package:insulink/src/injection/meal_camera_zoom.dart';
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
/// the live picture, close and torch at the top, a round shutter at
/// the foot.
///
/// The picture is shown whole at the top and starts at 0.8x where the lens
/// allows; a swipe up or down zooms in or out ([CameraZoom]).
///
/// After the shutter the photo stays on screen under [MealAnalysingOverlay]
/// while the server estimates it, instead of a spinner popup over a page the
/// user no longer looks at. A failed estimate, or one that saw no food, says so
/// and hands back the live picture for another try.
///
/// The capture runs at [ResolutionPreset.veryHigh] (1080p): at 720p the crust
/// edges of stacked toast blurred into one and the model counted too few
/// slices. The JPEG stays well under the server's 2 MB cap.
///
/// With [next] it is the first step of the bolus flow: a "manual" button sits
/// under the shutter, and the estimate, or null for the manual choice or a
/// camera that would not open, replaces the camera with the page [next] builds.
class MealCameraPage extends StatefulWidget {
  const MealCameraPage({super.key, this.next});

  /// The page a photo or the manual choice leads to. Null pops the estimate
  /// back to whoever pushed the camera instead.
  final Widget Function(PhotoEstimate? estimate)? next;

  @override
  State<MealCameraPage> createState() => _MealCameraPageState();
}

class _MealCameraPageState extends State<MealCameraPage> {
  CameraController? _camera;
  CameraZoom? _zoom;
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

  /// Starts the back camera slightly zoomed out ([CameraZoom.start]), so a
  /// plate fits without leaning over it. No camera, or the permission refused,
  /// says so and leaves the page.
  Future<void> _openCamera() async {
    try {
      final camera = CameraController(
        await _backCamera(),
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await camera.initialize();
      final zoom = await _startZoom(camera);
      if (!mounted) {
        return await camera.dispose();
      }
      setState(() {
        _camera = camera;
        _zoom = zoom;
      });
    } catch (_) {
      await _fail('injection.photo.no_camera', leave: true);
    }
  }

  /// Moves [camera] to [CameraZoom.start] and returns the range it can swipe in.
  Future<CameraZoom> _startZoom(CameraController camera) async {
    final zoom = CameraZoom.start(
      min: await camera.getMinZoomLevel(),
      max: await camera.getMaxZoomLevel(),
    );
    await camera.setZoomLevel(zoom.level);
    return zoom;
  }

  /// A swipe up zooms in, down zooms out. The camera is not awaited: drag
  /// updates arrive faster than it answers, and the next one supersedes it.
  void _swipeZoom(DragUpdateDetails details) {
    final zoom = _zoom?.swiped(details.delta.dy);
    if (zoom == null) {
      return;
    }
    setState(() => _zoom = zoom);
    _camera?.setZoomLevel(zoom.level).ignore();
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

  /// Freezes the shot on screen, switches the torch off (the live picture it lit
  /// is gone) and asks the server about it.
  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || _photo != null) {
      return;
    }
    final photo = await (await camera.takePicture()).readAsBytes();
    if (!mounted) {
      return;
    }
    setState(() {
      _photo = photo;
      _torch = false;
    });
    camera.setFlashMode(FlashMode.off).ignore();
    final estimate = await PhotoEstimate.request(context, photo);
    if (!mounted) {
      return;
    }
    if (estimate == null || !estimate.hasFood) {
      return _fail(
        estimate == null ? 'injection.photo.failed' : 'injection.photo.no_food',
      );
    }
    _finish(estimate);
  }

  /// Hands [estimate] on: to the [MealCameraPage.next] page in place of the
  /// camera, else back to the caller.
  void _finish(PhotoEstimate? estimate) {
    final next = widget.next;
    if (next == null) {
      Navigator.of(context).pop(estimate);
      return;
    }
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => next(estimate)));
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
      return _finish(null);
    }
    setState(() => _photo = null);
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photo;
    return MealCameraFrame(
      zoomLabel: photo == null ? _zoom?.label : null,
      torch: _torch,
      onTorch: _camera == null || photo != null ? null : _toggleTorch,
      onShutter: _camera == null || photo != null ? null : _capture,
      onManual: widget.next == null || photo != null
          ? null
          : () => _finish(null),
      picture: photo != null
          ? MealAnalysingOverlay(photo: photo)
          : _camera == null
          ? const SizedBox.shrink()
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: _swipeZoom,
              child: MealCameraPreview(camera: _camera!),
            ),
    );
  }
}
