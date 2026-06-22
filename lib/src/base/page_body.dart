import 'package:flutter/material.dart';

class PageBodyController {
  void Function()? navigatorCallback;
}

abstract class AppPageBody extends StatelessWidget {
  AppPageBody({
    super.key,
    required this.name,
    required this.unselectedIcon,
    required this.selectedIcon,
  });

  final String name;
  final IconData unselectedIcon;
  final IconData selectedIcon;
  final PageBodyController controller = PageBodyController();

  @override
  Widget build(BuildContext context) => content(context);

  Widget content(BuildContext context);

  /// Optional widget shown as the title in the app [Header] for this page.
  /// Returns null (the default) when the page wants no header title.
  Widget? title(BuildContext context) => null;

  Future<int> notifications(BuildContext context) async => 0;
}
