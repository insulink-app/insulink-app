import 'package:flutter/material.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/localization/locales.dart';

class ProductNavigator extends StatefulWidget implements PreferredSizeWidget {
  final int selectedIndex;
  final Function(int) updateIndex;
  final List<ProductPageBody> pageBodies;

  const ProductNavigator({
    super.key,
    required this.selectedIndex,
    required this.updateIndex,
    required this.pageBodies,
  });

  @override
  State<ProductNavigator> createState() => _ProductNavigatorState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _ProductNavigatorState extends State<ProductNavigator> {
  Map<int, int> notificationCounts = {};

  /// Display position of the empty slot that leaves room for the centre-docked
  /// floating button. The real [widget.pageBodies] indices are mapped around it
  /// (a tab at body index >= this sits one slot further right on screen).
  int get _spacerIndex => widget.pageBodies.length ~/ 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      loadNotifications(context);
      for (var i = 0; i < widget.pageBodies.length; i++) {
        var pageBody = widget.pageBodies[i];
        pageBody.controller.navigatorCallback = () {
          pageBody.notifications(context).then((count) {
            setState(() {
              notificationCounts[i] = count;
            });
          });
        };
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Stack(
        children: [
          BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            selectedItemColor: Color.lerp(
              Theme.of(context).colorScheme.onSurface,
              Theme.of(context).colorScheme.onSurface,
              0.8,
            ),
            currentIndex: widget.selectedIndex >= _spacerIndex
                ? widget.selectedIndex + 1
                : widget.selectedIndex,
            onTap: (displayIndex) {
              // The centre spacer slot carries no page — ignore taps on it.
              if (displayIndex == _spacerIndex) return;
              final bodyIndex = displayIndex > _spacerIndex
                  ? displayIndex - 1
                  : displayIndex;
              setState(() {
                notificationCounts[bodyIndex] = 0;
              });
              widget.updateIndex(bodyIndex);
            },
            unselectedFontSize: 13,
            selectedFontSize: 13,
            selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold),
            unselectedLabelStyle: TextStyle(fontWeight: FontWeight.bold),
            items: navigationBarItems(context),
          ),
        ],
      ),
    );
  }

  void loadNotifications(context) {
    for (var i = 0; i < widget.pageBodies.length; i++) {
      widget.pageBodies[i].notifications(context).then((count) {
        setState(() {
          notificationCounts[i] = count;
        });
      });
    }
  }

  List<BottomNavigationBarItem> navigationBarItems(BuildContext context) {
    var primaryColor = Theme.of(context).colorScheme.primary;
    var textColor = Theme.of(context).colorScheme.onSurface;
    List<BottomNavigationBarItem> items = [];
    for (var i = 0; i < widget.pageBodies.length; i++) {
      var body = widget.pageBodies[i];
      bool isSelected = widget.selectedIndex == i;
      final count = notificationCounts[i];

      List<Widget> iconChildren = [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          margin: EdgeInsets.only(bottom: 5),
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
        ),
      ];

      if (count != null && count != 0) {
        iconChildren.add(createNotificationBadge(count));
      }

      items.add(
        BottomNavigationBarItem(
          icon: Stack(children: iconChildren),
          label: Locales.string(context, body.name),
        ),
      );
    }
    // Reserve an empty slot in the middle so the centre-docked floating button
    // has room and doesn't overlap the surrounding tabs.
    items.insert(
      _spacerIndex,
      const BottomNavigationBarItem(icon: SizedBox.shrink(), label: ''),
    );
    return items;
  }

  Widget createNotificationBadge(int count) {
    var theme = Theme.of(context);
    if (count == -1) {
      return Positioned(
        right: 0,
        top: 0,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
            border: Border.all(
              color: theme.appBarTheme.backgroundColor ?? Colors.white,
              width: 1,
            ),
          ),
        ),
      );
    }
    return Positioned(
      right: 5,
      top: 0,
      child: Container(
        width: count < 10 ? 20 : null,
        height: 20,
        padding: count < 10
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.appBarTheme.backgroundColor ?? Colors.white,
            width: 1,
          ),
        ),
        child: Text(
          count.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            height: 1,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
