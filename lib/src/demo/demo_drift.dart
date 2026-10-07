import 'dart:math';

/// How far the demo sensor wanders off the demo curve. Each step keeps most of
/// the previous step's direction, so consecutive five-minute readings move
/// smoothly like a real CGM's instead of zigzagging around the curve (fresh
/// noise on every reading made the line look sampled far more often).
class DemoDrift {
  DemoDrift(this.random);

  final Random random;

  /// How much of the last step's direction carries over.
  static const double carry = 0.85;

  /// The largest new push per step, in mg/dL.
  static const double push = 1.2;

  /// Pulls the offset back towards the curve, so it never runs away.
  static const double pull = 0.97;

  double _velocity = 0;
  double _value = 0;

  /// The current offset from the curve, in mg/dL.
  double get value => _value;

  /// Advances one reading and returns how much the offset changed.
  double step() {
    _velocity = _velocity * carry + (random.nextDouble() - 0.5) * push;
    final next = (_value + _velocity) * pull;
    final change = next - _value;
    _value = next;
    return change;
  }
}
