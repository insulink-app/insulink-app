import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/g7/g7_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/profile_developer_state.dart';
import 'package:insulink/src/profile/profile_glucose_state.dart';
import 'package:insulink/src/sensor/sensor_info.dart';
import 'package:provider/provider.dart';

class SensorBody extends AppPageBody {
  SensorBody({super.key})
    : super(
        name: "sensor.label",
        unselectedIcon: CupertinoIcons.drop,
        selectedIcon: CupertinoIcons.drop_fill,
      );

  @override
  Widget content(BuildContext context) {
    return const SensorBodyContent();
  }

  @override
  Future<int> notifications(BuildContext context) async {
    final g7 = Provider.of<G7Controller>(context, listen: false);
    // -1 renders as a small red dot in the navigator (see
    // AppNavigator.createNotificationBadge) — shown while no sensor is set up.
    return g7.hasSensor ? 0 : -1;
  }
}

class SensorBodyContent extends StatefulWidget {
  const SensorBodyContent({super.key});

  @override
  State<SensorBodyContent> createState() => _SensorBodyContentState();
}

class _SensorBodyContentState extends State<SensorBodyContent> {
  /// Drives the gradual fade of the connection box as the attribute list is
  /// scrolled. The box reaches full transparency after [_fadeDistance] px.
  final ScrollController _scroll = ScrollController();
  static const double _fadeDistance = 80;

  /// Gap between the pinned box and the scrolling content. Kept larger than
  /// [_fadeDistance] so the box has fully faded out before the content scrolls
  /// up into its place (no overlap).
  static const double _gap = 80;

  /// The pinned box is overlaid on top of the scroll view; its measured height
  /// is used to push the content below it so nothing starts hidden.
  final GlobalKey _boxKey = GlobalKey();
  double _boxHeight = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Read the box's rendered height after layout and reserve that much space
  /// above the scrolling content. Runs each frame but only rebuilds on change.
  void _measureBox() {
    final h = _boxKey.currentContext?.size?.height;
    if (h != null && h != _boxHeight) {
      setState(() => _boxHeight = h);
    }
  }

  /// Snap to one of two resting positions once the user lets go: fully showing
  /// the box (offset 0) or fully scrolled past it (box gone, content at top).
  /// Crossing [_fadeDistance] commits to the collapsed position for a snappy
  /// feel instead of leaving the box half-faded.
  bool _snapScroll() {
    if (!_scroll.hasClients) return false;
    final snapTarget = (_boxHeight + _gap).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    if (snapTarget <= 0) return false;
    final offset = _scroll.offset;
    // Only act between the two anchors; never fight the user mid-list.
    if (offset >= snapTarget) return false;
    final target = offset >= _fadeDistance ? snapTarget : 0.0;
    if ((offset - target).abs() < 1) return false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
    return false;
  }

  /// Copy the whole log (chronological) to the clipboard and confirm via a
  /// snackbar.
  Future<void> _copyLog(BuildContext context, G7Controller g7) async {
    final message = Locales.string(
      context,
      'sensor.log_copied',
      params: ['${g7.log.length}'],
    );
    await Clipboard.setData(ClipboardData(text: g7.logText));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final g7 = context.watch<G7Controller>();
    final showLog = context.watch<ProfileDeveloperState>().enabled;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureBox());
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The connection box stays pinned at the top, the attribute list
            // scrolls underneath it. As you scroll, the box fades out to free
            // up the room it occupies.
            Expanded(
              child: Stack(
                children: [
                  // Scrolling content, pushed below the pinned box.
                  Positioned.fill(
                    child: NotificationListener<ScrollEndNotification>(
                      onNotification: (_) => _snapScroll(),
                      child: SingleChildScrollView(
                        controller: _scroll,
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: _boxHeight > 0 ? _boxHeight + _gap : 0,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              LocaleText(
                                'sensor.info.title',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SensorInfo(
                                info: g7.info,
                                sensorStart: g7.sensorStart,
                                state: g7.latest?.state,
                                age: g7.latest?.secsSinceStart,
                                lastUpdate: g7.lastUpdate,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Pinned connection box that fades as you scroll.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: AnimatedBuilder(
                      animation: _scroll,
                      builder: (context, child) {
                        final offset = _scroll.hasClients
                            ? _scroll.offset
                            : 0.0;
                        final opacity = (1 - offset / _fadeDistance).clamp(
                          0.0,
                          1.0,
                        );
                        // Once mostly faded, let touches reach the content below.
                        return IgnorePointer(
                          ignoring: opacity < 0.5,
                          child: Opacity(opacity: opacity, child: child),
                        );
                      },
                      child: _ControlBox(key: _boxKey, g7: g7),
                    ),
                  ),
                ],
              ),
            ),
            // Connection log — developer mode only.
            if (showLog) _LogPanel(g7: g7, onCopy: () => _copyLog(context, g7)),
          ],
        ),
      ),
    );
  }
}

