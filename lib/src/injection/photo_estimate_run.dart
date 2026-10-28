import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:insulink/src/injection/photo_estimate.dart';
import 'package:insulink/src/request/request.dart';

/// One estimate of a meal photo that the user can call off: by taking a new
/// photo or by leaving the camera, the close button and the back gesture alike
/// (`insulink-api` `docs/MEAL_PHOTO_ESTIMATE.md`, Cancelling).
///
/// Dropping the request alone would leave the model running on the server,
/// spending tokens on an answer nobody reads, so [cancel] also tells the server
/// to stop this run, by the id the request carried.
class PhotoEstimateRun {
  /// Unique per user: no two photos are taken in the same microsecond.
  final String id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final _abort = Completer<void>();
  bool _answered = false;

  bool get cancelled => _abort.isCompleted;

  /// The estimate of [jpeg], or null when it failed or was called off.
  Future<PhotoEstimate?> result(BuildContext context, Uint8List jpeg) async {
    final estimate = await PhotoEstimate.request(
      context,
      jpeg,
      runId: id,
      abortTrigger: _abort.future,
    );
    _answered = true;
    return cancelled ? null : estimate;
  }

  /// Drops the upload or the wait and stops the server's run. Does nothing once
  /// the answer is in or the run is already called off.
  void cancel() {
    if (_answered || cancelled) {
      return;
    }
    _abort.complete();
    Request.post(
      url: '/nutrition/estimate/cancel/',
      body: {'run_id': id},
    ).send(null).ignore();
  }
}
