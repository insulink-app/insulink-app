import 'package:flutter/material.dart';

/// App-weites Scroll-Verhalten: iOS-artiges Überziehen (Bounce) auf ALLEN
/// Plattformen und für jede scrollbare Fläche — statt jede Seite einzeln mit
/// `physics:` zu bestücken.
class BouncyScrollBehavior extends MaterialScrollBehavior {
  const BouncyScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics();
}