/// Top-of-page controls: end the current reading session, or fully forget the
/// sensor. Both are guarded by a confirmation dialog so they can't fire by
/// accident.
class _ControlBox extends StatelessWidget {
  const _ControlBox({super.key, required this.g7});

  final G7Controller g7;

  Future<bool> _confirm(
    BuildContext context, {
    required String titleKey,
    required String bodyKey,
    required String confirmKey,
    bool destructive = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Locales.string(ctx, titleKey)),
        content: Text(Locales.string(ctx, bodyKey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Locales.string(ctx, 'alert.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: destructive
                ? TextButton.styleFrom(foregroundColor: Colors.redAccent)
                : null,
            child: Text(Locales.string(ctx, confirmKey)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final connected = g7.connected;
    final busy = g7.busy;
    final hasReading = g7.currentMgdl != null;
    // Pairing code entered + service running, but no reading has arrived yet.
    final searching = (connected || busy) && !hasReading;
    // Never paired and nothing running yet → offer the pairing form.
    final unpaired = !g7.hasSensor && !connected && !busy;

    return unpaired
        ? _pairingForm(context, scheme)
        : _statusBox(context, scheme, searching: searching);
  }

  /// Box shown when no sensor is set up yet: enter the pairing code + connect.
  Widget _pairingForm(BuildContext context, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary.withValues(alpha: 0.15),
                ),
                child: Icon(
                  CupertinoIcons.drop,
                  size: 32,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LocaleText(
                      'sensor.pair.title',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    LocaleText(
                      'sensor.pair.hint',
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: g7.code,
            decoration: InputDecoration(
              labelText: Locales.string(context, 'overview.pairing_code'),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: g7.busy ? null : g7.start,
            icon: const Icon(Icons.bluetooth_searching, size: 20),
            label: LocaleText(
              g7.busy ? 'overview.connecting' : 'overview.connect',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
          ),
        ],
      ),
    );
  }

  /// Box shown once paired: connection status + session controls. While
  /// [searching] (connected but no reading yet) the header shows a spinner.
  Widget _statusBox(
    BuildContext context,
    ColorScheme scheme, {
    required bool searching,
  }) {
    final connected = g7.connected;
    final accent = (connected || searching) ? scheme.primary : Colors.grey;

    final Widget subtitle;
    if (searching) {
      subtitle = LocaleText(
        'sensor.searching.hint',
        style: TextStyle(fontSize: 13, color: Colors.grey[500]),
      );
    } else if (connected && g7.currentMgdl != null) {
      subtitle = Text(
        context.watch<ProfileGlucoseState>().formatWithUnit(g7.currentMgdl!),
        style: TextStyle(fontSize: 13, color: Colors.grey[500]),
      );
    } else {
      subtitle = LocaleText(
        g7.hasSensor ? 'sensor.status.paired' : 'sensor.status.unpaired',
        style: TextStyle(fontSize: 13, color: Colors.grey[500]),
      );
    }

    final String titleKey = searching
        ? 'sensor.status.searching'
        : connected
        ? 'sensor.status.connected'
        : 'sensor.status.disconnected';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Larger status display icon (spinner while searching).
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.15),
                ),
                child: searching
                    ? Padding(
                        padding: const EdgeInsets.all(15),
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: accent,
                        ),
                      )
                    : Icon(
                        connected
                            ? CupertinoIcons.dot_radiowaves_left_right
                            : CupertinoIcons.drop,
                        size: 32,
                        color: accent,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LocaleText(
                      titleKey,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    subtitle,
                  ],
                ),
              ),
            ],
          ),
          if (g7.sensorStart != null) ...[
            const SizedBox(height: 18),
            _SensorLifeBar(
              start: g7.sensorStart!,
              // The sensor's reported session length is best-effort metadata that
              // often hasn't arrived yet — fall back to maxLifetime, then to the
              // standard G7 lifetime (10 days + 12 h grace) so the bar still shows.
              sessionLengthSec:
                  g7.info.sessionLengthSec ??
                  (g7.info.maxLifetimeDays != null
                      ? g7.info.maxLifetimeDays! * 86400
                      : 907200),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: connected
                ? () async {
                    if (await _confirm(
                      context,
                      titleKey: 'sensor.control.end_session_title',
                      bodyKey: 'sensor.control.end_session_body',
                      confirmKey: 'sensor.control.end_session',
                    )) {
                      await g7.disconnect();
                    }
                  }
                : null,
            icon: const Icon(Icons.stop_circle_outlined, size: 20),
            label: LocaleText('sensor.control.end_session'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              backgroundColor: scheme.primary.withValues(alpha: 0.15),
              foregroundColor: scheme.primary,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: (connected || g7.hasSensor)
                ? () async {
                    if (await _confirm(
                      context,
                      titleKey: 'sensor.control.stop_sensor_title',
                      bodyKey: 'sensor.control.stop_sensor_body',
                      confirmKey: 'sensor.control.stop_sensor',
                      destructive: true,
                    )) {
                      await g7.forgetSensor();
                    }
                  }
                : null,
            icon: const Icon(Icons.link_off, size: 20),
            label: LocaleText('sensor.control.stop_sensor'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              minimumSize: const Size.fromHeight(46),
              side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sensor durability shown as one rectangle per day: the remaining days are
/// filled with the accent colour, elapsed days are greyed out.
class _SensorLifeBar extends StatelessWidget {
  const _SensorLifeBar({required this.start, required this.sessionLengthSec});

  final DateTime start;
  final int sessionLengthSec;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final totalDays = (sessionLengthSec / 86400).round().clamp(1, 30);
    final remainingSecs =
        sessionLengthSec - DateTime.now().difference(start).inSeconds;
    final expired = remainingSecs <= 0;
    // Round a partial remaining day UP so the current day still counts as left.
    final filled = (remainingSecs / 86400).ceil().clamp(0, totalDays);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            LocaleText(
              'sensor.life.title',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const Spacer(),
            Text(
              expired
                  ? Locales.string(context, 'sensor.value.expired')
                  : Locales.string(
                      context,
                      'sensor.life.remaining',
                      params: ['$filled'],
                    ),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: expired ? Colors.redAccent : scheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < totalDays; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: Container(
                  height: 9,
                  decoration: BoxDecoration(
                    color: i < filled
                        ? scheme.primary
                        : scheme.onSurface.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Scrollable connection log with a copy button. Shown only in developer mode.
class _LogPanel extends StatelessWidget {
  const _LogPanel({required this.g7, required this.onCopy});

  final G7Controller g7;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            LocaleText(
              'sensor.log',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
            const Spacer(),
            if (g7.log.isNotEmpty)
              TextButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy, size: 16),
                label: LocaleText('sensor.copy'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          height: 200,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(8),
          ),
          // SelectableText so individual lines can also be selected by hand;
          // the Kopieren button grabs the whole log at once. Scrollable
          // because SelectableText won't scroll on its own.
          child: SingleChildScrollView(
            child: SelectableText(
              g7.log.join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }
}
