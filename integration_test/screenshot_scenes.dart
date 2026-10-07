import 'package:flutter/material.dart';
import 'package:insulink/src/connections/connections_body.dart';
import 'package:insulink/src/connections/history/device_history_page.dart';
import 'package:insulink/src/connections/history/device_history_sync.dart';
import 'package:insulink/src/connections/status/connection_status_page.dart';
import 'package:insulink/src/google_health/google_health_detail_page.dart';
import 'package:insulink/src/google_health/google_health_models.dart';
import 'package:insulink/src/google_health/heart_rate_page.dart';
import 'package:insulink/src/google_health/sleep/sleep_page.dart';
import 'package:insulink/src/hba1c/hba1c_page.dart';
import 'package:insulink/src/injection/injection_page.dart';
import 'package:insulink/src/inventory/inventory_body.dart';
import 'package:insulink/src/inventory/inventory_calendar_page.dart';
import 'package:insulink/src/nutrition/meal/meal_log_page.dart';
import 'package:insulink/src/nutrition/stats/nutrition_detail_page.dart';
import 'package:insulink/src/nutrition/stats/nutrition_tile.dart';
import 'package:insulink/src/overview/all_values_page.dart';
import 'package:insulink/src/overview/chart/overview_chart_page.dart';
import 'package:insulink/src/profile/profile_page.dart';
import 'package:insulink/src/pump/loop/loop_journal_page.dart';
import 'package:insulink/src/pump/pod_delivery_log_page.dart';
import 'package:insulink/src/sport/activity/activity_detail_page.dart';
import 'package:insulink/src/sport/activity/activity_log_page.dart';
import 'package:insulink/src/sport/calendar/sport_calendar_page.dart';
import 'package:insulink/src/sport/exercises/exercises_page.dart';
import 'package:insulink/src/sport/logbook/workout_session_detail_page.dart';
import 'package:insulink/src/sport/routines/routine_editor_page.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/stats/sport_stats_page.dart';
import 'package:insulink/src/sport/training/cardio_detail_page.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:insulink/src/sport/weight/weight_detail_page.dart';
import 'package:provider/provider.dart';

/// One picture: its file name and how to bring the screen up from the app's
/// home, given a context below the app's navigator.
typedef ScreenshotScene = ({String name, void Function(BuildContext) open});

/// Every screen photographed on top of the tabs, opened the way the app opens
/// it, so the shots need no taps on localized text.
final List<ScreenshotScene> screenshotScenes = [
  _page('glucose', const OverviewChartPage()),
  (name: 'bolus-calculator', open: showInjectionSheet),
  (name: 'sensor', open: openSensorPage),
  (name: 'sensor-history', open: _history(DeviceHistoryKind.sensors)),
  (name: 'pump', open: openPumpPage),
  (name: 'pump-history', open: _history(DeviceHistoryKind.pumps)),
  (name: 'insulin-delivered', open: openPodDeliveryLog),
  (name: 'loop-journal', open: PodLoopJournalPage.open),
  (name: 'connections', open: openConnectionsPage),
  (name: 'reception', open: openConnectionStatus),
  _page('all-values', const AllValuesPage()),
  _page('hba1c', const Hba1cPage()),
  (name: 'walk', open: _cardio(CardioType.walk)),
  (name: 'jog', open: _cardio(CardioType.jog)),
  (name: 'ride', open: _cardio(CardioType.bike)),
  (name: 'routine-edit', open: _routine),
  (name: 'workout-result', open: _session),
  _page('exercise-stats', const SportStatsPage()),
  _page('exercises', const ExercisesPage()),
  _page('calendar', const SportCalendarPage()),
  _page('activity-log', const ActivityLogPage()),
  _page('steps', const ActivityDetailPage(metric: ActivityMetric.steps)),
  _page('weight', const WeightDetailPage()),
  _page('heart-rate', const HeartRatePage()),
  _page('sleep', const SleepPage()),
  _page(
    'resting-heart-rate',
    const GoogleHealthDetailPage(metric: GoogleHealthMetric.restingHr),
  ),
  _page('meals', const MealLogPage()),
  _page('carbs', const NutritionDetailPage(tile: NutritionTile.carbs)),
  _page('inventory', const InventoryPage()),
  _page('inventory-calendar', const InventoryCalendarPage()),
  _page('profile', ProfilePage()),
];

ScreenshotScene _page(String name, Widget page) => (
  name: name,
  open: (context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
);

void Function(BuildContext) _history(DeviceHistoryKind kind) =>
    (context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DeviceHistoryPage(kind: kind)),
    );

/// The newest demo training of [type] (the demo has a walk, a jog and a ride).
void Function(BuildContext) _cardio(CardioType type) => (context) {
  final training = context.read<CardioTrainingState>().trainings.lastWhere(
    (entry) => entry.type == type,
  );
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CardioDetailPage(training: training),
    ),
  );
};

void _routine(BuildContext context) {
  final routine = context.read<TrainingState>().routines.first;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => RoutineEditorPage(routineId: routine.id),
    ),
  );
}

void _session(BuildContext context) {
  final session = context.read<TrainingState>().sessions.last;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => WorkoutSessionDetailPage(session: session),
    ),
  );
}
