import 'package:flutter/foundation.dart';
import 'package:insulink/src/overview/chart/chart_x_axis.dart';

/// What the glucose chart and the insulin chart under it share so the pair reads
/// as one graph rather than two stacked ones.
///
/// The glucose chart owns the window and writes it here; the insulin chart
/// follows. Either can scrub, and both draw the result, so one finger produces
/// one readout across both. A pinch anywhere over the pair is forwarded back to
/// whoever owns the range through [onPinch], because the range lives with the
/// glucose chart's persistence and there is no reason to move it.
///
/// A `ChangeNotifier` rather than lifted state: the window changes on every pan
/// frame and the scrub on every pointer move, and rebuilding the page for each
/// would rebuild the glucose chart from inside its own reporting.
class ChartSync extends ChangeNotifier {
  /// The wall-clock stretch on screen, once the glucose chart has laid out.
  DateTime? from;
  DateTime? to;

  /// Where measured data stops and the forecast begins, which is not the end of
  /// the window: the window reaches past the last reading to show the forecast,
  /// and a chart of things that have HAPPENED has to stop here.
  DateTime? liveEdge;

  /// The labels for the shared axis, drawn under the lower chart.
  List<ChartTick> ticks = const [];

  /// Where the pointer is across the plot (0 = left edge, 1 = right), or null.
  double? scrub;

  bool _gesturing = false;

  /// Whether more than one finger is down over the pair.
  ///
  /// A pinch is not a scrub, and both charts were reading it as one: fl_chart
  /// keeps reporting touches through a two-finger gesture, so zooming on the
  /// glucose chart published a scrub and the insulin chart answered with a
  /// tooltip instead of zooming with it. While this is set nothing scrubs, and
  /// setting it drops whatever readout was on screen.
  bool get gesturing => _gesturing;

  set gesturing(bool value) {
    if (_gesturing == value) {
      return;
    }
    _gesturing = value;
    if (value) {
      scrub = null;
      scrubMirrored = false;
    }
    notifyListeners();
  }

  /// Whether the scrub came from the lower chart, so the upper one knows to
  /// mirror it instead of leaving its own touch handling to draw it twice.
  bool scrubMirrored = false;

  /// Applies a two-finger gesture measured over either chart. Registered by the
  /// chart that owns the range.
  void Function({
    required double scale,
    required double focalTravelX,
    required double plotWidth,
    required double focalFraction,
  })?
  onPinch;

  bool get hasWindow => from != null && to != null;

  /// How often a range was picked on the selector (not pinched), so both
  /// charts can cross-fade into the new window together.
  int rangeSwitches = 0;

  void noteRangeSwitch() {
    rangeSwitches++;
    notifyListeners();
  }

  /// Called after the frame by the chart that owns the window, never during a
  /// build.
  void reportWindow({
    required DateTime from,
    required DateTime to,
    required DateTime liveEdge,
    required List<ChartTick> ticks,
  }) {
    if (this.from == from && this.to == to && this.liveEdge == liveEdge) {
      this.ticks = ticks;
      return;
    }
    this.from = from;
    this.to = to;
    this.liveEdge = liveEdge;
    this.ticks = ticks;
    notifyListeners();
  }

  /// [mirrored] marks a scrub that came from the lower chart.
  ///
  /// Ignored entirely while [gesturing]: a finger that is half of a pinch is not
  /// pointing at anything.
  void setScrub(double? fraction, {bool mirrored = false}) {
    final wanted = _gesturing ? null : fraction;
    final wantedMirror = wanted == null ? false : mirrored;
    if (scrub == wanted && scrubMirrored == wantedMirror) {
      return;
    }
    scrub = wanted;
    scrubMirrored = wantedMirror;
    notifyListeners();
  }
}
