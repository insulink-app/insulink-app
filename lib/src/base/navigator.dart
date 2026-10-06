import 'package:flutter/material.dart';
import 'package:insulink/src/base/floating_dock.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:provider/provider.dart';

/// The bottom navigation: owns the tab badges and hands them, with the tabs, to
/// the [FloatingDock] that draws them.
class AppNavigator extends StatefulWidget {
  final int selectedIndex;
  final Function(int) updateIndex;
  final List<AppPageBody> pageBodies;

  const AppNavigator({
    super.key,
    required this.selectedIndex,
    required this.updateIndex,
    required this.pageBodies,
  });

  @override
  State<AppNavigator> createState() => _AppNavigatorState();
}

class _AppNavigatorState extends State<AppNavigator> {
  Map<int, int> notificationCounts = {};

  /// The badges (e.g. the sensor "no sensor" dot) depend on app state, so the
  /// navigator listens to the controller and reloads them whenever it changes.
  CgmController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      loadNotifications(context);
      _wireNavigatorCallbacks();
    });
  }

  void _wireNavigatorCallbacks() {
    for (var index = 0; index < widget.pageBodies.length; index++) {
      final pageBody = widget.pageBodies[index];
      pageBody.controller.navigatorCallback = () {
        pageBody.notifications(context).then((count) {
          setState(() => notificationCounts[index] = count);
        });
      };
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<CgmController>();
    if (!identical(controller, _controller)) {
      _controller?.removeListener(_refreshNotifications);
      _controller = controller..addListener(_refreshNotifications);
    }
  }

  void _refreshNotifications() {
    if (mounted) {
      loadNotifications(context);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_refreshNotifications);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FloatingDock(
      pageBodies: widget.pageBodies,
      selectedIndex: widget.selectedIndex,
      badges: notificationCounts,
      onSelect: _onTap,
    );
  }

  void _onTap(int index) {
    setState(() => notificationCounts[index] = 0);
    widget.updateIndex(index);
  }

  void loadNotifications(BuildContext context) {
    for (var index = 0; index < widget.pageBodies.length; index++) {
      widget.pageBodies[index].notifications(context).then((count) {
        setState(() => notificationCounts[index] = count);
      });
    }
  }
}
