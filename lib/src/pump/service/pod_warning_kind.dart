/// The pod warnings [PodAlarmManager] can raise, each with the notification id
/// it occupies (kept clear of the CGM manager's 0–104) and whether it means
/// insulin is no longer arriving. The overview reads both: the id to tell its
/// notifications apart, the severity to colour them.
enum PodWarningKind {
  expiry(110),
  expired(111, critical: true),
  reservoir(112),
  alarm(113, critical: true),
  unreachable(114),
  stopped(115, critical: true),
  loopStopped(116);

  const PodWarningKind(this.id, {this.critical = false});

  final int id;

  /// Whether delivery has stopped or is about to, rather than something to
  /// keep an eye on.
  final bool critical;
}
