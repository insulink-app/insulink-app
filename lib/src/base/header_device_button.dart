import 'package:flutter/material.dart';
import 'package:insulink/src/base/header_icon_button.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/connections/connections_body.dart';
import 'package:insulink/src/theme/insulink_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Header shortcut to the connections page. Its dot is green while a sensor is
/// paired and red when none is.
class HeaderDeviceButton extends StatelessWidget {
  const HeaderDeviceButton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.insulinkColors;
    final hasSensor = context.watch<CgmController>().hasSensor;
    return HeaderIconButton(
      icon: PhosphorIconsRegular.plug,
      labelKey: 'connections.label',
      statusColor: hasSensor ? colors.range : colors.low,
      onTap: () => openConnectionsPage(context),
    );
  }
}
