import 'package:flutter/material.dart';
import 'package:insulink/src/base/header.dart';
import 'package:insulink/src/base/navigator.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/devices/devices_body.dart';
import 'package:insulink/src/injection/injection_button.dart';
import 'package:insulink/src/overview/overview_body.dart';
import 'package:insulink/src/sport/sport_body.dart';
import 'package:insulink/src/statistics/statistics_body.dart';

/// Lets any page request a tab switch (e.g. the overview's empty state linking
/// to the devices page). The value is the index into [AppPageState.pageBodies].
final ValueNotifier<int> appTab = ValueNotifier<int>(0);

/// Tab index of the devices page (Sensor + Pump) within
/// [AppPageState.pageBodies].
const int kDevicesTabIndex = 3;

class AppPage extends StatefulWidget {
  final int? initialPageIndex;

  const AppPage({super.key, this.initialPageIndex = 0});

  @override
  State<AppPage> createState() => AppPageState();
}

class AppPageState extends State<AppPage> {
  final List<AppPageBody> pageBodies = [
    OverviewBody(),
    SportBody(),
    StatisticsBody(),
    DevicesBody(),
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
        appBar: Header(title: pageBodies[_selectedIndex].title(context)),
        bottomNavigationBar: AppNavigator(
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
