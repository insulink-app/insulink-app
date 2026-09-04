import 'dart:developer' as developer;

import 'package:flutter/services.dart';

import '../profile/glucose/profile_glucose_state.dart';
import '../theme/glucose_colors.dart';

/// Pushes the latest reading to the Android home-screen widget.
///
/// The formatting, the unit and the target-range colour are resolved HERE, so
/// the native side only draws what it is handed and the widget can never
/// disagree with the app about what counts as in range.
class HomeWidgetGlucose {
  static const _channel = MethodChannel('insulink/glucose_widget');

  /// Draw [mgdl] on the home-screen widget, in [profile]'s unit and target
  /// colour, with [arrow] as the trend glyph.
  ///
  /// Best-effort: a platform error (no widget placed, channel missing, iOS)
  /// is logged and swallowed. A reading must never fail over its own display.
  Future<void> publish({
    required ProfileGlucoseState profile,
    required int mgdl,
    required String arrow,
  }) async {
    try {
      await _channel.invokeMethod<void>('publish', {
        'value': profile.format(mgdl),
        'unit': profile.unit.label,
        'arrow': arrow,
        'color': GlucoseColors.standard.forValue(mgdl, profile).toARGB32(),
        'time': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (error) {
      developer.log('home widget push failed: $error', name: 'Insulink');
    }
  }
}
