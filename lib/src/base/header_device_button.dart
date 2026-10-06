import 'package:flutter/material.dart';
import 'package:insulink/src/base/header_icon_button.dart';
import 'package:insulink/src/connections/connections_body.dart';
import 'package:insulink/src/connections/device_attention.dart';
import 'package:insulink/src/theme/insulink_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Header shortcut to the devices page. Its dot is red while any device needs
/// attention ([DeviceAttention], the page marks which) and green otherwise.
class HeaderDeviceButton extends StatelessWidget {
  const HeaderDeviceButton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.insulinkColors;
    final attention = DeviceAttention.of(context);
    return HeaderIconButton(
      icon: PhosphorIconsRegular.plug,
      labelKey: 'connections.label',
      statusColor: attention.any ? colors.low : colors.range,
      onTap: () => openConnectionsPage(context),
    );
  }
}
