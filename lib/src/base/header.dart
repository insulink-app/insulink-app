import 'package:flutter/material.dart';
import 'package:insulink/src/base/header_account_button.dart';
import 'package:insulink/src/base/header_device_button.dart';
import 'package:insulink/src/base/header_inventory_button.dart';

class Header extends StatefulWidget implements PreferredSizeWidget {
  /// Title widget for the currently shown page (see [AppPageBody.title]).
  final Widget? title;

  const Header({super.key, this.title});

  @override
  State<Header> createState() => _HeaderState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _HeaderState extends State<Header> {
  @override
  Widget build(BuildContext context) {
    return AppBar(
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      title: widget.title,
      titleSpacing: 10,
      actions: <Widget>[
        HeaderInventoryButton(),
        HeaderDeviceButton(),
        HeaderAccountButton(),
      ],
      automaticallyImplyLeading: false,
    );
  }
}
