/// The Android `STEP_COUNTER` reports a cumulative total that increases
/// monotonically since boot. "Steps today" = current value minus the value at
/// the start of the day. [StepBaseline] holds this reference point (date +
/// counter) and resets it when the day changes or the counter drops (reboot ⇒
/// counter restarts at 0). Pure logic, no plugin — testable.
class StepBaseline {
  final String date;
  final int counter;

  const StepBaseline({required this.date, required this.counter});

  /// Applies the current cumulative [counter], read on day [today]. Returns the
  /// (possibly reset) reference point and today's steps.
  ({StepBaseline baseline, int today}) update(String today, int counter) {
    if (date != today || counter < this.counter) {
      return (baseline: StepBaseline(date: today, counter: counter), today: 0);
    }
    return (baseline: this, today: counter - this.counter);
  }
}
