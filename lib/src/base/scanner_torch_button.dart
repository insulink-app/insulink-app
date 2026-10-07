import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The flashlight switch at the top right of a camera scanner: a filled bolt
/// while the light is on, an outlined one while it is off. Hidden while the
/// camera has no light to offer (not started yet, or a front camera).
class ScannerTorchButton extends StatelessWidget {
  const ScannerTorchButton({super.key, required this.controller});

  final MobileScannerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: controller,
      builder: (context, state, _) {
        final torch = state.torchState;
        if (!state.isRunning || torch == TorchState.unavailable) {
          return const SizedBox.shrink();
        }
        final on = torch == TorchState.on;
        return IconButton(
          icon: Icon(
            on ? PhosphorIconsFill.lightning : PhosphorIconsBold.lightning,
          ),
          tooltip: Locales.string(
            context,
            on ? 'scan.torch_off' : 'scan.torch_on',
          ),
          onPressed: controller.toggleTorch,
        );
      },
    );
  }
}
