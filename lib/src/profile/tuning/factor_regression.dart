import 'dart:math';

import 'package:insulink/src/profile/tuning/tuning_dose.dart';

/// Pulls the correction factor out of ordinary MEAL windows.
///
/// A single meal window cannot say what one unit does: its glucose movement is
/// the sum of the food and the insulin, one equation with two unknowns, and any
/// correction factor fits it if the carbohydrate factor moves to match. That is
/// why the direct measurement needs a dose with no food of its own.
///
/// Many windows together are a different question. Across them,
///
/// ```
/// drift = base + perGram * carbsAbsorbed - perUnit * insulinActing
/// ```
///
/// is three unknowns and one equation PER WINDOW, so it can be solved by least
/// squares. `perUnit` is the correction factor and `perGram / perUnit` the
/// carbohydrate factor. What makes it work on real data is that a meal bolus is
/// not a pure function of the carbohydrates: it carries a correction for
/// whatever glucose was at the time, it gets rounded, and the food is counted
/// imperfectly. That variation is what separates the two.
///
/// Where the variation is absent, so is the answer: somebody who always doses
/// exactly `carbs / carbFactor` gives two columns that are multiples of each
/// other and the fit is meaningless. That case is not guessed at, it is refused,
/// and [maxRelativeError] is what refuses it: collinear columns inflate the
/// standard error of `perUnit`, so one guard covers both "too few windows to be
/// sure" and "these windows cannot tell the two apart".
///
/// ponytail: plain least squares on three parameters, no weighting and no robust
/// loss. Ceiling: one badly mislogged meal pulls the fit, where the median used
/// everywhere else would shrug it off. The standard-error guard is what keeps
/// that from reaching the user, and the 20 % cap bounds what it could do if it
/// ever did. Upgrade path if it proves too jumpy: iteratively reweighted least
/// squares.
class CorrectionFactorFit {
  const CorrectionFactorFit(this.windows);

  final List<TuningDose> windows;

  /// Windows needed before a fit is attempted. Well above the five a median
  /// needs: three parameters have to be pinned rather than one, and the whole
  /// point is to separate two columns that mostly move together.
  static const int minWindows = 20;

  /// How uncertain the answer may be, as a fraction of itself. A quarter is
  /// generous for a suggestion nobody applies automatically, and it is what
  /// rejects a log where the insulin only ever follows the carbohydrates.
  static const double maxRelativeError = 0.25;

  /// mg/dL that one unit lowered, or null when these windows cannot say.
  double? get mgdlPerUnit {
    final usable = windows
        .where((window) => !window.isCorrection && window.insulinActing > 0)
        .toList();
    if (usable.length < minWindows) {
      return null;
    }
    final fit = _solve(usable);
    if (fit == null) {
      return null;
    }
    final perUnit = -fit.slopes[2];
    if (perUnit <= 0 ||
        fit.standardErrorOfInsulin > perUnit * maxRelativeError) {
      return null;
    }
    return perUnit;
  }

  /// How many windows the answer rests on, for the card to show.
  int get samples => windows
      .where((window) => !window.isCorrection && window.insulinActing > 0)
      .length;

  /// Least squares on `[1, carbs, insulin]`, with the uncertainty of the insulin
  /// coefficient, which is the whole reason the normal equations are solved by
  /// hand rather than reduced to two sums.
  _Fit? _solve(List<TuningDose> usable) {
    final rows = [
      for (final window in usable)
        [1.0, window.carbsAbsorbed, window.insulinActing],
    ];
    final drifts = [for (final window in usable) window.drift.toDouble()];
    final normal = _multiplyTransposed(rows, rows);
    final projected = _multiplyTransposedBy(rows, drifts);
    final inverse = _invert(normal);
    if (inverse == null) {
      return null;
    }
    final slopes = _apply(inverse, projected);
    var residualSquares = 0.0;
    for (var row = 0; row < rows.length; row++) {
      final predicted =
          slopes[0] * rows[row][0] +
          slopes[1] * rows[row][1] +
          slopes[2] * rows[row][2];
      residualSquares += pow(drifts[row] - predicted, 2);
    }
    final variance = residualSquares / (rows.length - 3);
    return _Fit(
      slopes: slopes,
      standardErrorOfInsulin: sqrt(max(variance * inverse[2][2], 0)),
    );
  }

  List<List<double>> _multiplyTransposed(
    List<List<double>> left,
    List<List<double>> right,
  ) {
    final out = List.generate(3, (_) => List<double>.filled(3, 0));
    for (var row = 0; row < left.length; row++) {
      for (var first = 0; first < 3; first++) {
        for (var second = 0; second < 3; second++) {
          out[first][second] += left[row][first] * right[row][second];
        }
      }
    }
    return out;
  }

  List<double> _multiplyTransposedBy(
    List<List<double>> left,
    List<double> right,
  ) {
    final out = List<double>.filled(3, 0);
    for (var row = 0; row < left.length; row++) {
      for (var column = 0; column < 3; column++) {
        out[column] += left[row][column] * right[row];
      }
    }
    return out;
  }

  List<double> _apply(List<List<double>> matrix, List<double> vector) => [
    for (var row = 0; row < 3; row++)
      matrix[row][0] * vector[0] +
          matrix[row][1] * vector[1] +
          matrix[row][2] * vector[2],
  ];

  /// The inverse of a symmetric 3 by 3, or null when it is singular, which is
  /// what perfectly proportional columns produce.
  List<List<double>>? _invert(List<List<double>> matrix) {
    final cofactors = List.generate(3, (_) => List<double>.filled(3, 0));
    for (var row = 0; row < 3; row++) {
      for (var column = 0; column < 3; column++) {
        cofactors[row][column] = _cofactor(matrix, row, column);
      }
    }
    final determinant =
        matrix[0][0] * cofactors[0][0] +
        matrix[0][1] * cofactors[0][1] +
        matrix[0][2] * cofactors[0][2];
    if (determinant.abs() < 1e-9 || !determinant.isFinite) {
      return null;
    }
    return [
      for (var row = 0; row < 3; row++)
        [
          for (var column = 0; column < 3; column++)
            cofactors[column][row] / determinant,
        ],
    ];
  }

  double _cofactor(List<List<double>> matrix, int row, int column) {
    final rows = [0, 1, 2]..remove(row);
    final columns = [0, 1, 2]..remove(column);
    final minor =
        matrix[rows[0]][columns[0]] * matrix[rows[1]][columns[1]] -
        matrix[rows[0]][columns[1]] * matrix[rows[1]][columns[0]];
    return (row + column).isEven ? minor : -minor;
  }
}

class _Fit {
  const _Fit({required this.slopes, required this.standardErrorOfInsulin});

  /// `[base, mg/dL per gram, mg/dL per unit]`. The last is negative: insulin
  /// lowers glucose.
  final List<double> slopes;

  final double standardErrorOfInsulin;
}
