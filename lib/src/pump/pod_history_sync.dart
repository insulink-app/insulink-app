import 'dart:convert';

import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/request/response_json.dart';

/// Mirrors the pod's delivery log and its contact log to the account, so what
/// the pump put out and when it was reachable outlive the phone: the delivery
/// log is wiped with every pod and the contact log keeps about two days.
///
/// Each push sends the whole local log and the account merges by time, so a
/// repeat is harmless, and a log unchanged since its last accepted push is not
/// sent at all. Best-effort: a failed push is retried on the next pod poll.
///
/// The loop's micro boluses ride along (kind `microBolus`), so the account
/// keeps bolus, micro bolus and basal apart and the pump's list can be rebuilt
/// after a reinstall ([PodAccountHistory]).
///
/// The delivery log is a record of the PUMP, never an insulin source. Boluses
/// reach insulin on board and the forecast as meal records, basal through
/// [InsulinSync]; reading this back as insulin would count every dose twice.
class PodHistorySync {
  String? _pushedDeliveries;
  String? _pushedContacts;

  Future<void> push(PodStore store) async {
    _pushedDeliveries = await _pushChanged(
      '/insulin/delivery/sync/',
      {
        'deliveries': deliveryEntries(
          [...store.deliveryLog, ...store.loopMicroBoluses],
          store.unconfirmedBoluses,
        ),
      },
      _pushedDeliveries,
    );
    _pushedContacts = await _pushChanged(
      '/pump/contact/sync/',
      {'contacts': contactTimes(store.contactMinutes)},
      _pushedContacts,
    );
  }

  /// Sends [body] unless it is what the account last accepted, and returns what
  /// the account holds now: the new body once accepted, [pushed] otherwise.
  Future<String?> _pushChanged(
    String url,
    Map<String, Object> body,
    String? pushed,
  ) async {
    final encoded = jsonEncode(body);
    if (encoded == pushed) {
      return pushed;
    }
    final response = await Request.post(url: url, body: body).send(null);
    return response.isApiSuccess ? encoded : pushed;
  }

  /// The wire entries: confirmed deliveries, then the boluses the pod never
  /// named back (they may or may not have run).
  List<Map<String, Object>> deliveryEntries(
    List<PodDelivery> delivered,
    List<PodDelivery> unconfirmed,
  ) => [
    for (final delivery in delivered) _entry(delivery, confirmed: true),
    for (final delivery in unconfirmed) _entry(delivery, confirmed: false),
  ];

  Map<String, Object> _entry(PodDelivery delivery, {required bool confirmed}) =>
      {
        'at': delivery.at.millisecondsSinceEpoch,
        'kind': delivery.kind.name,
        'source': delivery.source?.name ?? '',
        'units': delivery.units,
        'confirmed': confirmed,
      };

  /// Contact minutes as the epoch ms every timestamp on the wire is.
  List<int> contactTimes(List<int> minutes) => [
    for (final minute in minutes) minute * Duration.millisecondsPerMinute,
  ];
}
