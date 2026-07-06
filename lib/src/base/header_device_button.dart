import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/devices/devices_body.dart';
import 'package:provider/provider.dart';

/// Header shortcut to the devices page, with a red dot when a device needs
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
          icon: const Icon(CupertinoIcons.device_phone_portrait, size: 34),
          color: const Color(0xFFB3B3B3),
          onPressed: () => openDevicesPage(context),
        ),
        if (needsAttention)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).appBarTheme.backgroundColor ??
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
