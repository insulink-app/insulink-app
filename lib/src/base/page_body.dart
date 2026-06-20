import 'package:flutter/material.dart';

class PageBodyController {
  void Function()? navigatorCallback;
}

abstract class ProductPageBody extends StatelessWidget {
  ProductPageBody({
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

  Future<int> notifications(BuildContext context) async => 0;
}
