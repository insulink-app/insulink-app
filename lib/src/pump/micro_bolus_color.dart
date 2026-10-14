import 'package:flutter/material.dart';
import 'package:insulink/src/injection/active_insulin_chart.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The colour a micro bolus is drawn in on the pump's delivery page: the bolus
/// colour, lighter, because it is a bolus nobody chose. One definition, so the
/// rows and the total under the bar cannot drift apart.
extension MicroBolusColor on InsulinkColors {
  Color get microBolus =>
      pace.withValues(alpha: ActiveInsulinChart.microBolusTint);
}
