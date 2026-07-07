import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/cgm/cgm_connection.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/developer/profile_developer_state.dart';
import 'package:insulink/src/sensor/control/sensor_control_box.dart';
import 'package:insulink/src/sensor/info/libre3_sensor_info.dart';
import 'package:insulink/src/sensor/info/sensor_info.dart';
import 'package:insulink/src/sensor/sensor_log_panel.dart';
import 'package:provider/provider.dart';

/// The sensor device page, shown inside the Devices tab (see [DevicesBody]).
class SensorBodyContent extends StatefulWidget {
  const SensorBodyContent({super.key});

  @override
  State<SensorBodyContent> createState() => _SensorBodyContentState();
}

class _SensorBodyContentState extends State<SensorBodyContent> {
  /// Drives the gradual fade of the connection box as the attribute list is
  /// scrolled. The box reaches full transparency after [_fadeDistance] px — a
  /// longer distance than the scroll it tracks, so the fade feels gentle.
  final ScrollController _scroll = ScrollController();
  static const double _fadeDistance = 160;

  /// How far the box drifts upward as it fades, so it doesn't just dissolve in
  /// place but slides out of the way.
  static const double _riseDistance = 40;

  /// Gap between the pinned box and the scrolling content. Kept at least
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
    final height = _boxKey.currentContext?.size?.height;
    if (height != null && height != _boxHeight) {
      setState(() => _boxHeight = height);
    }
  }

  /// Snap to one of two resting positions once the user lets go: fully showing
  /// the box (offset 0) or fully scrolled past it (box gone, content at top).
  /// Crossing [_fadeDistance] commits to the collapsed position for a snappy
  /// feel instead of leaving the box half-faded.
  bool _snapScroll() {
    if (!_scroll.hasClients) {
      return false;
    }
    final snapTarget = (_boxHeight + _gap).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    final offset = _scroll.offset;
    if (snapTarget <= 0 || offset >= snapTarget) {
      return false;
    }
    final target = offset >= _fadeDistance ? snapTarget : 0.0;
    if ((offset - target).abs() >= 1) {
      _animateTo(target);
    }
    return false;
  }

  void _animateTo(double target) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Copy the whole log (chronological) to the clipboard and confirm via a
  /// snackbar.
  Future<void> _copyLog(BuildContext context, CgmController controller) async {
    final message = Locales.string(
      context,
      'sensor.log_copied',
      params: ['${controller.log.length}'],
    );
    await Clipboard.setData(ClipboardData(text: controller.logText));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CgmController>();
    final showLog = context.watch<ProfileDeveloperState>().enabled;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureBox());
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _pinnedScrollArea(controller)),
            if (showLog)
              SensorLogPanel(
                controller: controller,
                onCopy: () => _copyLog(context, controller),
              ),
          ],
        ),
      ),
    );
  }

  /// The connection box stays pinned at the top; the attribute list scrolls
  /// underneath it and the box fades out to free up the room it occupies.
  Widget _pinnedScrollArea(CgmController controller) {
    return Stack(
      children: [
        Positioned.fill(child: _scrollContent(controller)),
        _pinnedBox(controller),
      ],
    );
  }

  Widget _scrollContent(CgmController controller) {
    return NotificationListener<ScrollEndNotification>(
      onNotification: (_) => _snapScroll(),
      child: SingleChildScrollView(
        controller: _scroll,
        physics: const ClampingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.only(top: _boxHeight > 0 ? _boxHeight + _gap : 0),
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
              _sensorInfo(controller),
            ],
          ),
        ),
      ),
    );
  }

  /// The G7 info page reads a [G7DeviceInfo]; the Libre 3 has its own builder
  /// (activation MAC, session clock, plus the one-minute reading's predicted
  /// glucose / trend / temperature).
  Widget _sensorInfo(CgmController controller) {
    if (controller.sensorType == SensorType.abbottLibre3) {
      return Libre3SensorInfo(
        mac: controller.libreMac,
        sensorStart: controller.sensorStart,
        lastUpdate: controller.lastUpdate,
        latest: controller.latest,
      );
    }
    return SensorInfo(
      info: controller.info,
      sensorStart: controller.sensorStart,
      state: controller.latest?.state,
      age: controller.latest?.secsSinceStart,
      lastUpdate: controller.lastUpdate,
    );
  }

  Widget _pinnedBox(CgmController controller) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: _scroll,
        builder: (context, child) => _fade(child!),
        child: SensorControlBox(key: _boxKey, controller: controller),
      ),
    );
  }

  Widget _fade(Widget child) {
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final progress = (offset / _fadeDistance).clamp(0.0, 1.0);
    final opacity = 1 - progress;
    // Once mostly faded, let touches reach the content below.
    return IgnorePointer(
      ignoring: opacity < 0.5,
      child: Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(0, -progress * _riseDistance),
          child: child,
        ),
      ),
    );
  }
}
