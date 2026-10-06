import 'package:flutter/material.dart';
import 'package:insulink/src/base/header_account_button.dart';
import 'package:insulink/src/base/header_device_button.dart';
import 'package:insulink/src/base/header_inventory_button.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The app bar every tab shares: the page's own title on the left, three
/// separate round buttons on the right, 20 px from the edges.
class Header extends StatelessWidget implements PreferredSizeWidget {
  /// Title widget for the currently shown page (see [AppPageBody.title]).
  final Widget? title;

  const Header({super.key, this.title});

  static const double _edge = 20;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  /// How far the header's fade reaches down over the page.
  static const double _fade = 24;

  /// The app bar plus a soft fade painted below it, over the top of the page,
  /// so content scrolling up runs out into the header like it runs into the
  /// dock instead of being cut at a hard edge. Painted only: touches go
  /// straight through to the page.
  @override
  Widget build(BuildContext context) {
    final ground = context.ink.ground;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _bar(),
        Positioned(
          left: 0,
          right: 0,
          bottom: -_fade,
          height: _fade,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [ground, ground.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bar() {
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
