import 'package:flutter/material.dart';
import 'package:insulink/src/base/nav_badge.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:provider/provider.dart';

class AppNavigator extends StatefulWidget implements PreferredSizeWidget {
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

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _AppNavigatorState extends State<AppNavigator> {
  Map<int, int> notificationCounts = {};

  /// The badges (e.g. the sensor "no sensor" dot) depend on app state, so the
  /// navigator listens to the controller and reloads them whenever it changes.
  CgmController? _controller;

  /// Display position of the empty slot that leaves room for the centre-docked
  /// floating button. The real [widget.pageBodies] indices are mapped around it
  /// (a tab at body index >= this sits one slot further right on screen).
  int get _spacerIndex => widget.pageBodies.length ~/ 2;

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
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).colorScheme.onSurface,
        currentIndex: widget.selectedIndex >= _spacerIndex
            ? widget.selectedIndex + 1
            : widget.selectedIndex,
        onTap: _onTap,
        unselectedFontSize: 13,
        selectedFontSize: 13,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        items: navigationBarItems(context),
      ),
    );
  }

  void _onTap(int displayIndex) {
    // The centre spacer slot carries no page — ignore taps on it.
    if (displayIndex == _spacerIndex) {
      return;
    }
    final bodyIndex = displayIndex > _spacerIndex
        ? displayIndex - 1
        : displayIndex;
    setState(() => notificationCounts[bodyIndex] = 0);
    widget.updateIndex(bodyIndex);
  }

  void loadNotifications(BuildContext context) {
    for (var index = 0; index < widget.pageBodies.length; index++) {
      widget.pageBodies[index].notifications(context).then((count) {
        setState(() => notificationCounts[index] = count);
      });
    }
  }

  List<BottomNavigationBarItem> navigationBarItems(BuildContext context) {
    final items = [
      for (var index = 0; index < widget.pageBodies.length; index++)
        _barItem(context, index),
    ];
    // Reserve an empty slot in the middle so the centre-docked floating button
    // has room and doesn't overlap the surrounding tabs.
    items.insert(
      _spacerIndex,
      const BottomNavigationBarItem(icon: SizedBox.shrink(), label: ''),
    );
    return items;
  }

  BottomNavigationBarItem _barItem(BuildContext context, int index) {
    final body = widget.pageBodies[index];
    final isSelected = widget.selectedIndex == index;
    final count = notificationCounts[index];
    return BottomNavigationBarItem(
      icon: Stack(
        children: [
          _navIcon(context, body, isSelected, count),
          if (count != null && count != 0) NavBadge(count: count),
        ],
      ),
      label: Locales.string(context, body.name),
    );
  }

  Widget _navIcon(
    BuildContext context,
    AppPageBody body,
    bool isSelected,
    int? count,
  ) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final textColor = Theme.of(context).colorScheme.onSurface;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        color: isSelected
            ? primaryColor.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: (count != null && count > 9) ? 5 : 0,
        ),
        child: Icon(
          isSelected ? body.selectedIcon : body.unselectedIcon,
          size: 30,
          color: isSelected
              ? Color.lerp(textColor, primaryColor, 0.8)
              : textColor.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
