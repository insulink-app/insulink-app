import 'package:insulink/src/auth/guest_mode.dart';
import 'package:insulink/src/cgm/cgm_store.dart';
import 'package:insulink/src/cgm/event_sync.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/google_health/google_health_sync.dart';
import 'package:insulink/src/google_health/intraday_pulse_store.dart';
import 'package:insulink/src/google_health/pulse_sync.dart';
import 'package:insulink/src/hba1c/hba1c_state.dart';
import 'package:insulink/src/hba1c/hba1c_sync.dart';
import 'package:insulink/src/profile/profile_settings.dart';
import 'package:insulink/src/request/sync_ledger.dart';

/// Hands everything collected in [GuestMode] to the account just signed into,
/// around the usual sign-in pull ([prepare] before it, [finish] after it).
///
/// Glucose needs nothing here: `GlucoseBacklog` uploads the whole archive the
/// account has not confirmed. The pod and sensor mirror themselves on the next
/// resume or reading, and the basal queue is persisted already.
class OfflineHandover {
  /// Every replace-all collection the [SyncLedger] guards.
  static const _collections = [
    'nutrition.meals',
    'nutrition.drinks',
    'nutrition.products',
    'sport.measurements',
    'sport.exercises',
    'sport.routines',
    'sport.workouts',
    'sport.trainings',
    'inventory.items',
  ];
  static const _ledger = SyncLedger();

  const OfflineHandover();

  /// Marks every collection unconfirmed, so the sign-in pull merges the
  /// account's copy with the local one and pushes the union, instead of
  /// replacing what was recorded offline.
  Future<void> prepare() async {
    for (final collection in _collections) {
      await _ledger.mark(collection);
    }
  }

  /// Pushes the collections that merge on pull rather than replace (their pull
  /// kept the local data, but nothing sends it up), then ends guest mode.
  Future<void> finish() async {
    await ProfileSettings().push(null);
    Hba1cSync().push((await Hba1cState.load()).entries);
    GoogleHealthSync().push((await GoogleHealthState.load()).archive);
    PulseSync().push((await const IntradayPulseStore().days()).toSet());
    await EventSync().sync(await CgmStore.open(), (_) {});
    await const GuestMode().leave();
  }
}
