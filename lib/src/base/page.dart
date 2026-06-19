import 'package:flutter/material.dart';
import 'package:insulink/src/base/navigator.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/injection/injection_button.dart';
import 'package:insulink/src/overview/overview_body.dart';
import 'package:insulink/src/profile/profile_body.dart';
import 'package:insulink/src/pump/pump_body.dart';
import 'package:insulink/src/sensor/sensor_body.dart';

class ProductPage extends StatefulWidget {
  final int? initialPageIndex;

  const ProductPage({super.key, this.initialPageIndex = 0});

  @override
  State<ProductPage> createState() => ProductPageState();
}

class ProductPageState extends State<ProductPage> {
  final List<ProductPageBody> pageBodies = [
    OverviewBody(),
    SensorBody(),
    PumpBody(),
    ProfileBody(),
  ];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialPageIndex ?? 0;
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        // Zero-height toolbar: the AppBar still paints behind the status bar
        // (notch/camera) via the safe-area inset, but adds no extra height.
        appBar: AppBar(toolbarHeight: 0),
        bottomNavigationBar: ProductNavigator(
          selectedIndex: _selectedIndex,
          updateIndex: _onItemTapped,
          pageBodies: pageBodies,
        ),
        body: pageBodies[_selectedIndex].content(context),
        floatingActionButton: InjectionButton(),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      ),
    );
  }
}
