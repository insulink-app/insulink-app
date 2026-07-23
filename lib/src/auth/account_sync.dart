import 'package:flutter/widgets.dart';
import 'package:insulink/src/cgm/event_sync.dart';
import 'package:insulink/src/cgm/glucose_sync.dart';
import 'package:insulink/src/google_health/google_health_sync.dart';
import 'package:insulink/src/google_health/pulse_sync.dart';
import 'package:insulink/src/inventory/inventory_sync.dart';
import 'package:insulink/src/nutrition/nutrition_sync.dart';
import 'package:insulink/src/profile/profile_settings.dart';
import 'package:insulink/src/sport/sport_sync.dart';

/// Adopts everything the account holds on the backend into the local stores:
/// settings, glucose archive, analysis events, sport, nutrition and health.
///
/// Runs on sign-in AND on every cold start (`main.dart`), so data changed
/// elsewhere — the web panel, another device — reaches this device without a
/// re-login. Each branch is best-effort and independent: a failing one leaves
/// that collection's local data untouched and the next start retries.
///
/// The branches run CONCURRENTLY because a cold start blocks on this: sequential
/// they are 14 round trips (sport alone is 6), which a mobile connection cannot
/// finish inside the startup budget. They are safe to overlap — each writes its
/// own storage keys, and a simultaneous token refresh is deduped by
/// `RequestRefresh`.
class AccountSync {
  /// A null [context] is the startup path — there is no widget tree yet. It only
  /// costs the logout alert on an auth failure (see `RequestReset`); the token
  /// refresh itself works without it.
  Future<void> pullAll(BuildContext? context) async {
    await Future.wait([
      ProfileSettings().pull(context),
      GlucoseSync().pullHistory(context),
      EventSync().pullHistory(context),
      SportSync().pull(context),
      NutritionSync().pull(context),
      InventorySync().pull(context),
      GoogleHealthSync().pull(context),
      PulseSync().pull(context),
    ]);
  }
}
