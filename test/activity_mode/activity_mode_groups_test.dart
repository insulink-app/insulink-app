import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/activity_mode/activity_mode_section.dart';
import 'package:insulink/src/activity_mode/activity_mode_settings.dart';

/// Every number of the activity mode shows on the page, under one heading.
void main() {
  test('the groups hold every setting exactly once', () {
    final grouped = [
      for (final group in ActivityModeSection.groups) ...group.settings,
    ];

    expect(grouped.toSet(), ActivityModeSettings.all.toSet());
    expect(grouped.length, ActivityModeSettings.all.length);
  });
}
