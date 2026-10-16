import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The meal camera's chrome around [picture], black and white like the barcode
/// scanner: close and torch at the top, the hint and the round shutter at the
/// foot. A null [onShutter] or [onTorch] hides that control (camera starting,
/// or a photo being analysed).
class MealCameraFrame extends StatelessWidget {
  const MealCameraFrame({
    super.key,
    required this.picture,
    required this.torch,
    required this.onTorch,
    required this.onShutter,
  });

  final Widget picture;
  final bool torch;
  final VoidCallback? onTorch;
  final VoidCallback? onShutter;

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
        actions: [if (onTorch != null) _torchButton(context)],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [picture, if (onShutter != null) _foot()],
      ),
    );
  }

  Widget _torchButton(BuildContext context) {
    return IconButton(
      icon: Icon(
        torch ? PhosphorIconsFill.lightning : PhosphorIconsBold.lightning,
      ),
      tooltip: Locales.string(
        context,
        torch ? 'scan.torch_off' : 'scan.torch_on',
      ),
      onPressed: onTorch,
    );
  }

  Widget _foot() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 24,
            children: [
              const LocaleText(
                'injection.photo.hint',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
              _ShutterButton(onPressed: onShutter!),
            ],
          ),
        ),
      ),
    );
  }
}

/// The live picture, whole: centred and not cropped, so the frame on screen is
/// the frame of the photo. Filling the screen used to cut off its sides, which
/// made the user step closer than the photo needed.
class MealCameraPreview extends StatelessWidget {
  const MealCameraPreview({super.key, required this.camera});

  final CameraController camera;

  @override
  Widget build(BuildContext context) {
    return Center(child: CameraPreview(camera));
  }
}

/// A white ring around a white disc, the camera apps' shutter.
class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: Locales.string(context, 'injection.photo.shutter'),
      child: GestureDetector(
        onTap: onPressed,
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
    );
  }
}

/// The photo just taken, held still while the server looks at it: darkened, a
/// soft accent line sweeping down over it like a scanner, and "Analysing" with
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
        Image.memory(widget.photo, fit: BoxFit.contain, gaplessPlayback: true),
        const ColoredBox(color: Colors.black38),
        AnimatedBuilder(
          animation: _sweep,
          builder: (context, _) => _scanLine(context, _sweep.value),
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
