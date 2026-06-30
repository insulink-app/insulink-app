/// Der Android-`STEP_COUNTER` liefert eine seit dem Boot monoton steigende
/// Gesamtzahl. „Schritte heute" = aktueller Stand minus dem Stand zu
/// Tagesbeginn. [StepBaseline] hält diesen Bezugspunkt (Datum + Zählerstand)
/// und setzt ihn zurück, wenn der Tag wechselt oder der Zähler kleiner wird
/// (Reboot ⇒ Zähler startet wieder bei 0). Reine Logik, ohne Plugin — testbar.
class StepBaseline {
  final String date;
  final int counter;

  const StepBaseline({required this.date, required this.counter});

  /// Wendet den aktuellen kumulativen [counter], gelesen am Tag [today], an.
  /// Gibt den (ggf. zurückgesetzten) Bezugspunkt und die heutigen Schritte zurück.
  ({StepBaseline baseline, int today}) update(String today, int counter) {
    if (date != today || counter < this.counter) {
      return (baseline: StepBaseline(date: today, counter: counter), today: 0);
    }
    return (baseline: this, today: counter - this.counter);
  }
}
