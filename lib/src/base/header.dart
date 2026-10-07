import 'package:flutter/material.dart';
import 'package:insulink/src/base/header_account_button.dart';
import 'package:insulink/src/base/header_device_button.dart';
import 'package:insulink/src/base/header_inventory_button.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The app bar every tab shares: the page's own title on the left, three
/// separate round buttons on the right, 20 px from the edges.
class Header extends StatefulWidget implements PreferredSizeWidget {
  /// Title widget for the currently shown page (see [AppPageBody.title]).
  final Widget? title;

  const Header({super.key, this.title});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  State<Header> createState() => _HeaderState();
}

class _HeaderState extends State<Header> {
  static const double _edge = 20;

  /// How far the header's fade reaches down over the page.
  static const double _fade = 24;

  ScrollNotificationObserverState? _observer;

  /// Whether page content sits under the header, so the fade has something
  /// to fade. At rest the page's top stays clear of it.
  bool _scrolledUnder = false;

  /// Listens to the page's scrolling the way [AppBar] does for its own
  /// "scrolled under" state, through the Scaffold's observer.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _observer?.removeListener(_onScroll);
    _observer = ScrollNotificationObserver.maybeOf(context);
    _observer?.addListener(_onScroll);
  }

  @override
  void dispose() {
    _observer?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (notification is! ScrollUpdateNotification ||
        metrics.axis != Axis.vertical) {
      return;
    }
    final under = metrics.extentBefore > 0;
    if (under != _scrolledUnder) {
      setState(() => _scrolledUnder = under);
    }
  }

  /// The app bar plus a soft fade painted below it, over the top of the page,
  /// so content scrolling up runs out into the header like it runs into the
  /// dock instead of being cut at a hard edge. Shown only while content is
  /// under the header, and painted only: touches go straight to the page.
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
            child: AnimatedOpacity(
              opacity: _scrolledUnder ? 1 : 0,
              duration: const Duration(milliseconds: 180),
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
        ),
      ],
    );
  }

  Widget _bar() {
    return AppBar(
      toolbarHeight: widget.preferredSize.height,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      title: widget.title,
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
