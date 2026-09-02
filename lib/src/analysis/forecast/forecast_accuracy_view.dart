import 'package:flutter/material.dart';
import 'package:insulink/src/analysis/analysis_segment.dart';
import 'package:insulink/src/analysis/averages/glucose_summary.dart';
import 'package:insulink/src/analysis/forecast/forecast_accuracy.dart';
import 'package:insulink/src/analysis/forecast/forecast_accuracy_chart.dart';
import 'package:insulink/src/analysis/forecast/forecast_backtest.dart';
import 'package:insulink/src/analysis/stat_tiles.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// "Forecast": how well the model's own predictions matched what the sensor
/// went on to read, scored on this device.
///
/// The backend replays the user's model over its stored history; the readings it
/// is judged against never leave the phone. Both horizons are offered because
/// the ROADMAP scores them separately — a model can earn its place at 30 minutes
/// and lose it at 60.
class ForecastAccuracyView extends StatefulWidget {
  const ForecastAccuracyView({super.key});

  @override
  State<ForecastAccuracyView> createState() => _ForecastAccuracyViewState();
}

class _ForecastAccuracyViewState extends State<ForecastAccuracyView> {
  static const List<int> _horizons = [30, 60];

  int _horizon = 30;
  bool _loading = true;
  ForecastBacktest? _backtest;

  /// The window the running fetch was started for, so a rebuild carrying the
  /// same analysis range does not re-ask the backend for the same replay.
  Object? _window;

  /// Counts the fetches, so a slow answer for a window the user has already
  /// left is dropped instead of overwriting the newer one.
  int _request = 0;

  /// The range selector above this view drives every analysis, so the scored
  /// window follows it. The dependency is registered by the watch in [build];
  /// the fields are set without setState because this runs during the build.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<CgmController>();
    final window = (
      controller.statsPreset,
      controller.statsCustomFrom,
      controller.statsCustomTo,
    );
    if (window == _window) {
      return;
    }
    _window = window;
    _loading = true;
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    final range = context.read<CgmController>().statsRange;
    final backtest = await ForecastBacktestFetcher().fetch(
      _horizon,
      from: range.from,
      to: range.to,
    );
    if (!mounted || request != _request) {
      return;
    }
    setState(() {
      _backtest = backtest;
      _loading = false;
    });
  }

  void _select(int horizon) {
    if (horizon == _horizon) {
      return;
    }
    setState(() {
      _horizon = horizon;
      _loading = true;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final glucose = context.watch<ProfileGlucoseState>();
    final archive = context.watch<CgmController>().statsArchive;
    final backtest = _backtest;
    final score = backtest == null
        ? null
        : ForecastAccuracy(backtest: backtest, archive: archive).build();
    return Column(
      children: [
        _selector(context),
        Expanded(child: _content(context, score, glucose)),
      ],
    );
  }

  Widget _selector(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          for (final horizon in _horizons)
            Expanded(
              child: AnalysisSegment(
                selected: horizon == _horizon,
                onTap: () => _select(horizon),
                child: Text(
                  Locales.string(
                    context,
                    'analysis.forecast.horizon',
                  ).replaceFirst('#', '$horizon'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _content(
    BuildContext context,
    ForecastScore? score,
    ProfileGlucoseState glucose,
  ) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    // Two different nothings, and the difference is the whole answer to "why is
    // this blank": the backend had no past forecasts to give (no model trained
    // yet, or it is not reachable), or it gave some and none of them has a
    // reading on this device to be judged against.
    if (_backtest == null) {
      return const EmptyState(
        icon: PhosphorIconsBold.chartLineUp,
        titleKey: 'analysis.forecast.empty',
        subtitleKey: 'analysis.forecast.empty_hint',
      );
    }
    if (score == null) {
      return const EmptyState(
        icon: PhosphorIconsBold.chartLineUp,
        titleKey: 'analysis.forecast.unmatched',
        subtitleKey: 'analysis.forecast.unmatched_hint',
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnalysisStatTiles(stats: _stats(score, glucose)),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: ForecastAccuracyChart(
                  outcomes: score.outcomes,
                  glucose: glucose,
                ),
              ),
              const SizedBox(height: 16),
              _hint(context),
            ],
          ),
        ),
      ),
    );
  }

  /// The skill score leads: it is the one number that says whether the model
  /// beat "glucose stays where it is", which is what the errors below it are
  /// measured against.
  List<GlucoseStat> _stats(ForecastScore score, ProfileGlucoseState glucose) {
    final unit = glucose.unit.label;
    final coverage = score.bandCoverage;
    return [
      GlucoseStat(
        'analysis.forecast.skill',
        score.skillScore.toStringAsFixed(2),
        '',
      ),
      GlucoseStat(
        'analysis.forecast.matched',
        '${score.matched}',
        Locales.string(context, 'analysis.forecast.points'),
      ),
      GlucoseStat(
        'analysis.forecast.mae',
        glucose.format(score.meanAbsoluteError.round()),
        unit,
      ),
      GlucoseStat(
        'analysis.forecast.rmse',
        glucose.format(score.rootMeanSquareError.round()),
        unit,
      ),
      GlucoseStat(
        'analysis.forecast.persistence',
        glucose.format(score.persistenceRootMeanSquareError.round()),
        unit,
      ),
      if (coverage != null)
        GlucoseStat(
          'analysis.forecast.coverage',
          (coverage * 100).toStringAsFixed(0),
          '%',
        ),
    ];
  }

  Widget _hint(BuildContext context) {
    return LocaleText(
      'analysis.forecast.hint',
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      ),
    );
  }
}
