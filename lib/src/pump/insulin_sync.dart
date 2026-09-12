import 'package:http/http.dart' show Response;
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/request/response_json.dart';

/// Pushes pod basal deliveries to the account, where the forecasting sidecar
/// reads them.
///
/// Append-only, unlike the replace-all syncs: each sample is a measurement of a
/// window that has passed and can never be revised, so there is nothing to
/// replace. Samples are dropped locally only once the account has accepted them —
/// the service polls the pod whether or not the phone has a connection, and a lost
/// sample is a hole in the insulin history that nothing later can fill.
///
/// Boluses are NOT sent here. They already reach the account as meal records, and
/// sending them again would have the model count every dose twice.
class InsulinSync {
  /// The most samples to offer in one request, so a queue that built up while
  /// offline is drained in bounded chunks rather than one huge body.
  static const int batchSize = 50;

  Future<void> push(PodStore store) async {
    final pending = store.pendingBasalDeliveries;
    if (pending.isEmpty) {
      return;
    }
    final batch = pending.take(batchSize).toList();
    final response = await Request.post(
      url: '/insulin/basal/sync/',
      body: {'deliveries': batch},
    ).send(null);
    if (_isSuccess(response)) {
      await store.clearBasalDeliveries(batch.length);
    }
  }

  bool _isSuccess(Response? response) {
    if (response == null) {
      return false;
    }
    try {
      return response.isApiSuccess;
    } catch (_) {
      return false;
    }
  }
}
