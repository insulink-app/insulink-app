import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';

/// The server's model subscription has used up its usage for now, so the photo
/// was not analysed (`insulink-api` `docs/MEAL_PHOTO_ESTIMATE.md`, error 1605).
/// [resetsAt] is when it frees up again, null when the server did not know.
class PhotoEstimateLimit implements Exception {
  const PhotoEstimateLimit(this.resetsAt);

  /// The API's error code for a usage limit.
  static const int code = 1605;

  final DateTime? resetsAt;

  /// Reads the reset from the error reply (`resets_at`, epoch ms).
  factory PhotoEstimateLimit.fromJson(Map<String, dynamic>? json) {
    final resetsAt = json?['resets_at'];
    return PhotoEstimateLimit(
      resetsAt is int ? DateTime.fromMillisecondsSinceEpoch(resetsAt) : null,
    );
  }

  /// When it is usable again and how long that is from now, or that this is
  /// unknown.
  String resetText(BuildContext context) {
    final at = resetsAt;
    if (at == null) {
      return Locales.string(context, 'injection.photo.limit_unknown');
    }
    return Locales.string(
      context,
      'injection.photo.limit_reset',
      params: [_moment(context, at), _wait(context, at)],
    );
  }

  /// The clock time, with the date in front when it is not today.
  String _moment(BuildContext context, DateTime at) {
    final materialLocale = MaterialLocalizations.of(context);
    final clock = materialLocale.formatTimeOfDay(
      TimeOfDay.fromDateTime(at),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    if (DateUtils.isSameDay(at, DateTime.now())) {
      return clock;
    }
    return '${materialLocale.formatShortDate(at)}, $clock';
  }

  /// The time left, in whole hours and minutes, rounded up to the minute.
  String _wait(BuildContext context, DateTime at) {
    final seconds = at.difference(DateTime.now()).inSeconds.clamp(0, 1 << 31);
    final minutes = (seconds + 59) ~/ 60;
    return Locales.string(
      context,
      'injection.photo.limit_wait',
      params: ['${minutes ~/ 60}', '${minutes % 60}'],
    );
  }
}
