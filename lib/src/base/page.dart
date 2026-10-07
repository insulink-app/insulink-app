import 'package:flutter/material.dart';
import 'package:insulink/src/base/header.dart';
import 'package:insulink/src/base/navigator.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/base/tab_transition.dart';
import 'package:insulink/src/nutrition/nutrition_body.dart';
import 'package:insulink/src/overview/overview_body.dart';
import 'package:insulink/src/sport/sport_body.dart';
import 'package:insulink/src/sport/training/cardio_recording_page.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:insulink/src/sport/workout/workout_runner_page.dart';
import 'package:insulink/src/analysis/analysis_body.dart';
import 'package:provider/provider.dart';

/// Lets any page request a tab switch (e.g. the overview's empty state linking
/// to the devices page). The value is the index into [AppPageState.pageBodies].
///
/// It also OUTLIVES the shell, so the selected tab is remembered even if [AppPage]
/// is ever rebuilt: reading the initial tab back from here restores it. (The
/// account pull no longer remounts the shell — `main.dart` keeps the [Navigator]
/// mounted across a reload — but persisting the tab here is cheap insurance.)
final ValueNotifier<int> appTab = ValueNotifier<int>(0);

/// Tab index of the analysis page within [AppPageState.pageBodies].
const int kAnalysisTabIndex = 3;

class AppPage extends StatefulWidget {
  final int? initialPageIndex;

  const AppPage({super.key, this.initialPageIndex});

  @override
  State<AppPage> createState() => AppPageState();
}

class AppPageState extends State<AppPage> with WidgetsBindingObserver {
  final List<AppPageBody> pageBodies = [
    OverviewBody(),
    SportBody(),
    NutritionBody(),
    AnalysisBody(),
  ];
  int _selectedIndex = 0;

  /// The workout whose runner this shell has already opened, identified by its
  /// start. Without it every [TrainingState] change would push another runner —
  /// including after the user deliberately backed out of one that is still
  /// paused and running.
  int? _openedWorkoutStartedAt;

  /// Cached so [dispose] can detach its listener WITHOUT a `context.read` — during
  /// full-tree teardown (the app closing) the provider ancestor is already gone,
  /// and reading it there throws a null-check crash.
  late final TrainingState _training = context.read<TrainingState>();

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialPageIndex ?? appTab.value;
    appTab.value = _selectedIndex;
    appTab.addListener(_onExternalTab);
    WidgetsBinding.instance.addObserver(this);
    _training.addListener(_onTrainingChanged);
    _watchActiveWorkout();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resumeActive());
  }

  /// Follows the account's workout only while the user is actually in the app —
  /// polling every few seconds through a night in the background would be pure
  /// waste. Resuming re-checks immediately, so coming back to the phone after
  /// starting a routine in the panel shows it at once.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _watchActiveWorkout();
      return;
    }
    if (state == AppLifecycleState.paused) {
      context.read<TrainingState>().stopWatchingActiveWorkout();
    }
  }

  void _watchActiveWorkout() {
    context.read<TrainingState>().watchActiveWorkout();
  }

  /// A workout appeared (or changed) on the account — most likely started in the
  /// web panel. Open it, so the phone lands on the running routine instead of
  /// making the user find it.
  void _onTrainingChanged() {
    if (!mounted) {
      return;
    }
    _openActiveWorkout();
  }

  /// Reopen anything that was still running when the app was last closed, so it
  /// resumes with the correct elapsed time regardless of the active tab. A
  /// running GPS training is opened LAST so it ends up on top (it is
  /// time-sensitive), with a paused workout reachable underneath.
  void _resumeActive() {
    if (!mounted) {
      return;
    }
    _openActiveWorkout();
    _resumeActiveTraining();
  }

  /// Opens the runner for the account's running workout, once per workout.
  ///
  /// A snapshot whose routine is not here is left alone rather than cleared: the
  /// routine is far more likely to be a sync still in flight than one genuinely
  /// deleted, and clearing now ends the workout on every device — including the
  /// panel the user is standing in front of. An unmatched snapshot shows no
  /// banner and opens no runner, so leaving it costs nothing.
  void _openActiveWorkout() {
    final training = context.read<TrainingState>();
    final snapshot = training.activeWorkout;
    if (snapshot == null) {
      _openedWorkoutStartedAt = null;
      return;
    }
    if (training.drivingActiveWorkout ||
        snapshot.startedAtMs == _openedWorkoutStartedAt) {
      return;
    }
    final routine = training.routineForSnapshot(snapshot);
    if (routine == null) {
      return;
    }
    _openedWorkoutStartedAt = snapshot.startedAtMs;
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
    WidgetsBinding.instance.removeObserver(this);
    appTab.removeListener(_onExternalTab);
    _training
      ..removeListener(_onTrainingChanged)
      ..stopWatchingActiveWorkout();
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
        body: TabTransition(
          index: _selectedIndex,
          child: pageBodies[_selectedIndex].content(context),
        ),
      ),
    );
  }
}
