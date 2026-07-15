import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/connections/connections_body.dart';
import 'package:provider/provider.dart';

/// Header shortcut to the connections page, with a red dot when a device needs
/// attention (currently: no sensor paired).
class HeaderDeviceButton extends StatelessWidget {
  const HeaderDeviceButton({super.key});

  @override
  Widget build(BuildContext context) {
    final needsAttention = !context.watch<CgmController>().hasSensor;
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(PhosphorIconsRegular.plug, size: 30),
          color: const Color(0xFFB3B3B3),
          onPressed: () => openConnectionsPage(context),
        ),
        if (needsAttention)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      Theme.of(context).appBarTheme.backgroundColor ??
                      Theme.of(context).scaffoldBackgroundColor,
                  width: 1.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
