import 'package:flutter/material.dart';
import 'package:insulink/src/base/navigator.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/injection/injection_button.dart';
import 'package:insulink/src/overview/overview_body.dart';
import 'package:insulink/src/profile/profile_body.dart';
import 'package:insulink/src/pump/pump_body.dart';
import 'package:insulink/src/sensor/sensor_body.dart';

/// Lets any page request a tab switch (e.g. the overview's empty state linking
/// to the sensor page). The value is the index into [ProductPageState.pageBodies].
final ValueNotifier<int> appTab = ValueNotifier<int>(0);

/// Tab index of the sensor page within [ProductPageState.pageBodies].
const int kSensorTabIndex = 1;

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
    appTab.value = _selectedIndex;
    appTab.addListener(_onExternalTab);
  }

  @override
  void dispose() {
    appTab.removeListener(_onExternalTab);
    super.dispose();
  }

  /// React to tab-switch requests coming from a page (via [appTab]).
  void _onExternalTab() {
    if (appTab.value != _selectedIndex) {
      setState(() => _selectedIndex = appTab.value);
    }
  }

  void _onItemTapped(int index) {
    // Route through [appTab] so external requests and taps share one path.
    appTab.value = index;
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
