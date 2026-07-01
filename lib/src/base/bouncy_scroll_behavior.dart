import 'package:flutter/material.dart';

/// App-wide scroll behavior: iOS-style overscroll (bounce) on ALL platforms and
/// for every scrollable surface — instead of equipping each page individually
/// with `physics:`.
class BouncyScrollBehavior extends MaterialScrollBehavior {
  const BouncyScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics();
}
