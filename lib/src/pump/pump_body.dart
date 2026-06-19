import 'package:flutter/cupertino.dart';
import 'package:insulink/src/base/page_body.dart';

class PumpBody extends ProductPageBody {
  final GlobalKey<_PumpBodyContentState> _key =
  GlobalKey<_PumpBodyContentState>();

  PumpBody({super.key})
      : super(
    name: "pump.label",
    unselectedIcon: CupertinoIcons.today,
    selectedIcon: CupertinoIcons.today_fill,
  );

  @override
  Widget content(BuildContext context) {
    return PumpBodyContent(key: _key);
  }
}

class PumpBodyContent extends StatefulWidget {
  const PumpBodyContent({super.key});

  @override
  State<PumpBodyContent> createState() => _PumpBodyContentState();
}

class _PumpBodyContentState extends State<PumpBodyContent> {
  @override
  Widget build(BuildContext context) {
    return SizedBox.shrink();
  }
}