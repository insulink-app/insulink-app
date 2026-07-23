/// Rate limit for the pulls a page fires when it is OPENED.
///
/// The shell rebuilds a tab body from scratch on every tab switch, so its
/// `initState` pull ran on every single visit — six round trips for Sport — and
/// the answers landing a second later re-decoded every collection, rewrote the
/// stores and rebuilt the page. That burst is the hitch that shows up shortly
/// after a tab switch, on a page that was scrolling smoothly until then.
///
/// The account does not change that fast, and nothing here is the only path to
/// fresh data: cold start still pulls everything (`AccountSync`), and
/// pull-to-refresh deliberately does NOT go through this gate.
///
/// A failed pull still counts as a run — every pull is best-effort and leaves
/// the local data in place, so the cost of waiting for the next window is a page
/// showing what it already showed.
class PullThrottle {
  const PullThrottle(this.key, {this.interval = const Duration(minutes: 1)});

  /// Last run per key, at module scope so it outlives the page that started it —
  /// which is the whole point, since the page is destroyed on the way out.
  static final Map<String, DateTime> _lastRun = {};

  final String key;
  final Duration interval;

  /// Runs [pull] unless it already ran within [interval]. The stamp is taken
  /// BEFORE the pull, so two opens in quick succession cannot both fire it.
  Future<void> run(Future<void> Function() pull) async {
    final last = _lastRun[key];
    final now = DateTime.now();
    if (last != null && now.difference(last) < interval) {
      return;
    }
    _lastRun[key] = now;
    await pull();
  }

  /// Forgets the last run, so the next [run] pulls again. For tests and for a
  /// path that must invalidate what was just fetched.
  void reset() => _lastRun.remove(key);
}
