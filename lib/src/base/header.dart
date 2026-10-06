import 'package:flutter/material.dart';
import 'package:insulink/src/base/header_account_button.dart';
import 'package:insulink/src/base/header_device_button.dart';
import 'package:insulink/src/base/header_inventory_button.dart';

/// The app bar every tab shares: the page's own title on the left, three
/// separate round buttons on the right, 20 px from the edges.
class Header extends StatelessWidget implements PreferredSizeWidget {
  /// Title widget for the currently shown page (see [AppPageBody.title]).
  final Widget? title;

  const Header({super.key, this.title});

  static const double _edge = 20;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: preferredSize.height,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      title: title,
      titleSpacing: _edge,
      automaticallyImplyLeading: false,
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: _edge),
          child: Row(
            spacing: 8,
            children: [
              HeaderInventoryButton(),
              HeaderDeviceButton(),
              HeaderAccountButton(),
            ],
          ),
        ),
      ],
    );
  }
}
