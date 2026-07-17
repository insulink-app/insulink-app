import 'package:flutter/material.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/sport/activity/activity_summary_card.dart';
import 'package:insulink/src/sport/activity/health_importer.dart';
import 'package:insulink/src/sport/activity/recent_activities_section.dart';
import 'package:insulink/src/sport/activity/sport_activity_state.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:insulink/src/sport/sport_sync.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:insulink/src/sport/routines/routines_section.dart';
import 'package:insulink/src/sport/training/cardio_section.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

class SportBody extends AppPageBody {
  SportBody({super.key})
    : super(
        name: "sport.label",
        unselectedIcon: PhosphorIconsRegular.courtBasketball,
        selectedIcon: PhosphorIconsFill.courtBasketball,
      );

  @override
  Widget content(BuildContext context) {
    return const SportBodyContent();
  }
}

/// Sport home page. Its own sections (Today, Weight); routines + statistics
/// follow in phase 2/3. Its own widget so the step counter can be started on
/// first open.
class SportBodyContent extends StatefulWidget {
  const SportBodyContent({super.key});

  @override
  State<SportBodyContent> createState() => _SportBodyContentState();
}

class _SportBodyContentState extends State<SportBodyContent> {
  // Captured on first open so [dispose] can stop the live poll without a
  // `context.read` (which Provider forbids during dispose).
  GoogleHealthState? _health;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final activity = context.read<SportActivityState>();
      activity.ensureStarted();
      // Run the background service so cardio auto-detection works even without a
      // CGM sensor (samplers + detection live in that isolate).
      context.read<CgmController>().ensureDetectionService();
      // Straight away, NOT behind the account pull: this also drains the
      // Confirm/Reject notification taps, and making a decision wait seconds for
      // a network round trip is exactly the lag it exists to avoid.
      context.read<CardioTrainingState>().reloadPending();
      _health = context.read<GoogleHealthState>();
      _health!.startLive();
      _syncGoogleHealth(context.read<SportState>(), activity);
      _syncAccount();
    });
  }

  /// Pull-to-refresh: re-pull the account AND re-fetch today's Google Health data
  /// (steps/distance/calories) when connected, so a manual pull updates both.
  /// The two are independent, so they run concurrently.
  Future<void> _refresh() async {
    await Future.wait([
      _syncAccount(),
      _syncGoogleHealth(
        context.read<SportState>(),
        context.read<SportActivityState>(),
      ),
    ]);
  }

  /// Adopts the account's sport data, then re-reads it into the shared state so
  /// the page shows it. Runs on every entry to the tab (the shell rebuilds the
  /// body per tab switch, so [initState] IS "on enter") and behind the
  /// pull-to-refresh.
  ///
  /// The pull only rewrites the STORE; without the reloads below, the in-memory
  /// state would keep what it read at startup and nothing would change on screen.
  /// [CardioTrainingState.reloadPending] doubles as the drain for Confirm/Reject
  /// notification taps, which is why it runs even when the pull fails.
  Future<void> _syncAccount() async {
    final sport = context.read<SportState>();
    final training = context.read<TrainingState>();
    final cardio = context.read<CardioTrainingState>();
    await SportSync().pull(context);
    if (!mounted) {
      return;
    }
    await Future.wait([
      sport.reload(),
      training.reload(),
      cardio.reloadPending(),
    ]);
  }

  /// Refreshes the Google Health metrics, then — while connected — imports
  /// today's steps/distance/calories from it (overriding the pedometer estimate).
  /// The two run SEQUENTIALLY: each does its own `requestAuthorization`, and the
  /// `health` plugin has a single activity-result channel, so firing both at once
  /// drops one request. Not connected ⇒ pedometer + estimates stay the source.
  Future<void> _syncGoogleHealth(
    SportState sport,
    SportActivityState activity,
  ) async {
    await _health!.refreshIfConnected();
    if (!mounted || _health!.connected != true) {
      return;
    }
    await HealthImporter().import(sport, activity);
  }

  @override
  void dispose() {
    _health?.stopLive();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        // Always scrollable/bouncy so the whole page scrolls as one block (no
        // "stuck" section) — and so the pull-to-refresh is reachable even when
        // the content is shorter than the screen.
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        // Bottom padding keeps the centered injection FAB (page.dart) clear.
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 64),
        children: const [
          ActivitySummaryCard(),
          SizedBox(height: 28),
          RoutinesSection(),
          SizedBox(height: 28),
          CardioSection(),
          SizedBox(height: 28),
          RecentActivitiesSection(),
        ],
      ),
    );
  }
}
