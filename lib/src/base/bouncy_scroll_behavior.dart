import 'package:flutter/material.dart';

/// App-wide scroll behavior: iOS-style overscroll (bounce) on ALL platforms and
/// for every scrollable surface — instead of equipping each page individually
/// with `physics:`.
///
/// No scrollbars anywhere. Material only adds them on desktop platforms, which
/// includes the browser demo on the website, where they drew a bar along the
/// edge of every list.
class BouncyScrollBehavior extends MaterialScrollBehavior {
  const BouncyScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
