import 'package:flutter/material.dart';
import 'package:insulink/src/base/header.dart';
import 'package:insulink/src/base/navigator.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/devices/devices_body.dart';
import 'package:insulink/src/injection/injection_button.dart';
import 'package:insulink/src/overview/overview_body.dart';
import 'package:insulink/src/sport/sport_body.dart';
import 'package:insulink/src/sport/training/cardio_recording_page.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:insulink/src/sport/workout/workout_runner_page.dart';
import 'package:insulink/src/statistics/statistics_body.dart';
import 'package:provider/provider.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _resumeActive());
  }

  /// Reopen anything that was still running when the app was last closed, so it
  /// resumes with the correct elapsed time regardless of the active tab. A
  /// running GPS training is opened LAST so it ends up on top (it is
  /// time-sensitive), with a paused workout reachable underneath.
  void _resumeActive() {
    if (!mounted) {
      return;
    }
    _resumeActiveWorkout();
    _resumeActiveTraining();
  }

  /// Reopen a workout that was still running. A snapshot whose routine no longer
  /// exists is cleared.
  void _resumeActiveWorkout() {
    final training = context.read<TrainingState>();
    final snapshot = training.activeWorkout;
    if (snapshot == null) {
      return;
    }
    final routine = training.routineById(snapshot.routineId);
    if (routine == null) {
      training.clearActiveWorkout();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutRunnerPage(routine: routine, resume: snapshot),
      ),
    );
  }

  /// Reopen a GPS training that is still recording in the service.
  void _resumeActiveTraining() {
    if (context.read<CardioTrainingState>().activeTraining == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CardioRecordingPage(resume: true),
      ),
    );
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
