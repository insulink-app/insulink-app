import 'package:flutter/widgets.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/request/response_json.dart';

/// Where the server's estimate of a meal photo is while it runs (`insulink-api`
/// `docs/MEAL_PHOTO_ESTIMATE.md`, Progress): looking at the photo, searching
/// the web for a product (the query as [detail]) or looking at one food (its
/// name as [detail]). Shown under "Analysing", so a long run visibly moves.
class PhotoEstimateStep {
  const PhotoEstimateStep({required this.step, required this.detail});

  /// The steps this app has words for; a newer server's other steps show none.
  static const _known = {'looking', 'searching', 'estimating'};

  final String step;
  final String detail;

  /// The step the user's running estimate is at. Null when none runs, the
  /// request failed, or the step is unknown.
  static Future<PhotoEstimateStep?> request(BuildContext context) async {
    final response = await Request.get(
      url: '/nutrition/estimate/progress/',
    ).send(context);
    final json = response?.jsonObject;
    final step = json?['step'];
    if (json == null || !response!.isApiSuccess || !_known.contains(step)) {
      return null;
    }
    return PhotoEstimateStep(
      step: step as String,
      detail: json['detail'] as String? ?? '',
    );
  }

  String get localeKey => 'injection.photo.step.$step';
}
