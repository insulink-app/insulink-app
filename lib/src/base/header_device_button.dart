import 'package:flutter/material.dart';
import 'package:insulink/src/base/header_icon_button.dart';
import 'package:insulink/src/connections/connections_body.dart';
import 'package:insulink/src/connections/device_attention.dart';
import 'package:insulink/src/theme/insulink_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Header shortcut to the devices page, with a red dot while any device needs
/// attention ([DeviceAttention]). No dot otherwise: a dot here always means
/// "look", and the devices page marks which device it is about.
class HeaderDeviceButton extends StatelessWidget {
  const HeaderDeviceButton({super.key});

  @override
  Widget build(BuildContext context) {
    final attention = DeviceAttention.of(context);
    return HeaderIconButton(
      icon: PhosphorIconsRegular.plug,
      labelKey: 'connections.label',
      statusColor: attention.any ? context.insulinkColors.low : null,
      onTap: () => openConnectionsPage(context),
    );
  }
}
