import 'package:flutter/cupertino.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/sport/activity/activity_summary_card.dart';
import 'package:insulink/src/sport/activity/recent_activities_section.dart';
import 'package:insulink/src/sport/activity/sport_activity_state.dart';
import 'package:insulink/src/sport/routines/routines_section.dart';
import 'package:insulink/src/sport/training/cardio_section.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';
import 'package:provider/provider.dart';

class SportBody extends AppPageBody {
  SportBody({super.key})
    : super(
        name: "sport.label",
        unselectedIcon: CupertinoIcons.sportscourt,
        selectedIcon: CupertinoIcons.sportscourt_fill,
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
      context.read<SportActivityState>().ensureStarted();
      // Run the background service so cardio auto-detection works even without a
      // CGM sensor (samplers + detection live in that isolate).
      context.read<CgmController>().ensureDetectionService();
      context.read<CardioTrainingState>().reloadPending();
      _health = context.read<GoogleHealthState>();
      _health!.refreshIfConnected();
      _health!.startLive();
    });
  }

  @override
  void dispose() {
    _health?.stopLive();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      // Always scrollable/bouncy so the whole page scrolls as one block (no
      // "stuck" section).
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
    );
  }
}
