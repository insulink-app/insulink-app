import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:insulink/src/google_health/google_health_models.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/request/request.dart';

/// Mirrors the Google Health day archive (resting HR, sleep + stages, blood
/// oxygen, hypnogram) to the user's backend account and pulls it back on sign-in,
/// like [SportSync]. [push] debounces a best-effort replace-all of the whole
/// archive (null context — the app always holds the complete list, so replace-all
/// keeps it correct); [pull] runs in the UI isolate on sign-in and merges the
/// account's days into local storage before the provider reloads.
class GoogleHealthSync {
  static Timer? _timer;

  void push(List<GoogleHealthDay> archive) {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), () => _send(archive));
  }

  Future<void> _send(List<GoogleHealthDay> archive) async {
    await Request.post(
      url: '/health/days/sync/',
      body: {'days': [for (final day in archive) day.toJson()]},
    ).send(null);
  }

  /// Adopts the account's health days into local storage on sign-in. Merged, not
  /// clobbered, so the connected flag and any locally-newer days survive.
  Future<void> pull(BuildContext context) async {
    final response = await Request.get(url: '/health/days/find/').send(context);
    if (response == null) {
      return;
    }
    final body = jsonDecode(response.body);
    if (body['success'] != true || body['days'] is! List) {
      return;
    }
    await GoogleHealthState.mergePersisted([
      for (final day in body['days'] as List)
        GoogleHealthDay.fromJson((day as Map).cast()),
    ]);
  }
}
